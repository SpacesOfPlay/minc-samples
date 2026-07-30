// shim_demo.mc — call a C shim, in both directions.
//
// shim_demo.c is compiled to a per-platform object and pulled in by the
// @link tags below; minc merges it statically, so the result has no C
// runtime and no shared-library dependencies.
//
// Build & run:  ./build.sh shim   (or  .\build.ps1 shim  on Windows)
//
// @link paths resolve relative to this file, so "build/x" lands in the
// repo's build/ dir from any working directory. Each platform links its
// native object format (ELF / Mach-O / COFF).
when os(linux) {
    @link "build/shim_demo_linux.o"
}
when os(macos) {
    @link "build/shim_demo_macos.o"
}
when os(windows) {
    @link "build/shim_demo_win.obj"
}

// minc -> C: a plain extern — the symbol comes from the linked object,
// not a shared library, so there's no library name.
extern i32 shim_mix(i32 a, i32 b);

// C -> minc: the shim calls this back through a function pointer. minc's
// `fn(i32, i32): i32` matches C's `int32_t (*)(int32_t, int32_t)`.
extern i32 shim_reduce(fn(i32, i32): i32 op, i32* arr, i32 n);

// Callbacks the C side invokes.
i32 add(i32 a, i32 b) { return a + b; }
i32 imax(i32 a, i32 b) { if a > b { return a; } return b; }

i32 main() {
    // minc calls C.
    print("shim_mix(5, 2)        = {}\n", shim_mix(5, 2));   // 5*5 + 2*3 = 31

    // C calls back into minc through a function pointer.
    i32[5] data = { 3, 1, 4, 1, 5 };
    print("reduce add over data  = {}\n", shim_reduce(add, &data[0], 5));   // 14
    print("reduce max over data  = {}\n", shim_reduce(imax, &data[0], 5));  // 5
    return 0;
}
