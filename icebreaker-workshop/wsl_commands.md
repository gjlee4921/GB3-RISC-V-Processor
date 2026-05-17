# iCEBreaker WSL Command Reference
> Personal setup guide for GB3 RISC-V project  
> Device: iCEBreaker V1.1a (VID:PID 0403:6010) | WSL2 Ubuntu  
> ⚠️ BUSID changes every time you replug — always look it up first (see Step 2)

---

## Every Session — Do This First

Every time you open a new terminal session or replug the board, run these steps in order.

### Step 1 — Open WSL terminal in VS Code
In VS Code, open the terminal and make sure it's a WSL terminal (not PowerShell).  
Bottom-left corner should show **WSL: Ubuntu** (or similar).  
If not: `Ctrl+Shift+P` → "WSL: New WSL Terminal"

---

### Step 2 — Attach the board (PowerShell Admin required)
Open **Admin PowerShell** (`Win + X` → `A`) and run these two commands:

**First, find the iCEBreaker's current BUSID:**
```powershell
usbipd list
```
Look for the line containing `iCEBreaker` or `0403:6010` — note the BUSID (e.g. `2-4`, `2-6`, etc. — it changes each time you replug).

**Then attach it using that BUSID:**
```powershell
usbipd attach --wsl --busid <BUSID>
# Example: usbipd attach --wsl --busid 2-6
```

**Or do both in one command (auto-detects BUSID):**
```powershell
usbipd attach --wsl --busid (usbipd list | Select-String "0403:6010" | ForEach-Object { $_.ToString().Trim().Split(" ")[0] })
```

> Do this every time you plug/replug the iCEBreaker.  
> You must keep the WSL terminal open while doing this.

---

### Step 3 — Activate OSS CAD Suite (if not already active)
Check your terminal prompt. If it shows `⦗OSS CAD Suite⦘` you're good.  
If not, run:
```bash
source ~/oss-cad-suite/environment
```

---

### Step 4 — Verify board is connected
```bash
lsusb
# Should show: 0403:6010 (bus 1, device X)

iceprog -t
# Should show: flash ID: 0xEF 0x40 0x18 0x00
```
If `iceprog -t` fails, run `newgrp plugdev` then try again.

---

## How the Build System Works

### What the Makefile does
The Makefile defines `PROJ = stopwatch`, meaning it looks for `stopwatch.v` as its entry point. The build pipeline is:

```
stopwatch.v  →  stopwatch.json  →  stopwatch.asc  →  stopwatch.bin
   (yosys synthesis)   (nextpnr place & route)   (icepack bitstream)
```

### Build output files (all auto-generated, safe to delete)
| File | Tool | Purpose |
|---|---|---|
| `stopwatch.json` | yosys | Synthesised netlist |
| `stopwatch.yslog` | yosys | Synthesis log |
| `stopwatch.asc` | nextpnr | Place & route output |
| `stopwatch.nplog` | nextpnr | Place & route log |
| `stopwatch.rpt` | icetime | Timing report |
| `stopwatch.bin` | icepack | Final bitstream — this gets flashed |

---

### Do I only need to edit stopwatch.v?
**Yes, for most work.** The Makefile points directly to `stopwatch.v` as the single source file:
```makefile
$(PROJ).json: $(PROJ).v
    yosys ... $<   # $< means "first dependency" = stopwatch.v
```
You only need to also edit `icebreaker.pcf` if you change which physical pins you're using.

---

### Can I use multiple Verilog files?
Yes — three ways:

**Option A: List multiple files in the Makefile (recommended for separate modules)**
Edit the Makefile's yosys line to include all your `.v` files:
```makefile
$(PROJ).json: $(PROJ).v my_module.v another_module.v
    yosys -ql $(PROJ).yslog -p 'synth_ice40 -top top -json $@' $^
```
Note: `$^` means "all dependencies" (vs `$<` which means only the first one).

**Option B: Chain files using `include (like a header)**
Inside `stopwatch.v`, add at the top:
```verilog
`include "my_module.v"
```
This pulls in another file directly — no Makefile changes needed.

**Option C: Define multiple modules in one file (already done in stopwatch.v)**
`stopwatch.v` already contains multiple modules (`top`, `bcd8_increment`, `seven_seg_ctrl`, `seven_seg_hex`) all in one file. The top module instantiates the others by name:
```verilog
seven_seg_ctrl seven_segment_ctrl (
    .CLK(CLK),
    .din(display_value[7:0]),
    .dout(seven_segment)
);
```

---

### To rename the project or use a different top-level .v file
Change the first line of the Makefile:
```makefile
PROJ = stopwatch   # change this to your new filename (without .v)
```
Then rename your `.v` file to match. Everything else updates automatically.

---

## Building and Flashing

### Navigate to stopwatch directory
```bash
cd ~/icebreaker-workshop/stopwatch
# or if using your VS Code repo path:
cd /path/to/GB3-RISC-V-PROCESSOR/icebreaker-workshop/stopwatch
```

### Build the bitstream
```bash
make
```
This runs: **yosys** (synthesis) → **nextpnr** (place & route) → **icepack** (bitstream)  
Output: `stopwatch.bin`

### Flash to board
```bash
iceprog stopwatch.bin
```
> Board must be attached via `usbipd` first (Step 2 above).

### Build AND flash in one command
```bash
make prog
```

### Clean build files
```bash
make clean
```

---

## Simulation / Testbench

### Run a testbench with iverilog
```bash
iverilog -o sim.out stopwatch_tb.v stopwatch.v
vvp sim.out
```

### Generate waveform (VCD) and view
```bash
# In your testbench, add: $dumpfile("wave.vcd"); $dumpvars;
iverilog -o sim.out stopwatch_tb.v stopwatch.v
vvp sim.out
# Opens wave.vcd — view with GTKWave:
gtkwave wave.vcd
```

---

## RISC-V Toolchain

### Compile a C file to RISC-V
```bash
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -o output.elf input.c
```

### Check toolchain is working
```bash
riscv-none-elf-gcc --version
```

---

## Serial Monitor (UART)

### Connect to board serial output (WSL)
```bash
screen /dev/ttyUSB0 115200
# Exit screen: Ctrl+A then K
```
> Try `/dev/ttyUSB1` if `USB0` doesn't work.

### Or use PuTTY on Windows
- Connection type: **Serial**
- Speed: **115200**
- Port: Check Device Manager for the COM port number (e.g. COM3)

---

## Useful Checks

### Check FPGA resource usage (after build)
```bash
cat stopwatch.yslog    # Yosys synthesis log
cat stopwatch.nplog    # nextpnr place & route log
cat stopwatch.rpt      # Timing report
```

### Read timing report summary
```bash
grep "Timing estimate" stopwatch.rpt
# Should say: PASSED for 12 MHz constraint
```

### Check what pins are mapped
```bash
cat icebreaker.pcf
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `iceprog` not found | Run `source ~/oss-cad-suite/environment` |
| `Can't find iCE FTDI USB device` | Run `usbipd list` in PowerShell Admin, find iCEBreaker BUSID, then `usbipd attach --wsl --busid <BUSID>` |
| `iceprog` permission denied | Run `newgrp plugdev` then retry |
| Board not in `lsusb` | Replug USB, then reattach via usbipd |
| WSL doesn't start | Open Ubuntu from Start menu first, then rerun usbipd attach |
| `riscv-none-elf-gcc` not found | Run `export PATH=~/xpack-riscv-none-elf-gcc-13.2.0-2/bin:$PATH` |

---

## Session Startup Checklist

- [ ] VS Code terminal is WSL (not PowerShell)
- [ ] `source ~/oss-cad-suite/environment` (if prompt doesn't show OSS CAD Suite)
- [ ] iCEBreaker plugged in via USB
- [ ] `usbipd list` in Admin PowerShell → find iCEBreaker BUSID → `usbipd attach --wsl --busid <BUSID>`
- [ ] `iceprog -t` returns flash ID successfully
- [ ] 7-segment Pmod plugged into **PMOD1A**