/*
 * test_FIR.c — Host PC verification
 * Expected result: 0x83 (131 decimal)
 *
 * Compile: gcc test_FIR.c -o test_FIR && ./test_FIR
 */

#include <stdint.h>
#include <stdio.h>

#define SIGNAL_SIZE 100
#define FILTER_SIZE 16

unsigned char run_workload(void) {
    unsigned char signal[SIGNAL_SIZE] = {
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
    unsigned char filter_coeffs[FILTER_SIZE] = {
        4, 7, 2, 10, 12, 32, 20, 18, 6, 3, 24, 31, 8, 11, 15, 6
    };
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

int main(void) {
    unsigned char result = run_workload();
    printf("FIR: 0x%02X (%d decimal)\n", result, result);
    return 0;
}
