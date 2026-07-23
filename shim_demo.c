// shim_demo.c — a tiny C shim that minc statically links and calls.
//
// minc merges this object into its own executable via the @link tags in
// shim_demo.mc — one freestanding binary, no C runtime. Two consequences:
// there is no libc here (no printf/malloc), and any stack-protector
// support symbol the compiler references has to be defined locally,
// because no CRT is linked to supply it.
//
// FFI both directions:
//   minc -> C : shim_mix    (a plain calculation)
//   C -> minc : shim_reduce (calls a minc callback through a fn pointer)

#include <stdint.h>

// Stack-protector support symbols, as no-ops. Build with the protector
// off (-fno-stack-protector, or /GS- for MSVC), a small shim like this
// emits no canary at all. 
//
// But a compiler may still insert a canary check for a function with 
// a stack buffer (even with the flag), and the check references these 
// symbols. The link would then fail on an unresolved symbol.
//
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

// C -> minc: fold an array with a minc-supplied callback. The loop lives
// in C; the per-step operation lives in minc.
int32_t shim_reduce(int32_t (*fn)(int32_t, int32_t), const int32_t* arr, int32_t n) {
    if (n <= 0) return 0;
    int32_t acc = arr[0];
    for (int32_t i = 1; i < n; i++) {
        acc = fn(acc, arr[i]);
    }
    return acc;
}
