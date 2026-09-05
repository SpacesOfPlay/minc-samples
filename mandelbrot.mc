// mandelbrot.mc — animated Mandelbrot zoom in the terminal.
//
// Native: exits after N_FRAMES (~16 s) or on Ctrl-C. WASM: the
// playground calls frame() until it returns 1.

@utf8_console

import math;
import terminal;
import thread;

// signal() for the Ctrl-C handler that restores cursor and colour.
when os(macos) || os(ios) {
    extern "libSystem.B.dylib" void* signal(i32 sig, void* handler);
}
when os(linux) || os(android) {
    extern "libc.so.6" void* signal(i32 sig, void* handler);
}

// ----- Mandelbrot kernel ----------------------------------------------------

// Smooth iteration count nu = i + 1 - log2(log2(|z|)); the fractional
// part keeps colour gradients from banding. Returns max_iter when the
// point does not escape.
f64 mandel_iter(f64 cx, f64 cy, i32 max_iter) {
    f64 zx = 0.0;
    f64 zy = 0.0;
    for i32 i = 0; i < max_iter; i++ {
        f64 zx2 = zx * zx;
        f64 zy2 = zy * zy;
        f64 mag2 = zx2 + zy2;
        if mag2 > 4.0 {
            // log2(|z|) = log2(mag2) / 2
            f64 log_mag = log2(mag2) * 0.5;
            return i + 1.0 - log2(log_mag);
        }
        f64 zxn = zx2 - zy2 + cx;
        zy = 2.0 * zx * zy + cy;
        zx = zxn;
    }
    return max_iter;
}

// ----- Frame rendering ------------------------------------------------------

// Frame grid in terminal cells. detect_term_size() refreshes it from
// the host; the defaults stand on wasm and when detection fails.
i32 g_cols = 80;
i32 g_rows = 32;
// Frame buffer size, 12 bytes per cell worst case; detect_term_size()
// recomputes it.
i32 g_buf_len = 32768;

// WASM animation state, seeded by main() and advanced by frame().
u8* g_wasm_buf   = null;
f64 g_wasm_width = 4.0;
i32 g_wasm_f     = 0;

// glyph palette
const str PAL = "@%#*+=-:. ";

// 32-step gradient
const i32[32] COLOR_PAL = {
    // dark blue (far exterior)
     17,  18,  19,  20,
    // mid → bright blue
     21,  27,  33,  39,
    // light blue → purple
     45,  51,  56,  92,
    // purple
    128,  93,  99, 105,
    // magenta → pink
    165, 201, 200, 199,
    // red
    198, 197, 196, 202,
    // orange
    208, 214,
    // yellow
    220, 226,
    // bright yellow (near boundary)
    227, 228, 229, 230
};
const i32 NCOLOR = sizeof(COLOR_PAL) / sizeof(i32);  // 32

// Maps nu in [0, max_iter / SHIFT] onto the palette, so boundary cells
// reach the bright end.
const i32 SHIFT = 4;

i32 nu_to_color(f64 nu, i32 max_iter) {
    f64 ci_f = nu * (SHIFT * NCOLOR) / max_iter;
    i32 ci = cast(i32, ci_f);
    if ci < 0 { ci = 0; }
    if ci >= NCOLOR { ci = NCOLOR - 1; }
    return COLOR_PAL[ci];
}

// Append src at idx; return the new idx. A frame is a single write:
// two writes per frame flicker the Windows console.
i32 buf_append(u8* buf, i32 idx, str src) {
    i32 n = cast(i32, src.len);
    for i32 i = 0; i < n; i = i + 1 {
        buf[idx + i] = src.data[i];
    }
    return idx + n;
}

// Append the 256-colour foreground escape `\x1b[38;5;Nm`.
i32 emit_fg256(u8* out, i32 idx, i32 color) {
    idx = buf_append(out, idx, "\x1b[38;5;");
    if color >= 100 {
        out[idx] = cast(u8, 48 + color / 100);        idx++;
        out[idx] = cast(u8, 48 + (color / 10) % 10);  idx++;
        out[idx] = cast(u8, 48 + color % 10);         idx++;
    } else if color >= 10 {
        out[idx] = cast(u8, 48 + color / 10);  idx++;
        out[idx] = cast(u8, 48 + color % 10);  idx++;
    } else {
        out[idx] = cast(u8, 48 + color);  idx++;
    }
    out[idx] = 'm'; idx++;
    return idx;
}

// Render one frame into `out` (>= g_buf_len bytes). With `color`, the
// foreground escape is emitted only when the colour changes.
i32 render_frame(u8* out, f64 cx, f64 cy, f64 width, i32 max_iter, bool color) {
    f64 height = width * g_rows / g_cols * 2.0;   // cells are ~2x taller than wide
    f64 x0 = cx - width  * 0.5;
    f64 y0 = cy - height * 0.5;
    f64 dx = width  / g_cols;
    f64 dy = height / g_rows;
    i32 idx = 0;
    i32 last_color = 0 - 1;
    const i32 pal_len = cast(i32, PAL.len);
    for i32 ry = 0; ry < g_rows; ry++ {
        f64 py = y0 + ry * dy;
        for i32 rx = 0; rx < g_cols; rx++ {
            f64 px = x0 + rx * dx;
            f64 nu = mandel_iter(px, py, max_iter);
            // glyph from the integer part of nu
            i32 it_q = cast(i32, nu);
            if it_q < 0 { it_q = 0; }
            if it_q > max_iter { it_q = max_iter; }
            i32 pi = it_q * pal_len / max_iter;
            if pi >= pal_len { pi = pal_len - 1; }
            if color {
                i32 c = nu_to_color(nu, max_iter);
                if c != last_color {
                    idx = emit_fg256(out, idx, c);
                    last_color = c;
                }
            }
            out[idx] = PAL.data[pi];
            idx++;
        }
        out[idx] = '\n';
        idx++;
    }
    if color {
        idx = buf_append(out, idx, "\x1b[0m");
    }
    return idx;
}

// ----- Main animation loop --------------------------------------------------

// zoom target
const f64 TARGET_CX = -0.7756838;
const f64 TARGET_CY = 0.1364674;
const f64 ZOOM_PER_FRAME = 0.985;     // ~46 frames per 2× zoom
const i32 N_FRAMES = 480;             // ~16s at 30fps

// Refresh the grid from the host terminal. Zero fields keep their
// current value (wasm-supplied size, or the defaults). One row is
// reserved for the trailing newline so the frame does not scroll.
void detect_term_size() {
    TermSize sz = term_size();
    if sz.cols > 0 { g_cols = sz.cols; }
    if sz.rows > 0 { g_rows = sz.rows - 1; }
    if g_cols < 40 { g_cols = 40; }
    if g_rows < 16 { g_rows = 16; }
    // 12 B/cell + per-row newline + reset epilogue + slack.
    g_buf_len = g_cols * g_rows * 12 + g_rows * 4 + 64;
}

// Signal handler: restore cursor and colour, exit. write() is
// signal-safe; print() is not.
when os(macos) || os(ios) || os(linux) || os(android) {
    void on_term_signal(i32 sig) {
        write(stdout(), "\x1b[0m\x1b[?25h\n", 11);
        exit(128 + sig);
    }
}

when os(wasm) {
    // Called by the playground with its panel size before main().
    export i32 set_term_size(i32 cols, i32 rows) {
        if cols > 0 { g_cols = cols; }
        if rows > 0 { g_rows = rows; }
        return 0;
    }

    // One frame per call; returns 1 when done.
    export i32 frame() {
        if g_wasm_f >= N_FRAMES {
            return 1;
        }
        i32 max_iter = 80 + g_wasm_f * 2;
        i32 idx = buf_append(g_wasm_buf, 0, "\x1b[H");
        i32 cells = render_frame(g_wasm_buf + idx, TARGET_CX, TARGET_CY, g_wasm_width, max_iter, true);
        idx = idx + cells;
        // reset fg for the next frame
        idx = buf_append(g_wasm_buf, idx, "\x1b[0m");
        write(stdout(), g_wasm_buf, idx);
        g_wasm_width = g_wasm_width * ZOOM_PER_FRAME;
        g_wasm_f = g_wasm_f + 1;
        return 0;
    }
}

i32 main() {
    // No-op outside legacy Windows cmd.
    term_enable_vt();

    // Size the frame buffer from the terminal; a large window needs
    // over 100 KB.
    detect_term_size();

    // Heap: the wasm stack is 64 KB.
    u8* frame_buf = alloc<u8>(g_buf_len);

    when os(wasm) {
        // hand off to frame()
        g_wasm_buf = frame_buf;
        g_wasm_width = 4.0;
        g_wasm_f = 0;
        print("\x1b[2J\x1b[H");
        return 0;
    }
    else {
        defer free(frame_buf);

        // Hide the cursor; defer restores it on return, the signal
        // handler on Ctrl-C.
        when os(macos) || os(ios) || os(linux) || os(android) {
            signal(2,  cast(void*, &on_term_signal));   // SIGINT
            signal(15, cast(void*, &on_term_signal));   // SIGTERM
        }
        print("\x1b[?25l\x1b[2J\x1b[H");
        defer print("\x1b[0m\x1b[?25h\n");

        const f64 START_WIDTH = 4.0;
        f64 width = START_WIDTH;
        i64 freq = qpf();
        i64 frame_target_us = 33333;    // ~30 fps

        for i32 f = 0; f < N_FRAMES; f++ {
            i64 frame_start = qpc();

            // more iterations as the zoom deepens
            i32 max_iter = 80 + f * 2;

            // One write per frame, wrapped in DEC 2026 synchronized
            // output; terminals without it ignore the escape.
            i32 idx = buf_append(frame_buf, 0, "\x1b[?2026h\x1b[H");
            i32 cells = render_frame(frame_buf + idx, TARGET_CX, TARGET_CY, width, max_iter, true);
            idx = idx + cells;
            idx = buf_append(frame_buf, idx, "\x1b[?2026l");
            write(stdout(), frame_buf, idx);

            width = width * ZOOM_PER_FRAME;

            // Pace to the frame budget.
            i64 elapsed = qpc() - frame_start;
            i64 elapsed_us = elapsed * 1000000 / freq;
            i64 sleep_us = frame_target_us - elapsed_us;
            i32 sleep_ms = cast(i32, sleep_us / 1000);
            if sleep_ms > 0 {
                thread_sleep(sleep_ms);
            }
        }
        return 0;
    }
}
