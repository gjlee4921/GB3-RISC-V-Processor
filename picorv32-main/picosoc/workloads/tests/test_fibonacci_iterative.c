/*
 * test_fibonacci_iterative.c — Host PC verification
 * Expected result: 0xC3 (195 decimal) — Fibonacci(100) mod 256
 *
 * Compile: gcc test_fibonacci_iterative.c -o test_fib_iter && ./test_fib_iter
 */

#include <stdint.h>
#include <stdio.h>

#define FIB_SIZE 100

unsigned char run_workload(void) {
    unsigned char fib_numbers[FIB_SIZE];
    fib_numbers[0] = 1;
    fib_numbers[1] = 1;

    for (int i = 2; i < FIB_SIZE; i++)
        fib_numbers[i] = fib_numbers[i-1] + fib_numbers[i-2];

    return fib_numbers[FIB_SIZE - 1];
}

int main(void) {
    unsigned char result = run_workload();
    printf("Fibonacci Iterative: 0x%02X (%d decimal)\n", result, result);
    return 0;
}
