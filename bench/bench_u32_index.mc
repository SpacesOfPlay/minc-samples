// u32 loop-counter / array-index benchmark.
// Verifies that using u32 (instead of i32) as loop counters in indexed
// hot loops doesn't regress vs MSVC /O2. Workload picks loop-carried
// dependency chains so neither compiler autovectorizes the inner loop —
// the ratio reflects scalar codegen quality, not vectoriser disparity.
//

#include "bench_util.mc"

// Loop-carried mix32 + indexed read. The `acc = acc * mix * a[i]` chain
// is fully sequential; SSE2 paddq can't help.
u32 hash_chain(u32* a, u32 n) {
    u32 acc = 0xDEADBEEF;
    for u32 i = 0; i < n; i++ {
        acc = acc ^ a[i];
        acc = acc * 0x9E3779B9;
        acc = acc ^ (acc >> 16);
        acc = acc + i;
    }
    return acc;
}

// Indirect index chain: each load decides the next index. No prefetch,
// no parallelism. Stresses the index-truncation path repeatedly.
u32 jump_chain(u32* a, u32 n, u32 iters) {
    u32 idx = 0;
    u32 acc = 0;
    for u32 k = 0; k < iters; k++ {
        u32 v = a[idx & (n - 1)];
        acc = acc ^ v;
        idx = (idx + v) ^ k;
    }
    return acc;
}

// Histogram with scatter — scatter on a u32 index chain. MSVC won't
// vectorise the scatter; both compilers stay scalar.
u64 hist_scatter(u32* buf, u32 size) {
    u32[256] counts;
    for u32 i = 0; i < size; i++ {
        u32 b = buf[i] & 255;
        counts[b] = counts[b] + 1;
    }
    u64 cs = 0;
    for u32 i = 0; i < 256; i++ {
        cs = cs + cast(u64, counts[i]) * cast(u64, i);
    }
    return cs;
}

i32 main() {
    u32 size = 1_048_576;       // power of 2 for jump_chain mask
    u32* buf = alloc<u32>(size);
    u64 state = 11111;
    for u32 i = 0; i < size; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        buf[i] = cast(u32, (state >> 33) & 0xFFFFFFFF);
    }

    // Warm up
    u32 r1 = hash_chain(buf, size);
    u32 r2 = jump_chain(buf, size, size);
    u64 r3 = hist_scatter(buf, size);

    i64 freq = qpf();
    i64 start = qpc();
    for u32 iter = 0; iter < 50; iter++ {
        r1 = r1 ^ hash_chain(buf, size);
        r2 = r2 ^ jump_chain(buf, size, size);
        r3 = r3 + hist_scatter(buf, size);
    }
    i64 end = qpc();

    free(buf);
    i64 result = cast(i64, cast(u64, r1)) ^ cast(i64, cast(u64, r2)) ^ cast(i64, r3);
    bench_print("u32_index", result, elapsed_us(start, end, freq));
    return 0;
}
