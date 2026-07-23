// bench_bitops.c - bitwise operation chains benchmark
#include "bench_timer.h"

static long long bitops(long long *arr, int n) {
    long long acc = 0;
    long long mask = 0xA5A5A5A5A5A5A5A5LL;
    for (int i = 0; i < n; i++) {
        long long v = arr[i];
        // XOR with rolling mask
        v = v ^ mask;
        // Popcount the full 64-bit value (split into two i32 halves)
        acc += bench_popcount((unsigned int)(v & 0xFFFFFFFF)) +
               bench_popcount((unsigned int)((v >> 32) & 0xFFFFFFFF));
        // Bitwise chain: shift, XOR, AND/OR (feeds back into accumulator)
        long long hi = (v >> 32) & 0xFFFFFFFF;
        long long lo = v & 0xFFFFFFFF;
        long long mixed = (hi ^ lo) | ((v >> 16) & 0xFF00FF);
        acc ^= mixed;
        // Rotate mask
        mask = (mask << 7) | (((unsigned long long)mask) >> 57);
    }
    return acc;
}

static void fill_data(long long *arr, int n) {
    long long state = 55555;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        arr[i] = state;
    }
}

int main(void) {
    int n = 10000000;
    long long *arr = (long long *)malloc((size_t)n * sizeof(long long));
    fill_data(arr, n);

    // Warm up
    long long result = bitops(arr, n);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 50; iter++) {
        result = bitops(arr, n);
        BENCH_USE(result);
    }
    bench_timer_start(&t2);

    free(arr);
    long long elapsed = bench_elapsed_us(t1, t2);
    printf("bitops: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
