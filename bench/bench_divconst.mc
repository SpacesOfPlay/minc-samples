// bench_divconst.mc - integer division by constant (magic multiply + shift strength reduction)
#include "bench_util.mc"

i64 divconst(i32* arr, i32 n) {
    i64 sum = 0;
    for i32 i = 0; i < n; i++ {
        // Division by 7 (non-power-of-2) — tests magic multiply optimization
        sum = sum + arr[i] / 7;
    }
    return sum;
}

void fill_data(i32* arr, i32 n) {
    i64 state = 44444;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        arr[i] = cast(i32, (state >> 33) & 0x7FFFFFFF);
    }
}

i32 main() {
    i32 n = 10_000_000;
    i32* arr = alloc<i32>(n);
    fill_data(arr, n);

    // Warm up
    i64 result = divconst(arr, n);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 50; iter++ {
        result = divconst(arr, n);
    }
    i64 end = qpc();

    free(arr);
    bench_print("divconst", result, elapsed_us(start, end, freq));
    return 0;
}
