// mandelbrot.mc — animated Mandelbrot zoom in the terminal.
//
// Targets: macOS, Linux, Windows 10+, WASM (driven by the
// playground's frame() loop).
//
// Native run exits after ~16s or on Ctrl-C. WASM stops after
// N_FRAMES — the playground's frame() loop ends.

@utf8_console

import math;
import terminal;
import thread;

// SIGINT/SIGTERM handler 
// Used to restore cursor + colour on ctrl+C.
when os(macos) || os(ios) {
    extern "libSystem.B.dylib" void* signal(i32 sig, void* handler);
}
when os(linux) || os(android) {
    extern "libc.so.6" void* signal(i32 sig, void* handler);
}

// ----- Mandelbrot kernel ----------------------------------------------------

// Smooth iteration count: integer escape iter plus a fractional
// refinement from the final |z|. Cells that share an integer iter
// land on distinct nu, so colour gradients don't band.
//
//   nu = i + 1 - log2(log2(|z|))
//
// One log2 per escaped cell, none for interior. Returns max_iter
// (widened to f64) when the point doesn't escape.
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

// Frame grid: g_cols × g_rows cells, one byte each, '\n' per row.
// render_frame's 2× height factor compensates for terminal cells
// being about twice as tall as wide. detect_term_size() refreshes
// from the host; defaults stand on wasm and on pipe-failure.
i32 g_cols = 80;
i32 g_rows = 32;
// Worst-case 256-color frame: 11 bytes ANSI fg + 1 char = 12 per
// cell. detect_term_size() rescales to the detected dimensions.
i32 g_buf_len = 32768;

// WASM animation state. main() seeds these; frame() (below) is
// driven from JS via requestAnimationFrame.
u8* g_wasm_buf   = null;
f64 g_wasm_width = 4.0;
i32 g_wasm_f     = 0;

// Glyph palette (length via PAL.len — single source of truth)
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

// Compress the smooth-iter axis so the bright end of the palette
// covers boundary cells (nu ≈ max_iter / SHIFT) instead of only
// the deep interior.
const i32 SHIFT = 4;

i32 nu_to_color(f64 nu, i32 max_iter) {
    f64 ci_f = nu * (SHIFT * NCOLOR) / max_iter;
    i32 ci = cast(i32, ci_f);
    if ci < 0 { ci = 0; }
    if ci >= NCOLOR { ci = NCOLOR - 1; }
    return COLOR_PAL[ci];
}

// Copy src into buf at idx; return new idx. Lets the prologue and
// epilogue escapes ride along with the cells in one write — two
// writes per frame flickers the Windows console.
i32 buf_append(u8* buf, i32 idx, str src) {
    i32 n = cast(i32, src.len);
    for i32 i = 0; i < n; i = i + 1 {
        buf[idx + i] = src.data[i];
    }
    return idx + n;
}

// Append `\x1b[38;5;Nm` (set 256-color foreground). Emits 1-3
// decimal digits so single-digit indices don't pad the frame.
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

// Render one frame at the given viewport. `out` must be >=
// g_buf_len bytes. `color`: emit ANSI fg-256 before each cell,
// run-length encoded (only on change).
i32 render_frame(u8* out, f64 cx, f64 cy, f64 width, i32 max_iter, bool color) {
    f64 height = width * g_rows / g_cols * 2.0;
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
            // Glyph: clamp + quantize the integer part of nu.
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

// Centre viewport from frame 0.
const f64 TARGET_CX = -0.7756838;
const f64 TARGET_CY = 0.1364674;
const f64 ZOOM_PER_FRAME = 0.985;     // ~46 frames per 2× zoom
const i32 N_FRAMES = 480;             // ~16s at 30fps

// Refresh g_cols / g_rows / g_buf_len from the host terminal. Zero
// fields are left untouched so wasm's JS-supplied dimensions and
// pipe-failure defaults both survive. The -1 on rows leaves room for
// the trailing newline so the frame doesn't scroll each paint. Floors
// of 40×16 keep the demo readable in tiny windows.
void detect_term_size() {
    TermSize sz = term_size();
    if sz.cols > 0 { g_cols = sz.cols; }
    if sz.rows > 0 { g_rows = sz.rows - 1; }
    if g_cols < 40 { g_cols = 40; }
    if g_rows < 16 { g_rows = 16; }
    // 12 B/cell + per-row newline + reset epilogue + slack.
    g_buf_len = g_cols * g_rows * 12 + g_rows * 4 + 64;
}

// Async-signal-safe handler — restores cursor + colour, exits.
// write() and exit() are signal-safe; print() is not.
when os(macos) || os(ios) || os(linux) || os(android) {
    void on_term_signal(i32 sig) {
        write(stdout(), "\x1b[0m\x1b[?25h\n", 11);
        exit(128 + sig);
    }
}

when os(wasm) {
    // Seed terminal dimensions before main runs. The playground
    // measures its output panel and calls this; detect_term_size's
    // wasm path is a no-op, so the values survive.
    export i32 set_term_size(i32 cols, i32 rows) {
        if cols > 0 { g_cols = cols; }
        if rows > 0 { g_rows = rows; }
        return 0;
    }

    // One frame per call. The playground rAFs this; returns 1
    // after N_FRAMES so the rAF loop stops.
    export i32 frame() {
        if g_wasm_f >= N_FRAMES {
            return 1;
        }
        i32 max_iter = 80 + g_wasm_f * 2;
        i32 idx = buf_append(g_wasm_buf, 0, "\x1b[H");
        i32 cells = render_frame(g_wasm_buf + idx, TARGET_CX, TARGET_CY, g_wasm_width, max_iter, true);
        idx = idx + cells;
        // Reset fg so the next frame's first cell paints in a known state.
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

    // Read the terminal size before allocating the frame buffer —
    // a maximised window can want >100 KB.
    detect_term_size();

    // Heap-allocated: WASM's linear-memory stack is only 64 KB.
    u8* frame_buf = alloc<u8>(g_buf_len);

    when os(wasm) {
        // Stash state for frame() and hand back to JS.
        g_wasm_buf = frame_buf;
        g_wasm_width = 4.0;
        g_wasm_f = 0;
        print("\x1b[2J\x1b[H");
        return 0;
    }
    else {
        // WASM linear memory is reclaimed when the page tears down.
        // free for all native platforms, would be reclaimed on exit.
        defer free(frame_buf);

        // Hide the cursor for the run. defer restores on normal return;
        // the signal handler covers Ctrl+C.
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

            // More iter as the view shrinks: boundary detail keeps up
            // with the geometric zoom.
            i32 max_iter = 80 + f * 2;

            // One write per frame: [sync-begin][home][cells][sync-end].
            // DEC ?2026 lets supporting terminals (Windows Terminal,
            // iTerm2, kitty, ghostty) present the frame atomically;
            // others ignore the CSI.
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
