// Byte frequency histogram benchmark
// Counts byte frequencies in 50 MB of random data, 20 iterations.

#include "bench_util.mc"

i64 histogram(u8* buf, i32 size) {
    i32* counts = alloc<i32>(256);
    memset(cast(void*, counts), 0, 256 * 4);

    for i32 i = 0; i < size; i++ {
        i32 b = buf[i];
        counts[b] = counts[b] + 1;
    }

    // Weighted checksum
    i64 cs = 0;
    for i32 i = 0; i < 256; i++ {
        cs = cs + cast(i64, counts[i]) * cast(i64, i);
    }
    free(counts);
    return cs;
}

void fill_random(u8* buf, i32 n) {
    i64 state = 11111;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        buf[i] = cast(u8, (state >> 33) & 255);
    }
}

i32 main() {
    i32 size = 50_000_000;
    u8* buf = alloc<u8>(size);
    fill_random(buf, size);

    // Warm up
    i64 result = histogram(buf, size);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 20; iter++ {
        result = histogram(buf, size);
    }
    i64 end = qpc();

    free(buf);
    bench_print("histogram", result, elapsed_us(start, end, freq));
    return 0;
}
