# RISC-V Instruction & Data Cache on the iCE40UP5K

A custom instruction/data cache system for the PicoRV32 RISC-V soft processor,
implemented on the iCEBreaker v1.0b (Lattice iCE40UP5K, 5280 LC, 30 EBR).

## Project overview

A Harvard split-cache system was inserted into the PicoRV32/PicoSoC memory
bus to eliminate instruction-fetch stalls caused by repeated QDDR SPI flash
transactions. Three phases were implemented (each documented in `docs/`):

- **Phase 1** — 32-set, direct-mapped instruction cache with 4-word lines and EBR-backed synchronous reads (512 B, `dcache` module on instruction path) — [`docs/direct_mapped_icache.md`](docs/direct_mapped_icache.md)
- **Phase 2** — upgrade to 2-way set-associativity (1 KB, `icache` module) — [`docs/set_associative_icache.md`](docs/set_associative_icache.md)
- **Phase 3** — 32-set, direct-mapped data cache for `.rodata` flash constants (512 B, `dcache` module on data path), plus area recovery and PLL overclock — [`docs/harvard_cache.md`](docs/harvard_cache.md)

A PLL overclock from 12 MHz to 18.75 MHz was enabled alongside the cache work.

Primary benchmark: `kalman_steady_state` — 3.99× wall-clock speedup (1.56× PLL,
2.55× cache cycle reduction). Final build: 4618/5280 LC (87%), 13/30 EBR, 2.62 ns timing margin.

---

## What this builds on

This is **not** a from-scratch SoC. It starts from the **PicoRV32** RISC-V CPU
core and the **PicoSoC** reference system-on-chip — both by Claire Xenia Wolf /
YosysHQ, from [github.com/YosysHQ/picorv32](https://github.com/YosysHQ/picorv32)
(ISC licensed; the upstream license is kept at
[`picorv32-main/COPYING`](picorv32-main/COPYING)). PicoSoC provides the CPU, the
QDDR SPI-flash controller (`spimemio`), the UART, the SPRAM, and the iCEBreaker
top level. The cache system is the work added on top of that base.

The FPGA toolchain — **Yosys** (synthesis), **nextpnr** (place & route), and
**icetime / icepack / iceprog** (timing and programming) — is also from YosysHQ,
distributed in the [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build).
These are external tools and are not included in this repository.

### Files created for this project (the cache work)

| File | Role |
|------|------|
| `picosoc/icache.v` | 2-way set-associative instruction cache (Phase 2) |
| `picosoc/dcache.v` | direct-mapped cache (icache path in Phase 1, data cache in Phase 3) |
| `picosoc/picosoc_nocache.v`, `picosoc_directmap.v`, `picosoc_icache_only.v` | build variants derived from `picosoc.v` for each phase |
| `picosoc/tb_direct.v` | directed cache integration testbench |
| `picosoc/performance.py` | speedup plot from measurements |
| `picosoc/workloads/*.c` | benchmark programs + host-side correctness tests |
| `cache_testbenches/*.v` | standalone cache unit/integration testbenches |
| `data/*` | all measurement data, synthesis logs, and waveform captures |

### Upstream files modified

| File | Change |
|------|--------|
| `picosoc/picosoc.v` | inserted the icache/dcache into the PicoRV32 memory bus |
| `picosoc/icebreaker.v` | added the PLL, 7-segment remap, and CPU feature overrides (`ENABLE_DIV=0`, etc.) |
| `picosoc/firmware.c` | `run_workload()` harness and LED/7-seg output loop |
| `picosoc/icebreaker_tb.v` | extended the simulation cycle budget |
| `picosoc/Makefile` | added the cache sources and the five build-variant targets |

### Upstream files used unchanged

`picorv32-main/picorv32.v` (CPU core), and in `picosoc/`: `picosoc_baseline.v`
(the original PicoSoC configuration, used as the baseline), `spimemio.v`,
`simpleuart.v`, `ice40up5k_spram.v`, `spiflash.v`, `spiflash_tb.v`, `start.s`,
`sections.lds`, and `icebreaker.pcf`.

---

## Directory structure

```
GB3-RISC-V-Processor/
├── README.md                      this file
├── data/                          measurement data, synthesis logs, waveform captures
│   ├── measurements.md            all raw Picoscope readings, derived cycle counts, speedup tables
│   ├── workloads.txt              raw LED frequency readings per workload
│   ├── icebreaker_*.log           Yosys synthesis logs for each build
│   ├── icebreaker_*.rpt           icetime timing reports for each build
│   ├── *.png / *.pdf              Picoscope waveform captures (5 builds × kalman_steady_state)
│   └── *.png                      block diagram, address decomposition, handshake diagrams
└── picorv32-main/
    ├── picorv32.v                 PicoRV32 CPU core (upstream YosysHQ)
    ├── cache_testbenches/        standalone cache unit testbenches (iverilog)
    │   ├── dmap_evict_tb.v        direct-mapped cache eviction test
    │   ├── dmap_hit_miss_latency_tb.v  hit/miss latency timing test
    │   ├── dmap_hotloop_tb.v      hot inner-loop hit-rate test
    │   └── harv_caches_validation_tb.v Harvard split-cache integration test
    └── picosoc/
        ├── Makefile               all build targets (see below)
        ├── icache.v               2-way set-associative instruction cache
        ├── dcache.v               direct-mapped data/instruction cache
        ├── picosoc.v              full build (icache + dcache, ENABLE_COUNTERS=1)
        ├── picosoc_baseline.v     12 MHz, no cache, original PicoSoC parameters
        ├── picosoc_nocache.v      18.75 MHz PLL, no cache, reduced CPU features
        ├── picosoc_directmap.v    18.75 MHz, 32-set direct-mapped icache only
        ├── picosoc_icache_only.v  18.75 MHz, 2-way set-assoc icache only
        ├── icebreaker.v           top-level iCEBreaker wrapper (PLL, I/O, 7-seg)
        ├── icebreaker.pcf         iCEBreaker pin constraints
        ├── spimemio.v             QDDR SPI flash controller
        ├── simpleuart.v           UART peripheral
        ├── ice40up5k_spram.v      iCE40UP5K SPRAM simulation model
        ├── spiflash.v             SPI flash simulation model
        ├── firmware.c             workload runner firmware (main entry point)
        ├── start.s                RISC-V startup assembly
        ├── sections.lds           linker script template
        ├── icebreaker_sections.lds  compiled linker script for iCEBreaker
        ├── icebreaker_tb.v        full system simulation testbench
        ├── tb_direct.v            directed cache integration testbench
        ├── spiflash_tb.v          SPI flash model testbench
        ├── performance.py         Python script to plot speedup from measurements
        ├── performance.png        generated speedup plot
        └── workloads/
            ├── kalman_steady_state.c  primary benchmark (fixed-point Kalman update)
            ├── bubble_sort.c          secondary benchmark
            ├── fibonacci_iterative.c  secondary benchmark
            ├── fibonacci_recursive.c  secondary benchmark
            ├── secret*_fw.bin         pre-compiled external test binaries (9 files)
            └── tests/                 host-side unit tests for workload correctness
```

---

## Prerequisites

The build needs the OSS CAD Suite (Yosys, nextpnr, icetime, iceprog, iverilog)
and a RISC-V GCC cross-compiler.

Install the OSS CAD Suite:
```
https://github.com/YosysHQ/oss-cad-suite-build
```

Activate it (adjust the path to your install), which puts the whole FPGA
toolchain on your `PATH`:
```bash
source /path/to/oss-cad-suite/environment
```

Install the RISC-V toolchain (macOS via Homebrew):
```bash
brew tap riscv-software-src/riscv
brew install riscv-tools
```

The RISC-V GCC cross-compiler is auto-detected by the Makefile; if it is not on
your `PATH`, set `CROSS` in `picorv32-main/picosoc/Makefile` to its prefix.

All commands below assume the OSS CAD Suite environment is active and the working
directory is `picorv32-main/picosoc/`.

---

## Building and programming the five hardware configurations

Each configuration is synthesised, placed-and-routed, and timed independently.

### Full build (icache + dcache, final build)
```bash
make icebreaker.bin           # synthesise, place-and-route, timing check
make icebprog                 # program bitstream + firmware onto board
```

### Baseline (12 MHz, no cache, original PicoSoC parameters)
```bash
make icebreaker_baseline.bin
make icebprog_baseline
```

### No-cache with PLL (18.75 MHz, reduced CPU features, no cache)
```bash
make icebreaker_nocache.bin
make icebprog_nocache
```

### Direct-mapped icache only — Phase 1 (32-set, 1-way, 512 B)
```bash
make icebreaker_directmap.bin
make icebprog_directmap
```

### Set-associative icache only — Phase 2 (32-set, 2-way, 1 KB)
```bash
make icebreaker_icache_only.bin
make icebprog_icache_only
```

After programming the bitstream, program the firmware separately if needed:
```bash
make icebprog_fw              # re-flash firmware without reflashing bitstream
```

---

## Switching workloads

The `firmware.c` file calls `run_workload()` from a separate workload file.
The Makefile `FW` variable selects which file is compiled as the firmware:

```bash
# Use the default firmware.c (kalman_steady_state is compiled in by default)
make icebreaker_fw.bin

# Use a specific workload file
make FW=workloads/bubble_sort icebreaker_fw.bin
make FW=workloads/fibonacci_iterative icebreaker_fw.bin
make FW=workloads/fibonacci_recursive icebreaker_fw.bin
make FW=workloads/kalman_steady_state icebreaker_fw.bin

# Re-flash firmware only (bitstream already on board)
make icebprog_fw
```

---

## Running system simulation

The system testbench simulates the full iCEBreaker SoC with a SPI flash model.

```bash
make icebsim                  # compile and run icebreaker_tb.vvp with default firmware
```

To simulate with a specific workload:
```bash
make icebreaker_fw.hex FW=workloads/bubble_sort
make icebsim
```

To run the directed integration testbench:
```bash
iverilog -s testbench -o tb_direct.vvp tb_direct.v icebreaker.v ice40up5k_spram.v \
  spimemio.v simpleuart.v picosoc.v ../picorv32.v spiflash.v icache.v dcache.v \
  `yosys-config --datdir/ice40/cells_sim.v` -DNO_ICE40_DEFAULT_ASSIGNMENTS
vvp -N tb_direct.vvp
```

---

## Cache unit testbenches (standalone)

The `cache_testbenches/` testbenches test `icache.v` and `dcache.v` in isolation,
without the full SoC. Run from `picorv32-main/cache_testbenches/`:

```bash
cd ../cache_testbenches

# Direct-mapped cache eviction behaviour
iverilog -o sim_evict.vvp dmap_evict_tb.v ../picosoc/dcache.v && vvp sim_evict.vvp

# Hit/miss latency (2-cycle hit, multi-cycle miss)
iverilog -o sim_latency.vvp dmap_hit_miss_latency_tb.v ../picosoc/dcache.v && vvp sim_latency.vvp

# Hot inner-loop hit rate
iverilog -o sim_hotloop.vvp dmap_hotloop_tb.v ../picosoc/dcache.v && vvp sim_hotloop.vvp

# Harvard split-cache integration (icache + dcache together)
iverilog -o sim_harv.vvp harv_caches_validation_tb.v ../picosoc/icache.v ../picosoc/dcache.v && vvp sim_harv.vvp
```

Expected outputs and pass/fail criteria are documented as comments inside each
testbench file.

---

## Measurement methodology

Performance is measured by attaching a Picoscope to the **LED1** pin on the
iCEBreaker board. The firmware toggles LED1 once per `run_workload()` call,
producing a square wave. The toggle frequency `f` gives:

```
execution time per iteration  T = 1 / (2f)
cycle count                   N = f_clk / (2f)
```

where `f_clk = 12 MHz` for the baseline build and `18.75 MHz` for all
PLL builds.

All raw Picoscope readings and derived results are in `data/measurements.md`.
Waveform screenshots for `kalman_steady_state` across all five builds are in
`data/*.png`.

To reproduce the speedup plot:
```bash
cd picosoc
python3 performance.py
```

---

## Synthesis and timing reports

The `data/` directory contains the Yosys synthesis logs and icetime timing
reports for all five builds:

| File | Contents |
|------|----------|
| `icebreaker*.log` | Yosys cell counts (LUT4, FF, EBR, DSP, SPRAM, PLL) |
| `icebreaker*.rpt` | icetime critical path, max clock, logic levels |

These were produced by the Makefile targets above and are included so results
can be verified without re-running synthesis.
