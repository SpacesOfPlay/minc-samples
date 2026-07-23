// bench_lex_scan.c - lexer-like byte scanning benchmark
#include "bench_timer.h"

static void fill_source(unsigned char *buf, int size) {
    long long state = 777;
    for (int i = 0; i < size; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        int r = (int)((state >> 33) % 100);
        if (r < 40) {
            buf[i] = (unsigned char)(97 + (int)((state >> 40) % 26));
        } else if (r < 60) {
            buf[i] = (unsigned char)(48 + (int)((state >> 40) % 10));
        } else if (r < 80) {
            buf[i] = (r < 75) ? ' ' : '\n';
        } else {
            const char syms[] = "+-*/=(){};" ;
            int si = (int)((state >> 40) % 10);
            buf[i] = (unsigned char)syms[si];
        }
    }
}

static int is_alpha(unsigned char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

static int is_digit(unsigned char c) {
    return c >= '0' && c <= '9';
}

static int is_space(unsigned char c) {
    return c == ' ' || c == '\n' || c == '\r' || c == '\t';
}

static int scan_tokens(unsigned char *buf, int size) {
    int count = 0;
    int pos = 0;
    while (pos < size) {
        unsigned char c = buf[pos];
        if (is_space(c)) {
            while (pos < size && is_space(buf[pos])) pos++;
            count++;
        } else if (is_alpha(c)) {
            while (pos < size && (is_alpha(buf[pos]) || is_digit(buf[pos]))) pos++;
            count++;
        } else if (is_digit(c)) {
            while (pos < size && is_digit(buf[pos])) pos++;
            count++;
        } else {
            pos++;
            count++;
        }
    }
    return count;
}

int main(void) {
    int size = 10000000;
    unsigned char *buf = (unsigned char *)malloc(size);
    fill_source(buf, size);

    // Warm up
    int count = scan_tokens(buf, size);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 10; iter++) {
        count = scan_tokens(buf, size);
        BENCH_CLOBBER(buf);
    }
    bench_timer_start(&t2);

    free(buf);

    long long elapsed = bench_elapsed_us(t1, t2);
    printf("lex_scan: result=%d time=%lld us\n", count, elapsed);
    return 0;
}
