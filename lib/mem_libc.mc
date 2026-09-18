// mem_libc.mc: the C library allocator as the program's heap on Linux x64.
//
// Use with `import mem_libc;`
//
// Linux x64 only. On Windows and macOS the C library allocator is already the
// default.
//
// The program links libc.so.6 dynamically. The default allocator is 
// dependency free.
//


when os(linux) && arch(x64) {
    // free and realloc are minc builtins, so the C symbols get local names.
    extern "libc.so.6" {
        void* c_malloc(u64 n) from "malloc";
        void c_free(void* p) from "free";
        void* c_realloc(void* p, u64 n) from "realloc";
    }

    void* __minc_alloc(i64 n) { return c_malloc(cast(u64, n)); }
    void __minc_free(void* p) { c_free(p); }
    void* __minc_realloc(void* p, i64 n) { return c_realloc(p, cast(u64, n)); }
}
