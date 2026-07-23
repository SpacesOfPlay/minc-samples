// bench_conv_f64.c - 1D convolution (mixed int+float)
// Integer signal, float kernel, float accumulation, integer output
#include "bench_timer.h"

int main(void) {
    int n = 5000000;
    int ksize = 15;
    int khalf = ksize / 2;

    int *signal_buf = (int *)malloc((size_t)n * sizeof(int));
    int *output = (int *)malloc((size_t)n * sizeof(int));
    double *kernel = (double *)malloc((size_t)ksize * sizeof(double));

    // Initialize signal with pseudo-random values
    long long state = 31415;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        signal_buf[i] = (int)((state >> 33) % 256);
    }

    // Initialize kernel: triangle window normalized to sum ~1.0
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

    // Warm up
    for (int i = khalf; i < n - khalf; i++) {
        double acc = 0.0;
        for (int k = 0; k < ksize; k++) {
            acc += (double)signal_buf[i - khalf + k] * kernel[k];
        }
        output[i] = (int)acc;
    }

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 5; iter++) {
        for (int i = khalf; i < n - khalf; i++) {
            double acc = 0.0;
            for (int k = 0; k < ksize; k++) {
                acc += (double)signal_buf[i - khalf + k] * kernel[k];
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

    long long elapsed = bench_elapsed_us(t1, t2);
    printf("conv_f64: result=%lld time=%lld us\n", checksum, elapsed);
    return 0;
}
