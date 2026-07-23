// bench_particle2_f64.c - particle simulation (optimized version)
// Same algorithm as particle_f64 but with local variables for positions
#include "bench_timer.h"

void particle_step(double * __restrict px, double * __restrict py,
                   double * __restrict vx, double * __restrict vy, int n) {
    for (int i = 0; i < n; i++) {
        double x = px[i] + vx[i];
        double dx = vx[i];
        if (x < 0.0) { x = -x; dx = -dx; }
        if (x >= 256.0) { x = 512.0 - x; dx = -dx; }
        px[i] = x;
        vx[i] = dx;
        double y = py[i] + vy[i];
        double dy = vy[i];
        if (y < 0.0) { y = -y; dy = -dy; }
        if (y >= 256.0) { y = 512.0 - y; dy = -dy; }
        py[i] = y;
        vy[i] = dy;
    }
}

void grid_bin(int * __restrict grid, double * __restrict px, double * __restrict py,
              int n, int grid_sz) {
    for (int g = 0; g < grid_sz * grid_sz; g++) grid[g] = 0;
    for (int i = 0; i < n; i++) {
        int gx = (int)px[i];
        int gy = (int)py[i];
        if (gx >= 0 && gx < grid_sz && gy >= 0 && gy < grid_sz) {
            grid[gy * grid_sz + gx]++;
        }
    }
}

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

    for (int s = 0; s < 2; s++) particle_step(px, py, vx, vy, n);

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
        particle_step(px, py, vx, vy, n);
        if (s % 10 == 0) grid_bin(grid, px, py, n, grid_sz);
        BENCH_CLOBBER(px);
    }
    bench_timer_start(&t2);

    long long checksum = 0;
    for (int g = 0; g < grid_sz * grid_sz; g++) checksum += (long long)grid[g];
    for (int i = 0; i < n; i++) checksum += (long long)px[i] + (long long)py[i];

    free(px); free(py); free(vx); free(vy); free(grid);
    long long elapsed = bench_elapsed_us(t1, t2);
    printf("particle2_f64: result=%lld time=%lld us\n", checksum, elapsed);
    return 0;
}
