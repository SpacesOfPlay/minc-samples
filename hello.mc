// hello.mc - minimal minc program

// enable multi-byte (emoji, non-ASCII) support for windows terminals.
// has a small launch overhead so only added when explicitly enabled.
@utf8_console

i32 main() {
    print("Hello, world! 🎉\n");
    return 0;
}
