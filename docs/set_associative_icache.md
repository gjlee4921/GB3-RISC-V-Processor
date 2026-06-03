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
lines) and repeatedly-read constant matrices in flash (for a future data cache).

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

| | `kalman_steady_state.c` | `kalman_full.c` |
|---|---|---|
| State predict `x = F x` | ✓ | ✓ |
| Covariance predict `P = F P Fᵀ + Q` | ✗ | ✓ |
| Innovation `z − H x` | ✓ | ✓ |
| Innovation covariance `S = H P Hᵀ + R` | ✗ | ✓ |
| Gain `K = P Hᵀ S⁻¹` (matrix inverse) | ✗ (fixed `K`) | ✓ |
| State update `x + K y` | ✓ | ✓ |
| Covariance update `P = (I − K H) P` | ✗ | ✓ |
| Arithmetic | Q4 integer | Q8 integer (incl. fixed-point divide) |

**The headline 9.70× result below uses `kalman_steady_state.c`.** It is reported
honestly as a steady-state / constant-gain Kalman filter: its hardcoded gain is
an illustrative tuned value, not the exact solution of the discrete algebraic
Riccati equation. `kalman_full.c` implements the complete filter (heavier
instruction footprint, even more cache-stressing) and is provided for a fuller
demonstration; its expected output must be obtained by running the identical
fixed-point code on a host PC before trusting the board.

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
execute-in-place — relevant for a future data cache, but not cached by this
instruction-only design.

## Hardware Measurements

Measured on the iCEBreaker (iCE40UP5K) at 12 MHz with QDDR flash, via the
`[B]` UART workload-benchmark command. Cache vs no-cache selected by the
`CACHE_EN` parameter.

### Performance

| Configuration | Cycles | Hex |
|---|---|---|
| No cache (`CACHE_EN = 0`) | 7,680,714 | `0x007532ca` |
| With cache (`CACHE_EN = 1`) | 792,156 | `0x000c165c` |
| **Speedup** | **9.70×** | |

Both configurations return `0xC7` on the 7-segment display, confirming the
cache is functionally transparent — the same answer is computed, only faster.
Since the instruction count is identical between runs, the 9.70× cycle
reduction is also a 9.70× reduction in effective CPI, well beyond the project's
CPI target.

### Area and Timing

| Metric | Result | Constraint |
|---|---|---|
| Logic cells (ICESTORM_LC) | 4426 / 5280 (**83%**) | < 85% (plan target) |
| Block RAM (ICESTORM_RAM) | 10 / 30 (33%) | — |
| Max clock (icetime) | 16.18 MHz | ≥ 12 MHz (PASS) |

The cache data arrays occupy block RAM (RAM utilisation rose from the
baseline's 4/30 to 10/30), keeping logic-cell usage within the 85% area budget.

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
