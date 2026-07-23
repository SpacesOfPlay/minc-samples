// bench_lex_scan.mc - lexer-style token scanning (switch dispatch, multi-byte token spans)
#include "bench_util.mc"

// Simple token types
i32 TOK_WORD = 1;
i32 TOK_NUM = 2;
i32 TOK_SYM = 3;
i32 TOK_WS = 4;

// Fill buffer with pseudo-random "source code" bytes
void fill_source(u8* buf, i32 size) {
    i64 state = 777;
    // Characters: letters, digits, spaces, symbols
    for i32 i = 0; i < size; i++ {
        state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
        i32 r = cast(i32, (state >> 33) % 100);
        if r < 40 {
            // letter a-z
            buf[i] = cast(u8, 97 + cast(i32, (state >> 40) % 26));
        } else if r < 60 {
            // digit 0-9
            buf[i] = cast(u8, 48 + cast(i32, (state >> 40) % 10));
        } else if r < 80 {
            // space or newline
            if r < 75 {
                buf[i] = 32;
            } else {
                buf[i] = 10;
            }
        } else {
            // symbols: + - * / = ( ) { } ;
            i32 si = cast(i32, (state >> 40) % 10);
            u8[10] syms;
            syms[0] = 43; syms[1] = 45; syms[2] = 42; syms[3] = 47; syms[4] = 61;
            syms[5] = 40; syms[6] = 41; syms[7] = 123; syms[8] = 125; syms[9] = 59;
            buf[i] = syms[si];
        }
    }
}

bool is_alpha(u8 c) {
    return (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95;
}

bool is_digit(u8 c) {
    return c >= 48 && c <= 57;
}

bool is_space(u8 c) {
    return c == 32 || c == 10 || c == 13 || c == 9;
}

i32 scan_tokens(u8* buf, i32 size) {
    i32 count = 0;
    i32 pos = 0;
    while pos < size {
        i32 c = buf[pos];
        switch c {
            // Whitespace: space, tab, newline, cr
            case 9, 10, 13, 32: {
                while pos < size && is_space(buf[pos]) {
                    pos++;
                }
                count++;
            }
            // Digits 0-9
            case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57: {
                while pos < size && is_digit(buf[pos]) {
                    pos++;
                }
                count++;
            }
            // Lowercase a-z
            case 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77,
                 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90,
                 95,
                 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109,
                 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122: {
                while pos < size && (is_alpha(buf[pos]) || is_digit(buf[pos])) {
                    pos++;
                }
                count++;
            }
            default: {
                pos++;
                count++;
            }
        }
    }
    return count;
}

i32 main() {
    i32 size = 10_000_000;
    u8* buf = alloc<u8>(size);
    fill_source(buf, size);

    // Warm up
    i32 count = scan_tokens(buf, size);

    i64 freq = qpf();
    i64 start = qpc();
    for i32 iter = 0; iter < 10; iter++ {
        count = scan_tokens(buf, size);
    }
    i64 end = qpc();

    free(buf);

    bench_print("lex_scan", count, elapsed_us(start, end, freq));
    return 0;
}
