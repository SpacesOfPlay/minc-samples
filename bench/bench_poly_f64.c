// bench_poly_f64.c - Horner polynomial evaluation (FMA latency chain)
#include "bench_timer.h"

static double poly_eval(double x) {
    // Degree-8 polynomial: c0 + x*(c1 + x*(c2 + ...))
    double r = 1.1;
    r = r * x + (-3.2);
    r = r * x + 0.9;
    r = r * x + (-1.8);
    r = r * x + 2.1;
    r = r * x + (-0.5);
    r = r * x + 3.7;
    r = r * x + (-2.3);
    r = r * x + 1.5;
    return r;
}

int main(void) {
    int n = 5000000;
    size_t sz = (size_t)n * sizeof(double);
    double *xs = (double *)malloc(sz);

    // Initialize input array with varied values
    long long state = 54321;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        int raw = (int)((state >> 33) % 4000) - 2000;
        xs[i] = (double)raw * 0.001;
    }

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    double sum = 0.0;
    for (int iter = 0; iter < 5; iter++) {
        sum = 0.0;
        for (int i = 0; i < n; i++) {
            sum += poly_eval(xs[i]);
        }
        BENCH_USE((long long)sum);
    }
    bench_timer_start(&t2);

    long long res = (long long)sum;
    long long elapsed = bench_elapsed_us(t1, t2);
    free(xs);
    printf("poly_f64: result=%lld time=%lld us\n", res, elapsed);
    return 0;
}
