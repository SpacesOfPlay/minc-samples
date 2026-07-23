// bench_dp_edit.mc - Levenshtein edit distance via dynamic programming (O(n^2) DP table)
#include "bench_util.mc"

i32 edit_distance(u8* a, i32 alen, u8* b, i32 blen, i32* prev, i32* curr) {
    // Initialize prev row
    for i32 j = 0; j <= blen; j++ {
        prev[j] = j;
    }

    for i32 i = 1; i <= alen; i++ {
        curr[0] = i;
        for i32 j = 1; j <= blen; j++ {
            i32 cost = 0;
            if a[i - 1] != b[j - 1] { cost = 1; }

            i32 del = prev[j] + 1;
            i32 ins = curr[j - 1] + 1;
            i32 sub = prev[j - 1] + cost;

            i32 m = del;
            if ins < m { m = ins; }
            if sub < m { m = sub; }
            curr[j] = m;
        }
        // Swap prev and curr
        i32* tmp = prev;
        prev = curr;
        curr = tmp;
    }
    return prev[blen];
}

void gen_string(u8* buf, i32 len, i64* state_ptr) {
    i64 state = *state_ptr;
    for i32 i = 0; i < len; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        buf[i] = cast(u8, 97 + cast(i32, (state >> 33) % 4));
    }
    *state_ptr = state;
}

i32 main() {
    i32 slen = 10000;
    u8* a = alloc<u8>(slen);
    u8* b = alloc<u8>(slen);
    i32* prev = alloc<i32>(slen + 1);
    i32* curr = alloc<i32>(slen + 1);

    i64 state = 24680;
    gen_string(a, slen, &state);
    gen_string(b, slen, &state);

    // Warm up
    i64 result = edit_distance(a, slen, b, slen, prev, curr);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 3; iter++ {
        result = edit_distance(a, slen, b, slen, prev, curr);
    }
    i64 end = qpc();

    free(curr);
    free(prev);
    free(b);
    free(a);
    bench_print("dp_edit", result, elapsed_us(start, end, freq));
    return 0;
}
