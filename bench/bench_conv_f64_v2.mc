// bench_conv_f64_v2.mc — same 1D convolution as v1, with two source-level
// refactors that cut the inner loop's per-iteration work.
//
//   A. Convert the signal from i32 to f64 once up front into `sig_f[]`,
//      then run the kernel in pure f64. v1 casts every signal sample
//      from i32 to f64 inside the hot loop — pulling that conversion
//      out of the loop removes one operation per load.
//
//   B. Compute 4 output positions per outer-loop iteration instead of 1.
//      Each inner-loop step reads 4 adjacent signal values, multiplies
//      by the single kernel weight for that tap, and accumulates into
//      4 independent f64 running sums. Four independent add chains run
//      in parallel on the CPU instead of serialising through one.
//
// Same checksum as v1.
#include "bench_util.mc"

i32 main() {
    const i32 n = 5_000_000;
    const i32 ksize = 15;
    const i32 khalf = ksize / 2;

    // i32 storage for signal (same as v1) — the pre-convert loop below
    // produces the f64 view once.
    i32* signal = alloc<i32>(n);
    i32* output = alloc<i32>(n);
    f64* kernel = alloc<f64>(ksize);

    // Pre-converted f64 view of the signal. The hot inner loop reads
    // from here, so it never has to convert i32→f64 on each load the
    // way v1's inner loop does.
    f64* sig_f = alloc<f64>(n);

    // Seed same as v1 so both produce identical output under same
    // arithmetic order (FMA-contract aside — kernel triangle is
    // symmetric, so reordering is exact).
    i64 state = 31_415;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        signal[i] = cast(i32, (state >> 33) % 256);
    }

    // Kernel: identical to v1.
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

    // Pre-convert signal to f64. Runs once outside the timed region,
    // so the cast cost is amortized across all convolution iterations.
    for i32 i = 0; i < n; i++ {
        sig_f[i] = cast(f64, signal[i]);
    }

    // Warm up — same shape as the timed region.
    for i32 i = khalf; i < n - khalf - 3; i = i + 4 {
        f64 a0, a1, a2, a3;
        i32 base = i - khalf;
        for i32 k = 0; k < ksize; k++ {
            f64 kv = kernel[k];
            a0 = a0 + sig_f[base + k + 0] * kv;
            a1 = a1 + sig_f[base + k + 1] * kv;
            a2 = a2 + sig_f[base + k + 2] * kv;
            a3 = a3 + sig_f[base + k + 3] * kv;
        }
        output[i + 0] = cast(i32, a0);
        output[i + 1] = cast(i32, a1);
        output[i + 2] = cast(i32, a2);
        output[i + 3] = cast(i32, a3);
    }
    // Warm-up scalar tail (so the arr_out layout matches before timing).
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
        // Outer loop unrolled 4x: 4 output positions per iteration.
        // Each accumulator is independent, so the CPU can advance them
        // in parallel instead of waiting for one chain at a time.
        for i32 i = khalf; i < n - khalf - 3; i = i + 4 {
            f64 a0, a1, a2, a3;
            i32 base = i - khalf;
            for i32 k = 0; k < ksize; k++ {
                f64 kv = kernel[k];
                a0 = a0 + sig_f[base + k + 0] * kv;
                a1 = a1 + sig_f[base + k + 1] * kv;
                a2 = a2 + sig_f[base + k + 2] * kv;
                a3 = a3 + sig_f[base + k + 3] * kv;
            }
            output[i + 0] = cast(i32, a0);
            output[i + 1] = cast(i32, a1);
            output[i + 2] = cast(i32, a2);
            output[i + 3] = cast(i32, a3);
        }

        // Scalar tail for the 0..3 outputs the unrolled loop didn't cover.
        i32 tail_start = ((n - khalf) - khalf) / 4 * 4 + khalf;
        for i32 i = tail_start; i < n - khalf; i++ {
            f64 acc;
            i32 base = i - khalf;
            for i32 k = 0; k < ksize; k++ {
                acc = acc + sig_f[base + k] * kernel[k];
            }
            output[i] = cast(i32, acc);
        }
    }
    i64 end = qpc();

    // Checksum — identical to v1's (sum of all output values).
    i64 checksum = 0;
    for i32 i = 0; i < n; i++ {
        checksum = checksum + output[i];
    }

    free(signal);
    free(output);
    free(kernel);
    free(sig_f);
    bench_print("conv_f64_v2", checksum, elapsed_us(start, end, freq));
    return 0;
}
