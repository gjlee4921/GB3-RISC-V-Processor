# Hardware Measurements — GB3 RISC-V Cache Project

All measurements taken on iCEBreaker board (iCE40UP5K) at room temperature.
Performance measured via Picoscope on LED1 (GPIO bit 5). LED toggles once per
`run_workload()` iteration, producing a square wave whose half-period equals
one workload execution time.

---

## 1. Configuration Definitions

| Label | Verilog file | Clock | Instruction cache | Data cache | CPU parameters |
|---|---|---|---|---|---|
| **Baseline** | `picosoc_baseline.v` | 12 MHz (crystal, no PLL) | none | none | ENABLE_IRQ=1, ENABLE_COUNTERS=1, ENABLE_DIV=1, ENABLE_MUL=1, ENABLE_FAST_MUL=0, BARREL_SHIFTER=1 |
| **Nocache** | `picosoc_nocache.v` | 18.75 MHz (PLL, DIVF=49) | none | none | ENABLE_IRQ=0, ENABLE_COUNTERS=0, ENABLE_DIV=0, ENABLE_MUL=0, ENABLE_FAST_MUL=1, BARREL_SHIFTER=1 |
| **Direct-map** | `picosoc_directmap.v` | 18.75 MHz (PLL, DIVF=49) | 32-set, 1-way, 4-word lines — 512 B | none | same as nocache |
| **Icache only** | `picosoc_icache_only.v` | 18.75 MHz (PLL, DIVF=49) | 32-set, 2-way, 4-word lines — 1024 B | none | same as nocache |
| **Full** | `picosoc.v` | 18.75 MHz (PLL, DIVF=49) | 32-set, 2-way, 4-word lines — 1024 B | 32-set, 1-way, 4-word lines — 512 B | ENABLE_IRQ=0, ENABLE_COUNTERS=1, ENABLE_DIV=0, ENABLE_MUL=0, ENABLE_FAST_MUL=1, BARREL_SHIFTER=1 |

**Notes:**
- Baseline is synthesised with `-D NO_PLL`; all other builds use the shared `icebreaker.v` top level with PLL active.
- Direct-map icache uses the `dcache` module instantiated on the instruction fetch path.
- Full design re-enables `ENABLE_COUNTERS` (vs nocache/directmap/icache-only) for secret-benchmark compatibility; this does not affect the workloads measured here.
- ENABLE_DIV=0 in all PLL builds (overridden by `icebreaker.v`); kalman_steady_state does not use division.

---

## 2. Cycle Count Derivation

LED square-wave frequency `f` (Hz) → execution time per iteration:

```
T_exec = 1 / (2f)    [seconds]

Cycle count = f_clk × T_exec = f_clk / (2f)

Baseline  (12.00 MHz):  cycles = 6,000,000 / f_Hz
All other (18.75 MHz):  cycles = 9,375,000 / f_Hz
```

---

## 3. Performance — Raw Picoscope Measurements

Source: `workloads.txt` (Picoscope frequency counter; period column = T_exec = half-period of LED square wave)

### 3.1 kalman_steady_state (primary workload)

| Configuration | LED freq (Hz) | T_exec (ms) |
|---|---|---|
| Baseline | 4.144 | 120.7 |
| Nocache | 6.475 | 77.22 |
| Direct-map | 13.32 | 37.53 |
| Icache only | 16.36 | 30.57 |
| Full | 16.54 | 30.23 |

### 3.2 fibonacci_iterative

| Configuration | LED freq (Hz) | T_exec |
|---|---|---|
| Baseline | 263.4 | 1.898 ms |
| Nocache | 411.6 | 1.214 ms |
| Full | 799.7 | 625.2 μs |

### 3.3 fibonacci_recursive

| Configuration | LED freq (Hz) | T_exec (ms) |
|---|---|---|
| Baseline | 9.65 | 51.81 |
| Nocache | 15.08 | 33.16 |
| Full | 39.91 | 12.52 |

### 3.4 bubble_sort

| Configuration | LED freq (Hz) | T_exec (ms) |
|---|---|---|
| Baseline | 3.906 | 128.0 |
| Nocache | 6.104 | 81.92 |
| Full | 12.03 | 41.55 |

---

## 4. Performance — Derived Cycle Counts

### 4.1 kalman_steady_state

| Configuration | Cycles | T_exec (ms) |
|---|---|---|
| Baseline | 1,447,876 | 120.7 |
| Nocache | 1,447,877 | 77.22 |
| Direct-map | 703,604 | 37.53 |
| Icache only | 573,104 | 30.57 |
| Full | 566,807 | 30.23 |

### 4.2 fibonacci_iterative

| Configuration | Cycles | T_exec |
|---|---|---|
| Baseline | 22,779 | 1.898 ms |
| Nocache | 22,779 | 1.214 ms |
| Full | 11,723 | 625.2 μs |

### 4.3 fibonacci_recursive

| Configuration | Cycles | T_exec (ms) |
|---|---|---|
| Baseline | 621,762 | 51.81 |
| Nocache | 621,352 | 33.16 |
| Full | 234,978 | 12.52 |

### 4.4 bubble_sort

| Configuration | Cycles | T_exec (ms) |
|---|---|---|
| Baseline | 1,535,587 | 128.0 |
| Nocache | 1,535,716 | 81.92 |
| Full | 779,301 | 41.55 |

---

## 5. Performance — Speedup

### 5.1 Wall-clock speedup vs baseline (T_exec ratio)

| Workload | Full vs Baseline |
|---|---|
| kalman_steady_state | 3.99× |
| fibonacci_iterative | 3.04× |
| fibonacci_recursive | 4.14× |
| bubble_sort | 3.08× |

Wall-clock speedup = f_full / f_baseline = T_baseline / T_full.

### 5.2 Speedup decomposition (kalman_steady_state)

| Comparison | Metric | Value |
|---|---|---|
| Nocache vs Baseline (cycle count) | CPU parameter change | 1.00× |
| Nocache vs Baseline (wall clock) | PLL: 18.75 / 12 MHz | 1.5625× |
| Direct-map vs Nocache (cycle count) | 32-set direct-mapped icache | 2.06× |
| Icache-only vs Nocache (cycle count) | 32-set 2-way set-assoc icache | 2.53× |
| Full vs Nocache (cycle count) | icache + dcache | 2.55× |
| Full vs Icache-only (cycle count) | dcache contribution alone | 1.01× |
| Full vs Baseline (wall clock) | total speedup | 3.99× |

Total wall-clock speedup = PLL × cache = 1.5625 × 2.55 = 3.98× ≈ 3.99× (rounding in Picoscope readings).

### 5.3 Cycle count speedup vs nocache — all workloads (full design)

| Workload | Cycles nocache | Cycles full | Speedup |
|---|---|---|---|
| kalman_steady_state | 1,447,877 | 566,807 | 2.55× |
| fibonacci_iterative | 22,779 | 11,723 | 1.94× |
| fibonacci_recursive | 621,352 | 234,978 | 2.64× |
| bubble_sort | 1,535,716 | 779,301 | 1.97× |

---

## 6. Area

### 6.1 Yosys synthesis cell counts (post-synthesis, pre-placement)

Source: `icebreaker_*.log` (Yosys synthesis logs). These are netlist counts after technology mapping, before nextpnr place-and-route.

| Configuration | SB_LUT4 | SB_CARRY | FF total | EBR (SB_RAM40_4K) | DSP (SB_MAC16) | SPRAM (SB_SPRAM256KA) | PLL (SB_PLL40_PAD) |
|---|---|---|---|---|---|---|---|
| Baseline | 3357 | 743 | 1242 | 4 | 4 | 4 | 0 |
| Nocache | 2706 | 588 | 999 | 4 | 4 | 4 | 1 |
| Direct-map | 2968 | 588 | 1188 | 7 | 4 | 4 | 1 |
| Icache only | 3319 | 588 | 1257 | 10 | 4 | 4 | 1 |
| Full | 3742 | 712 | 1508 | 13 | 4 | 4 | 1 |

FF total = sum of SB_DFF + SB_DFFE + SB_DFFESR + SB_DFFESS + SB_DFFN + SB_DFFSR + SB_DFFSS.

EBR breakdown (SB_RAM40_4K = 4 Kb each):
- 4 EBR present in baseline and nocache: CPU register file (2 read ports, 32×32-bit)
- Direct-map adds 3 EBR vs nocache: direct-mapped icache data array
- Icache only adds 3 EBR vs direct-map: 2-way set-assoc icache data arrays (2 ways)
- Full adds 3 EBR vs icache only: data cache data array

Total EBR used: baseline 4/30, nocache 4/30, directmap 7/30, icache-only 10/30, full 13/30.

Device-fixed resources (same in all builds):
- SPRAM: 4/4 (100%) — iCE40UP5K 256 KB SRAM used as CPU main memory in all builds
- DSP: 4/8 (50%) — fast multiplier (`picorv32_pcpi_fast_mul`, enabled in all PLL builds via `ENABLE_FAST_MUL=1`)

### 6.2 Placed ICESTORM_LC count (nextpnr, from project documentation)

NextPnr output was not captured to file for all builds. Confirmed placed LC count:

| Configuration | ICESTORM_LC | Total | Utilisation |
|---|---|---|---|
| Full | 4618 | 5280 | **87%** |

### 6.3 LUT4 increment analysis

| Transition | ΔSB_LUT4 | Cause |
|---|---|---|
| Baseline → Nocache | −651 | ENABLE_IRQ=0 (−~600), ENABLE_COUNTERS=0 (−~143), ENABLE_DIV=0, ENABLE_FAST_MUL=1 |
| Nocache → Direct-map | +262 | Direct-mapped icache FSM + tag/valid registers |
| Direct-map → Icache only | +351 | Set-assoc upgrade: 2-way, LRU logic, larger FSM |
| Icache only → Full | +423 | Data cache FSM + tag/valid registers + BRAM arbiter + ENABLE_COUNTERS re-enabled (+~143) |

**Note on ENABLE_COUNTERS inconsistency:** Nocache, direct-map, and icache-only all have `ENABLE_COUNTERS=0` — counters were disabled as part of the initial area optimisation (~143 LC saving). The full design re-enables them (`ENABLE_COUNTERS=1`) because several secret-benchmark binaries execute `rdcycle`/`rdinstret` before the LED loop; with counters disabled these become illegal instructions and the CPU halts. Baseline also has `ENABLE_COUNTERS=1` (original PicoSoC default). This means the LUT4 counts for nocache/direct-map/icache-only are each ~143 lower than they would be with counters on, and the `icache-only → full` delta of +423 is inflated by ~143 (the true cost of adding the data cache alone is ~+280 LUT4). Area comparisons between the full design and baseline are unaffected since both have counters enabled.

---

## 7. Timing

Source: `icebreaker_*.rpt` (icetime topological timing analysis). icetime reports are conservative estimates (`max_span_hack` enabled).

| Configuration | Critical path (ns) | Max clock icetime (MHz) | Logic levels | Run clock (MHz) | Timing margin (ns) |
|---|---|---|---|---|---|
| Baseline | 52.71 | 18.97 | 13 | 12.00 | 30.62 |
| Nocache | 45.32 | 22.07 | 11 | 18.75 | 8.01 |
| Direct-map | 42.22 | 23.69 | 11 | 18.75 | 11.11 |
| Icache only | 47.93 | 20.87 | 12 | 18.75 | 5.40 |
| Full | 50.71 | 19.72 | 14 | 18.75 | 2.62 |

Timing margin = clock period − critical path.
- Baseline: 83.33 ns − 52.71 ns = 30.62 ns
- PLL builds: 53.33 ns − critical path

All configurations pass timing at their respective run clocks.

---

## 8. Power

Measured during active `run_workload()` loop (kalman_steady_state).

| Configuration | Power (W) |
|---|---|
| Baseline (12 MHz, no cache) | 0.76 |
| Full (18.75 MHz, icache + dcache) | 0.66 |

Power reduction: 0.10 W (13.2%).
