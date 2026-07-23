// bench_struct_traverse.c - array-of-structs traversal benchmark
#include "bench_timer.h"

typedef struct {
    int a, b, c, d, e;
} Record;

static long long struct_traverse(Record *arr, int n) {
    long long sum_a = 0, sum_b = 0, sum_c = 0, sum_d = 0, sum_e = 0;
    for (int i = 0; i < n; i++) {
        sum_a += arr[i].a;
        sum_b += arr[i].b;
        sum_c += arr[i].c;
        sum_d += arr[i].d;
        sum_e += arr[i].e;
    }
    return sum_a + sum_b * 3 + sum_c * 7 + sum_d * 13 + sum_e * 31;
}

static void fill_records(Record *arr, int n) {
    long long state = 33333;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        arr[i].a = (int)((state >> 33) & 0xFF);
        arr[i].b = (int)((state >> 41) & 0xFF);
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        arr[i].c = (int)((state >> 33) & 0xFF);
        arr[i].d = (int)((state >> 41) & 0xFF);
        arr[i].e = (int)((state >> 49) & 0xFF);
    }
}

int main(void) {
    int n = 1000000;
    Record *arr = (Record *)malloc((size_t)n * sizeof(Record));
    fill_records(arr, n);

    // Warm up
    long long result = struct_traverse(arr, n);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 200; iter++) {
        result = struct_traverse(arr, n);
        BENCH_USE(result);
    }
    bench_timer_start(&t2);

    free(arr);
    long long elapsed = bench_elapsed_us(t1, t2);
    printf("struct_traverse: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
