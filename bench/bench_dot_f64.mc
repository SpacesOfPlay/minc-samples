// bench_dot_f64.mc - f64 dot product (10M elements, streaming FMA throughput)
#include "bench_util.mc"

void init_arrays(f64* a, f64* b, i32 n) {
    i64 state = 12_345;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        a[i] = cast(i32, (state >> 33) & 1023);
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        b[i] = cast(i32, (state >> 33) & 1023);
    }
}

f64 dot_product(f64* a, f64* b, i32 n) {
    f64 sum = 0.0;
    for i32 i = 0; i < n; i++ {
        sum = sum + a[i] * b[i];
    }
    return sum;
}

i32 main() {
    i32 n = 10_000_000;
    f64* a = alloc<f64>(n);
    f64* b = alloc<f64>(n);
    init_arrays(a, b, n);

    i64 freq = qpf();
    i64 start = qpc();
    f64 result = 0.0;
    for i32 iter = 0; iter < 10; iter++ {
        result = dot_product(a, b, n);
    }
    i64 end = qpc();

    i64 res = cast(i64, result);
    i64 us = elapsed_us(start, end, freq);
    free(a);
    free(b);
    bench_print("dot_f64", res, us);
    return 0;
}
