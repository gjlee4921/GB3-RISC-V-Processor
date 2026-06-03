/*
 * fibonacci_recursive.c — Recursive Fibonacci benchmark
 *
 * Computes fib(15) using the naive recursive algorithm.
 * fib(n) = fib(n-1) + fib(n-2), fib(0)=0, fib(1)=1.
 * Makes 1973 recursive calls total, exercising deep call chains and
 * creating high instruction cache pressure from repeated re-entry.
 *
 * This was the original workload used in Phase 1 simulation testing
 * (bench_fib_rec in firmware.c), and the first workload tested on hardware.
 * Simulation results (16-set direct-mapped icache):
 *   No cache:   288,074 cycles  (fib(10))
 *   With cache: 161,387 cycles  (fib(10))  → 1.78× speedup
 * Hardware results with QDDR flash (fib(15)):
 *   No cache:  3,201,186 cycles  (0x0030d8a2)
 *   With cache: 1,777,806 cycles  (0x001b208e)  → 1.80× speedup
 *
 * Cache properties:
 *   Instruction cache — function body is ~10 instructions, fits easily
 *                       within a 16-set cache; near-100% hit rate after
 *                       cold start due to tiny instruction footprint.
 *   Data cache        — no flash data reads; all state is in registers
 *                       and on the stack.
 *
 * Expected return value: 0x62 (98 decimal) — fib(15) mod 256.
 *   fib(15) = 610; 610 & 0xFF = 98.
 */

#include <stdint.h>
#include <stdbool.h>

#ifdef ICEBREAKER
#  define MEM_TOTAL 0x20000
#else
#  error "Set -DICEBREAKER when compiling this C source file"
#endif

extern uint32_t sram;

#define reg_spictrl     (*(volatile uint32_t*)0x02000000)
#define reg_uart_clkdiv (*(volatile uint32_t*)0x02000004)
#define reg_uart_data   (*(volatile uint32_t*)0x02000008)
#define reg_leds        (*(volatile uint8_t*)0x03000000)
#define reg_7seg        (*(volatile uint8_t*)0x03000004)

extern uint32_t flashio_worker_begin;
extern uint32_t flashio_worker_end;

void flashio(uint8_t* data, int len, uint8_t wrencmd) {
	uint32_t func[&flashio_worker_end - &flashio_worker_begin];
	uint32_t* src_ptr = &flashio_worker_begin;
	uint32_t* dst_ptr = func;
	while (src_ptr != &flashio_worker_end)
		*(dst_ptr++) = *(src_ptr++);
	((void(*)(uint8_t*, uint32_t, uint32_t))func)(data, len, wrencmd);
}

void set_flash_qspi_flag() {
	uint8_t buffer[8];
	buffer[0] = 0x35; buffer[1] = 0x00;
	flashio(buffer, 2, 0);
	uint8_t sr2 = buffer[1];
	buffer[0] = 0x31; buffer[1] = sr2 | 2;
	flashio(buffer, 2, 0x50);
}
void set_flash_mode_qddr() { reg_spictrl = (reg_spictrl & ~0x007f0000) | 0x00670000; }

void putchar(char c) { if (c == '\n') putchar('\r'); reg_uart_data = c; }
void print(const char* p) { while (*p) putchar(*(p++)); }
void print_hex(uint32_t v, int digits) {
	for (int i = 7; i >= 0; i--) {
		char c = "0123456789abcdef"[(v >> (4*i)) & 15];
		if (c == '0' && i >= digits) continue;
		putchar(c); digits = i;
	}
}

void setup_picosoc(void) {
	reg_uart_clkdiv = 104; reg_leds = 0x00;
	set_flash_qspi_flag(); set_flash_mode_qddr();
}

// --------------------------------------------------------

static uint32_t fib_rec(int n) {
	if (n <= 1) return n;
	return fib_rec(n-1) + fib_rec(n-2);
}

unsigned char run_workload(void) {
	return (unsigned char)(fib_rec(15) & 0xFF);
}

void main(void) {
	setup_picosoc();
	unsigned char leds_value = 0x20;
	while (1) { reg_7seg = run_workload(); reg_leds = leds_value; leds_value ^= 0x20; }
}
