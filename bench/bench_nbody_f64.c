// bench_nbody_f64.c - floating-point N-body simulation benchmark
#include "bench_timer.h"

typedef struct {
    double x;
    double y;
    double vx;
    double vy;
} FBody;

static void nbody_f64_step(FBody *bodies, int n) {
    for (int i = 0; i < n; i++) {
        FBody *bi = &bodies[i];
        double ax = 0.0;
        double ay = 0.0;
        for (int j = 0; j < n; j++) {
            if (i != j) {
                FBody *bj = &bodies[j];
                double dx = bj->x - bi->x;
                double dy = bj->y - bi->y;
                double dist2 = dx * dx + dy * dy + 1.0;
                ax += dx * 1000.0 / dist2;
                ay += dy * 1000.0 / dist2;
            }
        }
        bi->vx += ax;
        bi->vy += ay;
    }
    for (int i = 0; i < n; i++) {
        FBody *bi = &bodies[i];
        bi->x += bi->vx;
        bi->y += bi->vy;
    }
}

static long long nbody_f64_checksum(FBody *bodies, int n) {
    long long cs = 0;
    for (int i = 0; i < n; i++) {
        cs += (long long)bodies[i].x + (long long)bodies[i].y;
    }
    return cs;
}

static void init_fbodies(FBody *bodies, int n) {
    long long state = 99999;
    for (int i = 0; i < n; i++) {
        FBody *bi = &bodies[i];
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        bi->x = (double)((int)((state >> 33) % 10000) - 5000);
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        bi->y = (double)((int)((state >> 33) % 10000) - 5000);
        bi->vx = 0.0;
        bi->vy = 0.0;
    }
}

int main(void) {
    int n = 1000;
    int steps = 200;
    FBody *bodies = (FBody *)malloc((size_t)n * sizeof(FBody));

    // Warm up
    init_fbodies(bodies, n);
    for (int s = 0; s < 2; s++) {
        nbody_f64_step(bodies, n);
    }

    // Timed run
    init_fbodies(bodies, n);
    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int s = 0; s < steps; s++) {
        nbody_f64_step(bodies, n);
        BENCH_CLOBBER(bodies);
    }
    bench_timer_start(&t2);

    long long result = nbody_f64_checksum(bodies, n);
    free(bodies);

    long long elapsed = bench_elapsed_us(t1, t2);
    printf("nbody_f64: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
