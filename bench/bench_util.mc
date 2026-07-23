// bench_util.mc — shared benchmark helpers
// #include this from each benchmark .mc file

i64 elapsed_us(i64 start, i64 end, i64 freq) {
    return (end - start) * 1_000_000 / freq;
}

void bench_print(u8* name, i64 result, i64 time_us) {
    // print() formats u8* as pointer address, so write name directly
    i32 len = 0;
    while name[len] != 0 { len++; }
    write(stdout(), name, len);
    print(": result={} time={} us\n", result, time_us);
}
