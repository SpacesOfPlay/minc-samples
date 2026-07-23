// bench_fib_iter.c - iterative fibonacci benchmark
#include "bench_timer.h"

static long long fib(int n) {
    long long a = 0, b = 1;
    for (int i = 0; i < n; i++) {
        long long t = a + b;
        a = b;
        b = t;
    }
    return a;
}

int main(void) {
    volatile int n = 92;
    // Warm up
    long long r = fib(n);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    long long result = 0;
    for (int iter = 0; iter < 10000000; iter++) {
        result = fib(n);
        BENCH_USE(result);
    }
    bench_timer_start(&t2);

    // fib(92) = 7540113804746346429
    if (result != 7540113804746346429LL) return 1;

    long long elapsed = bench_elapsed_us(t1, t2);
    printf("fib_iter: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
