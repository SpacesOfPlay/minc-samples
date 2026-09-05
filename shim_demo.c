// shim_demo.c — C shim that minc links statically and calls.
//
// The @link tags in shim_demo.mc merge this object into the minc
// executable. No C runtime is linked, so there is no libc here and any
// stack-protector symbol the compiler references must be defined below.
//
//   minc -> C : shim_mix
//   C -> minc : shim_reduce (calls a minc callback through a fn pointer)

#include <stdint.h>

// Stack-protector symbols as no-ops. Even with the protector off
// (-fno-stack-protector, /GS-) a compiler may emit a canary check for a
// function with a stack buffer; without these the link fails on an
// unresolved symbol.
#if defined(_WIN32)
uintptr_t __security_cookie = 0;
void __security_check_cookie(uintptr_t c) { (void)c; }
#else
uintptr_t __stack_chk_guard = 0;
void __stack_chk_fail(void) { }
#endif


// minc -> C: a plain calculation.
int32_t shim_mix(int32_t a, int32_t b) {
    return a * a + b * 3;
}

// C -> minc: fold an array with a minc callback.
int32_t shim_reduce(int32_t (*fn)(int32_t, int32_t), const int32_t* arr, int32_t n) {
    if (n <= 0) return 0;
    int32_t acc = arr[0];
    for (int32_t i = 1; i < n; i++) {
        acc = fn(acc, arr[i]);
    }
    return acc;
}
