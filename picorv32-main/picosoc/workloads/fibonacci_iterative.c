/*
 * fibonacci_iterative.c — Iterative Fibonacci benchmark
 *
 * Computes 100 Fibonacci numbers iteratively using unsigned char arithmetic
 * (values wrap at 256). Array is stack-allocated (SRAM).
 *
 * Cache properties:
 *   Instruction cache — single tight loop; very small instruction footprint,
 *                       fits entirely within a 16-set cache after first pass.
 *   Data cache        — fib_numbers[] is on the stack (SRAM); no benefit
 *                       from data cache.
 *
 * Expected return value: 0xC3 (195 decimal) — fib_numbers[99] mod 256.
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
#define reg_7seg        (*(volatile uint8_t*)0x03000001)

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
	reg_uart_clkdiv = 104; reg_7seg = 0x03; reg_leds = 0x00;
	set_flash_qspi_flag(); set_flash_mode_qddr();
}

// --------------------------------------------------------

#define FIB_SIZE 100

unsigned char run_workload(void) {
	unsigned char fib_numbers[FIB_SIZE];
	fib_numbers[0] = 1;
	fib_numbers[1] = 1;
	for (int i = 2; i < FIB_SIZE; i++)
		fib_numbers[i] = fib_numbers[i-1] + fib_numbers[i-2];
	return fib_numbers[FIB_SIZE - 1];
}

unsigned char run_workload_timed(void) {
	uint32_t t0, t1, i0, i1;
	__asm__ volatile ("rdcycle   %0" : "=r"(t0));
	__asm__ volatile ("rdinstret %0" : "=r"(i0));
	unsigned char result = run_workload();
	__asm__ volatile ("rdcycle   %0" : "=r"(t1));
	__asm__ volatile ("rdinstret %0" : "=r"(i1));
	print("Cycles: 0x"); print_hex(t1 - t0, 8); putchar('\n');
	print("Instns: 0x"); print_hex(i1 - i0, 8); putchar('\n');
	print("Result: 0x"); print_hex(result,   2); putchar('\n');
	return result;
}

void main(void) {
	setup_picosoc();
	unsigned char leds_value = 0x02;
	run_workload_timed();
	while (1) { reg_7seg = run_workload(); reg_leds = leds_value; leds_value ^= 0x02; }
}
