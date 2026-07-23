// Bitwise operation chains benchmark
// Tests XOR/AND/OR chains, shift patterns, mask CSE, popcount.

#include "bench_util.mc"

i64 bitops(i64* arr, i32 n) {
    i64 acc = 0;
    u64 mask = 0xA5A5A5A5A5A5A5A5;
    for i32 i = 0; i < n; i++ {
        i64 v = arr[i];
        // XOR with rolling mask
        v = v ^ mask;
        // Popcount the full 64-bit value (split into two i32 halves)
        acc = acc + popcount(cast(i32, v & 0xFFFFFFFF))
                  + popcount(cast(i32, (v >> 32) & 0xFFFFFFFF));
        // Bitwise chain: shift, XOR, AND/OR
        i64 hi = (v >> 32) & 0xFFFFFFFF;
        i64 lo = v & 0xFFFFFFFF;
        i64 mixed = (hi ^ lo) | ((v >> 16) & 0xFF00FF);
        acc = acc ^ mixed;
        // Rotate mask
        mask = (mask << 7) | (mask >> 57);
    }
    return acc;
}

void fill_data(i64* arr, i32 n) {
    i64 state = 55555;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        arr[i] = state;
    }
}

i32 main() {
    i32 n = 10_000_000;
    i64* arr = alloc<i64>(n);
    fill_data(arr, n);

    // Warm up
    i64 result = bitops(arr, n);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 50; iter++ {
        result = bitops(arr, n);
    }
    i64 end = qpc();

    free(arr);
    bench_print("bitops", result, elapsed_us(start, end, freq));
    return 0;
}
