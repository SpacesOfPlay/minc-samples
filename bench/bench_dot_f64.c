// bench_dot_f64.c - dot product benchmark (streaming FMA throughput)
#include "bench_timer.h"

static void init_arrays(double *a, double *b, int n) {
    long long state = 12345;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        a[i] = (double)((int)((state >> 33) & 1023));
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        b[i] = (double)((int)((state >> 33) & 1023));
    }
}

static double dot_product(double *a, double *b, int n) {
    double sum = 0.0;
    for (int i = 0; i < n; i++) {
        sum += a[i] * b[i];
    }
    return sum;
}

int main(void) {
    int n = 10000000;
    size_t sz = (size_t)n * sizeof(double);
    double *a = (double *)malloc(sz);
    double *b = (double *)malloc(sz);
    init_arrays(a, b, n);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    double result = 0.0;
    for (int iter = 0; iter < 10; iter++) {
        result = dot_product(a, b, n);
        BENCH_USE((long long)result);
    }
    bench_timer_start(&t2);

    long long res = (long long)result;
    long long elapsed = bench_elapsed_us(t1, t2);
    free(a);
    free(b);
    printf("dot_f64: result=%lld time=%lld us\n", res, elapsed);
    return 0;
}
