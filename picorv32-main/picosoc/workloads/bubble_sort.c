/*
 * bubble_sort.c — Bubble sort benchmark
 *
 * Sorts a fixed 100-element array of unsigned chars in ascending order.
 * Up to 99 outer passes; inner loop shrinks each pass as the sorted
 * suffix grows.
 *
 * Cache properties:
 *   Instruction cache — small nested loop body; strong temporal locality.
 *   Data cache        — numbers[] is stack-allocated (SRAM); no flash data
 *                       reads during the sort.
 *
 * Expected return value: 0xFC (252 decimal) — maximum element at numbers[99].
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

#define ARRAY_SIZE 100

unsigned char run_workload(void) {
	unsigned char numbers[ARRAY_SIZE] = {
	   142,  87, 213,  42, 119,   8, 176,  54, 231,  99,
	    12, 165,  74, 201,  33, 150,  88, 245,  19, 111,
	   182,  63, 137,  95, 222,   4, 158,  81, 209,  47,
	   126,  71, 194,  28, 147, 252,  91,  16, 115, 170,
	    58, 239,  83, 132,   2, 205,  67, 149, 226,  38,
	   104, 188,  51, 161,  94, 242,  11, 123,  79, 217,
	   134,  45, 173,  89, 250,  23, 155,  61, 199, 108,
	    31, 140, 212,  76,   7, 185,  53, 167, 234,  92,
	   121,  14, 203,  69, 152,  41, 228,  85, 114, 191,
	    26, 179,  60, 247,  97, 136,   5, 221,  73, 162
	};
	int i, j; unsigned char temp;
	for (i = 0; i < ARRAY_SIZE - 1; i++)
		for (j = 0; j < ARRAY_SIZE - i - 1; j++)
			if (numbers[j] > numbers[j + 1]) {
				temp = numbers[j]; numbers[j] = numbers[j+1]; numbers[j+1] = temp;
			}
	return numbers[ARRAY_SIZE - 1];
}

void main(void) {
	setup_picosoc();
	unsigned char leds_value = 0x20;
	while (1) { reg_7seg = run_workload(); reg_leds = leds_value; leds_value ^= 0x20; }
}
