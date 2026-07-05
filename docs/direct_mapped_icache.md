# Phase 1 — Direct-Mapped Instruction Cache

This is the first phase of the cache system. The unmodified PicoSoC connects
PicoRV32 directly to the SPI flash controller (`spimemio`), so every
instruction fetch triggers a full SPI transaction — command, 24-bit address,
and dummy cycles — before a single instruction word is returned. Profiling the
baseline showed roughly **88 % of execution cycles** were spent stalled on
these fetches. Phase 1 inserts an instruction cache in front of the flash
controller to remove that stall from the common case.

## Architecture

A **32-set, direct-mapped instruction cache** with **4-word (16-byte) cache
lines**, giving **512 bytes** of capacity. On a miss, the cache fetches four
consecutive instruction words in a single flash transaction, so the SPI setup
cost (command, address, dummy cycles) is amortised across four words instead of
paid per word. This matches the access pattern of tight inner loops, where
instructions execute sequentially.

This cache is implemented by the **`dcache.v`** module. The same module is
reused unchanged on the data path in [Phase 3](harvard_cache.md), which is what
makes the eventual Harvard split-cache cheap to build.

### Address decomposition (24-bit flash address)

```
[23:9]  tag           (15 bits)
[8:4]   index          (5 bits → selects one of 32 sets)
[3:2]   word-in-line   (2 bits → selects one of 4 words in the line)
[1:0]   byte offset    (always 00 for word-aligned instructions)
```

On a **hit**, the requested word is served from the cache. On a **miss**, the
four words of the line are fetched from flash, written into the indexed set,
and the requested word is returned.

### Storage split (the key design decision)

| State | Storage | Read type | Why |
|---|---|---|---|
| tag / valid | logic-cell registers | combinational | small; enables same-cycle hit detection |
| 4-word data lines | **EBR block RAM** | **synchronous** | large; block RAM is the only way to fit |

The tag and valid bits are held in logic-cell registers and read
combinationally for the hit comparison:

```verilog
wire hit_c = cpu_valid && valid[index] && (tag[index] == tag_w);
```

The 4-word data lines use a **registered (synchronous) read** so Yosys maps
them to the FPGA's `SB_RAM40_4K` EBR primitives rather than logic-cell
flip-flops. This is essential: a combinational read of the data arrays forces
every storage bit onto the read multiplexer in the same cycle, inflating the
design to **227 %** of the device's logic-cell budget. The synchronous-read
version drops this to **83 %** and frees roughly 7,500 logic cells.

The only cost is one extra cycle of hit latency, so a **hit takes 2 cycles**:
cycle 0 issues the block-RAM read and registers the tag comparison into
`hit_r`; cycle 1 serves the data from the registered BRAM output. Against the
tens-of-cycle QDDR flash miss penalty this extra cycle is negligible.

Direct-mapped associativity (one way per set, no LRU) was chosen because the
target workloads have tight inner loops with strong temporal locality, which a
single way captures at minimal hardware cost. This gives a correct, measurable
baseline before adding associativity in [Phase 2](set_associative_icache.md).

## Integration

`picosoc.v` is modified to intercept the PicoRV32 memory bus between the CPU and
`spimemio`. An instruction-flash request is asserted when the CPU issues an
instruction fetch to the flash range:

```verilog
wire insn_flash_req = mem_valid && mem_instr && (mem_addr < FLASH_END);
```

On a cache hit the icache drives `mem_ready` and `mem_rdata` directly; on a miss
it asserts its flash-valid signal to `spimemio` and forwards the data once the
line arrives. This build is `picosoc_directmap.v`, clocked at **18.75 MHz** via
the on-chip PLL.

## Results (`kalman_steady_state`)

Measured on the iCE40UP5K board by observing the LED1 square-wave frequency on a
Picoscope; cycles are derived as `f_clk / (2·f)`.

| Build | LED freq (Hz) | Cycles | Cycle reduction vs no-cache |
|---|---|---|---|
| No-cache (18.75 MHz, no cache) | 6.475 | 1,447,877 | — |
| **Direct-map (Phase 1)** | **13.32** | **703,604** | **2.06×** |

The 2.06× cycle reduction over the uncached build confirms that
instruction-fetch latency dominates the baseline runtime.

### Area and timing

| Metric | Direct-map build | Note |
|---|---|---|
| SB_LUT4 | 2968 | Yosys post-synthesis (`data/icebreaker_directmap.log`) |
| EBR (block RAM) | 7 / 30 | 4 CPU register file + 3 for the cache data array |
| Critical path | 42.22 ns | icetime (`data/icebreaker_directmap.rpt`) |
| Max clock | 22.07 MHz | closes comfortably at 18.75 MHz |

## Next phase

[Phase 2 — 2-Way Set-Associative Instruction Cache](set_associative_icache.md)
adds a second way and an LRU victim policy to eliminate conflict misses and
double the instruction-cache capacity to 1 KB.
