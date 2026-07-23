// bench_vec4_transform.mc — 4x4 matrix × float4 transform of N points.
// Uses the `float4x4 * float4` builtin operator which lowers to
// IR_MAT4_MUL_VEC4 on x64 (broadcast + vmulps + 3× vfmadd231ps).
// Matrix is stored column-major; every entry is non-zero so MSVC /O2
// cannot constant-fold any term.
#include "bench_util.mc"

void init_points(float4* buf, i32 n) {
    for i32 i = 0; i < n; i++ {
        f32 fi = cast(f32, i);
        buf[i] = float4{ fi * 0.001f, fi * 0.002f, fi * 0.003f, 1.0f };
    }
}

i32 main() {
    i32 N = 100_000;
    i32 REPS = 200;
    float4* in_buf  = alloc<float4>(N);
    float4* out_buf = alloc<float4>(N);
    init_points(in_buf, N);

    // Column-major, no zero entries.
    float4x4 M = {
        0.8660254f, -0.5f,       0.123f, 1.0f,  // col0
        0.5f,       0.8660254f,  0.234f, 2.0f,  // col1
        0.345f,     0.456f,      1.0f,   3.0f,  // col2
        0.567f,     0.678f,      0.789f, 1.0f   // col3
    };

    // Warmup
    for i32 i = 0; i < N; i++ {
        out_buf[i] = M * in_buf[i];
    }

    i64 freq = qpf();
    i64 start = qpc();
    f32 sum = 0.0f;
    for i32 r = 0; r < REPS; r++ {
        for i32 i = 0; i < N; i++ {
            out_buf[i] = M * in_buf[i];
        }
        float4 last = out_buf[N - 1];
        sum = sum + last.x + last.y + last.z + last.w;
    }
    i64 end = qpc();

    i64 res = cast(i64, sum);
    i64 us = elapsed_us(start, end, freq);
    free(in_buf);
    free(out_buf);
    bench_print("vec4_transform", res, us);
    return 0;
}
