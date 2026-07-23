// Recursive Fibonacci benchmark
// Classic exponential-time recursion — tests function call overhead.

#include "bench_util.mc"

i32 fibonacci(i32 n) {
    if n <= 1 { return n; }
    return fibonacci(n - 1) + fibonacci(n - 2);
}

i32 main() {
    i64 freq = qpf();
    i64 start = qpc();
    i32 result = 0;
    for i32 iter = 0; iter < 3; iter++ {
        result = fibonacci(40);
    }
    i64 end = qpc();

    if result != 102_334_155 { return 1; }

    bench_print("fib_rec", result, elapsed_us(start, end, freq));
    return 0;
}
