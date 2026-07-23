// bench_vec4_transform.c — 4x4 matrix × vec4 transform (C reference).
// Matches the minc side: column-major storage, no zero entries. Computes
// result = col0*v.x + col1*v.y + col2*v.z + col3*v.w (column-vector).
#include "bench_timer.h"

typedef struct { float x, y, z, w; } vec4;
typedef struct { vec4 c0, c1, c2, c3; } mat4;

static inline vec4 mat4_mul_vec4(mat4 m, vec4 v) {
    vec4 r;
    r.x = m.c0.x*v.x + m.c1.x*v.y + m.c2.x*v.z + m.c3.x*v.w;
    r.y = m.c0.y*v.x + m.c1.y*v.y + m.c2.y*v.z + m.c3.y*v.w;
    r.z = m.c0.z*v.x + m.c1.z*v.y + m.c2.z*v.z + m.c3.z*v.w;
    r.w = m.c0.w*v.x + m.c1.w*v.y + m.c2.w*v.z + m.c3.w*v.w;
    return r;
}

static void init_points(vec4 *buf, int n) {
    for (int i = 0; i < n; i++) {
        float fi = (float)i;
        buf[i] = (vec4){ fi*0.001f, fi*0.002f, fi*0.003f, 1.0f };
    }
}

int main(void) {
    const int N = 100000;
    const int REPS = 200;
    size_t sz = (size_t)N * sizeof(vec4);
    vec4 *in_buf  = (vec4 *)malloc(sz);
    vec4 *out_buf = (vec4 *)malloc(sz);
    init_points(in_buf, N);

    mat4 M = {
        { 0.8660254f, -0.5f,       0.123f, 1.0f },   // col0
        { 0.5f,        0.8660254f, 0.234f, 2.0f },   // col1
        { 0.345f,      0.456f,     1.0f,   3.0f },   // col2
        { 0.567f,      0.678f,     0.789f, 1.0f }    // col3
    };

    // Warmup
    for (int i = 0; i < N; i++) out_buf[i] = mat4_mul_vec4(M, in_buf[i]);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    float sum = 0.0f;
    for (int r = 0; r < REPS; r++) {
        for (int i = 0; i < N; i++) out_buf[i] = mat4_mul_vec4(M, in_buf[i]);
        vec4 last = out_buf[N - 1];
        sum += last.x + last.y + last.z + last.w;
        BENCH_USE((long long)sum);
    }
    bench_timer_start(&t2);

    long long res = (long long)sum;
    long long elapsed = bench_elapsed_us(t1, t2);
    free(in_buf);
    free(out_buf);
    printf("vec4_transform: result=%lld time=%lld us\n", res, elapsed);
    return 0;
}
