// bench_divconst.c - integer division by constant benchmark
#include "bench_timer.h"

static long long divconst(int *arr, int n) {
    long long sum = 0;
    for (int i = 0; i < n; i++) {
        // Division by 7 (non-power-of-2) — tests magic multiply optimization
        sum += arr[i] / 7;
    }
    return sum;
}

static void fill_data(int *arr, int n) {
    long long state = 44444;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        arr[i] = (int)((state >> 33) & 0x7FFFFFFF);
    }
}

int main(void) {
    int n = 10000000;
    int *arr = (int *)malloc((size_t)n * sizeof(int));
    fill_data(arr, n);

    // Warm up
    long long result = divconst(arr, n);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 50; iter++) {
        result = divconst(arr, n);
        BENCH_USE(result);
    }
    bench_timer_start(&t2);

    free(arr);
    long long elapsed = bench_elapsed_us(t1, t2);
    printf("divconst: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
