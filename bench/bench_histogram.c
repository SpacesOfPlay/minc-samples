// bench_histogram.c - byte frequency histogram benchmark
#include "bench_timer.h"
#include <string.h>

static long long histogram(unsigned char *buf, int size) {
    int counts[256];
    memset(counts, 0, sizeof(counts));
    for (int i = 0; i < size; i++) {
        counts[buf[i]]++;
    }
    // Weighted checksum
    long long cs = 0;
    for (int i = 0; i < 256; i++) {
        cs += (long long)counts[i] * (long long)i;
    }
    return cs;
}

static void fill_random(unsigned char *buf, int n) {
    long long state = 11111;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        buf[i] = (unsigned char)((state >> 33) & 255);
    }
}

int main(void) {
    int size = 50000000;
    unsigned char *buf = (unsigned char *)malloc((size_t)size);
    fill_random(buf, size);

    // Warm up
    long long result = histogram(buf, size);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 20; iter++) {
        result = histogram(buf, size);
        BENCH_USE(result);
    }
    bench_timer_start(&t2);

    free(buf);
    long long elapsed = bench_elapsed_us(t1, t2);
    printf("histogram: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
