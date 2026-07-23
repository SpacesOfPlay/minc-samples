// bench_indirect_call.c - function pointer dispatch benchmark
#include "bench_timer.h"

static long long op_add(long long a, long long b) { return a + b; }
static long long op_sub(long long a, long long b) { return a - b; }
static long long op_xor(long long a, long long b) { return a ^ b; }
static long long op_mul(long long a, long long b) { return (a * b) >> 32; }

typedef long long (*binop_fn)(long long, long long);

static long long indirect_call(int *indices, int n) {
    binop_fn ops[4] = { op_add, op_sub, op_xor, op_mul };

    long long acc = 1;
    for (int i = 0; i < n; i++) {
        int idx = indices[i];
        acc = ops[idx](acc, (long long)i);
    }
    return acc;
}

static void fill_indices(int *arr, int n) {
    long long state = 11223;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        arr[i] = (int)((unsigned long long)(state >> 33) % 4);
    }
}

int main(void) {
    int n = 10000000;
    int *indices = (int *)malloc((size_t)n * sizeof(int));
    fill_indices(indices, n);

    // Warm up
    long long result = indirect_call(indices, n);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 20; iter++) {
        result = indirect_call(indices, n);
        BENCH_USE(result);
    }
    bench_timer_start(&t2);

    free(indices);
    long long elapsed = bench_elapsed_us(t1, t2);
    printf("indirect_call: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
