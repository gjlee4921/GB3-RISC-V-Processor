# Data Cache, Parameter Optimisation, and PLL Overclock

This document covers the second phase of hardware optimisation, picking up
from where `set_associative_icache.md` left off. At the end of that phase,
the design occupied 5268/5280 LCs (99%) — leaving only 12 cells spare and
no room for any further hardware. This phase freed that area via CPU parameter
changes, then used it to add a data cache and a PLL overclock.

The three changes in order:

1. **Parameter optimisation** — disable unused CPU features to recover area
2. **Data cache** — 32-set direct-mapped dcache for `.rodata` flash reads
3. **PLL overclock** — 12 MHz → 18 MHz using the iCE40UP5K hard PLL block

Combined result: **3.16× total speedup** on the Kalman filter benchmark
versus the original stock hardware at 12 MHz.

---

## 1. Parameter Optimisation

### ENABLE_IRQ and ENABLE_COUNTERS

PicoRV32 contains two optional hardware blocks enabled by default in PicoSoC:

- **`ENABLE_IRQ=1`** — interrupt controller, dispatch FSM, and 32 IRQ vectors.
  None of the benchmark workloads use interrupts.
- **`ENABLE_COUNTERS=1`** — `rdcycle` and `rdinstret` CSR registers. These
  are only used in the interactive firmware `[B]` mode, not in the workload
  loop.

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
stage of the CPU pipeline — collectively much more expensive than the
register-file additions alone.

### Three-file design structure

Rather than modifying a single file, three separate `picosoc_*.v` files are
maintained so that all three configurations can be synthesised and measured
independently:

| File | `ENABLE_IRQ` | `ENABLE_COUNTERS` | Cache |
|---|---|---|---|
| `picosoc_baseline.v` | 1 (original) | 1 (original) | none |
| `picosoc_nocache.v` | 0 | 0 | none |
| `picosoc.v` | 0 | 0 | icache + dcache |

`picosoc_baseline.v` matches the original repository `picosoc.v` exactly
(no icache wiring, original CPU defaults) and is synthesised without PLL —
it runs at the stock 12 MHz. `picosoc_nocache.v` and `picosoc.v` both use
the PLL at 18 MHz.

---

## 2. Data Cache

### Why it is now feasible

The failed attempt in the icache phase tried to add an 8-set direct-mapped
dcache alongside 5268 LCs of existing logic — it needed 5645 LCs (106%).
With 755 LCs now spare, the same class of design fits comfortably.

### Design: 32-set, direct-mapped, 4-word lines (`dcache.v`)

The dcache is intentionally simpler than the icache:

- **Direct-mapped** (1 way, no LRU) — halves tag/valid storage versus 2-way
- **Read-only** — SPI flash is read-only, so no dirty bits or write-back logic
  are needed. CPU writes go to SRAM or IO and never reach the dcache.
- **32 sets, 4-word (16-byte) lines** — 32 × 4 × 4 = 512 bytes total
  capacity, enough to hold the Kalman filter's entire `.rodata` working set
  without conflict evictions

Address decomposition (24-bit flash address):

```
[23:8]  tag         (16 bits)
[7:4]   index        (5 bits → selects one of 32 sets)
[3:2]   word-in-line (2 bits)
[1:0]   byte offset  (always 00)
```

Storage:

| State | Storage | Why |
|---|---|---|
| tag / valid | logic-cell registers | 32 × 16-bit = 512 bits — small |
| data | **1 EBR block RAM** | 32 × 4 × 32-bit = 4096 bits = exactly 1 EBR |

Like the icache, data uses a **synchronous read** so Yosys maps it to EBR.
Hit latency is 2 cycles (cycle 0 = BRAM read + tag compare, cycle 1 = serve).

### Why 32 sets specifically

The Kalman filter's constant matrices in `.rodata` total approximately
352 bytes across 100 filter iterations:

- `F[4][4]` int64: 128 bytes = 8 cache lines
- `H[2][4]` int64: 64 bytes = 4 cache lines
- `Qm[4][4]` int64: 128 bytes = 8 cache lines
- `Rm[2][2]` int64: 32 bytes = 2 cache lines

With 16-set (256 bytes): the working set exceeds capacity, causing conflict
evictions between matrices and a hit rate below 100%.

With 32-set (512 bytes): all 352 bytes fit without conflicts. After the first
iteration, all matrix data is resident and all subsequent 99 iterations run
entirely from cache.

32 sets is also the maximum that fits in a single EBR (128 × 32-bit entries).
Going to 64 sets would require a second EBR for no benefit to this workload.

### Flash port sharing with icache

Both icache and dcache share the single spimemio flash port. This works
without an arbiter because PicoRV32 has only one outstanding memory request
at a time: when `mem_instr=1` the icache is active; when `mem_instr=0` and
the address is in flash range the dcache is active. The two are mutually
exclusive by CPU design, so `spimemio.valid = icache_flash_valid || dcache_flash_valid`
and each cache sees `spimem_flash_ready` directly without masking.

### Area cost

| Design | Logic cells | vs previous |
|---|---|---|
| Icache + barrel (phase 1) | 5268 / 5280 (99%) | — |
| After parameter optimisation | 4525 / 5280 (85%) | −743 LC |
| + dcache (32-set) | 4809 / 5280 (91%) | +284 LC |
| + PLL (hard block) | **4892 / 5280 (92%)** | +83 LC |

---

## 3. PLL Overclock

The iCE40UP5K contains one `SB_PLL40_PAD` hard block that consumes **0 logic
cells** — it is a dedicated silicon block separate from the LC fabric. It takes
the 12 MHz crystal input and generates a higher-frequency system clock.

### Settings (12 MHz → 18 MHz)

```
DIVR = 0, DIVF = 47, DIVQ = 5
VCO = 12 × (47 + 1) / 1 = 576 MHz   (within 533–1066 MHz range)
Output = 576 / 2^5 = 18.0 MHz
```

icetime reports 19.01 MHz maximum for the routed design, giving a **3 ns
timing margin** at 18 MHz. nextpnr confirms `PASS at 18.00 MHz`.

The PLL is instantiated in `icebreaker.v` (the shared top level) and gated
by a `NO_PLL` synthesis define — the baseline bitstream is synthesised with
`yosys -D NO_PLL` so it runs at 12 MHz, preserving a true stock comparison.

The reset counter waits for `pll_locked` before releasing reset, ensuring
the CPU does not start until the PLL has achieved lock.

### Effect on cycle formula

| Clock | Cycles per iteration formula |
|---|---|
| 12 MHz (baseline) | `cycles = 6,000,000 / f_Hz` |
| 18 MHz (nocache + full design) | `cycles = 9,000,000 / f_Hz` |

---

## Hardware Measurements

All measurements on iCEBreaker (iCE40UP5K), `kalman_filter.c` workload.
LED toggles once per iteration; Picoscope reads the toggle frequency.

### Commands

Flash each configuration in turn and measure the LED frequency on the Picoscope:

```bash
# Baseline — stock PicoSoC, no PLL (12 MHz)
make FW=workloads/kalman_filter icebprog_baseline

# Nocache — CPU opts + PLL, no cache (18 MHz)
make FW=workloads/kalman_filter icebprog_nocache

# Full design — CPU opts + icache + dcache + PLL (18 MHz)
make FW=workloads/kalman_filter icebprog
```

Each command compiles the firmware and flashes both the bitstream and firmware
in one step. The bitstream is only rebuilt if `.v` files have changed since the
last synthesis run; otherwise it skips straight to flashing.

### Three-way Kalman Filter comparison

| Configuration | Clock | Picoscope freq | Calculated cycles |
|---|---|---|---|
| Baseline — stock PicoSoC, no cache | 12 MHz | ~204 mHz | ~29,400,000 |
| Nocache — CPU opts (no IRQ/counters), no cache | 18 MHz | 306.4 mHz | 29,373,000 |
| Full design — CPU opts + icache + dcache | 18 MHz | **645.4 mHz** | **13,944,000** |

### Speedup breakdown

| Contribution | Calculation | Multiplier |
|---|---|---|
| PLL clock (12 → 18 MHz) | 306.4 / 204 mHz | **1.50×** |
| CPU parameter opts (IRQ/counters off) | 306.4 / 204 mHz | **~1.0×** (no effect on kalman) |
| Instruction cache + data cache | 645.4 / 306.4 mHz | **2.11×** |
| **Total vs original stock at 12 MHz** | 645.4 / 204 mHz | **3.16×** |

The CPU parameter optimisations (`ENABLE_IRQ=0`, `ENABLE_COUNTERS=0`)
contribute no runtime improvement to the Kalman filter because the workload
uses neither interrupts nor cycle-counter instructions. Their value is
purely area: they freed 743 LCs, making the data cache and PLL feasible.

The cache contribution improved from **2.02×** (icache + barrel shifter only,
measured in phase 1) to **2.11×** — the ~5% increase comes from the dcache
eliminating flash stalls for the 352 bytes of `.rodata` matrix data that
are reread on every filter iteration.

### Final design resource summary

| Resource | Used | Total | Utilisation |
|---|---|---|---|
| Logic cells (ICESTORM_LC) | 4892 | 5280 | **92%** |
| Block RAM (ICESTORM_RAM) | 13 | 30 | 43% |
| PLL (ICESTORM_PLL) | 1 | 1 | 100% |
| DSP (ICESTORM_DSP) | 4 | 8 | 50% |
| SPRAM (ICESTORM_SPRAM) | 4 | 4 | 100% |
| Max clock (icetime) | 19.01 MHz | — | PASS at 18 MHz |
