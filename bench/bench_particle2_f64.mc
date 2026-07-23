// bench_particle2_f64.mc - particle simulation, idiomatic loop variant
//
// Same physics + grid-binning workload as bench_particle_f64.mc, just
// rewritten in the style you'd usually want for a tight float inner loop:
//
// 1. Read each array element into a local, do all the work on the
//    local, and write it back once at the end of the iteration:
//
//        f64 x = px[i] + vx[i];
//        if x < 0.0    { x = -x;        dx = -dx; }
//        if x >= 256.0 { x = 512.0 - x; dx = -dx; }
//        px[i] = x; vx[i] = dx;
//
//    The v1 form (`px[i] = px[i] + vx[i]; if px[i] < 0 { ... }`) hides
//    that single value behind several memory accesses, which is harder
//    for the compiler to keep tight.
//
// 2. Process one axis at a time (finish X before touching Y) instead
//    of interleaving x and y updates. Smaller working set per iteration.
//
// On minc this version runs ~30% faster than bench_particle_f64.mc.
//
#include "bench_util.mc"

void particle_step(noalias f64* px, noalias f64* py, noalias f64* vx, noalias f64* vy, i32 n) {
    for i32 i = 0; i < n; i++ {
        // X axis: 2 float locals at a time (low register pressure)
        f64 x = px[i] + vx[i];
        f64 dx = vx[i];
        if x < 0.0 { x = -x; dx = -dx; }
        if x >= 256.0 { x = 512.0 - x; dx = -dx; }
        px[i] = x;
        vx[i] = dx;
        // Y axis: same pattern, x/dx are dead
        f64 y = py[i] + vy[i];
        f64 dy = vy[i];
        if y < 0.0 { y = -y; dy = -dy; }
        if y >= 256.0 { y = 512.0 - y; dy = -dy; }
        py[i] = y;
        vy[i] = dy;
    }
}

void grid_bin(noalias i32* grid, noalias f64* px, noalias f64* py, i32 n, i32 grid_sz) {
    for i32 g = 0; g < grid_sz * grid_sz; g++ {
        grid[g] = 0;
    }
    for i32 i = 0; i < n; i++ {
        i32 gx = cast(i32, px[i]);
        i32 gy = cast(i32, py[i]);
        if gx >= 0 && gx < grid_sz && gy >= 0 && gy < grid_sz {
            grid[gy * grid_sz + gx] = grid[gy * grid_sz + gx] + 1;
        }
    }
}

i32 main() {
    i32 n = 50_000;
    i32 steps = 3000;
    i32 grid_sz = 256;

    f64* px = alloc<f64>(n);
    f64* py = alloc<f64>(n);
    f64* vx = alloc<f64>(n);
    f64* vy = alloc<f64>(n);

    i32* grid = alloc<i32>(grid_sz * grid_sz);

    // Initialize particles
    i64 state = 77_777;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        px[i] = cast(i32, (state >> 33) % 25_600) * 0.01;
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        py[i] = cast(i32, (state >> 33) % 25_600) * 0.01;
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        vx[i] = (cast(i32, (state >> 33) % 200) - 100.0) * 0.01;
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        vy[i] = (cast(i32, (state >> 33) % 200) - 100.0) * 0.01;
    }

    // Warm up
    for i32 s = 0; s < 2; s++ {
        particle_step(px, py, vx, vy, n);
    }

    // Re-initialize for timed run
    state = 77_777;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        px[i] = cast(i32, (state >> 33) % 25_600) * 0.01;
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        py[i] = cast(i32, (state >> 33) % 25_600) * 0.01;
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        vx[i] = (cast(i32, (state >> 33) % 200) - 100.0) * 0.01;
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        vy[i] = (cast(i32, (state >> 33) % 200) - 100.0) * 0.01;
    }

    i64 freq = qpf();
    i64 start = qpc();
    for i32 s = 0; s < steps; s++ {
        particle_step(px, py, vx, vy, n);
        if s % 10 == 0 {
            grid_bin(grid, px, py, n, grid_sz);
        }
    }
    i64 end = qpc();

    // Checksum
    i64 checksum = 0;
    for i32 g = 0; g < grid_sz * grid_sz; g++ {
        checksum = checksum + grid[g];
    }
    for i32 i = 0; i < n; i++ {
        checksum = checksum + cast(i64, px[i]) + cast(i64, py[i]);
    }

    free(px);
    free(py);
    free(vx);
    free(vy);
    free(grid);
    bench_print("particle2_f64", checksum, elapsed_us(start, end, freq));
    return 0;
}
