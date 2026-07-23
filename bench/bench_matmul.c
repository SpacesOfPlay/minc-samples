// bench_matmul.c - matrix multiply benchmark
#include "bench_timer.h"
#include <string.h>

#define MAT_N 512

static void mat_fill(int *m, int n, int seed) {
    long long state = (long long)seed;
    for (int i = 0; i < n * n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        m[i] = (int)((state >> 33) % 100);
    }
}

static void mat_mul(int *c, int *a, int *b, int n) {
    memset(c, 0, (size_t)n * n * 4);
    for (int i = 0; i < n; i++) {
        for (int k = 0; k < n; k++) {
            int aik = a[i * n + k];
            for (int j = 0; j < n; j++) {
                c[i * n + j] += aik * b[k * n + j];
            }
        }
    }
}

static long long mat_diag_sum(int *m, int n) {
    long long sum = 0;
    for (int i = 0; i < n; i++) {
        sum += (long long)m[i * n + i];
    }
    return sum;
}

int main(void) {
    int n = MAT_N;
    int sz = n * n * 4;
    int *a = (int *)malloc(sz);
    int *b = (int *)malloc(sz);
    int *c = (int *)malloc(sz);

    mat_fill(a, n, 42);
    mat_fill(b, n, 99);

    // Warm up
    mat_mul(c, a, b, n);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 3; iter++) {
        mat_mul(c, a, b, n);
        BENCH_CLOBBER(c);
    }
    bench_timer_start(&t2);

    long long diag = mat_diag_sum(c, n);

    free(a);
    free(b);
    free(c);

    long long elapsed = bench_elapsed_us(t1, t2);
    printf("matmul: result=%lld time=%lld us\n", diag, elapsed);
    return 0;
}
