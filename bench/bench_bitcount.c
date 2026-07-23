// bench_bitcount.c - population count benchmark (Kernighan's method)
#include "bench_timer.h"

static long long count_bits(int *arr, int n) {
    long long total = 0;
    for (int i = 0; i < n; i++) {
        total += bench_popcount((unsigned int)arr[i]);
    }
    return total;
}

static void fill_random(int *arr, int n) {
    long long state = 77777;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        arr[i] = (int)((state >> 33) & 2147483647LL);
    }
}

int main(void) {
    int n = 10000000;
    int *arr = (int *)malloc((size_t)n * 4);
    fill_random(arr, n);

    // Warm up
    long long result = count_bits(arr, n);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 5; iter++) {
        result = count_bits(arr, n);
        BENCH_USE(result);
    }
    bench_timer_start(&t2);

    free(arr);
    long long elapsed = bench_elapsed_us(t1, t2);
    printf("bitcount: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
