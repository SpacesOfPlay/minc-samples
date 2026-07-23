// bench_indirect_call.mc - function pointer dispatch (indirect call overhead, branch target prediction)
#include "bench_util.mc"

i64 op_add(i64 a, i64 b) { return a + b; }
i64 op_sub(i64 a, i64 b) { return a - b; }
i64 op_xor(i64 a, i64 b) { return a ^ b; }
i64 op_mul(i64 a, i64 b) { return (a * b) >> 32; }

// Use i64 array as storage for function pointers (same size on x64)
i64[4] g_ops;

void init_ops() {
    g_ops[0] = cast(i64, op_add);
    g_ops[1] = cast(i64, op_sub);
    g_ops[2] = cast(i64, op_xor);
    g_ops[3] = cast(i64, op_mul);
}

i64 indirect_call(i32* indices, i32 n) {
    i64 acc = 1;
    for i32 i = 0; i < n; i++ {
        i32 idx = indices[i];
        fn(i64, i64): i64 op = cast(fn(i64, i64): i64, g_ops[idx]);
        acc = op(acc, i);
    }
    return acc;
}

void fill_indices(i32* arr, i32 n) {
    i64 state = 11223;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        arr[i] = cast(i32, cast(u64, state >> 33) % 4);
    }
}

i32 main() {
    i32 n = 10_000_000;
    i32* indices = alloc<i32>(n);
    fill_indices(indices, n);
    init_ops();

    // Warm up
    i64 result = indirect_call(indices, n);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 20; iter++ {
        result = indirect_call(indices, n);
    }
    i64 end = qpc();

    free(indices);
    bench_print("indirect_call", result, elapsed_us(start, end, freq));
    return 0;
}
