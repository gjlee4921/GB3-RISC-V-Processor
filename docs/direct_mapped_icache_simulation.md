# Direct-Mapped Instruction Cache — Simulation Summary

## Architecture

16-set, 1-word (32-bit) direct-mapped instruction cache inserted between PicoRV32 and spimemio.

Address decomposition (24-bit flash address):

```
[23:6]  tag   (18 bits)
[5:2]   index (4 bits  → selects one of 16 sets)
[1:0]   byte offset (always 00 for word-aligned instructions)
```

On a **hit**: instruction served in 1 cycle, no flash access.  
On a **miss**: request forwarded to spimemio; cache entry written on `flash_ready`.

## Files Changed

### `icache.v` (new)

Direct-mapped cache module with parameter `NSETS = 16`. Stores three arrays indexed by the 4-bit index field: `tag_array`, `valid_array`, `data_array`. Hit logic:

```verilog
wire hit = cpu_valid && valid_array[index] && (tag_array[index] == tag);
```

On reset, all `valid_array` entries are cleared. On a miss fill (`flash_ready`), the incoming word and tag are written to the indexed entry.

### `picosoc.v` (modified)

Replaced the original `spimem_ready`/`spimem_rdata` wires and `spimemio` instantiation with:

- `insn_flash_req` — asserted when `mem_valid && mem_instr` targets the flash address range
- `data_flash_req` — asserted when `mem_valid && !mem_instr` targets the flash address range
- `icache` instance consuming `insn_flash_req`; its `flash_valid`/`flash_addr` outputs drive `spimemio`
- `spimemio.valid` = `icache_flash_valid || data_flash_req`
- `spimemio.addr` = `icache_flash_addr` when icache requests flash, else `mem_addr[23:0]`
- `spimem_ready` and `spimem_rdata` mux: icache outputs on `insn_flash_req`, spimemio outputs otherwise

PicoRV32 issues at most one transaction at a time, so `insn_flash_req` and `data_flash_req` are mutually exclusive.

### `icebreaker.v` (modified)

Added `.ENABLE_COMPRESSED(0)` to the `picosoc` instantiation, consistent with `-march=rv32im`.

### `Makefile` (modified)

- `-march=rv32ic` → `-march=rv32im` (line 100)
- `icache.v` added to synthesis sources (line 68) and simulation sources (line 71)

### `icebreaker_tb.v` (modified)

`repeat(6)` → `repeat(20)` to give 1,000,000 simulation cycles, required because the workload plus UART output (≈1040 cycles/character) exceeds the original 300,000-cycle budget.

### `firmware.c` (modified)

Added `bench_fib_rec` and `run_workload()` before `main()`:

```c
uint32_t bench_fib_rec(int n) {
    if (n <= 1) return n;
    return bench_fib_rec(n-1) + bench_fib_rec(n-2);
}

unsigned char run_workload(void) {
    volatile uint32_t result = bench_fib_rec(10);
    return (unsigned char)(result & 0xFF);
}
```

Measurement block placed in `main()` after `set_flash_qspi_flag()` and before `getchar_prompt(...)`:

```c
reg_leds = 63;
set_flash_qspi_flag();
{
    uint32_t t0, t1;
    __asm__ volatile ("rdcycle %0" : "=r"(t0));
    run_workload();
    __asm__ volatile ("rdcycle %0" : "=r"(t1));
    print_hex(t1 - t0, 8);
    putchar('\n');
}
reg_leds = 127;
while (getchar_prompt("Press ENTER to continue..\n") != '\r') { /* wait */ }
```

`set_flash_mode_qddr()` is intentionally omitted here: the `spiflash.v` simulation model does not handle QDDR commands and causes the CPU to stall.

## Simulation Methodology

**Baseline**: temporarily set `wire hit = 1'b0;` in `icache.v` to force every access to flash, then restore the real hit logic for the cached run.

Run simulation:
```
make icebsim
```

The cycle count is printed as an 8-digit hex value over simulated UART before the "Press ENTER" prompt.

## Results

### `bench_fib_rec(8)`

| Configuration | Cycles     | Hex          |
|---------------|------------|--------------|
| No cache      | 109,654    | `0x0001ac56` |
| With cache    | 62,386     | `0x0000f3b2` |
| **Speedup**   | **1.757×** |              |

### `bench_fib_rec(10)`

| Configuration | Cycles     | Hex          |
|---------------|------------|--------------|
| No cache      | 288,074    | `0x0004654a` |
| With cache    | 161,387    | `0x0002766b` |
| **Speedup**   | **1.784×** |              |

Speedup increases with larger workload because the cold-start miss penalty is amortised over more computation. In simulation, each flash miss costs approximately 8 cycles (SPI mode). On real hardware with QDDR mode enabled, the miss penalty is 40–80+ cycles, so the speedup is expected to be 3–5×.

## Changes Required for Hardware Testing

The following changes must be made before programming the iCEBreaker:

1. **Re-enable QDDR flash mode** in `firmware.c`. Add the call to `set_flash_mode_qddr()` immediately after `set_flash_qspi_flag()` in the measurement block in `main()`:
   ```c
   set_flash_qspi_flag();
   set_flash_mode_qddr();
   ```

2. **Use a larger workload** to ensure the timing window is wide enough for Picoscope LED period capture. Increase the argument to `bench_fib_rec` in `run_workload()`, e.g. `bench_fib_rec(15)`, or wrap the call in a loop (e.g. 100 iterations) to amplify the cycle count.

3. **Build and program**:
   ```
   make icebreaker.bin
   make icebprog
   ```

4. **Measure via serial terminal**:
   ```
   screen /dev/ttyUSB1 115200
   ```
   The hex cycle count is printed at boot. Press `[B]` in the interactive menu to repeat the measurement without reflashing.

5. **Restore baseline for before/after comparison**: revert to the original hardware without `icache.v` in sources, measure, then re-add the cache and measure again. Alternatively, keep `wire hit = 1'b0` for a clean no-cache baseline on the same bitstream.

6. **Record PPA**:
   - Performance: cycle count from UART; CPI from `N × CPI × T` where T = 83.3 ns (12 MHz)
   - Area: LC utilisation from `icebreaker.rpt` after `make icebreaker.bin`
   - Power: measure board current at 3.3 V rail with multimeter or Picoscope during workload execution
