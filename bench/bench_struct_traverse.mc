// bench_struct_traverse.mc - array-of-structs multi-field traversal (AoS cache behavior, register pressure)
#include "bench_util.mc"

struct Record {
    i32 a;
    i32 b;
    i32 c;
    i32 d;
    i32 e;
}

i64 struct_traverse(Record* arr, i32 n) {
    i64 sum_a, sum_b, sum_c, sum_d, sum_e;
    for i32 i = 0; i < n; i++ {
        sum_a = sum_a + arr[i].a;
        sum_b = sum_b + arr[i].b;
        sum_c = sum_c + arr[i].c;
        sum_d = sum_d + arr[i].d;
        sum_e = sum_e + arr[i].e;
    }
    return sum_a + sum_b * 3 + sum_c * 7 + sum_d * 13 + sum_e * 31;
}

void fill_records(Record* arr, i32 n) {
    i64 state = 33333;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        arr[i].a = cast(i32, (state >> 33) & 0xFF);
        arr[i].b = cast(i32, (state >> 41) & 0xFF);
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        arr[i].c = cast(i32, (state >> 33) & 0xFF);
        arr[i].d = cast(i32, (state >> 41) & 0xFF);
        arr[i].e = cast(i32, (state >> 49) & 0xFF);
    }
}

i32 main() {
    i32 n = 1_000_000;
    Record* arr = alloc<Record>(n);
    fill_records(arr, n);

    // Warm up
    i64 result = struct_traverse(arr, n);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 200; iter++ {
        result = struct_traverse(arr, n);
    }
    i64 end = qpc();

    free(arr);
    bench_print("struct_traverse", result, elapsed_us(start, end, freq));
    return 0;
}
