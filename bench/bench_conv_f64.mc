// bench_conv_f64.mc - 1D convolution: integer signal, f64 triangle kernel, f64 accumulation
#include "bench_util.mc"

i32 main() {
    const i32 n = 5_000_000;
    const i32 ksize = 15;
    const i32 khalf = ksize / 2;

    // Allocate signal (i32), output (i32), kernel (f64)
    i32* signal = alloc<i32>(n);
    i32* output = alloc<i32>(n);
    f64* kernel = alloc<f64>(ksize);

    // Initialize signal with pseudo-random i32 values
    i64 state = 31_415;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        signal[i] = cast(i32, (state >> 33) % 256);
    }

    // Initialize kernel: triangle window normalized to sum ~1.0
    // weights: 1,2,3,...,8,7,...,2,1 / 64
    kernel[0] = 1.0 / 64.0;
    kernel[1] = 2.0 / 64.0;
    kernel[2] = 3.0 / 64.0;
    kernel[3] = 4.0 / 64.0;
    kernel[4] = 5.0 / 64.0;
    kernel[5] = 6.0 / 64.0;
    kernel[6] = 7.0 / 64.0;
    kernel[7] = 8.0 / 64.0;
    kernel[8] = 7.0 / 64.0;
    kernel[9] = 6.0 / 64.0;
    kernel[10] = 5.0 / 64.0;
    kernel[11] = 4.0 / 64.0;
    kernel[12] = 3.0 / 64.0;
    kernel[13] = 2.0 / 64.0;
    kernel[14] = 1.0 / 64.0;

    // Warm up
    for i32 i = khalf; i < n - khalf; i++ {
        f64 acc = 0.0;
        for i32 k = 0; k < ksize; k++ {
            acc = acc + signal[i - khalf + k] * kernel[k];
        }
        output[i] = cast(i32, acc);
    }

    // work
    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 5; iter++ {
        for i32 i = khalf; i < n - khalf; i++ {
            f64 acc;
            for i32 k = 0; k < ksize; k++ {
                acc = acc + signal[i - khalf + k] * kernel[k];
            }
            output[i] = cast(i32, acc);
        }
    }
    i64 end = qpc();

    // Checksum
    i64 checksum = 0;
    for i32 i = 0; i < n; i++ {
        checksum = checksum + output[i];
    }

    free(signal);
    free(output);
    free(kernel);
    bench_print("conv_f64", checksum, elapsed_us(start, end, freq));
    return 0;
}
