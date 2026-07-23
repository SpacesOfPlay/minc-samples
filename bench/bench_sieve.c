// bench_sieve.c - Sieve of Eratosthenes benchmark
#include "bench_timer.h"
#include <string.h>

static int sieve(unsigned char *flags, int size) {
    memset(flags, 1, size);
    flags[0] = 0;
    flags[1] = 0;

    int i = 2;
    while (i * i < size) {
        if (flags[i]) {
            int j = i * i;
            while (j < size) {
                flags[j] = 0;
                j += i;
            }
        }
        i++;
    }

    int count = 0;
    for (int k = 0; k < size; k++) {
        if (flags[k]) count++;
    }
    return count;
}

int main(void) {
    int size = 10000000;
    unsigned char *flags = (unsigned char *)malloc(size);

    // Warm up
    int count = sieve(flags, size);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 10; iter++) {
        count = sieve(flags, size);
        BENCH_USE((long long)count);
    }
    bench_timer_start(&t2);

    free(flags);

    if (count != 664579) return 1;

    long long elapsed = bench_elapsed_us(t1, t2);
    printf("sieve: result=%d time=%lld us\n", count, elapsed);
    return 0;
}
