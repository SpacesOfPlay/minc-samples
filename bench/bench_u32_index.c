// bench_u32_index.c - u32 loop-counter / array-index benchmark.
// MSVC reference for bench_u32_index.mc.
#include "bench_timer.h"
#include <string.h>
#include <stdint.h>

static uint32_t hash_chain(uint32_t *a, uint32_t n) {
    uint32_t acc = 0xDEADBEEFu;
    for (uint32_t i = 0; i < n; i++) {
        acc = acc ^ a[i];
        acc = acc * 0x9E3779B9u;
        acc = acc ^ (acc >> 16);
        acc = acc + i;
    }
    return acc;
}

static uint32_t jump_chain(uint32_t *a, uint32_t n, uint32_t iters) {
    uint32_t idx = 0;
    uint32_t acc = 0;
    for (uint32_t k = 0; k < iters; k++) {
        uint32_t v = a[idx & (n - 1u)];
        acc = acc ^ v;
        idx = (idx + v) ^ k;
    }
    return acc;
}

static uint64_t hist_scatter(uint32_t *buf, uint32_t size) {
    uint32_t counts[256];
    memset(counts, 0, sizeof(counts));
    for (uint32_t i = 0; i < size; i++) {
        uint32_t b = buf[i] & 255u;
        counts[b] = counts[b] + 1u;
    }
    uint64_t cs = 0;
    for (uint32_t i = 0; i < 256; i++) {
        cs = cs + (uint64_t)counts[i] * (uint64_t)i;
    }
    return cs;
}

int main(void) {
    uint32_t size = 1048576u;       // power of 2 for jump_chain mask
    uint32_t *buf = (uint32_t *)malloc((size_t)size * sizeof(uint32_t));
    uint64_t state = 11111;
    for (uint32_t i = 0; i < size; i++) {
        state = state * 6364136223846793005ULL + 1442695040888963407ULL;
        buf[i] = (uint32_t)((state >> 33) & 0xFFFFFFFFu);
    }

    // Warm up
    uint32_t r1 = hash_chain(buf, size);
    uint32_t r2 = jump_chain(buf, size, size);
    uint64_t r3 = hist_scatter(buf, size);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (uint32_t iter = 0; iter < 50; iter++) {
        r1 ^= hash_chain(buf, size);
        r2 ^= jump_chain(buf, size, size);
        r3 += hist_scatter(buf, size);
        BENCH_USE(r1);
        BENCH_USE(r2);
        BENCH_USE(r3);
    }
    bench_timer_start(&t2);

    free(buf);
    long long result = (long long)(uint64_t)r1 ^ (long long)(uint64_t)r2 ^ (long long)r3;
    long long elapsed = bench_elapsed_us(t1, t2);
    printf("u32_index: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
