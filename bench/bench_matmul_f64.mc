// bench_matmul_f64.mc - 512x512 f64 matrix multiply (ikj loop order, FMA-friendly)
#include "bench_util.mc"

i32 MAT_N = 512;

void mat_fill_f64(f64* m, i32 n, i32 seed) {
    i64 state = seed;
    for i32 i = 0; i < n * n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        m[i] = cast(i32, (state >> 33) % 100);
    }
}

void mat_mul_f64(noalias f64* c, noalias f64* a, noalias f64* b, i32 n) {
    // Zero c
    for i32 i = 0; i < n * n; i++ {
        c[i] = 0.0;
    }
    for i32 i = 0; i < n; i++ {
        for i32 k = 0; k < n; k++ {
            f64 aik = a[i * n + k];
            for i32 j = 0; j < n; j++ {
                c[i * n + j] = c[i * n + j] + aik * b[k * n + j];
            }
        }
    }
}

i64 mat_diag_sum_f64(f64* m, i32 n) {
    f64 sum = 0.0;
    for i32 i = 0; i < n; i++ {
        sum = sum + m[i * n + i];
    }
    return cast(i64, sum);
}

i32 main() {
    i32 n = MAT_N;
    f64* a = alloc<f64>(n * n);
    f64* b = alloc<f64>(n * n);
    f64* c = alloc<f64>(n * n);

    mat_fill_f64(a, n, 42);
    mat_fill_f64(b, n, 99);

    // Warm up
    mat_mul_f64(c, a, b, n);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 3; iter++ {
        mat_mul_f64(c, a, b, n);
    }
    i64 end = qpc();

    i64 diag = mat_diag_sum_f64(c, n);

    free(a);
    free(b);
    free(c);

    bench_print("matmul_f64", diag, elapsed_us(start, end, freq));
    return 0;
}
