// Integer matrix multiply benchmark
// 512×512 matrix multiplication (ikj loop order for cache efficiency).

#include "bench_util.mc"

const i32 MAT_N = 512;

void mat_fill(i32* m, i32 n, i32 seed) {
    i64 state = seed;
    for i32 i = 0; i < n * n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        m[i] = cast(i32, (state >> 33) % 100);
    }
}

void mat_mul(i32* c, i32* a, i32* b, i32 n) {
    memset(cast(void*, c), 0, n * n * 4);
    for i32 i = 0; i < n; i++ {
        for i32 k = 0; k < n; k++ {
            i32 aik = a[i * n + k];
            for i32 j = 0; j < n; j++ {
                c[i * n + j] = c[i * n + j] + aik * b[k * n + j];
            }
        }
    }
}

i64 mat_diag_sum(i32* m, i32 n) {
    i64 sum = 0;
    for i32 i = 0; i < n; i++ {
        sum = sum + m[i * n + i];
    }
    return sum;
}

i32 main() {
    i32 n = MAT_N;
    i32* a = alloc<i32>(n * n);
    i32* b = alloc<i32>(n * n);
    i32* c = alloc<i32>(n * n);

    mat_fill(a, n, 42);
    mat_fill(b, n, 99);

    // Warm up
    mat_mul(c, a, b, n);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 3; iter++ {
        mat_mul(c, a, b, n);
    }
    i64 end = qpc();

    i64 diag = mat_diag_sum(c, n);

    free(a);
    free(b);
    free(c);

    bench_print("matmul", diag, elapsed_us(start, end, freq));
    return 0;
}
