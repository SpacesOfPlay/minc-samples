// bench_cast_loop.c - int/float conversion chain benchmark
#include "bench_timer.h"

static long long cast_loop(int *arr, int n) {
    double running_avg = 0.0;
    long long isum = 0;
    for (int i = 0; i < n; i++) {
        int v = arr[i];
        // Int to float: update running average
        double fv = (double)v;
        running_avg = running_avg + (fv - running_avg) / (double)(i + 1);
        // Float to int: accumulate truncated partial average
        int iavg = (int)running_avg;
        isum += (long long)iavg;
    }
    // Combine both results into checksum
    return isum + (long long)(int)(running_avg * 1000.0);
}

static void fill_data(int *arr, int n) {
    long long state = 77777;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        arr[i] = (int)((state >> 33) % 10000);
    }
}

int main(void) {
    int n = 10000000;
    int *arr = (int *)malloc((size_t)n * sizeof(int));
    fill_data(arr, n);

    // Warm up
    long long result = cast_loop(arr, n);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 20; iter++) {
        result = cast_loop(arr, n);
        BENCH_USE(result);
    }
    bench_timer_start(&t2);

    free(arr);
    long long elapsed = bench_elapsed_us(t1, t2);
    printf("cast_loop: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
