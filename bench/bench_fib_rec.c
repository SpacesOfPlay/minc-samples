// bench_fib_rec.c - recursive fibonacci benchmark
#include "bench_timer.h"

#ifdef _WIN32
__declspec(noinline)
#else
__attribute__((noinline))
#endif
static int fib(int n) {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}

int main(void) {
    // Use volatile to prevent compile-time evaluation
    volatile int n = 40;

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    int result = 0;
    for (int iter = 0; iter < 3; iter++) {
        result = fib(n);
        BENCH_USE((long long)result);
    }
    bench_timer_start(&t2);

    if (result != 102334155) return 1;

    long long elapsed = bench_elapsed_us(t1, t2);
    printf("fib_rec: result=%d time=%lld us\n", result, elapsed);
    return 0;
}
