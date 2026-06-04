/*
 * test_bubble_sort.c — Host PC verification
 * Expected result: 0xFC (252 decimal)
 *
 * Compile: gcc test_bubble_sort.c -o test_bubble_sort && ./test_bubble_sort
 */

#include <stdint.h>
#include <stdio.h>

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

    int i, j;
    unsigned char temp;
    for (i = 0; i < ARRAY_SIZE - 1; i++)
        for (j = 0; j < ARRAY_SIZE - i - 1; j++)
            if (numbers[j] > numbers[j + 1]) {
                temp = numbers[j];
                numbers[j] = numbers[j+1];
                numbers[j+1] = temp;
            }

    return numbers[ARRAY_SIZE - 1];
}

int main(void) {
    unsigned char result = run_workload();
    printf("Bubble Sort: 0x%02X (%d decimal)\n", result, result);
    return 0;
}
