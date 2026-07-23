// bench_nbody.mc - integer N-body simulation (1000 bodies, 200 steps, O(n^2) gravity)
#include "bench_util.mc"

struct Body {
    i64 x;
    i64 y;
    i64 vx;
    i64 vy;
}

void nbody_step(Body* bodies, i32 n) {
    // Compute forces and update velocities
    for i32 i = 0; i < n; i++ {
        Body* bi = bodies + i;
        i64 ax = 0;
        i64 ay = 0;
        for i32 j = 0; j < n; j++ {
            if i != j {
                Body* bj = bodies + j;
                i64 dx = bj.x - bi.x;
                i64 dy = bj.y - bi.y;
                i64 dist2 = dx * dx + dy * dy + 1;
                ax = ax + dx * 1000 / dist2;
                ay = ay + dy * 1000 / dist2;
            }
        }
        bi.vx = bi.vx + ax;
        bi.vy = bi.vy + ay;
    }
    // Update positions
    for i32 i = 0; i < n; i++ {
        Body* bi = bodies + i;
        bi.x = bi.x + bi.vx;
        bi.y = bi.y + bi.vy;
    }
}

i64 nbody_checksum(Body* bodies, i32 n) {
    i64 cs = 0;
    for i32 i = 0; i < n; i++ {
        Body* bi = bodies + i;
        cs = cs + bi.x + bi.y;
    }
    return cs;
}

void init_bodies(Body* bodies, i32 n) {
    i64 state = 99_999;
    for i32 i = 0; i < n; i++ {
        Body* bi = bodies + i;
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        bi.x = (state >> 33) % 10_000 - 5000;
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        bi.y = (state >> 33) % 10_000 - 5000;
        bi.vx = 0;
        bi.vy = 0;
    }
}

i32 main() {
    i32 n = 1000;
    i32 steps = 200;
    Body* bodies = alloc<Body>(n);

    // Warm up (fewer steps)
    init_bodies(bodies, n);
    for i32 s = 0; s < 2; s++ {
        nbody_step(bodies, n);
    }

    // Timed run
    init_bodies(bodies, n);
    i64 freq = qpf();
    i64 start = qpc();
    for i32 s = 0; s < steps; s++ {
        nbody_step(bodies, n);
    }
    i64 end = qpc();

    i64 result = nbody_checksum(bodies, n);
    free(bodies);
    bench_print("nbody", result, elapsed_us(start, end, freq));
    return 0;
}
