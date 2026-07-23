// bench_qsort.c - quicksort benchmark
#include "bench_timer.h"

static void swap(int *arr, int a, int b) {
    int t = arr[a];
    arr[a] = arr[b];
    arr[b] = t;
}

static int partition(int *arr, int lo, int hi) {
    int pivot = arr[hi];
    int i = lo;
    for (int j = lo; j < hi; j++) {
        if (arr[j] < pivot) {
            swap(arr, i, j);
            i++;
        }
    }
    swap(arr, i, hi);
    return i;
}

static void quicksort(int *arr, int lo, int hi) {
    if (lo >= hi) return;
    int p = partition(arr, lo, hi);
    quicksort(arr, lo, p - 1);
    quicksort(arr, p + 1, hi);
}

static void fill_random(int *arr, int n) {
    long long state = 12345;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        arr[i] = (int)((state >> 33) & 2147483647LL);
    }
}

static long long checksum(int *arr, int n) {
    long long sum = 0;
    for (int i = 0; i < 10; i++) {
        sum += (long long)arr[i];
    }
    for (int i = n - 10; i < n; i++) {
        sum += (long long)arr[i];
    }
    return sum;
}

int main(void) {
    int n = 1000000;
    int *arr = (int *)malloc((size_t)n * 4);

    // Warm up
    fill_random(arr, n);
    quicksort(arr, 0, n - 1);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 5; iter++) {
        fill_random(arr, n);
        quicksort(arr, 0, n - 1);
        BENCH_CLOBBER(arr);
    }
    bench_timer_start(&t2);

    // Verify sorted
    for (int i = 1; i < n; i++) {
        if (arr[i] < arr[i - 1]) { free(arr); return 1; }
    }

    long long cs = checksum(arr, n);
    free(arr);

    long long elapsed = bench_elapsed_us(t1, t2);
    printf("qsort: result=%lld time=%lld us\n", cs, elapsed);
    return 0;
}
