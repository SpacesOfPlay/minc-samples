// bench_particle_f64.mc - 50k particle simulation with wall bouncing and grid binning
// Float physics + integer grid binning + float-to-int casts
#include "bench_util.mc"

i32 main() {
    i32 n = 50_000;
    i32 steps = 3000;
    i32 grid_sz = 256;

    // Allocate particle arrays: x, y, vx, vy (f64 each)
    f64* px = alloc<f64>(n);
    f64* py = alloc<f64>(n);
    f64* vx = alloc<f64>(n);
    f64* vy = alloc<f64>(n);

    // Grid for binning (count particles per cell)
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

    // Warm up: 2 steps
    for i32 s = 0; s < 2; s++ {
        for i32 i = 0; i < n; i++ {
            px[i] = px[i] + vx[i];
            py[i] = py[i] + vy[i];
            // Bounce off walls [0, 256)
            if px[i] < 0.0 { px[i] = -(px[i]); vx[i] = -(vx[i]); }
            if px[i] >= 256.0 { px[i] = 512.0 - px[i]; vx[i] = -(vx[i]); }
            if py[i] < 0.0 { py[i] = -(py[i]); vy[i] = -(vy[i]); }
            if py[i] >= 256.0 { py[i] = 512.0 - py[i]; vy[i] = -(vy[i]); }
        }
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
        // Update positions
        for i32 i = 0; i < n; i++ {
            px[i] = px[i] + vx[i];
            py[i] = py[i] + vy[i];
            // Bounce off walls
            if px[i] < 0.0 { px[i] = -(px[i]); vx[i] = -(vx[i]); }
            if px[i] >= 256.0 { px[i] = 512.0 - px[i]; vx[i] = -(vx[i]); }
            if py[i] < 0.0 { py[i] = -(py[i]); vy[i] = -(vy[i]); }
            if py[i] >= 256.0 { py[i] = 512.0 - py[i]; vy[i] = -(vy[i]); }
        }

        // Bin into grid (every 10 steps to amortize)
        if s % 10 == 0 {
            // Clear grid
            for i32 g = 0; g < grid_sz * grid_sz; g++ {
                grid[g] = 0;
            }
            // Bin particles
            for i32 i = 0; i < n; i++ {
                i32 gx = cast(i32, px[i]);
                i32 gy = cast(i32, py[i]);
                if gx >= 0 && gx < grid_sz && gy >= 0 && gy < grid_sz {
                    grid[gy * grid_sz + gx] = grid[gy * grid_sz + gx] + 1;
                }
            }
        }
    }
    i64 end = qpc();

    // Checksum: sum of final grid
    i64 checksum = 0;
    for i32 g = 0; g < grid_sz * grid_sz; g++ {
        checksum = checksum + grid[g];
    }
    // Add position hash
    for i32 i = 0; i < n; i++ {
        checksum = checksum + cast(i64, px[i]) + cast(i64, py[i]);
    }

    free(px);
    free(py);
    free(vx);
    free(vy);
    free(grid);
    bench_print("particle_f64", checksum, elapsed_us(start, end, freq));
    return 0;
}
