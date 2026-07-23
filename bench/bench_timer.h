// bench_timer.h - cross-platform high-resolution timer for benchmarks
#ifndef BENCH_TIMER_H
#define BENCH_TIMER_H

#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
typedef LARGE_INTEGER bench_time_t;
static inline void bench_timer_start(bench_time_t *t) { QueryPerformanceCounter(t); }
static inline long long bench_elapsed_us(bench_time_t t1, bench_time_t t2) {
    LARGE_INTEGER freq;
    QueryPerformanceFrequency(&freq);
    return (t2.QuadPart - t1.QuadPart) * 1000000 / freq.QuadPart;
}
#else
#include <time.h>
typedef struct timespec bench_time_t;
static inline void bench_timer_start(bench_time_t *t) { clock_gettime(CLOCK_MONOTONIC, t); }
static inline long long bench_elapsed_us(bench_time_t t1, bench_time_t t2) {
    return (long long)(t2.tv_sec - t1.tv_sec) * 1000000LL + (long long)(t2.tv_nsec - t1.tv_nsec) / 1000LL;
}
#endif

// Prevent compiler from optimizing away benchmark computations.
// BENCH_USE: makes the value appear used (prevents dead code elimination).
// BENCH_CLOBBER: makes a pointer appear modified (prevents hoisting pure calls).
#ifdef _MSC_VER
static volatile long long bench_sink;
static volatile void *bench_ptr_sink;
#define BENCH_USE(x) (bench_sink = (long long)(x))
#define BENCH_CLOBBER(p) (bench_ptr_sink = (p))
#else
#define BENCH_USE(x) __asm__ volatile("" : : "r"((long long)(x)) : "memory")
#define BENCH_CLOBBER(p) __asm__ volatile("" : "+r"(p) :: "memory")
#endif

// Portable hardware popcount
#ifdef _MSC_VER
#include <intrin.h>
static inline int bench_popcount(unsigned int x) { return (int)__popcnt(x); }
#else
static inline int bench_popcount(unsigned int x) { return __builtin_popcount(x); }
#endif

#endif
