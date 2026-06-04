
# Auto-detect available RISC-V toolchain
ifneq ($(shell which riscv32-unknown-elf-gcc 2>/dev/null),)
    CROSS=riscv32-unknown-elf-
else ifneq ($(shell which riscv-none-elf-gcc 2>/dev/null),)
    CROSS=riscv-none-elf-
else ifneq ($(shell ls /usr/local/apps/GB3-RISCV/riscv32imc/bin/riscv32-unknown-elf-gcc 2>/dev/null),)
    CROSS=/usr/local/apps/GB3-RISCV/riscv32imc/bin/riscv32-unknown-elf-
else
    $(error No RISC-V toolchain found)
endif
CFLAGS=

# ---- iCE40 HX8K Breakout Board ----

hx8ksim: hx8kdemo_tb.vvp hx8kdemo_fw.hex
	vvp -N $< +firmware=hx8kdemo_fw.hex

hx8ksynsim: hx8kdemo_syn_tb.vvp hx8kdemo_fw.hex
	vvp -N $< +firmware=hx8kdemo_fw.hex

hx8kdemo.json: hx8kdemo.v spimemio.v simpleuart.v picosoc.v ../picorv32.v
	yosys -ql hx8kdemo.log -p 'synth_ice40 -top hx8kdemo -json hx8kdemo.json' $^

hx8kdemo_tb.vvp: hx8kdemo_tb.v hx8kdemo.v spimemio.v simpleuart.v picosoc.v ../picorv32.v spiflash.v
	iverilog -s testbench -o $@ $^ `yosys-config --datdir/ice40/cells_sim.v` -DNO_ICE40_DEFAULT_ASSIGNMENTS

hx8kdemo_syn_tb.vvp: hx8kdemo_tb.v hx8kdemo_syn.v spiflash.v
	iverilog -s testbench -o $@ $^ `yosys-config --datdir/ice40/cells_sim.v` -DNO_ICE40_DEFAULT_ASSIGNMENTS

hx8kdemo_syn.v: hx8kdemo.json
	yosys -p 'read_json hx8kdemo.json; write_verilog hx8kdemo_syn.v'

hx8kdemo.asc: hx8kdemo.pcf hx8kdemo.json
	nextpnr-ice40 --hx8k --package ct256 --asc hx8kdemo.asc --json hx8kdemo.json --pcf hx8kdemo.pcf

hx8kdemo.bin: hx8kdemo.asc
	icetime -d hx8k -c 12 -mtr hx8kdemo.rpt hx8kdemo.asc
	icepack hx8kdemo.asc hx8kdemo.bin

hx8kprog: hx8kdemo.bin hx8kdemo_fw.bin
	iceprog hx8kdemo.bin
	iceprog -o 1M hx8kdemo_fw.bin

hx8kprog_fw: hx8kdemo_fw.bin
	iceprog -o 1M hx8kdemo_fw.bin

hx8kdemo_sections.lds: sections.lds
	$(CROSS)cpp -P -DHX8KDEMO -o $@ $^

hx8kdemo_fw.elf: hx8kdemo_sections.lds start.s firmware.c
	$(CROSS)gcc $(CFLAGS) -DHX8KDEMO -mabi=ilp32 -march=rv32imc -Wl,--build-id=none,-Bstatic,-T,hx8kdemo_sections.lds,--strip-debug -ffreestanding -nostdlib -o hx8kdemo_fw.elf start.s firmware.c

hx8kdemo_fw.hex: hx8kdemo_fw.elf
	$(CROSS)objcopy -O verilog hx8kdemo_fw.elf hx8kdemo_fw.hex

hx8kdemo_fw.bin: hx8kdemo_fw.elf
	$(CROSS)objcopy -O binary hx8kdemo_fw.elf hx8kdemo_fw.bin

# ---- iCE40 IceBreaker Board ----

icebsim: icebreaker_tb.vvp icebreaker_fw.hex
	vvp -N $< +firmware=icebreaker_fw.hex

icebsynsim: icebreaker_syn_tb.vvp icebreaker_fw.hex
	vvp -N $< +firmware=icebreaker_fw.hex

icebreaker.json: icebreaker.v ice40up5k_spram.v spimemio.v simpleuart.v picosoc.v ../picorv32.v icache.v dcache.v
	yosys -ql icebreaker.log -p 'synth_ice40 -dsp -top icebreaker -json icebreaker.json' $^

icebreaker_tb.vvp: icebreaker_tb.v icebreaker.v ice40up5k_spram.v spimemio.v simpleuart.v picosoc.v ../picorv32.v spiflash.v icache.v dcache.v
	iverilog -s testbench -o $@ $^ `yosys-config --datdir/ice40/cells_sim.v` -DNO_ICE40_DEFAULT_ASSIGNMENTS

icebreaker_syn_tb.vvp: icebreaker_tb.v icebreaker_syn.v spiflash.v
	iverilog -s testbench -o $@ $^ `yosys-config --datdir/ice40/cells_sim.v` -DNO_ICE40_DEFAULT_ASSIGNMENTS

icebreaker_syn.v: icebreaker.json
	yosys -p 'read_json icebreaker.json; write_verilog icebreaker_syn.v'

icebreaker.asc: icebreaker.pcf icebreaker.json
	nextpnr-ice40 --freq 18 --up5k --package sg48 --asc icebreaker.asc --pcf icebreaker.pcf --json icebreaker.json

icebreaker.bin: icebreaker.asc
	icetime -d up5k -c 18 -mtr icebreaker.rpt icebreaker.asc
	icepack icebreaker.asc icebreaker.bin

icebprog: icebreaker.bin icebreaker_fw.bin
	iceprog icebreaker.bin
	iceprog -o 1M icebreaker_fw.bin

icebprog_fw: icebreaker_fw.bin
	iceprog -o 1M icebreaker_fw.bin

# True no-cache baseline: picosoc_nocache.v routes instructions directly to
# spimemio (1 word per fetch), bypassing the icache module entirely.
icebreaker_nocache.json: icebreaker.v ice40up5k_spram.v spimemio.v simpleuart.v picosoc_nocache.v ../picorv32.v
	yosys -ql icebreaker_nocache.log -p 'synth_ice40 -dsp -top icebreaker -json icebreaker_nocache.json' $^

icebreaker_nocache.asc: icebreaker.pcf icebreaker_nocache.json
	nextpnr-ice40 --freq 18 --up5k --package sg48 --asc icebreaker_nocache.asc --pcf icebreaker.pcf --json icebreaker_nocache.json

icebreaker_nocache.bin: icebreaker_nocache.asc
	icetime -d up5k -c 12 -mtr icebreaker_nocache.rpt icebreaker_nocache.asc
	icepack icebreaker_nocache.asc icebreaker_nocache.bin

icebprog_nocache: icebreaker_nocache.bin icebreaker_fw.bin
	iceprog icebreaker_nocache.bin
	iceprog -o 1M icebreaker_fw.bin

# Stock baseline: original PicoSoC defaults (ENABLE_IRQ=1, ENABLE_COUNTERS=1),
# no icache. Used as the unmodified starting point for the three-way comparison.
icebreaker_baseline.json: icebreaker.v ice40up5k_spram.v spimemio.v simpleuart.v picosoc_baseline.v ../picorv32.v
	yosys -D NO_PLL -ql icebreaker_baseline.log -p 'synth_ice40 -dsp -top icebreaker -json icebreaker_baseline.json' $^

icebreaker_baseline.asc: icebreaker.pcf icebreaker_baseline.json
	nextpnr-ice40 --freq 13 --up5k --package sg48 --asc icebreaker_baseline.asc --pcf icebreaker.pcf --json icebreaker_baseline.json

icebreaker_baseline.bin: icebreaker_baseline.asc
	icetime -d up5k -c 12 -mtr icebreaker_baseline.rpt icebreaker_baseline.asc
	icepack icebreaker_baseline.asc icebreaker_baseline.bin

icebprog_baseline: icebreaker_baseline.bin icebreaker_fw.bin
	iceprog icebreaker_baseline.bin
	iceprog -o 1M icebreaker_fw.bin

icebreaker_sections.lds: sections.lds
	$(CROSS)cpp -P -DICEBREAKER -o $@ $^

FW ?= firmware

icebreaker_fw.elf: icebreaker_sections.lds start.s $(FW).c
	$(CROSS)gcc $(CFLAGS) -DICEBREAKER -mabi=ilp32 -march=rv32im -Wl,-Bstatic,-T,icebreaker_sections.lds,--strip-debug -ffreestanding -nostdlib -o icebreaker_fw.elf start.s $(FW).c -lgcc
	
icebreaker_fw.hex: icebreaker_fw.elf
	$(CROSS)objcopy -O verilog icebreaker_fw.elf icebreaker_fw.hex

icebreaker_fw.bin: icebreaker_fw.elf
	$(CROSS)objcopy -O binary icebreaker_fw.elf icebreaker_fw.bin

# ---- Testbench for SPI Flash Model ----

spiflash_tb: spiflash_tb.vvp icebreaker_fw.hex
	vvp -N $< +firmware=icebreaker_fw.hex

spiflash_tb.vvp: spiflash.v spiflash_tb.v
	iverilog -s testbench -o $@ $^

# ---- ASIC Synthesis Tests ----

cmos.log: spimemio.v simpleuart.v picosoc.v ../picorv32.v
	yosys -l cmos.log -p 'synth -top picosoc; abc -g cmos2; opt -fast; stat' $^

# ---- Clean ----

clean:
	rm -f testbench.vvp testbench.vcd spiflash_tb.vvp spiflash_tb.vcd
	rm -f hx8kdemo_fw.elf hx8kdemo_fw.hex hx8kdemo_fw.bin cmos.log
	rm -f icebreaker_fw.elf icebreaker_fw.hex icebreaker_fw.bin
	rm -f hx8kdemo.json hx8kdemo.log hx8kdemo.asc hx8kdemo.rpt hx8kdemo.bin
	rm -f hx8kdemo_syn.v hx8kdemo_syn_tb.vvp hx8kdemo_tb.vvp
	rm -f icebreaker.json icebreaker.log icebreaker.asc icebreaker.rpt icebreaker.bin
	rm -f icebreaker_syn.v icebreaker_syn_tb.vvp icebreaker_tb.vvp
	rm -f icebreaker_nocache.json icebreaker_nocache.log icebreaker_nocache.asc icebreaker_nocache.rpt icebreaker_nocache.bin
	rm -f icebreaker_baseline.json icebreaker_baseline.log icebreaker_baseline.asc icebreaker_baseline.rpt icebreaker_baseline.bin

.PHONY: spiflash_tb clean
.PHONY: hx8kprog hx8kprog_fw hx8ksim hx8ksynsim
.PHONY: icebprog icebprog_fw icebsim icebsynsim icebprog_nocache icebprog_baseline
