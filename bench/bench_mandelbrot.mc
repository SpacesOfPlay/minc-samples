// bench_mandelbrot.mc - Mandelbrot set escape-time iteration (complex multiply + branch-heavy inner loop)
#include "bench_util.mc"

i64 mandelbrot(i32 width, i32 height, i32 max_iter, i32 offset) {
    i64 total = 0;
    for i32 py = 0; py < height; py++ {
        for i32 px = 0; px < width; px++ {
            f64 cx = (px - 400 + offset) * 0.005;
            f64 cy = (py - 300) * 0.005;
            f64 zx = 0.0;
            f64 zy = 0.0;
            i32 iter = 0;
            while iter < max_iter {
                f64 zx2 = zx * zx;
                f64 zy2 = zy * zy;
                if zx2 + zy2 >= 4.0 { break; }
                f64 tmp = zx2 - zy2 + cx;
                zy = 2.0 * zx * zy + cy;
                zx = tmp;
                iter++;
            }
            total = total + iter;
        }
    }
    return total;
}

i32 main() {
    i32 width = 800;
    i32 height = 600;
    i32 max_iter = 256;

    // Warm up
    mandelbrot(width, height, max_iter, 0);

    i64 freq = qpf();
    i64 start = qpc();
    i64 result = 0;
    for i32 run = 0; run < 3; run++ {
        result = result + mandelbrot(width, height, max_iter, run);
    }
    i64 end = qpc();

    bench_print("mandelbrot", result, elapsed_us(start, end, freq));
    return 0;
}
