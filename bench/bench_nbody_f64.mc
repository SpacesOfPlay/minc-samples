// N-body simulation benchmark (f64)
// 1000 bodies, 200 timesteps with gravitational attraction.

#include "bench_util.mc"

struct Body {
    f64 x;
    f64 y;
    f64 vx;
    f64 vy;
}

void nbody_step(Body* bodies, i32 n) {
    // Compute gravitational acceleration
    for i32 i = 0; i < n; i++ {
        Body* bi = bodies + i;
        f64 ax = 0.0;
        f64 ay = 0.0;
        for i32 j = 0; j < n; j++ {
            if i != j {
                Body* bj = bodies + j;
                f64 dx = bj.x - bi.x;
                f64 dy = bj.y - bi.y;
                f64 dist_sq = dx * dx + dy * dy + 1.0;  // softening
                ax = ax + dx * 1000.0 / dist_sq;
                ay = ay + dy * 1000.0 / dist_sq;
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
        cs = cs + cast(i64, bi.x) + cast(i64, bi.y);
    }
    return cs;
}

void init_bodies(Body* bodies, i32 n) {
    i64 state = 99999;
    for i32 i = 0; i < n; i++ {
        Body* bi = bodies + i;
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        bi.x = cast(i32, (state >> 33) % 10000) - 5000;
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        bi.y = cast(i32, (state >> 33) % 10000) - 5000;
        bi.vx = 0.0;
        bi.vy = 0.0;
    }
}

i32 main() {
    i32 n = 1000;
    i32 steps = 200;
    Body* bodies = alloc<Body>(n);

    // Warm up
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
    bench_print("nbody_f64", result, elapsed_us(start, end, freq));
    return 0;
}
