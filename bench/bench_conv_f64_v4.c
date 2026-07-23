// bench_conv_f64_v4.c — clang/MSVC reference for bench_conv_f64_v4.mc.
// Uses 8 scalar accumulators per outer iteration (8 output positions per
// iter). MSVC's auto-vectorizer will pack these into whatever the backend
// considers optimal.
#include "bench_timer.h"

int main(void) {
    int n = 5000000;
    int ksize = 15;
    int khalf = ksize / 2;

    int *signal_buf = (int *)malloc((size_t)n * sizeof(int));
    int *output = (int *)malloc((size_t)n * sizeof(int));
    double *kernel = (double *)malloc((size_t)ksize * sizeof(double));
    double *sig_f = (double *)malloc((size_t)n * sizeof(double));

    long long state = 31415;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        signal_buf[i] = (int)((state >> 33) % 256);
    }

    kernel[0]  = 1.0 / 64.0;
    kernel[1]  = 2.0 / 64.0;
    kernel[2]  = 3.0 / 64.0;
    kernel[3]  = 4.0 / 64.0;
    kernel[4]  = 5.0 / 64.0;
    kernel[5]  = 6.0 / 64.0;
    kernel[6]  = 7.0 / 64.0;
    kernel[7]  = 8.0 / 64.0;
    kernel[8]  = 7.0 / 64.0;
    kernel[9]  = 6.0 / 64.0;
    kernel[10] = 5.0 / 64.0;
    kernel[11] = 4.0 / 64.0;
    kernel[12] = 3.0 / 64.0;
    kernel[13] = 2.0 / 64.0;
    kernel[14] = 1.0 / 64.0;

    for (int i = 0; i < n; i++) sig_f[i] = (double)signal_buf[i];

    // Warm up.
    for (int i = khalf; i < n - khalf - 7; i += 8) {
        double a0 = 0.0, a1 = 0.0, a2 = 0.0, a3 = 0.0;
        double a4 = 0.0, a5 = 0.0, a6 = 0.0, a7 = 0.0;
        int base = i - khalf;
        for (int k = 0; k < ksize; k++) {
            double kv = kernel[k];
            a0 += sig_f[base + k + 0] * kv;
            a1 += sig_f[base + k + 1] * kv;
            a2 += sig_f[base + k + 2] * kv;
            a3 += sig_f[base + k + 3] * kv;
            a4 += sig_f[base + k + 4] * kv;
            a5 += sig_f[base + k + 5] * kv;
            a6 += sig_f[base + k + 6] * kv;
            a7 += sig_f[base + k + 7] * kv;
        }
        output[i + 0] = (int)a0;
        output[i + 1] = (int)a1;
        output[i + 2] = (int)a2;
        output[i + 3] = (int)a3;
        output[i + 4] = (int)a4;
        output[i + 5] = (int)a5;
        output[i + 6] = (int)a6;
        output[i + 7] = (int)a7;
    }
    int warm_tail_start = ((n - khalf) - khalf) / 8 * 8 + khalf;
    for (int i = warm_tail_start; i < n - khalf; i++) {
        double acc = 0.0;
        int base = i - khalf;
        for (int k = 0; k < ksize; k++) {
            acc += sig_f[base + k] * kernel[k];
        }
        output[i] = (int)acc;
    }

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 5; iter++) {
        for (int i = khalf; i < n - khalf - 7; i += 8) {
            double a0 = 0.0, a1 = 0.0, a2 = 0.0, a3 = 0.0;
            double a4 = 0.0, a5 = 0.0, a6 = 0.0, a7 = 0.0;
            int base = i - khalf;
            for (int k = 0; k < ksize; k++) {
                double kv = kernel[k];
                a0 += sig_f[base + k + 0] * kv;
                a1 += sig_f[base + k + 1] * kv;
                a2 += sig_f[base + k + 2] * kv;
                a3 += sig_f[base + k + 3] * kv;
                a4 += sig_f[base + k + 4] * kv;
                a5 += sig_f[base + k + 5] * kv;
                a6 += sig_f[base + k + 6] * kv;
                a7 += sig_f[base + k + 7] * kv;
            }
            output[i + 0] = (int)a0;
            output[i + 1] = (int)a1;
            output[i + 2] = (int)a2;
            output[i + 3] = (int)a3;
            output[i + 4] = (int)a4;
            output[i + 5] = (int)a5;
            output[i + 6] = (int)a6;
            output[i + 7] = (int)a7;
        }
        int tail_start = ((n - khalf) - khalf) / 8 * 8 + khalf;
        for (int i = tail_start; i < n - khalf; i++) {
            double acc = 0.0;
            int base = i - khalf;
            for (int k = 0; k < ksize; k++) {
                acc += sig_f[base + k] * kernel[k];
            }
            output[i] = (int)acc;
        }
        BENCH_CLOBBER(output);
    }
    bench_timer_start(&t2);

    long long checksum = 0;
    for (int i = 0; i < n; i++) {
        checksum += (long long)output[i];
    }

    free(signal_buf);
    free(output);
    free(kernel);
    free(sig_f);

    long long elapsed = bench_elapsed_us(t1, t2);
    printf("conv_f64_v4: result=%lld time=%lld us\n", checksum, elapsed);
    return 0;
}
