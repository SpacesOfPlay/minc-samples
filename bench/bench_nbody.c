// bench_nbody.c - integer N-body simulation benchmark
#include "bench_timer.h"

typedef struct {
    long long x;
    long long y;
    long long vx;
    long long vy;
} Body;

static void nbody_step(Body *bodies, int n) {
    // Compute forces and update velocities
    for (int i = 0; i < n; i++) {
        long long ax = 0, ay = 0;
        for (int j = 0; j < n; j++) {
            if (i != j) {
                long long dx = bodies[j].x - bodies[i].x;
                long long dy = bodies[j].y - bodies[i].y;
                long long dist2 = dx * dx + dy * dy + 1;
                ax += dx * 1000 / dist2;
                ay += dy * 1000 / dist2;
            }
        }
        bodies[i].vx += ax;
        bodies[i].vy += ay;
    }
    // Update positions
    for (int i = 0; i < n; i++) {
        bodies[i].x += bodies[i].vx;
        bodies[i].y += bodies[i].vy;
    }
}

static long long nbody_checksum(Body *bodies, int n) {
    long long cs = 0;
    for (int i = 0; i < n; i++) {
        cs += bodies[i].x + bodies[i].y;
    }
    return cs;
}

static void init_bodies(Body *bodies, int n) {
    long long state = 99999;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        bodies[i].x = (long long)((state >> 33) % 10000) - 5000;
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        bodies[i].y = (long long)((state >> 33) % 10000) - 5000;
        bodies[i].vx = 0;
        bodies[i].vy = 0;
    }
}

int main(void) {
    int n = 1000;
    int steps = 200;
    Body *bodies = (Body *)malloc((size_t)n * sizeof(Body));

    // Warm up (fewer steps)
    init_bodies(bodies, n);
    for (int s = 0; s < 2; s++) {
        nbody_step(bodies, n);
    }

    // Timed run
    init_bodies(bodies, n);
    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int s = 0; s < steps; s++) {
        nbody_step(bodies, n);
        BENCH_CLOBBER(bodies);
    }
    bench_timer_start(&t2);

    long long result = nbody_checksum(bodies, n);
    free(bodies);
    long long elapsed = bench_elapsed_us(t1, t2);
    printf("nbody: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
