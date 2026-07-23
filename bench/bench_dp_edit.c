// bench_dp_edit.c - Levenshtein edit distance benchmark
#include "bench_timer.h"

static int edit_distance(unsigned char *a, int alen, unsigned char *b, int blen, int *prev, int *curr) {
    // Initialize prev row
    for (int j = 0; j <= blen; j++) {
        prev[j] = j;
    }

    for (int i = 1; i <= alen; i++) {
        curr[0] = i;
        for (int j = 1; j <= blen; j++) {
            int cost = 0;
            if (a[i - 1] != b[j - 1]) cost = 1;

            int del = prev[j] + 1;
            int ins = curr[j - 1] + 1;
            int sub = prev[j - 1] + cost;

            int m = del;
            if (ins < m) m = ins;
            if (sub < m) m = sub;
            curr[j] = m;
        }
        // Swap prev and curr
        int *tmp = prev;
        prev = curr;
        curr = tmp;
    }
    return prev[blen];
}

static void gen_string(unsigned char *buf, int len, long long *state_ptr) {
    long long state = *state_ptr;
    for (int i = 0; i < len; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        buf[i] = (unsigned char)(97 + (int)((state >> 33) % 4));
    }
    *state_ptr = state;
}

int main(void) {
    int slen = 10000;
    unsigned char *a = (unsigned char *)malloc((size_t)slen);
    unsigned char *b = (unsigned char *)malloc((size_t)slen);
    int *prev = (int *)malloc((size_t)(slen + 1) * 4);
    int *curr = (int *)malloc((size_t)(slen + 1) * 4);

    long long state = 24680;
    gen_string(a, slen, &state);
    gen_string(b, slen, &state);

    // Warm up
    long long result = (long long)edit_distance(a, slen, b, slen, prev, curr);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 3; iter++) {
        result = (long long)edit_distance(a, slen, b, slen, prev, curr);
        BENCH_USE(result);
    }
    bench_timer_start(&t2);

    free(curr);
    free(prev);
    free(b);
    free(a);
    long long elapsed = bench_elapsed_us(t1, t2);
    printf("dp_edit: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
