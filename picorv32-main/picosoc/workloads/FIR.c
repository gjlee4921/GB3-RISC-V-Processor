/*
 * FIR.c — 16-tap FIR filter benchmark
 *
 * 16-tap FIR filter applied to a 100-sample signal.
 * Coefficients sum to 209; output normalised by dividing by 209.
 *
 * Cache properties:
 *   Instruction cache — tight nested loop (100 × 16 = 1600 iterations);
 *                       inner body reuses the same instructions each pass.
 *   Data cache        — signal[] and filter_coeffs[] are stack-allocated
 *                       (SRAM); declaring them static const would move them
 *                       to flash (.rodata) and exercise the data cache.
 *
 * Expected return value: 0x83 (131 decimal) — output[99].
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

#define SIGNAL_SIZE 100
#define FILTER_SIZE 16

static const unsigned char signal_init[SIGNAL_SIZE] = {
    217,  43, 189,  12, 156,  78, 234,  67, 143,  29,
    198,  54, 112, 245,  33, 167,  89, 201,  11, 178,
     56, 223,  91, 134,  45, 187,  23, 209,  77, 155,
    102, 241,  18, 163,  84, 220,  37, 171,  62, 248,
      9, 145,  73, 196,  28, 183,  51, 229,  94, 137,
    212,  41, 175,   6, 158,  82, 233,  16, 149,  70,
    205,  38, 191,  55, 240,  25, 168,  97, 214,  44,
    130,  87, 203,  19, 176,  61, 238,  13, 152,  79,
    218,  48, 193,  31, 160,  95, 222,  36, 174,  58,
    245,  21, 138,  75, 210,  46, 185,  27, 166,  92
};

static const unsigned char filter_coeffs[FILTER_SIZE] = {
    4, 7, 2, 10, 12, 32, 20, 18, 6, 3, 24, 31, 8, 11, 15, 6
};

unsigned char run_workload(void) {
	unsigned char signal[SIGNAL_SIZE];
	for (int i = 0; i < SIGNAL_SIZE; i++) signal[i] = signal_init[i];
	unsigned char output[SIGNAL_SIZE];
	for (int i = 0; i < SIGNAL_SIZE; i++) {
		uint32_t sum = 0;
		for (int j = 0; j < FILTER_SIZE; j++)
			if (i - j >= 0)
				sum += signal[i - j] * filter_coeffs[j];
		output[i] = sum / 209;
	}
	return output[SIGNAL_SIZE - 1];
}

void main(void) {
	setup_picosoc();
	unsigned char leds_value = 0x20;
	while (1) { reg_7seg = run_workload(); reg_leds = leds_value; leds_value ^= 0x20; }
}
