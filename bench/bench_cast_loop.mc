// bench_cast_loop.mc - int/float conversion chain (CVTI2F + CVTF2I pairing, mixed register pressure)
#include "bench_util.mc"

i64 cast_loop(i32* arr, i32 n) {
    f64 running_avg = 0.0;
    i64 isum = 0;
    for i32 i = 0; i < n; i++ {
        i32 v = arr[i];
        // Int to float: update running average
        f64 fv = v;
        running_avg = running_avg + (fv - running_avg) / (i + 1);
        // Float to int: accumulate truncated partial average
        i32 iavg = cast(i32, running_avg);
        isum = isum + iavg;
    }
    // Combine both results into checksum
    return isum + cast(i32, running_avg * 1000.0);
}

void fill_data(i32* arr, i32 n) {
    i64 state = 77777;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        arr[i] = cast(i32, (state >> 33) % 10000);
    }
}

i32 main() {
    i32 n = 10_000_000;
    i32* arr = alloc<i32>(n);
    fill_data(arr, n);

    // Warm up
    i64 result = cast_loop(arr, n);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 20; iter++ {
        result = cast_loop(arr, n);
    }
    i64 end = qpc();

    free(arr);
    bench_print("cast_loop", result, elapsed_us(start, end, freq));
    return 0;
}
