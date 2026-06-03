/*
 * test_fibonacci_recursive.c — Host PC verification
 * Expected result: 0x62 (98 decimal) — Fibonacci(15) mod 256
 *
 * Compile: gcc test_fibonacci_recursive.c -o test_fib_rec && ./test_fib_rec
 */

#include <stdint.h>
#include <stdio.h>

static uint32_t fib_rec(int n) {
    if (n <= 1) return n;
    return fib_rec(n-1) + fib_rec(n-2);
}

unsigned char run_workload(void) {
    return (unsigned char)(fib_rec(15) & 0xFF);
}

int main(void) {
    unsigned char result = run_workload();
    printf("Fibonacci Recursive: 0x%02X (%d decimal)\n", result, result);
    if (result == 0x62) printf("✓ CORRECT\n");
    else printf("✗ MISMATCH (expected 0x62)\n");
    return 0;
}
