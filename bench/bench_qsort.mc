// Quicksort benchmark
// Sorts 1 million random integers, 5 iterations.

#include "bench_util.mc"

void swap(i32* arr, i32 a, i32 b) {
    i32 tmp = arr[a];
    arr[a] = arr[b];
    arr[b] = tmp;
}

i32 partition(i32* arr, i32 lo, i32 hi) {
    i32 pivot = arr[hi];
    i32 i = lo;
    for i32 j = lo; j < hi; j++ {
        if arr[j] < pivot {
            swap(arr, i, j);
            i++;
        }
    }
    swap(arr, i, hi);
    return i;
}

void quicksort(i32* arr, i32 lo, i32 hi) {
    if lo >= hi { return; }
    i32 p = partition(arr, lo, hi);
    quicksort(arr, lo, p - 1);
    quicksort(arr, p + 1, hi);
}

void fill_random(i32* arr, i32 n) {
    i64 state = 12345;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        arr[i] = cast(i32, (state >> 33) & 0x7FFFFFFF);
    }
}

i64 checksum(i32* arr, i32 n) {
    // Sum first 10 + last 10 elements
    i64 sum = 0;
    for i32 i = 0; i < 10; i++ {
        sum = sum + arr[i];
    }
    for i32 i = n - 10; i < n; i++ {
        sum = sum + arr[i];
    }
    return sum;
}

i32 main() {
    i32 n = 1_000_000;
    i32* arr = alloc<i32>(n);

    // Warm up
    fill_random(arr, n);
    quicksort(arr, 0, n - 1);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 5; iter++ {
        fill_random(arr, n);
        quicksort(arr, 0, n - 1);
    }
    i64 end = qpc();

    // Verify sorted
    for i32 i = 1; i < n; i++ {
        if arr[i] < arr[i - 1] { free(arr); return 1; }
    }

    i64 cs = checksum(arr, n);
    free(arr);

    bench_print("qsort", cs, elapsed_us(start, end, freq));
    return 0;
}
