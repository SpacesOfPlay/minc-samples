// bench_mat4_mul.mc — bulk 4x4 × 4x4 matrix composition.
// Uses the `float4x4 * float4x4` builtin which lowers to 4×IR_MAT4_MUL_VEC4
// on x64 (one mat-vec per column of RHS). Matrices are stored column-major
// with every entry non-zero to prevent constant folding on the MSVC side.
#include "bench_util.mc"

// Fill one matrix with a per-index-varying pattern so no slot is zero and
// successive matrices differ.  Values kept small to avoid FP overflow over
// chained multiplies in the checksum.
void init_mats(float4x4* buf, i32 n) {
    for i32 i = 0; i < n; i++ {
        f32* p = cast(f32*, buf + i);
        f32 base = 0.01f + cast(f32, i & 63) * 0.001f;
        for i32 k = 0; k < 16; k++ {
            f32 off = cast(f32, k + 1) * 0.007f;
            p[k] = base + off;
        }
    }
}

i32 main() {
    i32 N = 1_000;
    i32 REPS = 1_000;
    float4x4* A_buf   = alloc<float4x4>(N);
    float4x4* B_buf   = alloc<float4x4>(N);
    float4x4* out_buf = alloc<float4x4>(N);
    init_mats(A_buf, N);
    init_mats(B_buf, N);

    // Warmup
    for i32 i = 0; i < N; i++ {
        out_buf[i] = A_buf[i] * B_buf[i];
    }

    i64 freq = qpf();
    i64 start = qpc();
    f32 sum = 0.0f;
    for i32 r = 0; r < REPS; r++ {
        for i32 i = 0; i < N; i++ {
            out_buf[i] = A_buf[i] * B_buf[i];
        }
        // Checksum: read four corner elements of the last product.
        f32* p = cast(f32*, out_buf + N - 1);
        sum = sum + p[0] + p[5] + p[10] + p[15];
    }
    i64 end = qpc();

    i64 res = cast(i64, sum);
    i64 us = elapsed_us(start, end, freq);
    free(A_buf);
    free(B_buf);
    free(out_buf);
    bench_print("mat4_mul", res, us);
    return 0;
}
