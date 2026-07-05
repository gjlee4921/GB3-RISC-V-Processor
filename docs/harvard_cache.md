# Phase 3 — Harvard Split Cache and Final Build

This document picks up from [Phase 2](set_associative_icache.md), which added
the 2-way set-associative instruction cache. Phase 3 adds a separate **data
cache** on the data-read path, forming a **modified Harvard architecture**: the
instruction fetch and data read paths each have their own dedicated cache backed
by iCE40 EBR block RAM, while sharing a single QDDR flash port. It also covers
the area recovery, PLL overclock, and final-build configuration that together
produce the as-run design.

The development steps in this phase were:

1. **Data cache** (`dcache.v`) — a second, direct-mapped cache for `.rodata` reads
2. **Area recovery** — disable unused CPU features to free logic cells
3. **PLL overclock** — 12 MHz → 18.75 MHz using the iCE40UP5K hard PLL block
4. **Final configuration** — re-enable the cycle counters and remap the
   7-segment so arbitrary externally-compiled binaries run; disable the hardware
   divider to pay for it

> **Final build:** icache 32-set / 2-way / 4-word (1 KB); dcache 32-set /
> direct-mapped / 4-word (512 B); `ENABLE_DIV=0`, `ENABLE_COUNTERS=1`; 7-seg at
> `0x03000001`; **18.75 MHz** PLL; **4618 / 5280 LC (87%)**, 13/30 EBR, 2.62 ns
> timing margin. Headline benchmark: `kalman_steady_state`.

## The five build configurations

All five synthesised configurations, measured throughout the project, are:

| Build | File | Clock | I-cache | D-cache |
|---|---|---|---|---|
| Baseline | `picosoc_baseline.v` | 12 MHz (no PLL) | None | None |
| No-cache | `picosoc_nocache.v` | 18.75 MHz (PLL) | None | None |
| Direct-map | `picosoc_directmap.v` | 18.75 MHz (PLL) | 32-set, 1-way, 512 B | None |
| I-cache only | `picosoc_icache_only.v` | 18.75 MHz (PLL) | 32-set, 2-way, 1 KB | None |
| **Full** | `picosoc.v` | 18.75 MHz (PLL) | 32-set, 2-way, 1 KB | 32-set, 1-way, 512 B |

`picosoc_baseline.v` matches the original repository `picosoc.v` and is
synthesised with `yosys -D NO_PLL` to run at stock 12 MHz, preserving a true
before/after comparison. The no-cache, direct-map, and i-cache-only builds were
synthesised with the cycle counters disabled (`ENABLE_COUNTERS = 0`) to recover
area during development; the baseline and full builds have them enabled, so the
baseline-to-full comparison is consistent.

---

## 1. Data Cache (`dcache.v`)

The data cache reuses the **same `dcache.v` module** as the
[Phase 1](direct_mapped_icache.md) direct-mapped instruction cache, this time
instantiated on the data-read path. It intercepts flash reads where
`mem_instr = 0` and the address falls within the flash range, targeting the
`.rodata` constant matrices that `kalman_steady_state` reads on every iteration.

### Design: 32-set, direct-mapped, 4-word lines

- **Direct-mapped** (1 way, no LRU) — halves tag/valid storage versus a 2-way
  design, and the read-only constant working set has no conflict pressure that
  would need associativity.
- **Read-only** — SPI flash is read-only at runtime; CPU writes go to SRAM or IO
  and never reach the dcache, so no dirty bits or write-back logic are required.
  Lines are filled on a miss and never invalidated during normal operation.
- **32 sets, 4-word (16-byte) lines** — 512 bytes capacity.

Address decomposition (24-bit flash address):

```
[23:9]  tag          (15 bits)
[8:4]   index         (5 bits → selects one of 32 sets)
[3:2]   word-in-line  (2 bits)
[1:0]   byte offset   (always 00)
```

Storage:

| State | Storage | Why |
|---|---|---|
| tag / valid | logic-cell registers | 32 × 16 bits — small; combinational hit detection |
| data | **EBR block RAM** (3 blocks) | large; a 32-bit synchronous read port spans several `SB_RAM40_4K` primitives (each ≤ 16 bits wide) |

Like the icache, the data array uses a **synchronous read** so Yosys maps it to
EBR rather than logic-cell flip-flops. Hit latency is 2 cycles (cycle 0 = BRAM
read + tag compare, cycle 1 = serve), negligible against the tens-of-cycle QDDR
flash miss penalty.

### Why 32 sets

The constant data read by `kalman_steady_state` (`kf_F`, `kf_H`, `kf_K`,
`kf_z_step`, `kf_z_noise`) totals **264 bytes**, which fits comfortably within
the 512-byte capacity without conflict evictions. After the first iteration all
of this data is resident in the EBR-backed cache, and subsequent iterations are
served in 1–2 cycles rather than the tens of cycles a flash access costs. The
simpler workloads (Fibonacci, bubble sort) have no `.rodata` working set, so the
data cache gives them no speedup — which is what isolates the dcache's
contribution to the Kalman result.

### Flash port sharing with the icache

The icache and dcache share the single `spimemio` flash port without an arbiter.
PicoRV32 has only one outstanding memory request at a time: when `mem_instr = 1`
the icache is active; when `mem_instr = 0` and the address is in flash range the
dcache is active. The two are mutually exclusive by CPU design, so their flash
requests are simply OR'd together with the address muxed accordingly.

---

## 2. Area Recovery (Parameter Optimisation)

Fitting the data cache, and later the PLL, required freeing logic-cell area.
PicoRV32 enables two optional hardware blocks by default in PicoSoC that none of
the workloads need:

- **`ENABLE_IRQ`** — interrupt controller, dispatch FSM, and 32 IRQ vectors.
  None of the workloads use interrupts. Disabling it saves **~600 LC** — the
  interrupt controller's state machine, priority encoder, and the `irq` fanout to
  every pipeline stage.
- **`ENABLE_COUNTERS`** — `rdcycle` / `rdinstret` CSRs. Disabling saves
  **~143 LC**. (These are re-enabled in the final build; see §4.1.)

Disabling both during development recovered roughly **743 LC**, which is what
made the data cache and the PLL feasible on top of the existing cache logic. The
saving is purely area — neither block affects the runtime of the benchmark
workloads.

---

## 3. PLL Overclock to 18.75 MHz

The iCE40UP5K contains one `SB_PLL40_PAD` hard block that consumes **0 logic
cells**. It takes the 12 MHz crystal input and generates the system clock via a
VCO:

```
DIVR = 0, DIVF = 49, DIVQ = 5
VCO    = 12 × (49 + 1) = 600 MHz     (within the 533–1066 MHz range)
Output = 600 / 32      = 18.75 MHz
```

The PLL is instantiated in `icebreaker.v` (the shared top level) and gated by a
`NO_PLL` synthesis define — the baseline bitstream is synthesised with
`yosys -D NO_PLL` so it runs at the stock 12 MHz. The reset counter waits for
`pll_locked` before releasing reset. Static timing (icetime) confirms the full
build closes at 18.75 MHz with a **2.62 ns margin** on the 53.33 ns clock period
(see §5).

---

## 4. Final Configuration (External-Binary Compatibility)

The final build must run **arbitrary externally-compiled RISC-V binaries** on
this processor, not just the project's own workloads. Three incompatibilities
surfaced, each forcing a change away from the pure performance-optimised build
of §1–3.

### 4.1 Re-enable the cycle counters (`ENABLE_COUNTERS = 1`)

Some external binaries call a timed wrapper that executes `rdcycle` /
`rdinstret` (for CPI measurement) **before** entering the LED loop. With
`ENABLE_COUNTERS = 0` these CSR reads are not decoded as counter instructions in
PicoRV32 (`picorv32.v` gates them on `ENABLE_COUNTERS`); they become **illegal
instructions**, and with `ENABLE_IRQ = 0` the core traps and halts. The binary
therefore hangs before displaying anything — no LED, no 7-seg. Re-enabling the
counters (~143 LC) makes those instructions legal so the binaries run to
completion.

### 4.2 Disable the hardware divider (`ENABLE_DIV = 0`)

The counters had to be paid for in area. The headline benchmark
`kalman_steady_state` is `int32` multiply-and-shift only, with **no division**,
so the divider is dead weight and was disabled in `icebreaker.v`
(`.ENABLE_DIV(0)`). The divider is the single largest CPU block, so removing it
frees far more area than the counters cost — enough to keep the 32-set icache and
still close timing comfortably at 87 % utilisation.

### 4.3 Remap the 7-segment to `0x03000001`

The external binaries write their two outputs to adjacent bytes:

| Address | Role |
|---|---|
| `0x03000000` | LED (toggles `0x02` → LED1) |
| `0x03000001` | 7-segment (the `run_workload()` answer) |

The original design decoded the 7-seg at `0x03000004`, so those binaries left
the 7-seg blank while a mis-aligned store corrupted the LED register.
`0x03000001` is an **odd** byte address, so a byte store lands on **byte lane 1**
(`iomem_wstrb[1]`, data in `iomem_wdata[15:8]`). The `icebreaker.v` decode was
changed accordingly:

```verilog
if (iomem_wstrb[0] && iomem_addr[7:0] == 8'h00) gpio[7:0] <= iomem_wdata[7:0];  // LED  @ 0x03000000
if (iomem_wstrb[1])                              seg7_val <= iomem_wdata[15:8]; // 7seg @ 0x03000001
```

### Final parameter set (effective, as synthesised)

`icebreaker.v` instantiation overrides `picosoc.v` defaults — the values below
are what actually reach PicoRV32:

| Parameter | Value | Set in | Rationale |
|---|---|---|---|
| `BARREL_SHIFTER` | 1 | `icebreaker.v` | single-cycle shifts (fixed-point `>>`) |
| `ENABLE_MUL` | 0 | `icebreaker.v` | superseded by FAST_MUL |
| `ENABLE_FAST_MUL` | 1 | `icebreaker.v` | DSP-based single-cycle multiply |
| `ENABLE_DIV` | **0** | `icebreaker.v` | benchmark needs no division; frees area (§4.2) |
| `ENABLE_COMPRESSED` | 0 | `icebreaker.v` | firmware built `-march=rv32im` (no C) |
| `ENABLE_COUNTERS` | **1** | `picosoc.v` default | external binaries use `rdcycle`/`rdinstret` (§4.1) |
| `ENABLE_IRQ` | 0 | `picosoc.v` | no interrupts used by any workload |
| Instruction cache | **32-set**, 2-way, 4-word (1 KB) | `icache.v` | Phase 2 |
| Data cache | 32-set, direct-mapped, 4-word (512 B) | `dcache.v` | Phase 3 |
| 7-seg address | `0x03000001` | `icebreaker.v` | external-binary output convention (§4.3) |
| System clock | **18.75 MHz** (PLL, DIVF=49) | `icebreaker.v` | overclock; passes timing (§3) |

---

## 5. Results

All measurements on the iCEBreaker (iCE40UP5K). LED1 toggles once per
`run_workload()` iteration; a Picoscope reads the toggle frequency `f`, and the
per-iteration cycle count is `f_clk / (2·f)`, using 12 MHz for the baseline and
18.75 MHz for all other builds.

### Performance — `kalman_steady_state`

| Build | LED freq (Hz) | Cycles | Time per iter (ms) |
|---|---|---|---|
| Baseline (12 MHz, no cache) | 4.144 | 1,447,876 | 120.7 |
| No-cache (18.75 MHz, no cache) | 6.475 | 1,447,877 | 77.2 |
| Direct-map (Phase 1) | 13.32 | 703,604 | 37.5 |
| I-cache only (Phase 2) | 16.36 | 573,104 | 30.6 |
| **Full (Phase 3)** | **16.54** | **566,807** | **30.2** |

### Speedup decomposition

| Comparison | Source of gain | Factor |
|---|---|---|
| No-cache vs Baseline (cycles) | CPU parameter change | 1.00× |
| No-cache vs Baseline (wall clock) | PLL: 18.75 / 12 MHz | **1.56×** |
| Direct-map vs No-cache (cycles) | 32-set direct-mapped icache | 2.06× |
| I-cache only vs No-cache (cycles) | 32-set 2-way set-assoc icache | 2.53× |
| Full vs No-cache (cycles) | icache + dcache | **2.55×** |
| Full vs I-cache only (cycles) | dcache contribution alone | 1.01× |
| **Full vs Baseline (wall clock)** | PLL + cache total | **3.99×** |

The caches reduce the cycle count by **2.55×** before any overclocking, and the
PLL multiplies this into a **3.99×** wall-clock speedup. The data cache adds only
**1.01×** on top of the instruction cache for this workload: once instructions
are cached, the remaining flash traffic is minimal, so the 264-byte constant
working set contributes little. The dcache would matter far more on a workload
with a large, frequently-read constant dataset.

The three secondary workloads have no `.rodata` working set, so their speedup
comes entirely from the instruction cache and PLL: `fibonacci_iterative` 3.04×,
`fibonacci_recursive` 4.14×, `bubble_sort` 3.08× (full vs baseline, wall clock).

### Area

Post-synthesis cell counts (Yosys, `data/icebreaker_*.log`):

| Build | SB_LUT4 | EBR | DSP | SPRAM | PLL |
|---|---|---|---|---|---|
| Baseline | 3357 | 4 | 4 | 4 | 0 |
| No-cache | 2706 | 4 | 4 | 4 | 1 |
| Direct-map | 2968 | 7 | 4 | 4 | 1 |
| I-cache only | 3319 | 10 | 4 | 4 | 1 |
| **Full** | **3742** | **13** | 4 | 4 | 1 |

The full build uses **13 of 30 EBR blocks**: 4 hold the PicoRV32 register file,
and each cache data array adds 3 more — 3 for the Phase 1 icache way, 3 for the
Phase 2 second way, and 3 for the Phase 3 data cache (4 + 3 + 3 + 3 = 13). The
placed resource usage of the final build:

| Resource | Used | Available | Utilisation |
|---|---|---|---|
| ICESTORM_LC | **4618** | 5280 | **87%** |
| ICESTORM_RAM | 13 | 30 | 43% |
| ICESTORM_DSP | 4 | 8 | 50% |
| ICESTORM_SPRAM | 4 | 4 | 100% |
| ICESTORM_PLL | 1 | 1 | 100% |

### Timing

Static timing (icetime, `data/icebreaker_*.rpt`). Margin = clock period −
critical-path length.

| Build | Critical path (ns) | Max clock (MHz) | Run clock (MHz) | Margin (ns) |
|---|---|---|---|---|
| Baseline | 52.71 | 18.97 | 12.00 | 30.62 |
| No-cache | 45.32 | 22.07 | 18.75 | 8.01 |
| Direct-map | 42.22 | 23.69 | 18.75 | 11.11 |
| I-cache only | 47.93 | 20.87 | 18.75 | 5.40 |
| **Full** | **50.71** | **19.72** | **18.75** | **2.62** |

### Power

| Build | Power (W) |
|---|---|
| Baseline (12 MHz, no cache) | 0.76 |
| Full (18.75 MHz, icache + dcache) | 0.66 |

Board power fell by **0.10 W (13.2%)** despite the higher clock, primarily
because each cache hit replaces a multi-cycle QDDR flash transaction with a short
on-chip EBR access, cutting the dynamic switching activity on the SPI bus and
flash peripheral.

---

## Building the configurations

From `picorv32-main/picosoc/`, with the OSS CAD Suite environment active:

```bash
make icebreaker_baseline.bin      # Baseline: stock PicoSoC, 12 MHz, no cache
make icebreaker_nocache.bin       # No-cache: CPU opts + PLL, no cache
make icebreaker_directmap.bin     # Phase 1: 32-set direct-mapped icache
make icebreaker_icache_only.bin   # Phase 2: 32-set 2-way icache
make icebreaker.bin               # Full (Phase 3): icache + dcache

# Select the workload compiled into the firmware:
make FW=workloads/kalman_steady_state icebreaker_fw.bin
```

Raw Picoscope readings, synthesis logs, and timing reports for every build are
in `data/` (see `data/measurements.md`).
