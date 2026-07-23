// bench_strscan.c - string byte scanning benchmark
#include "bench_timer.h"

static long long strscan(unsigned char *buf, int size) {
    int digits = 0, alpha = 0, spaces = 0, other = 0;
    for (int i = 0; i < size; i++) {
        int c = buf[i];
        if (c >= 48 && c <= 57) {
            digits++;
        } else if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122)) {
            alpha++;
        } else if (c == 32 || c == 9 || c == 10 || c == 13) {
            spaces++;
        } else {
            other++;
        }
    }
    return (long long)digits * 1000000 + (long long)alpha * 1000 + (long long)spaces;
}

static void fill_text(unsigned char *buf, int n) {
    long long state = 22222;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        int r = (int)((state >> 33) % 100);
        if (r < 40) {
            buf[i] = (unsigned char)(97 + (int)((state >> 40) % 26));
        } else if (r < 55) {
            buf[i] = (unsigned char)(65 + (int)((state >> 43) % 26));
        } else if (r < 70) {
            buf[i] = (unsigned char)(48 + (int)((state >> 46) % 10));
        } else if (r < 85) {
            buf[i] = 32;
        } else {
            buf[i] = (unsigned char)(33 + (int)((state >> 49) % 15));
        }
    }
}

int main(void) {
    int size = 50000000;
    unsigned char *buf = (unsigned char *)malloc((size_t)size);
    fill_text(buf, size);

    // Warm up
    long long result = strscan(buf, size);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 20; iter++) {
        result = strscan(buf, size);
        BENCH_USE(result);
    }
    bench_timer_start(&t2);

    free(buf);
    long long elapsed = bench_elapsed_us(t1, t2);
    printf("strscan: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
