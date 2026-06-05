# Harvard-style Cache Architecture

This document covers the second phase of hardware optimisation, picking up
from where `set_associative_icache.md` left off. At the end of that phase,
the design occupied 5268/5280 LCs (99%) with no room for further hardware.

This phase introduces separate instruction and data caches — a **modified
Harvard architecture** in which instruction fetch and data read paths each
have their own dedicated cache backed by iCE40 EBR block RAM, while sharing
a single QDDR flash port. The development sequence was:

1. **Parameter optimisation** — disable unused CPU features to recover area
2. **Data cache** (`dcache.v`) — 32-set direct-mapped cache for `.rodata` reads
3. **PLL overclock** — 12 MHz → 18 MHz using the iCE40UP5K hard PLL block
4. **32-set instruction cache** — double icache capacity from 512 B to 1 KB
5. **PLL frequency increase** — 18.0 → 18.375 MHz after timing improved
6. **Final configuration** (§6) — re-enables the cycle counters and remaps the
   7-segment so other teams' secret-benchmark binaries run; disables the
   hardware divider to pay for it; and with the freed area keeps the 32-set
   icache and pushes the clock to **18.75 MHz**

> **Note:** Sections 1–5 are the development narrative. The **as-submitted**
> configuration is defined in **§6** — read that for the final parameter set.
> The headline benchmark is `kalman_steady_state` (the final build disables
> the hardware divider, so the full `kalman_filter` no longer runs on it).
> Final build: **32-set icache, divider off, counters on, 18.75 MHz, 4618 LC (87%)**.

---

## 1. Parameter Optimisation

### ENABLE_IRQ and ENABLE_COUNTERS

PicoRV32 contains two optional hardware blocks enabled by default in PicoSoC:

- **`ENABLE_IRQ=1`** — interrupt controller, dispatch FSM, and 32 IRQ vectors.
  None of the benchmark workloads use interrupts.
- **`ENABLE_COUNTERS=1`** — `rdcycle` and `rdinstret` CSR registers. These
  are only used in interactive firmware mode, not in the workload loop.

Setting both to 0 in `picosoc.v` removes this logic entirely from synthesis.
The area saving was much larger than estimated:

| Parameter change | Logic cells saved |
|---|---|
| `ENABLE_IRQ` 1 → 0 | ~600 LC |
| `ENABLE_COUNTERS` 1 → 0 | ~143 LC |
| **Total** | **743 LC** |

| | Before | After |
|---|---|---|
| Logic cells | 5268 / 5280 (99%) | **4525 / 5280 (85%)** |
| Spare LCs | 12 | **755** |
| Max clock (icetime) | 18.86 MHz | 20.41 MHz |

The large saving from `ENABLE_IRQ` comes from the interrupt controller's
internal state machine, priority encoder, and the irq signal fanout to every
stage of the CPU pipeline.

### Three-file design structure

Three separate `picosoc_*.v` files are maintained so all configurations can
be synthesised and measured independently:

| File | `ENABLE_IRQ` | `ENABLE_COUNTERS` | Cache | PLL |
|---|---|---|---|---|
| `picosoc_baseline.v` | 1 (original) | 1 (original) | none | no (12 MHz) |
| `picosoc_nocache.v` | 0 | 0 | none | yes (18.375 MHz) |
| `picosoc.v` | 0 | 0 | icache + dcache | yes (18.375 MHz) |

`picosoc_baseline.v` matches the original repository `picosoc.v` exactly and
is synthesised with `yosys -D NO_PLL` to run at stock 12 MHz.

---

## 2. Data Cache (`dcache.v`)

### Why it is now feasible

The failed attempt in the icache phase tried to add a dcache alongside 5268 LCs
of existing logic — it needed 5645 LCs (106%). With 755 LCs now spare, the
same class of design fits comfortably.

### Design: 32-set, direct-mapped, 4-word lines

The dcache is simpler than the icache:

- **Direct-mapped** (1 way, no LRU) — halves tag/valid storage vs 2-way
- **Read-only** — SPI flash is read-only; CPU writes go to SRAM or IO and
  never reach the dcache, so no dirty bits or write-back logic are needed
- **32 sets, 4-word (16-byte) lines** — 512 bytes capacity, enough to hold
  the Kalman filter's entire `.rodata` working set without conflict evictions

Address decomposition (24-bit flash address):

```
[23:9]  tag         (15 bits)
[8:4]   index        (5 bits → selects one of 32 sets)
[3:2]   word-in-line (2 bits)
[1:0]   byte offset  (always 00)
```

Storage:

| State | Storage | Why |
|---|---|---|
| tag / valid | logic-cell registers | 32 × 15-bit = 480 bits — small |
| data | **1 EBR block RAM** | 32 × 4 × 32-bit = 4096 bits = exactly 1 EBR |

Like the icache, data uses a **synchronous read** so Yosys maps it to EBR.
Hit latency is 2 cycles (cycle 0 = BRAM read + tag compare, cycle 1 = serve).

### Why 32 sets

The Kalman filter's constant matrices in `.rodata` total approximately
352 bytes:

- `F[4][4]` int64: 128 bytes = 8 cache lines
- `H[2][4]` int64: 64 bytes = 4 cache lines
- `Qm[4][4]` int64: 128 bytes = 8 cache lines
- `Rm[2][2]` int64: 32 bytes = 2 cache lines

With 16-set (256 bytes): the working set exceeds capacity, causing conflict
evictions and a hit rate below 100% after warmup.

With 32-set (512 bytes): all 352 bytes fit without conflicts. After the first
iteration, all matrix data is resident and the remaining 99 iterations run
entirely from cache. 32 sets is also the maximum that fits in a single EBR.

### Flash port sharing with icache

Both icache and dcache share the single spimemio flash port without an
arbiter. PicoRV32 has only one outstanding memory request at a time — when
`mem_instr=1` the icache is active; when `mem_instr=0` and the address is in
flash range the dcache is active. The two are mutually exclusive by CPU design.

---

## 3. PLL Overclock (initial: 12 → 18 MHz)

The iCE40UP5K contains one `SB_PLL40_PAD` hard block that consumes **0 logic
cells**. It takes the 12 MHz crystal input and generates a higher-frequency
system clock.

Initial settings (DIVF=47):

```
DIVR = 0, DIVF = 47, DIVQ = 5
VCO = 12 × (47 + 1) = 576 MHz   (within 533–1066 MHz range)
Output = 576 / 32 = 18.0 MHz
```

The PLL is instantiated in `icebreaker.v` (the shared top level) and gated
by a `NO_PLL` synthesis define — the baseline bitstream is synthesised with
`yosys -D NO_PLL` so it runs at 12 MHz, preserving a true stock comparison.
The reset counter waits for `pll_locked` before releasing reset.

---

## 4. 32-set Instruction Cache

### Motivation

The icache was originally 16-set, 2-way, giving 512 bytes capacity. After
adding dcache and PLL, 388 LCs remained spare. Doubling the icache to 32 sets
increases instruction cache capacity to **1024 bytes** at minimal extra cost,
reducing cold-miss and conflict-miss stalls for workloads with a larger hot
instruction footprint.

### Change

In `icache.v`, `parameter NSETS = 16` → `parameter NSETS = 32`. The entire
address decomposition uses `$clog2(NSETS)` and adjusts automatically:

| Parameter | 16-set | 32-set |
|---|---|---|
| INDEX_BITS | 4 | 5 |
| TAG_BITS | 16 | 15 |
| Data per way | 64 × 32-bit = 2048 bits | 128 × 32-bit = 4096 bits |
| EBR per way | 1 (half-filled) | 1 (full) |
| Total EBR for icache | 2 | 2 (unchanged) |

The EBR count is unchanged because the 16-set arrays were already mapped to
dedicated EBRs; doubling the depth fills them completely without needing
additional block RAM.

### Area and timing

| Metric | Before (16-set) | After (32-set) |
|---|---|---|
| Logic cells | 4892 / 5280 (92%) | **5076 / 5280 (96%)** |
| LC cost | — | +184 LC |
| ICESTORM_RAM | 13 / 30 | **13 / 30 (unchanged)** |
| icetime max | 19.01 MHz | **19.39 MHz** |
| Critical path | 52.77 ns | **51.57 ns** |
| Spare LCs | 388 | **204** |

The critical path shortened by 1.2 ns due to improved nextpnr placement at
the higher utilisation level. This timing headroom enabled the PLL upgrade
in section 5.

---

## 5. PLL Frequency Increase: 18.0 → 18.375 MHz

After the 32-set icache expansion, the critical path improved from 52.77 ns
to **51.57 ns** (19.39 MHz icetime max, up from 19.01 MHz). This gave a
**2.85 ns margin** at 18.375 MHz — compared to the 2.79 ns that existed at
18.0 MHz before the expansion. With slightly more headroom available, the
PLL was bumped one step:

```
DIVR = 0, DIVF = 48, DIVQ = 5
VCO = 12 × (48 + 1) = 588 MHz
Output = 588 / 32 = 18.375 MHz
icetime: 19.39 MHz max → PASS at 18.38 MHz (2.85 ns margin)
```

18.375 MHz was chosen over 18.75 MHz (DIVF=49, 1.76 ns margin) after
analysing which workload stresses the critical path most: **bubble_sort**,
with its near-continuous SRAM array accesses, exercises the memory-interface
critical path 3–5× more frequently per clock cycle than kalman_filter. At
2.85 ns margin bubble_sort runs reliably; at 1.76 ns the risk is harder to
guarantee across all possible secret benchmarks.

### Effect on cycle formula

| Clock | Cycles per iteration formula |
|---|---|
| 12 MHz (baseline) | `cycles = 6,000,000 / f_Hz` |
| 18.375 MHz (nocache + full design) | `cycles = 9,187,500 / f_Hz` |

---

## 6. Final Configuration (Secret-Benchmark Compatibility)

The cross-evaluation requires running **other teams' compiled benchmark
binaries** on this processor. Three incompatibilities surfaced, each forcing
a configuration change away from the pure performance-optimised build of §1–5.

### 6.1 Re-enable the cycle counters (`ENABLE_COUNTERS = 1`)

Several secret binaries call a timed wrapper that executes `rdcycle` /
`rdinstret` (for CPI measurement) **before** entering the LED loop. With
`ENABLE_COUNTERS = 0` these CSR reads are not decoded as counter instructions
in PicoRV32 (`picorv32.v` gates them on `ENABLE_COUNTERS`); they become
**illegal instructions**, and with `ENABLE_IRQ = 0` the core traps and halts.
The binary therefore hangs before displaying anything — no LED, no 7-seg.

Re-enabling the counters (~143 LC) makes `rdcycle`/`rdinstret` legal so those
binaries run to completion.

### 6.2 Disable the hardware divider (`ENABLE_DIV = 0`)

The counters had to be paid for in area. Since the final headline benchmark is
`kalman_steady_state` — which is `int32` multiply-and-shift only, with **no
division** — the divider is dead weight and was disabled in `icebreaker.v`
(`.ENABLE_DIV(0)`). This frees enough area to absorb the counters.

**Consequence:** the full `kalman_filter` (which needs `__divdi3` → hardware
`DIV`) can no longer run on this build. That is an accepted trade: the divider
is the single largest CPU block, and the chosen benchmark does not use it.

### 6.3 Icache: 16-set transient, then restored to 32-set

When the counters were first re-enabled **while the divider was still present**,
utilisation hit ~99% and routing congestion failed timing. The icache was
temporarily reverted to 16-set to relieve it. However, once the divider was
disabled (§6.2) it freed ~660 LC net — far more than the icache costs — so the
**32-set icache was restored** and still fits comfortably at **87%** with a
better timing margin than the 16-set build had. The 16-set revert was therefore
only a transient debugging step; the final build is **32-set**.

### 6.4 Remap the 7-segment to `0x03000001`

Every secret binary writes its two outputs to adjacent bytes:

| Address | Role |
|---|---|
| `0x03000000` | LED (toggles `0x02` → LED1) |
| `0x03000001` | 7-segment (the `run_workload()` answer) |

The original design decoded the 7-seg at `0x03000004`, so every secret
benchmark's 7-seg stayed blank. `0x03000001` is an **odd** byte address, so a
byte store lands on **byte lane 1** (`iomem_wstrb[1]`, data in
`iomem_wdata[15:8]`). The `icebreaker.v` decode was changed accordingly:

```verilog
if (iomem_wstrb[0] && iomem_addr[7:0] == 8'h00) gpio[7:0] <= iomem_wdata[7:0];  // LED  @ 0x03000000
if (iomem_wstrb[1])                              seg7_val <= iomem_wdata[15:8]; // 7seg @ 0x03000001
```

### 6.5 PLL frequency increase to 18.75 MHz

Disabling the divider also shortened the critical path: icetime now reports a
**19.72 MHz** maximum (50.71 ns path), up from 19.39 MHz. That headroom allowed
one more PLL step:

```
DIVR = 0, DIVF = 49, DIVQ = 5
VCO = 12 × (49 + 1) = 600 MHz
Output = 600 / 32 = 18.75 MHz
icetime: 19.72 MHz max → PASS at 18.75 MHz (2.62 ns margin)
```

At 18.375 MHz the 18.75 step had only 1.76 ns margin and was rejected (§5); now,
with the divider gone, 18.75 MHz has **2.62 ns** — comparable to the margin that
bubble_sort was already validated at — so it is safe. This is a free +2% clock.

### Final parameter set (effective, as synthesised)

`icebreaker.v` instantiation overrides `picosoc.v` defaults — the values below
are what actually reach PicoRV32:

| Parameter | Value | Set in | Rationale |
|---|---|---|---|
| `BARREL_SHIFTER` | 1 | `icebreaker.v` | single-cycle shifts (fixed-point `>>`) |
| `ENABLE_MUL` | 0 | `icebreaker.v` | superseded by FAST_MUL |
| `ENABLE_FAST_MUL` | 1 | `icebreaker.v` | DSP-based single-cycle multiply |
| `ENABLE_DIV` | **0** | `icebreaker.v` | benchmark needs no division; frees area (§6.2) |
| `ENABLE_COMPRESSED` | 0 | `icebreaker.v` | handout mandates `-march=rv32im` (no C) |
| `ENABLE_COUNTERS` | **1** | `picosoc.v` default | secret binaries use `rdcycle`/`rdinstret` (§6.1) |
| `ENABLE_IRQ` | 0 | `picosoc.v` | no interrupts used by any workload |
| Instruction cache | **32-set**, 2-way, 4-word (1 KB) | `icache.v` | restored after divider freed area (§6.3) |
| Data cache | 32-set, direct-mapped, 4-word (512 B) | `dcache.v` | unchanged |
| 7-seg address | `0x03000001` | `icebreaker.v` | secret-benchmark convention (§6.4) |
| System clock | **18.75 MHz** (PLL, DIVF=49) | `icebreaker.v` | overclock; passes timing (§6.5) |

---

## Hardware Measurements

All measurements on iCEBreaker (iCE40UP5K). LED toggles once per iteration;
Picoscope reads the toggle frequency. The §1–5 tables below were taken on the
32-set / divider-on development build with `kalman_filter`; the final
as-submitted build (§6) uses `kalman_steady_state` and 16-set — re-measure
there for the figures quoted in the report.

### Commands

```bash
# Baseline — stock PicoSoC, no PLL (12 MHz)
make FW=workloads/kalman_filter icebprog_baseline

# Nocache — CPU opts + PLL, no cache (18.375 MHz)
make FW=workloads/kalman_filter icebprog_nocache

# Full design — CPU opts + icache (32-set) + dcache + PLL (18.375 MHz)
make FW=workloads/kalman_filter icebprog
```

### Three-way Kalman Filter comparison

| Configuration | Clock | Picoscope freq | Calculated cycles |
|---|---|---|---|
| Baseline — stock PicoSoC, no cache | 12 MHz | ~204 mHz | ~29,400,000 |
| Nocache — CPU opts, no cache | 18.375 MHz | ~312.8 mHz | ~29,373,000 |
| Full design — icache (32-set) + dcache + PLL | 18.375 MHz | **672.7 mHz** | **13,661,000** |

### Speedup breakdown

| Contribution | Measurement | Multiplier |
|---|---|---|
| PLL clock (12 → 18.375 MHz) | 312.8 / 204 mHz | **1.53×** |
| CPU parameter opts (IRQ/counters off) | 312.8 / 204 mHz | **~1.0×** (no effect on kalman) |
| Icache (16-set) + barrel shifter, phase 1 | 412.2 / 204 mHz at 12 MHz | **2.02×** cache |
| + Dcache 32-set | 645.4 / 306.4 mHz at 18 MHz | **2.11×** cache |
| + Icache expanded to 32-set | 659.0 / 306.4 mHz at 18 MHz | **2.15×** cache |
| + PLL to 18.375 MHz | 672.7 / 312.8 mHz | **2.15×** cache (ratio unchanged) |
| **Total vs original stock at 12 MHz** | 672.7 / 204 mHz | **3.30×** |

The CPU parameter optimisations contribute no runtime improvement to the
Kalman filter (it uses neither interrupts nor cycle-counter instructions) —
their value is purely area: 743 LCs freed, making dcache and PLL feasible.

Cache contribution across phases:
- Icache only (phase 1, 12 MHz): **2.02×**
- + Dcache 32-set (18 MHz): **2.11×**
- + Icache expanded to 32-set: **2.15×**
- + PLL 18.375 MHz: **2.15×** (clock faster, cache ratio identical)

### Resource summary — §5 development build (32-set, divider on, counters off)

| Resource | Used | Total | Utilisation |
|---|---|---|---|
| Logic cells (ICESTORM_LC) | 5076 | 5280 | **96%** |
| Block RAM (ICESTORM_RAM) | 13 | 30 | 43% |
| PLL (ICESTORM_PLL) | 1 | 1 | 100% |
| DSP (ICESTORM_DSP) | 4 | 8 | 50% |
| SPRAM (ICESTORM_SPRAM) | 4 | 4 | 100% |
| Max clock (icetime) | 19.39 MHz | — | PASS at 18.38 MHz |
| Spare LCs | 204 | — | — |

### Resource summary — §6 final build (32-set, divider off, counters on, 18.75 MHz)

This is the **as-submitted** configuration (Group 4) that runs the
secret-benchmark binaries. Disabling the divider frees the single largest CPU
block, which more than offsets re-enabling the counters — so even with the
32-set icache restored, utilisation is only **87%** and timing closes at the
higher 18.75 MHz clock.

| Resource | Used | Total | Utilisation |
|---|---|---|---|
| Logic cells (ICESTORM_LC) | **4618** | 5280 | **87%** |
| Block RAM (ICESTORM_RAM) | 13 | 30 | 43% |
| SB_IO | 24 | 39 | 61% |
| Global buffers (SB_GB) | 7 | 8 | 87% |
| PLL (ICESTORM_PLL) | 1 | 1 | 100% |
| DSP (ICESTORM_DSP) | 4 | 8 | 50% |
| SPRAM (ICESTORM_SPRAM) | 4 | 4 | 100% |
| Max clock (icetime) | 19.72 MHz | — | **PASS at 18.75 MHz** |
| Timing margin | 2.62 ns | — | (53.33 ns period − 50.71 ns path) |
| Spare LCs | 662 | — | — |

All other resource categories (SB_WARMBOOT, HFOSC, LFOSC, I2C, SPI, I3C,
LEDDA_IP, RGBA_DRV) are 0.

**Configuration:** icache 32-set/2-way/4-word (1 KB); dcache 32-set/direct/4-word
(512 B); `ENABLE_DIV=0`, `ENABLE_COUNTERS=1`; 7-seg at `0x03000001`; 18.75 MHz PLL.

Note the contrast with the §5 build (5076 LC / 96%): even after re-enabling the
counters and keeping the 32-set icache, the final build is **4618 LC (87%)** —
removing the divider saved ~640 LC net, confirming it was by far the most
expensive single CPU feature and the right block to drop once the benchmark
(`kalman_steady_state`) no longer needed it.
