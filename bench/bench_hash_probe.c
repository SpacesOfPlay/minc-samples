// bench_hash_probe.c - open-addressing hash table benchmark
#include "bench_timer.h"
#include <string.h>

static int hash_key(long long key, int mask) {
    return (int)(((key * (-7046029254386353131LL)) >> 33) & (long long)mask);
}

static void ht_insert(long long *table, int mask, long long key) {
    int idx = hash_key(key, mask);
    while (table[idx] != 0) {
        if (table[idx] == key) return;
        idx = (idx + 1) & mask;
    }
    table[idx] = key;
}

static int ht_lookup(long long *table, int mask, long long key) {
    int idx = hash_key(key, mask);
    while (table[idx] != 0) {
        if (table[idx] == key) return 1;
        idx = (idx + 1) & mask;
    }
    return 0;
}

static long long run_hash(long long *keys, int nkeys, long long *table, int capacity, int mask) {
    // Clear table
    memset(table, 0, (size_t)capacity * 8);

    // Insert all keys
    for (int i = 0; i < nkeys; i++) {
        ht_insert(table, mask, keys[i]);
    }

    // Lookup all keys, count hits
    long long count = 0;
    for (int i = 0; i < nkeys; i++) {
        if (ht_lookup(table, mask, keys[i])) {
            count++;
        }
    }
    return count;
}

int main(void) {
    int nkeys = 2000000;
    int capacity = 4194304;  // 2^22
    int mask = capacity - 1;

    long long *keys = (long long *)malloc((size_t)nkeys * 8);
    long long *table = (long long *)malloc((size_t)capacity * 8);

    // Generate random keys (non-zero)
    long long state = 54321;
    for (int i = 0; i < nkeys; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        keys[i] = ((state >> 33) & 2147483647LL) | 1;
    }

    // Warm up
    long long result = run_hash(keys, nkeys, table, capacity, mask);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 3; iter++) {
        result = run_hash(keys, nkeys, table, capacity, mask);
        BENCH_USE(result);
    }
    bench_timer_start(&t2);

    free(table);
    free(keys);
    long long elapsed = bench_elapsed_us(t1, t2);
    printf("hash_probe: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
