# Phase 2 — 2-Way Set-Associative Instruction Cache

Phase 2 upgrades the instruction cache from the direct-mapped design of
[Phase 1](direct_mapped_icache.md) to **2-way set-associativity**, keeping the
32-set organisation, 4-word cache lines, and EBR data storage. The change adds
a second tag, valid, and data array alongside the first — doubling capacity from
512 B to **1 KB** — and introduces a **1-bit LRU flag per set** to choose the
victim way on a miss.

## Motivation: conflict misses

With only one way per set, two hot code regions that map to the same cache index
evict each other on every access, even when their combined footprint is well
within the total capacity. The `kalman_steady_state` update body and its
surrounding call sites exhibit exactly this pattern, so a direct-mapped cache
thrashes on them. Adding a second way per set lets any two simultaneously-live
regions coexist, eliminating those conflict evictions.

## Architecture

- **32 sets, 2 ways**, each way with its own tag, valid bit, and 4-word data
  line — **1 KB** total capacity.
- **1-bit LRU per set** selects the way to evict on a miss.
- On a **hit**, the matching way's word is returned.
- On a **miss**, four words are fetched from flash into the LRU-selected way,
  then the requested word is returned.

This cache is a distinct module, **`icache.v`** (the Phase 1 direct-mapped
`dcache.v` is later reused for the data cache in
[Phase 3](harvard_cache.md)).

### Address decomposition (24-bit flash address)

```
[23:9]  tag           (15 bits)
[8:4]   index          (5 bits → selects one of 32 sets)
[3:2]   word-in-line   (2 bits → selects one of 4 words in the line)
[1:0]   byte offset    (always 00 for word-aligned instructions)
```

The layout is identical to Phase 1; the added associativity is expressed by
searching both ways of the selected set in parallel and using the per-set LRU
bit to pick the fill victim.

### Storage split

| State | Storage | Read type | Why |
|---|---|---|---|
| tag / valid / LRU | logic-cell registers | combinational | small; enables same-cycle hit detection |
| 4-word data lines (both ways) | **EBR block RAM** | **synchronous** | large; block RAM is the only way to fit |

As in Phase 1, the tag, valid, and LRU metadata stay in logic-cell registers for
combinational hit detection, while the data lines use a **synchronous read** so
Yosys maps them to `SB_RAM40_4K` EBR primitives. The second way's data array
adds three further EBR blocks. The **2-cycle hit latency** pipeline is unchanged
from Phase 1.

## Integration

The cache is instantiated on the instruction-flash path in
`picosoc_icache_only.v`, wired to the PicoRV32 memory bus exactly as in Phase 1
(hit → cache drives `mem_ready`/`mem_rdata`; miss → cache requests `spimemio`).
This build is clocked at **18.75 MHz** via the on-chip PLL.

## Results (`kalman_steady_state`)

Measured on the iCE40UP5K board via Picoscope LED1 frequency; cycles derived as
`f_clk / (2·f)`.

| Build | LED freq (Hz) | Cycles | Cycle reduction vs no-cache |
|---|---|---|---|
| No-cache (18.75 MHz, no cache) | 6.475 | 1,447,877 | — |
| Direct-map (Phase 1) | 13.32 | 703,604 | 2.06× |
| **I-cache only (Phase 2)** | **16.36** | **573,104** | **2.53×** |

The set-associative upgrade raises the cycle reduction from 2.06× to **2.53×**
over the uncached build — an additional **1.23×** on top of the direct-mapped
cache — by removing the conflict evictions that the single-way design suffered.

### Area and timing

| Metric | I-cache-only build | Note |
|---|---|---|
| SB_LUT4 | 3319 | Yosys post-synthesis (`data/icebreaker_icache_only.log`) |
| EBR (block RAM) | 10 / 30 | 4 CPU register file + 3 per data array (way 0 + way 1) |
| Critical path | 47.93 ns | icetime (`data/icebreaker_icache_only.rpt`) |
| Max clock | — | closes at 18.75 MHz |

## Next phase

[Phase 3 — Harvard split cache](harvard_cache.md) adds a separate direct-mapped
**data cache** (a second instance of `dcache.v`) for the read-only constant
matrices, recovers logic-cell area by disabling unused CPU features, and enables
the 18.75 MHz PLL overclock to reach the final build.
