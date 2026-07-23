// bench_particle_f64.c - particle simulation (mixed int+float)
// Float physics + integer grid binning + float-to-int casts
#include "bench_timer.h"

int main(void) {
    int n = 50000;
    int steps = 3000;
    int grid_sz = 256;

    size_t fsz = (size_t)n * sizeof(double);
    double *px = (double *)malloc(fsz);
    double *py = (double *)malloc(fsz);
    double *vx = (double *)malloc(fsz);
    double *vy = (double *)malloc(fsz);

    size_t gsz = (size_t)grid_sz * grid_sz * sizeof(int);
    int *grid = (int *)malloc(gsz);

    // Initialize particles
    long long state = 77777;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        px[i] = (double)((int)((state >> 33) % 25600)) * 0.01;
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        py[i] = (double)((int)((state >> 33) % 25600)) * 0.01;
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        vx[i] = ((double)((int)((state >> 33) % 200)) - 100.0) * 0.01;
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        vy[i] = ((double)((int)((state >> 33) % 200)) - 100.0) * 0.01;
    }

    // Warm up: 2 steps
    for (int s = 0; s < 2; s++) {
        for (int i = 0; i < n; i++) {
            px[i] += vx[i];
            py[i] += vy[i];
            if (px[i] < 0.0) { px[i] = -px[i]; vx[i] = -vx[i]; }
            if (px[i] >= 256.0) { px[i] = 512.0 - px[i]; vx[i] = -vx[i]; }
            if (py[i] < 0.0) { py[i] = -py[i]; vy[i] = -vy[i]; }
            if (py[i] >= 256.0) { py[i] = 512.0 - py[i]; vy[i] = -vy[i]; }
        }
    }

    // Re-initialize for timed run
    state = 77777;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        px[i] = (double)((int)((state >> 33) % 25600)) * 0.01;
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        py[i] = (double)((int)((state >> 33) % 25600)) * 0.01;
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        vx[i] = ((double)((int)((state >> 33) % 200)) - 100.0) * 0.01;
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        vy[i] = ((double)((int)((state >> 33) % 200)) - 100.0) * 0.01;
    }

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int s = 0; s < steps; s++) {
        for (int i = 0; i < n; i++) {
            px[i] += vx[i];
            py[i] += vy[i];
            if (px[i] < 0.0) { px[i] = -px[i]; vx[i] = -vx[i]; }
            if (px[i] >= 256.0) { px[i] = 512.0 - px[i]; vx[i] = -vx[i]; }
            if (py[i] < 0.0) { py[i] = -py[i]; vy[i] = -vy[i]; }
            if (py[i] >= 256.0) { py[i] = 512.0 - py[i]; vy[i] = -vy[i]; }
        }

        if (s % 10 == 0) {
            for (int g = 0; g < grid_sz * grid_sz; g++) {
                grid[g] = 0;
            }
            for (int i = 0; i < n; i++) {
                int gx = (int)px[i];
                int gy = (int)py[i];
                if (gx >= 0 && gx < grid_sz && gy >= 0 && gy < grid_sz) {
                    grid[gy * grid_sz + gx]++;
                }
            }
        }
        BENCH_CLOBBER(px);
    }
    bench_timer_start(&t2);

    long long checksum = 0;
    for (int g = 0; g < grid_sz * grid_sz; g++) {
        checksum += (long long)grid[g];
    }
    for (int i = 0; i < n; i++) {
        checksum += (long long)px[i] + (long long)py[i];
    }

    free(px);
    free(py);
    free(vx);
    free(vy);
    free(grid);

    long long elapsed = bench_elapsed_us(t1, t2);
    printf("particle_f64: result=%lld time=%lld us\n", checksum, elapsed);
    return 0;
}
