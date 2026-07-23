// Branch-heavy classify loop benchmark
// Tests CMOV conversion, branch prediction, nested if/else chains.

#include "bench_util.mc"

i64 branch_chain(i32* arr, i32 n) {
    i64[8] bins;
    for i32 i = 0; i < 8; i++ { bins[i] = 0; }

    for i32 i = 0; i < n; i++ {
        i32 v = arr[i];
        // Classify into 8 bins via nested if/else
        i32 bin = 0;
        if v < 0 {
            bin = 0;
        } else if v < 16 {
            bin = 1;
        } else if v < 64 {
            bin = 2;
        } else if v < 256 {
            bin = 3;
        } else if v < 1024 {
            bin = 4;
        } else if v < 4096 {
            bin = 5;
        } else if v < 16384 {
            bin = 6;
        } else {
            bin = 7;
        }
        bins[bin]++;
    }

    // Weighted checksum
    i64 cs = 0;
    for i32 i = 0; i < 8; i++ {
        cs = cs + bins[i] * (i + 1);
    }
    return cs;
}

void fill_data(i32* arr, i32 n) {
    i64 state = 66666;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        arr[i] = cast(i32, (state >> 33)) - 5000;
    }
}

i32 main() {
    i32 n = 10_000_000;
    i32* arr = alloc<i32>(n);
    fill_data(arr, n);

    // Warm up
    i64 result = branch_chain(arr, n);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 50; iter++ {
        result = branch_chain(arr, n);
    }
    i64 end = qpc();

    free(arr);
    bench_print("branch_chain", result, elapsed_us(start, end, freq));
    return 0;
}
