// bench_hash_probe.mc - open-addressing hash table with linear probing (insert + lookup)
#include "bench_util.mc"

i32 hash_key(i64 key, i32 mask) {
    return cast(i32, ((key * (0 - 7_046_029_254_386_353_131)) >> 33) & mask);
}

void ht_insert(i64* table, i32 mask, i64 key) {
    i32 idx = hash_key(key, mask);
    while table[idx] != 0 {
        if table[idx] == key { return; }
        idx = (idx + 1) & mask;
    }
    table[idx] = key;
}

bool ht_lookup(i64* table, i32 mask, i64 key) {
    i32 idx = hash_key(key, mask);
    while table[idx] != 0 {
        if table[idx] == key { return true; }
        idx = (idx + 1) & mask;
    }
    return false;
}

i64 run_hash(i64* keys, i32 nkeys, i64* table, i32 capacity, i32 mask) {
    // Clear table
    memset(cast(void*, table), 0, capacity * 8);

    // Insert all keys
    for i32 i = 0; i < nkeys; i++ {
        ht_insert(table, mask, keys[i]);
    }

    // Lookup all keys, count hits
    i64 count = 0;
    for i32 i = 0; i < nkeys; i++ {
        if ht_lookup(table, mask, keys[i]) {
            count++;
        }
    }
    return count;
}

i32 main() {
    i32 nkeys = 2_000_000;
    i32 capacity = 4_194_304;  // 2^22
    i32 mask = capacity - 1;

    i64* keys = alloc<i64>(nkeys);
    i64* table = alloc<i64>(capacity);

    // Generate random keys (non-zero)
    i64 state = 54321;
    for i32 i = 0; i < nkeys; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        keys[i] = ((state >> 33) & 0x7FFFFFFF) | 1;
    }

    // Warm up
    i64 result = run_hash(keys, nkeys, table, capacity, mask);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 3; iter++ {
        result = run_hash(keys, nkeys, table, capacity, mask);
    }
    i64 end = qpc();

    free(table);
    free(keys);
    bench_print("hash_probe", result, elapsed_us(start, end, freq));
    return 0;
}
