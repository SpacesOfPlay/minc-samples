// bench_poly_f64.mc - degree-8 Horner polynomial evaluation (FMA latency chain)
#include "bench_util.mc"

f64 poly_eval(f64 x) {
    // Degree-8 polynomial via Horner's method
    f64 r = 1.1;
    r = r * x - 3.2;
    r = r * x + 0.9;
    r = r * x - 1.8;
    r = r * x + 2.1;
    r = r * x - 0.5;
    r = r * x + 3.7;
    r = r * x - 2.3;
    r = r * x + 1.5;
    return r;
}

i32 main() {
    i32 n = 5_000_000;
    f64* xs = alloc<f64>(n);

    // Initialize input array with varied values
    i64 state = 54_321;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        // Map to range [-2.0, 2.0] roughly
        i32 raw = cast(i32, (state >> 33) % 4000) - 2000;
        xs[i] = raw * 0.001;
    }

    i64 freq = qpf();
    i64 start = qpc();
    f64 sum = 0.0;
    for i32 iter = 0; iter < 5; iter++ {
        sum = 0.0;
        for i32 i = 0; i < n; i++ {
            sum = sum + poly_eval(xs[i]);
        }
    }
    i64 end = qpc();

    i64 res = cast(i64, sum);
    i64 us = elapsed_us(start, end, freq);
    free(xs);
    bench_print("poly_f64", res, us);
    return 0;
}
