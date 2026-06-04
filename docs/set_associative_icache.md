# 2-Way Set-Associative, 4-Word-Line Instruction Cache — Hardware Summary

This document describes the instruction cache (`icache.v`): a 16-set,
2-way set-associative cache with 4-word (16-byte) lines, backed by iCE40 EBR
block RAM. It supersedes the earlier direct-mapped, 1-word-line design.

## Motivation

The direct-mapped 1-word-line cache works well for workloads with a tiny
instruction footprint, but a loop-heavy workload whose hot code exceeds the
cache capacity (e.g. the Kalman filter, with three matrix-vector loop nests)
thrashes a small cache and sees almost no benefit. Two improvements address
this:

- **4-word lines** exploit spatial locality: one miss fetches 4 consecutive
  instructions, so sequential code after a miss is already cached.
- **2-way associativity** removes conflict misses, letting two distinct hot
  regions that map to the same set coexist instead of evicting each other.

Together they raise the cache capacity from 64 bytes to **512 bytes**
(16 sets × 2 ways × 4 words × 4 bytes) and keep the hit rate high for larger
working sets.

## Architecture

Address decomposition (24-bit flash address):

```
[23:8]  tag         (16 bits)
[7:4]   index        (4 bits → selects one of 16 sets)
[3:2]   word-in-line (2 bits → selects one of 4 words in the line)
[1:0]   byte offset  (always 00 for word-aligned instructions)
```

- **2 ways per set**, each with its own tag, valid bit, and 4-word data line.
- **1-bit LRU per set** chooses the way to evict on a miss.
- On a **hit**, the matching way's word is returned.
- On a **miss**, 4 words are fetched from flash into the LRU-evicted way, then
  the requested word is returned.

### Storage split (the key design decision)

| State | Storage | Read type | Why |
|---|---|---|---|
| tag / valid / LRU | logic-cell registers | combinational | small; enables same-cycle hit detection |
| data lines | **EBR block RAM** | **synchronous** | large; block RAM is the only way to fit |

The data arrays use a **registered (synchronous) read** so the synthesis tool
maps them to the FPGA's EBR block RAM rather than logic-cell flip-flops. This
is what makes the design fit (see Design Evolution below). The consequence is
that a **hit takes 2 cycles** instead of 1: cycle 0 issues the block-RAM read
and registers the tag comparison, cycle 1 serves the data. On QDDR flash, where
a miss costs tens of cycles, this extra hit cycle is negligible.

## Files Changed

- **`icache.v`** — rewritten as 16-set, 2-way, 4-word-line cache with
  synchronous block-RAM data arrays and an FSM-driven fill.
- **`picosoc.v`** — icache instantiated with default `NSETS = 16` on the
  instruction flash path; data flash requests bypass it.

## Benchmark Workload: Kalman Filter

The measurement workload is a Kalman filter, chosen because it stresses every
cache feature: a large instruction footprint (for set-associativity and wide
lines) and repeatedly-read constant matrices in flash.

Two versions exist in `workloads/`, and it is important to be precise about
which one the headline measurement uses:

### Steady-state vs full Kalman filter

A full Kalman filter performs, each step: state predict, **covariance predict**
`P = F P Fᵀ + Q`, innovation, **innovation covariance** `S = H P Hᵀ + R`, **gain
computation** `K = P Hᵀ S⁻¹` (which requires a matrix inverse), state update,
and **covariance update** `P = (I − K H) P`. The covariance propagation and the
matrix inverse are by far the heaviest parts.

For a time-invariant system (constant `F, H, Q, R`), the covariance `P` and gain
`K` converge to constants. A **steady-state (constant-gain) Kalman filter**
exploits this by precomputing `K` offline and running only predict / innovation
/ update with a fixed gain — a real, widely-used embedded technique that avoids
the covariance work and the inverse entirely. It is therefore a **legitimate but
significantly simplified** variant, not a full filter.

| | `kalman_steady_state.c` | `kalman_filter.c` |
|---|---|---|
| State predict `x = F x` | ✓ | ✓ |
| Covariance predict `P = F P Fᵀ + Q` | ✗ | ✓ |
| Innovation `z − H x` | ✓ | ✓ |
| Innovation covariance `S = H P Hᵀ + R` | ✗ | ✓ |
| Gain `K = P Hᵀ S⁻¹` (matrix inverse) | ✗ (fixed `K`) | ✓ |
| State update `x + K y` | ✓ | ✓ |
| Covariance update `P = (I − K H) P` | ✗ | ✓ |
| Arithmetic | Q4 integer | Q8 integer (incl. fixed-point divide) |

`kalman_filter.c` implements the complete filter and is the primary benchmark.

## Workflow

### Synthesis and flashing

```bash
make FW=workloads/kalman_filter icebprog
```

Make compiles the firmware and flashes both the bitstream and firmware binary.
If `icebreaker.bin` is already up to date (no `.v` files changed since last
build), it skips synthesis and only recompiles and flashes the firmware.

**Check area utilisation without flashing:**
```bash
make icebreaker.bin
```

### True no-cache baseline (`picosoc_nocache.v`)

`picosoc_nocache.v` is a separate SoC file that removes the icache module
entirely, routing instruction fetches directly to spimemio (1 word per fetch).

```bash
make FW=workloads/kalman_filter icebprog          # cache design
make FW=workloads/kalman_filter icebprog_nocache  # no-cache baseline
```

## Hardware Measurements

All measurements at 12 MHz with QDDR flash. Cycles derived as `6,000,000 / f`
(LED toggles once per workload iteration; Picoscope reads toggle frequency).

### Performance — Full Kalman Filter (`kalman_filter.c`)

| Configuration | Picoscope frequency | Calculated cycles |
|---|---|---|
| No-cache (`picosoc_nocache.bin`) | 204.2 mHz | 29,384,000 |
| Cache only | 375.8 mHz | 15,981,000 |
| Cache + barrel shifter (`icebreaker.bin`) | 412.2 mHz | 14,563,000 |
| **True speedup (cache + barrel shifter vs no-cache)** | **2.02×** | |

Both configurations return `0x6C` on the 7-segment display.

The remaining runtime after caching (14.6M cycles) is dominated by data reads
from flash — the constant matrices in `.rodata` are read on every filter step
and are not cached by this instruction-only design. Roughly half the no-cache
runtime is instruction fetch (removed by the cache) and half is data reads and
compute, which is why the speedup is 2.02×.

### Area and Timing

| Metric | Cache only | Cache + barrel shifter | Constraint |
|---|---|---|---|
| Logic cells (ICESTORM_LC) | 4426 / 5280 (83%) | 5268 / 5280 (**99%**) | must fit |
| Block RAM (ICESTORM_RAM) | 10 / 30 (33%) | 10 / 30 (33%) | — |
| Max clock (icetime) | 16.18 MHz | 18.86 MHz | ≥ 12 MHz (PASS) |

## Design Evolution (Area Constraint)

The final design was reached after the cache data storage was found to exceed
the FPGA's logic-cell budget when implemented naively:

| Attempt | Data storage | Logic cells | Result |
|---|---|---|---|
| 16-set, 2-way, 4-word, combinational read | flip-flops | 11,989 / 5,280 (227%) | does not fit |
| Reduced to 4 sets, combinational read | flip-flops | 6,391 / 5,280 (121%) | does not fit |
| 16-set, 2-way, 4-word, **synchronous read** | **EBR block RAM** | 4,426 / 5,280 (83%) | **fits** |

Switching the data arrays to **synchronous reads** allowed them to be mapped to
the FPGA's dedicated EBR block RAM, freeing roughly 7,500 logic cells and
letting the full 16-set design fit comfortably. The only functional cost is the
extra hit-latency cycle, which is immaterial against the QDDR flash miss penalty.

## ENABLE_DIV and Barrel Shifter

### ENABLE_DIV: required for the full Kalman filter

The full Kalman filter (`kalman_filter.c`) uses fixed-point division via
`fdiv()`. The compiler emits this as a call to `__divdi3`, a 64-bit
software-division routine that issues RV32IM hardware `DIV` instructions.
With `ENABLE_DIV=0` (the PicoSoC default), PicoRV32 stalls indefinitely
waiting for a PCPI coprocessor that is never present — the processor hangs
on the first division instruction. `ENABLE_DIV=1` was therefore a hard
requirement to run the full Kalman filter on hardware at all.

### Barrel shifter

After the instruction cache removed fetch stalls, the next bottleneck is
compute CPI. The Q8 fixed-point multiply (`fmul`) performs `>>8` on every
product; without a barrel shifter, PicoRV32 executes this as 8 sequential
1-bit shifts (~8 cycles). The full Kalman filter calls `fmul` tens of
thousands of times per iteration, making iterative shifts a significant
fraction of the remaining runtime.

`BARREL_SHIFTER=1` replaces all shift instructions with single-cycle hardware.
It costs 842 logic cells, pushing utilisation from 83% to **99%** (only 12
cells spare):

| Metric | Value |
|---|---|
| Logic cells | 5268 / 5280 (99%) |
| Full Kalman cycles | 14,565,991 |
| Speedup vs no-cache | **2.02×** |

With only 12 logic cells remaining, the device was at capacity. No further
optimisations — data cache, additional CPU features, or clock changes — were
possible within this design phase. The icache + barrel shifter combination
was therefore taken as the complete design at this stage, with a final
speedup of **2.02×** on the Kalman filter benchmark at 12 MHz.

Further improvements (area recovery via parameter optimisation, data cache,
and PLL overclock) are documented in `docs/datacache.md`.
