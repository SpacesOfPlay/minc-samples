// Population count benchmark
// Counts set bits in 10M random integers using hardware popcount.

#include "bench_util.mc"

i64 count_bits(i32* arr, i32 n) {
    i64 total;
    for i32 i = 0; i < n; i++ {
        total += popcount(arr[i]);
    }
    return total;
}

void fill_random(i32* arr, i32 n) {
    i64 state = 77777;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        arr[i] = cast(i32, (state >> 33) & 0x7FFFFFFF);
    }
}

i32 main() {
    i32 n = 10_000_000;
    i32* arr = alloc<i32>(n);
    fill_random(arr, n);

    // Warm up
    i64 result = count_bits(arr, n);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 5; iter++ {
        result = count_bits(arr, n);
    }
    i64 end = qpc();

    free(arr);
    bench_print("bitcount", result, elapsed_us(start, end, freq));
    return 0;
}
