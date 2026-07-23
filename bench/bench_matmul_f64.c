// bench_matmul_f64.c - floating-point matrix multiply benchmark
#include "bench_timer.h"

#define MAT_N 512

static void mat_fill_f64(double *m, int n, int seed) {
    long long state = (long long)seed;
    for (int i = 0; i < n * n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        m[i] = (double)((int)((state >> 33) % 100));
    }
}

static void mat_mul_f64(double *c, double *a, double *b, int n) {
    for (int i = 0; i < n * n; i++) c[i] = 0.0;
    for (int i = 0; i < n; i++) {
        for (int k = 0; k < n; k++) {
            double aik = a[i * n + k];
            for (int j = 0; j < n; j++) {
                c[i * n + j] += aik * b[k * n + j];
            }
        }
    }
}

static long long mat_diag_sum_f64(double *m, int n) {
    double sum = 0.0;
    for (int i = 0; i < n; i++) {
        sum += m[i * n + i];
    }
    return (long long)sum;
}

int main(void) {
    int n = MAT_N;
    size_t sz = (size_t)n * n * sizeof(double);
    double *a = (double *)malloc(sz);
    double *b = (double *)malloc(sz);
    double *c = (double *)malloc(sz);

    mat_fill_f64(a, n, 42);
    mat_fill_f64(b, n, 99);

    // Warm up
    mat_mul_f64(c, a, b, n);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 3; iter++) {
        mat_mul_f64(c, a, b, n);
        BENCH_CLOBBER(c);
    }
    bench_timer_start(&t2);

    long long diag = mat_diag_sum_f64(c, n);

    free(a);
    free(b);
    free(c);

    long long elapsed = bench_elapsed_us(t1, t2);
    printf("matmul_f64: result=%lld time=%lld us\n", diag, elapsed);
    return 0;
}
