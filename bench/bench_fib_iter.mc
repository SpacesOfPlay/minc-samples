// Iterative Fibonacci benchmark
// Computes fib(92) — the largest Fibonacci number that fits in i64.

#include "bench_util.mc"

i64 fibonacci(i32 n) {
    i64 a = 0;
    i64 b = 1;
    for i32 i = 0; i < n; i++ {
        i64 next = a + b;
        a = b;
        b = next;
    }
    return a;
}

i32 main() {
    // Warm up
    fibonacci(92);

    i64 freq = qpf();
    i64 start = qpc();
    i64 result = 0;
    for i32 iter = 0; iter < 10_000_000; iter++ {
        result = fibonacci(92);
    }
    i64 end = qpc();

    // fib(92) = 7540113804746346429
    if result != 7540113804746346429 { return 1; }

    bench_print("fib_iter", result, elapsed_us(start, end, freq));
    return 0;
}
