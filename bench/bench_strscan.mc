// bench_strscan.mc - byte-level string classification (CMOV for char categories, tight byte loop)
#include "bench_util.mc"

i64 strscan(u8* buf, i32 size) {
    i32 digits = 0;
    i32 alpha = 0;
    i32 spaces = 0;
    i32 other = 0;
    for i32 i = 0; i < size; i++ {
        i32 c = buf[i];
        if c >= 48 && c <= 57 {
            digits++;
        } else if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) {
            alpha++;
        } else if c == 32 || c == 9 || c == 10 || c == 13 {
            spaces++;
        } else {
            other++;
        }
    }
    return cast(i64, digits) * 1_000_000 + cast(i64, alpha) * 1_000 + cast(i64, spaces);
}

void fill_text(u8* buf, i32 n) {
    // Fill with pseudo-random ASCII text (mix of digits, letters, spaces, punctuation)
    i64 state = 22222;
    for i32 i = 0; i < n; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        i32 r = cast(i32, (state >> 33) % 100);
        if r < 40 {
            // 40%: lowercase letters
            buf[i] = cast(u8, 97 + cast(i32, (state >> 40) % 26));
        } else if r < 55 {
            // 15%: uppercase letters
            buf[i] = cast(u8, 65 + cast(i32, (state >> 43) % 26));
        } else if r < 70 {
            // 15%: digits
            buf[i] = cast(u8, 48 + cast(i32, (state >> 46) % 10));
        } else if r < 85 {
            // 15%: spaces/whitespace
            buf[i] = 32;
        } else {
            // 15%: punctuation/other
            buf[i] = cast(u8, 33 + cast(i32, (state >> 49) % 15));
        }
    }
}

i32 main() {
    i32 size = 50_000_000;
    u8* buf = alloc<u8>(size);
    fill_text(buf, size);

    // Warm up
    i64 result = strscan(buf, size);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 20; iter++ {
        result = strscan(buf, size);
    }
    i64 end = qpc();

    free(buf);
    bench_print("strscan", result, elapsed_us(start, end, freq));
    return 0;
}
