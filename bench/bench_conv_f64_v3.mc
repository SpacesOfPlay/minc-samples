// bench_conv_f64_v3.mc — same 4 output positions per iteration as v2,
// but expressed directly as two f64x2 packed accumulators (acc01 and
// acc23) instead of four scalar accumulators.
//
// Each `+=` on a f64x2 is one SIMD multiply-add covering two output
// positions at once, so the inner loop runs two FMAs per kernel tap
// covering four outputs — the same total work as v2, written in the
// explicit-SIMD style when you know the shape up front.
//
// Same checksum as v1/v2.
#include "bench_util.mc"

i32 main() {
    i32 n = 5_000_000;
    i32 ksize = 15;
    i32 khalf = ksize / 2;

    i32* signal = alloc<i32>(n);
    i32* output = alloc<i32>(n);
    f64* kernel = alloc<f64>(ksize);
    f64* sig_f = alloc<f64>(n);

    i64 state = 31_415;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        signal[i] = cast(i32, (state >> 33) % 256);
    }

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

    for i32 i = 0; i < n; i++ {
        sig_f[i] = cast(f64, signal[i]);
    }

    // Warm up.
    for i32 i = khalf; i < n - khalf - 3; i = i + 4 {
        f64x2 acc01, acc23;
        i32 base = i - khalf;
        for i32 k = 0; k < ksize; k++ {
            f64 kv = kernel[k];
            f64x2 sig01 = f64x2_load(sig_f + base + k);
            f64x2 sig23 = f64x2_load(sig_f + base + k + 2);
            acc01 = acc01 + sig01 * kv;
            acc23 = acc23 + sig23 * kv;
        }
        output[i + 0] = cast(i32, acc01.x);
        output[i + 1] = cast(i32, acc01.y);
        output[i + 2] = cast(i32, acc23.x);
        output[i + 3] = cast(i32, acc23.y);
    }
    i32 warm_last = ((n - khalf) - khalf) / 4 * 4 + khalf;
    for i32 i = warm_last; i < n - khalf; i++ {
        f64 acc = 0.0;
        i32 base = i - khalf;
        for i32 k = 0; k < ksize; k++ {
            acc = acc + sig_f[base + k] * kernel[k];
        }
        output[i] = cast(i32, acc);
    }

    // work
    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 5; iter++ {
        for i32 i = khalf; i < n - khalf - 3; i = i + 4 {
            f64x2 acc01, acc23;
            i32 base = i - khalf;
            for i32 k = 0; k < ksize; k++ {
                f64 kv = kernel[k];
                f64x2 sig01 = f64x2_load(sig_f + base + k);
                f64x2 sig23 = f64x2_load(sig_f + base + k + 2);
                acc01 = acc01 + sig01 * kv;
                acc23 = acc23 + sig23 * kv;
            }
            output[i + 0] = cast(i32, acc01.x);
            output[i + 1] = cast(i32, acc01.y);
            output[i + 2] = cast(i32, acc23.x);
            output[i + 3] = cast(i32, acc23.y);
        }

        i32 tail_start = ((n - khalf) - khalf) / 4 * 4 + khalf;
        for i32 i = tail_start; i < n - khalf; i++ {
            f64 acc = 0.0;
            i32 base = i - khalf;
            for i32 k = 0; k < ksize; k++ {
                acc = acc + sig_f[base + k] * kernel[k];
            }
            output[i] = cast(i32, acc);
        }
    }
    i64 end = qpc();

    i64 checksum = 0;
    for i32 i = 0; i < n; i++ {
        checksum = checksum + output[i];
    }

    free(signal);
    free(output);
    free(kernel);
    free(sig_f);
    bench_print("conv_f64_v3", checksum, elapsed_us(start, end, freq));
    return 0;
}
