// bench_mandelbrot.c - Mandelbrot set escape-time benchmark
#include "bench_timer.h"

static long long mandelbrot(int width, int height, int max_iter, int offset) {
    long long total = 0;
    for (int py = 0; py < height; py++) {
        for (int px = 0; px < width; px++) {
            double cx = (double)(px - 400 + offset) * 0.005;
            double cy = (double)(py - 300) * 0.005;
            double zx = 0.0;
            double zy = 0.0;
            int iter = 0;
            while (iter < max_iter) {
                double zx2 = zx * zx;
                double zy2 = zy * zy;
                if (zx2 + zy2 >= 4.0) break;
                double tmp = zx2 - zy2 + cx;
                zy = 2.0 * zx * zy + cy;
                zx = tmp;
                iter++;
            }
            total += (long long)iter;
        }
    }
    return total;
}

int main(void) {
    int width = 800;
    int height = 600;
    int max_iter = 256;

    // Warm up
    mandelbrot(width, height, max_iter, 0);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    long long result = 0;
    for (int run = 0; run < 3; run++) {
        result += mandelbrot(width, height, max_iter, run);
        BENCH_USE(result);
    }
    bench_timer_start(&t2);

    long long elapsed = bench_elapsed_us(t1, t2);
    printf("mandelbrot: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
