// bench_branch_chain.c - branch-heavy classify loop benchmark
#include "bench_timer.h"

static long long branch_chain(int *arr, int n) {
    long long bins[8] = {0};
    for (int i = 0; i < n; i++) {
        int v = arr[i];
        int bin;
        // Nested if/else chain classifying into 8 bins
        if (v < 0) {
            bin = 0;
        } else if (v < 16) {
            bin = 1;
        } else if (v < 64) {
            bin = 2;
        } else if (v < 256) {
            bin = 3;
        } else if (v < 1024) {
            bin = 4;
        } else if (v < 4096) {
            bin = 5;
        } else if (v < 16384) {
            bin = 6;
        } else {
            bin = 7;
        }
        bins[bin]++;
    }
    // Weighted checksum
    long long cs = 0;
    for (int i = 0; i < 8; i++) {
        cs += bins[i] * (long long)(i + 1);
    }
    return cs;
}

static void fill_data(int *arr, int n) {
    long long state = 66666;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        // Mix of negative and positive values across all bin ranges
        arr[i] = (int)(state >> 33) - 5000;
    }
}

int main(void) {
    int n = 10000000;
    int *arr = (int *)malloc((size_t)n * sizeof(int));
    fill_data(arr, n);

    // Warm up
    long long result = branch_chain(arr, n);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 50; iter++) {
        result = branch_chain(arr, n);
        BENCH_USE(result);
    }
    bench_timer_start(&t2);

    free(arr);
    long long elapsed = bench_elapsed_us(t1, t2);
    printf("branch_chain: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
