// Sieve of Eratosthenes benchmark
// Finds all primes up to 10 million.

#include "bench_util.mc"

i32 sieve(u8* flags, i32 size) {
    // Mark all as prime candidates
    memset(cast(void*, flags), 1, size);
    flags[0] = 0;
    flags[1] = 0;

    // Sieve: for each prime, mark its multiples
    i32 i = 2;
    while i * i < size {
        if flags[i] != 0 {
            i32 j = i * i;
            while j < size {
                flags[j] = 0;
                j = j + i;
            }
        }
        i++;
    }

    // Count remaining primes
    i32 count = 0;
    for i32 k = 0; k < size; k++ {
        if flags[k] != 0 { count++; }
    }
    return count;
}

i32 main() {
    i32 size = 10_000_000;
    u8* flags = alloc<u8>(size);

    // Warm up
    i32 count = sieve(flags, size);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 10; iter++ {
        count = sieve(flags, size);
    }
    i64 end = qpc();

    free(flags);

    if count != 664_579 { return 1; }

    bench_print("sieve", count, elapsed_us(start, end, freq));
    return 0;
}
