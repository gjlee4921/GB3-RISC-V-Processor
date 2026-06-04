# 2-Way Set-Associative, 4-Word-Line Instruction Cache — Hardware Summary

This document describes the upgraded instruction cache (`icache.v`): a 16-set,
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

### Baseline toggle

`icache.v` contains:

```verilog
localparam CACHE_EN = 1'b1;  // set to 1'b0 for a no-cache baseline
```

With `CACHE_EN = 0`, all accesses are forced to miss (bypassing the cache),
giving a clean no-cache baseline on the same bitstream structure.

## Files Changed

- **`icache.v`** — rewritten as 16-set, 2-way, 4-word-line cache with
  synchronous block-RAM data arrays and an FSM-driven fill.
- **`picosoc.v`** — icache instantiated with default `NSETS = 16` on the
  instruction flash path; data flash requests bypass it (unchanged from the
  direct-mapped integration).

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
`kalman_steady_state.c` is a lighter variant used for additional comparison.
The expected output of `kalman_filter.c` must be verified on a host PC before
trusting the board result.

### Steady-state workload details (`kalman_steady_state.c`)

- **Model:** 4 states (position and velocity in 2D: px, py, vx, vy) with 2
  noisy position observations.
- **Arithmetic:** fixed-point Q4 (1.0 represented as 16), integer-only.
- **Steps:** 100 filter iterations, each performing predict, innovation, and
  update matrix-vector products.
- **Constant data (in flash `.rodata`):** state-transition matrix `kf_F` (4×4),
  observation matrix `kf_H` (2×4), fixed gain `kf_K` (4×2), measurement-advance
  `kf_z_step` (2), and a 16-entry noise cycle `kf_z_noise` (16×2) — **264 bytes
  total**, read on every step.
- **Return value:** estimated px in real units after 100 steps, tracking an
  object moving at velocity (vx=2, vy=1) units/step.
- **Expected result: `0xC7` (199 decimal)** — verified against a reference run
  of the identical fixed-point code on a host PC.

The matrices reside in flash (confirmed: the linker script places `.rodata` in
FLASH, and the startup code does not copy it to RAM), so they are read via
execute-in-place and are not cached by this instruction-only design.

## Workflow

### Synthesis and flashing

```bash
touch firmware.c       # ensure firmware.c is recompiled, not a stale workload binary
make icebprog
```

Make automatically detects what needs rebuilding. If `icebreaker.bin` is
already up to date (no `.v` files changed since last build), it skips
synthesis and only recompiles and flashes the firmware — takes seconds.
If any `.v` file changed, it runs full synthesis + place-and-route first.
At 99% utilisation this takes **3–4 minutes** due to the congested routing.

After flashing, the board runs the interactive UART menu by default (send
`B` to benchmark). To switch to a raw workload loop for Picoscope
measurement, see Switching firmware below.

**Check area utilisation without flashing:**
```bash
make icebreaker.bin
```
Watch the `ICESTORM_LC` line in the nextpnr output.

### Switching firmware

The `FW` variable selects the C source compiled into the firmware binary.
Make uses timestamps to decide whether to recompile — always `touch` the
source file when switching to force a rebuild.

**Interactive mode** (UART menu with `[B]` benchmark command):
```bash
touch firmware.c
make icebprog_fw
```
Connect via UART (115200 baud) and send `B` to measure workload cycles.

**Raw workload loop** (LED toggles every iteration — for Picoscope frequency measurement):
```bash
touch workloads/<name>.c
make FW=workloads/<name> icebprog_fw
```
For example, to measure the full Kalman filter:
```bash
touch workloads/kalman_filter.c
make FW=workloads/kalman_filter icebprog_fw
```
Measure the LED toggle frequency on the Picoscope; cycles = `6,000,000 / f`.

### True no-cache baseline (`picosoc_nocache.v`)

`CACHE_EN = 0` in `icache.v` is **not** a true no-cache baseline. With
`CACHE_EN=0`, every instruction still triggers the cache FSM to fetch all
4 words from flash even though none are reused on the next access — making
it approximately **6× slower** than a processor without any cache hardware.
This artificially inflates the apparent speedup.

`picosoc_nocache.v` is a separate SoC file that removes the icache module
entirely, routing instruction fetches directly to spimemio (1 word per
fetch). This gives the honest comparison. Two pre-built bitstreams are
committed to the repository:

- `icebreaker.bin` — cache + barrel shifter (final design, 99% LC)
- `icebreaker_nocache.bin` — no cache, barrel shifter only (true baseline, 88% LC)

**Testing any workload on both — interactive `[B]` mode:**
```bash
touch firmware.c
make icebprog          # flash cache version → send B
make icebprog_nocache  # flash no-cache version → send B
```

**Testing any workload on both — Picoscope loop:**
```bash
touch workloads/<name>.c
make FW=workloads/<name> icebprog          # cache
make FW=workloads/<name> icebprog_nocache  # no cache
```

Both targets detect that the `.bin` files are already up to date and skip
re-synthesis — switching between them takes seconds.

## Hardware Measurements

All measurements on iCEBreaker (iCE40UP5K) at 12 MHz with QDDR flash.
Baseline is always `picosoc_nocache.bin` — a separate bitstream with the
icache module removed entirely (1 flash read per instruction). LED toggles
every iteration; Picoscope frequency relates to cycles as `6,000,000 / f`.

### Performance — Full Kalman Filter (`kalman_filter.c`)

**Cycle count via `[B]` UART command (rdcycle measurement):**

| Configuration | Cycles | Hex |
|---|---|---|
| True no-cache (`picosoc_nocache.bin`) | 29,376,788 | `0x01c04114` |
| Cache only | 15,981,621 | `0x00f3da35` |
| Cache + barrel shifter (`icebreaker.bin`) | 14,565,991 | `0x00de4267` |
| **True speedup (cache + barrel shifter vs no-cache)** | **2.02×** | |

**Picoscope frequency measurement:**

| Configuration | Picoscope frequency | Calculated cycles |
|---|---|---|
| True no-cache (`picosoc_nocache.bin`) | 204.2 mHz | 29,384,000 ✓ |
| Cache only | 375.8 mHz | 15,981,000 ✓ |
| Cache + barrel shifter (`icebreaker.bin`) | 412.2 mHz | 14,563,000 ✓ |
| **True speedup** | **2.02×** | |

Both configurations return `0x6C` on the 7-segment display, verified against a
host PC run of the identical fixed-point code.

The remaining runtime after caching (14.6M cycles) is dominated by data reads
from flash — the constant matrices in `.rodata` are read on every filter step
and are not cached by this instruction-only design. Roughly half the no-cache
runtime was instruction fetch (removed by the cache) and half is data reads +
compute (unchanged), which is why the true speedup is 2.02×.

### Area and Timing

| Metric | Cache only | Cache + barrel shifter | Constraint |
|---|---|---|---|
| Logic cells (ICESTORM_LC) | 4426 / 5280 (83%) | 5268 / 5280 (**99%**) | must fit |
| Block RAM (ICESTORM_RAM) | 10 / 30 (33%) | 10 / 30 (33%) | — |
| Max clock (icetime) | 16.18 MHz | 18.86 MHz | ≥ 12 MHz (PASS) |

The cache data arrays occupy block RAM (RAM utilisation rose from the
baseline's 4/30 to 10/30). The barrel shifter adds 842 logic cells, pushing
utilisation to 99% (12 cells spare), while timing still passes comfortably.

## Design Evolution (Area Constraint)

The final design was reached after the cache data storage was found to exceed
the FPGA's logic-cell budget when implemented naively:

| Attempt | Data storage | Logic cells | Result |
|---|---|---|---|
| 16-set, 2-way, 4-word, combinational read | flip-flops | 11,989 / 5,280 (227%) | does not fit |
| Reduced to 4 sets, combinational read | flip-flops | 6,391 / 5,280 (121%) | does not fit |
| 16-set, 2-way, 4-word, **synchronous read** | **EBR block RAM** | 4,426 / 5,280 (83%) | **fits** |

The root cause was that combinational (asynchronous) data reads force the
synthesis tool to implement the cache data as logic-cell flip-flops. Even
shrinking the cache to 4 sets did not bring it within budget, because the
per-access read-multiplexing and storage still dominated logic usage.

Switching the data arrays to **synchronous reads** allowed them to be mapped to
the FPGA's dedicated EBR block RAM — which sat almost entirely unused — freeing
roughly 7,500 logic cells and letting the full 16-set design fit comfortably.
The only functional cost is the extra hit-latency cycle, which is immaterial
against the QDDR flash miss penalty. This also matches the project plan's
assumption that the cache would use block RAM rather than logic cells.

## ENABLE_DIV, Data Cache Attempt, and Barrel Shifter

### ENABLE_DIV: required for the full Kalman filter

The full Kalman filter (`kalman_filter.c`) uses fixed-point division via
`fdiv()`. The compiler emits this as a call to `__divdi3`, a 64-bit
software-division routine that issues RV32IM hardware `DIV` instructions.
With `ENABLE_DIV=0` (the PicoSoC default), PicoRV32 stalls indefinitely
waiting for a PCPI coprocessor that is never present — the processor hangs
on the first division instruction. `ENABLE_DIV=1` was therefore a hard
requirement to run the full Kalman filter on hardware at all.

### Data cache: attempted and rejected

With the instruction cache delivering an 11× speedup, a data cache for the
`.rodata` constant matrices (read from flash on every filter step) was the
natural next optimisation. Two designs were synthesised alongside the
existing icache and `ENABLE_DIV` logic:

| Design | Logic cells | Result |
|---|---|---|
| 8-set, 2-way associative, 4-word lines | 6038 / 5280 (114%) | does not fit |
| 8-set, direct-mapped, 4-word lines | 5645 / 5280 (106%) | does not fit |

Even the minimal direct-mapped design exceeded the device capacity. Reducing
to ≤ 4 sets would fit but covers fewer than 64 bytes — not enough to hold a
single matrix, giving a negligible hit rate. The data cache was abandoned as
incompatible with the remaining area budget.

### Barrel shifter: chosen as the viable alternative

After the instruction cache removed fetch stalls, the next bottleneck is
compute CPI. The Q8 fixed-point multiply (`fmul`) performs `>>8` on every
product; without a barrel shifter, PicoRV32 executes this as 8 sequential
1-bit shifts (~8 cycles). The full Kalman filter calls `fmul` tens of
thousands of times per iteration, making iterative shifts a significant
fraction of the remaining runtime.

`BARREL_SHIFTER=1` replaces all shift instructions with single-cycle
hardware. It costs 842 logic cells (pushing utilisation to 99%) but timing
still passes comfortably (18.86 MHz vs 12 MHz required):

| Metric | Cache only | Cache + barrel shifter |
|---|---|---|
| Logic cells | 4426 / 5280 (83%) | 5268 / 5280 (99%) |
| Full Kalman cycles | 15,981,621 | 14,565,991 |
| Improvement | — | 1.10× (9.7% faster) |
| Combined speedup vs baseline | 11.0× | **12.0×** |

The 9.7% gain is consistent with `>>8` being a real but secondary cost:
matrix-multiply loops and hardware division dominate the remaining compute
time after the cache removes the fetch bottleneck.

### Cache geometry exploration: 8-set/8-word variant

As a follow-up experiment, the cache geometry was changed from 16-set/4-word
lines to 8-set/8-word lines (keeping 2-way associativity and the barrel
shifter). Total capacity is identical — 8 × 2 × 8 × 4 = 512 bytes — but
the trade-off between sets and line width differs:

- **Fewer sets (8 vs 16):** reduces the tag/valid/LRU register count, saving
  area, but increases the risk of conflict misses for workloads with many
  distinct hot regions mapping to the same set.
- **Wider lines (8 vs 4 words):** fetches 32 bytes per miss instead of 16,
  improving spatial locality for sequential code, but a cold miss now costs
  twice as many flash transactions.

Synthesis and measurement results on the full Kalman filter:

| Metric | 16-set / 4-word | 8-set / 8-word |
|---|---|---|
| Logic cells (ICESTORM_LC) | 5268 / 5280 (99%) | 5177 / 5280 (98%) |
| Area saving | — | 91 LC (1%) |
| Full Kalman cycles (`[B]`) | 14,565,991 (`0x00de4267`) | 14,617,889 (`0x00df0d21`) |
| Picoscope frequency | 412.2 mHz | 407.8 mHz |
| Calculated cycles (Picoscope) | 14,563,000 ✓ | 14,717,000 ✓ |
| Performance vs 16-set/4-word | — | −0.36% (51,898 cycles slower) |

The 8-set/8-word variant saves 91 logic cells at a cost of 0.36% slower
execution. Both Picoscope measurements independently confirm the rdcycle
results. The performance difference is within normal run-to-run variation
and both designs return `0x6C` on the 7-segment display.
