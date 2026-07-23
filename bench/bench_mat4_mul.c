// bench_mat4_mul.c — bulk 4x4 × 4x4 matrix composition (C reference).
// Matches the minc side: column-major storage, dense (no zero entries).
// Computes each result column as A * B.col_i.
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

static inline mat4 mat4_mul(mat4 a, mat4 b) {
    mat4 r;
    r.c0 = mat4_mul_vec4(a, b.c0);
    r.c1 = mat4_mul_vec4(a, b.c1);
    r.c2 = mat4_mul_vec4(a, b.c2);
    r.c3 = mat4_mul_vec4(a, b.c3);
    return r;
}

static void init_mats(mat4 *buf, int n) {
    for (int i = 0; i < n; i++) {
        float *p = (float *)&buf[i];
        float base = 0.01f + (float)(i & 63) * 0.001f;
        for (int k = 0; k < 16; k++) {
            float off = (float)(k + 1) * 0.007f;
            p[k] = base + off;
        }
    }
}

int main(void) {
    const int N = 1000;
    const int REPS = 1000;
    size_t sz = (size_t)N * sizeof(mat4);
    mat4 *A_buf   = (mat4 *)malloc(sz);
    mat4 *B_buf   = (mat4 *)malloc(sz);
    mat4 *out_buf = (mat4 *)malloc(sz);
    init_mats(A_buf, N);
    init_mats(B_buf, N);

    // Warmup
    for (int i = 0; i < N; i++) out_buf[i] = mat4_mul(A_buf[i], B_buf[i]);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    float sum = 0.0f;
    for (int r = 0; r < REPS; r++) {
        for (int i = 0; i < N; i++) out_buf[i] = mat4_mul(A_buf[i], B_buf[i]);
        float *p = (float *)&out_buf[N - 1];
        sum += p[0] + p[5] + p[10] + p[15];
        BENCH_USE((long long)sum);
    }
    bench_timer_start(&t2);

    long long res = (long long)sum;
    long long elapsed = bench_elapsed_us(t1, t2);
    free(A_buf);
    free(B_buf);
    free(out_buf);
    printf("mat4_mul: result=%lld time=%lld us\n", res, elapsed);
    return 0;
}
