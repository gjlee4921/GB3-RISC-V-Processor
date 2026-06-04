# Harvard-style Cache Architecture

This document covers the second phase of hardware optimisation, picking up
from where `set_associative_icache.md` left off. At the end of that phase,
the design occupied 5268/5280 LCs (99%) with no room for further hardware.

This phase introduces separate instruction and data caches — a **modified
Harvard architecture** in which instruction fetch and data read paths each
have their own dedicated cache backed by iCE40 EBR block RAM, while sharing
a single QDDR flash port. Four changes are made in sequence:

1. **Parameter optimisation** — disable unused CPU features to recover area
2. **Data cache** (`dcache.v`) — 32-set direct-mapped cache for `.rodata` reads
3. **PLL overclock** — 12 MHz → 18 MHz using the iCE40UP5K hard PLL block
4. **32-set instruction cache** — double icache capacity from 512 B to 1 KB

Combined result: **3.23× total speedup** on the Kalman filter benchmark
versus the original stock hardware at 12 MHz.

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
| `picosoc_nocache.v` | 0 | 0 | none | yes (18 MHz) |
| `picosoc.v` | 0 | 0 | icache + dcache | yes (18 MHz) |

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

## 3. PLL Overclock

The iCE40UP5K contains one `SB_PLL40_PAD` hard block that consumes **0 logic
cells**. It takes the 12 MHz crystal input and generates an 18 MHz system clock.

### Settings (12 MHz → 18 MHz)

```
DIVR = 0, DIVF = 47, DIVQ = 5
VCO = 12 × (47 + 1) / 1 = 576 MHz   (within 533–1066 MHz range)
Output = 576 / 2^5 = 18.0 MHz
```

The PLL is instantiated in `icebreaker.v` (the shared top level) and gated
by a `NO_PLL` synthesis define — the baseline bitstream is synthesised with
`yosys -D NO_PLL` so it runs at 12 MHz, preserving a true stock comparison.
The reset counter waits for `pll_locked` before releasing reset.

### Effect on cycle formula

| Clock | Cycles per iteration formula |
|---|---|
| 12 MHz (baseline) | `cycles = 6,000,000 / f_Hz` |
| 18 MHz (nocache + full design) | `cycles = 9,000,000 / f_Hz` |

---

## 4. 32-set Instruction Cache

### Motivation

The icache was originally 16-set, 2-way, giving 512 bytes capacity. After
adding dcache and PLL (phase 2 above), 388 LCs remained spare. Doubling the
icache to 32 sets increases instruction cache capacity to **1024 bytes** at
minimal extra cost, potentially reducing cold-miss and conflict-miss stalls
for workloads with a larger hot instruction footprint.

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
| Timing at 18 MHz | PASS | **PASS** |
| Spare LCs | 388 | **204** |

---

## Hardware Measurements

All measurements on iCEBreaker (iCE40UP5K), `kalman_filter.c` workload.
LED toggles once per iteration; Picoscope reads the toggle frequency.

### Commands

```bash
# Baseline — stock PicoSoC, no PLL (12 MHz)
make FW=workloads/kalman_filter icebprog_baseline

# Nocache — CPU opts + PLL, no cache (18 MHz)
make FW=workloads/kalman_filter icebprog_nocache

# Full design — CPU opts + icache (32-set) + dcache + PLL (18 MHz)
make FW=workloads/kalman_filter icebprog
```

### Three-way Kalman Filter comparison

| Configuration | Clock | Picoscope freq | Calculated cycles |
|---|---|---|---|
| Baseline — stock PicoSoC, no cache | 12 MHz | ~204 mHz | ~29,400,000 |
| Nocache — CPU opts, no cache | 18 MHz | 306.4 mHz | 29,373,000 |
| Full design — icache (32-set) + dcache + PLL | 18 MHz | **659.0 mHz** | **13,657,000** |

### Speedup breakdown

| Contribution | Calculation | Multiplier |
|---|---|---|
| PLL clock (12 → 18 MHz) | 306.4 / 204 mHz | **1.50×** |
| CPU parameter opts (IRQ/counters off) | 306.4 / 204 mHz | **~1.0×** (no effect on kalman) |
| Icache (16-set) + barrel shifter, phase 1 | 412.2 / 204 mHz at 12 MHz | **2.02×** |
| + Dcache (32-set) | 645.4 / 306.4 mHz | **2.11×** cache total |
| + Icache expanded to 32-set | 659.0 / 306.4 mHz | **2.15×** cache total |
| **Total vs original stock at 12 MHz** | 659.0 / 204 mHz | **3.23×** |

The CPU parameter optimisations contribute no runtime improvement to the
Kalman filter (it uses neither interrupts nor cycle-counter instructions) —
their value is purely area: 743 LCs freed, making dcache and PLL feasible.

The cache contribution improved across phases:
- Icache only (phase 1, 12 MHz): **2.02×**
- + Dcache 32-set (18 MHz): **2.11×**
- + Icache expanded to 32-set: **2.15×**

### Final design resource summary

| Resource | Used | Total | Utilisation |
|---|---|---|---|
| Logic cells (ICESTORM_LC) | 5076 | 5280 | **96%** |
| Block RAM (ICESTORM_RAM) | 13 | 30 | 43% |
| PLL (ICESTORM_PLL) | 1 | 1 | 100% |
| DSP (ICESTORM_DSP) | 4 | 8 | 50% |
| SPRAM (ICESTORM_SPRAM) | 4 | 4 | 100% |
| Max clock (icetime) | 19.39 MHz | — | PASS at 18 MHz |
| Spare LCs | 204 | — | — |

With 204 LCs spare and timing passing comfortably at 18 MHz, the design is
at practical capacity for this device. The only remaining hardware option
without a complete redesign would be pushing the PLL to 18.75 MHz (DIVF=49,
VCO=600 MHz) — icetime now gives a 1.76 ns margin at that frequency, though
it carries hardware risk.
