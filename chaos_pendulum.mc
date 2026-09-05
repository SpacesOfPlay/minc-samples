// chaos_pendulum.mc — triple pendulum stepped by three kernels:
//
//   strict     @strict_float: Same bits on x64, arm64 and wasm.
//
//   canonical  plain code: fused multiply-add where the target has it.
//              Same bits on x64 and arm64. wasm has no FMA and differs.
//
//   divergent  one target-defined op in the solve, a reciprocal
//              square-root estimate. The bits differ between targets,
//              and on x64 between CPU vendors.
//
// The system is chaotic, a one-ulp difference grows to a visibly
// different swing within seconds. 
// 
// At 10 s the state hashes are validated against pins.
//
// Keys: SPACE restart, P pause, H hide the text.
//

import sokol_all;
import sokol_gl;
import sokol_debugtext_font;
import math;
import str;
import ext_libc;


// Equations of motion for n rigid links with point masses:
//
//   sum_j c_ij cos(th_i - th_j) a_j
//     = -sum_j c_ij sin(th_i - th_j) om_j^2 - g L_i M_i sin th_i
//   c_ij = M_max(i,j) L_i L_j,  M_k = sum of masses from link k down.
//

const f64 SIM_DT = 0.001;
const i32 PIN_STEPS = 10000;     // 10 s of sim time
const f64 GRAV = 9.81;

f64[3] PEND_LEN  = { 0.3, 0.27, 0.24 };   // metres
f64[3] PEND_MASS = { 1.0, 0.8, 0.6 };
f64[3] PEND_MSUM = { 2.4, 1.4, 0.6 };     // mass from link k down

struct PendState {
    f64[3] th;   // angle from the vertical, per link
    f64[3] om;   // angular velocity
}

// Pinned state hashes after PIN_STEPS.
const u64 PIN_STRICT    = 0x30aa32ff1c860cad;
const u64 PIN_CANONICAL = 0x21f197988839feac;

// All three pendulums start at rest, every link raised 135 degrees
// from the vertical.
void pend_reset(PendState* s) {
    for i32 i = 0; i < 3; i++ {
        s.th[i] = 2.356194490192345;
        s.om[i] = 0.0;
    }
}

// ---- strict ----------------------------------------------------------

@strict_float
void pend_accel_strict(f64* th, f64* om, f64* out) {
    f64[9] a;
    f64[3] b;
    for i32 i = 0; i < 3; i++ {
        f64 r = -GRAV * PEND_LEN[i] * PEND_MSUM[i] * sin(th[i]);
        for i32 j = 0; j < 3; j++ {
            i32 m = i;
            if j > i { m = j; }
            f64 c = PEND_MSUM[m] * PEND_LEN[i] * PEND_LEN[j];
            f64 d = th[i] - th[j];
            a[i * 3 + j] = c * cos(d);
            r = r - c * sin(d) * om[j] * om[j];
        }
        b[i] = r;
    }
    f64 c00 = a[4] * a[8] - a[5] * a[7];
    f64 c01 = a[3] * a[8] - a[5] * a[6];
    f64 c02 = a[3] * a[7] - a[4] * a[6];
    f64 det = a[0] * c00 - a[1] * c01 + a[2] * c02;
    f64 inv = 1.0 / det;
    out[0] = (b[0] * c00 - a[1] * (b[1] * a[8] - a[5] * b[2]) + a[2] * (b[1] * a[7] - a[4] * b[2])) * inv;
    out[1] = (a[0] * (b[1] * a[8] - a[5] * b[2]) - b[0] * c01 + a[2] * (a[3] * b[2] - b[1] * a[6])) * inv;
    out[2] = (a[0] * (a[4] * b[2] - b[1] * a[7]) - a[1] * (a[3] * b[2] - b[1] * a[6]) + b[0] * c02) * inv;
}

@strict_float
void pend_step_strict(PendState* s) {
    f64[3] k1; f64[3] k2; f64[3] k3; f64[3] k4;
    f64[3] t;  f64[3] o1; f64[3] o2; f64[3] o3;
    f64 h = SIM_DT;
    f64 h2 = SIM_DT * 0.5;
    f64 h6 = SIM_DT / 6.0;
    pend_accel_strict(&s.th[0], &s.om[0], &k1[0]);
    for i32 i = 0; i < 3; i++ { t[i] = s.th[i] + h2 * s.om[i]; o1[i] = s.om[i] + h2 * k1[i]; }
    pend_accel_strict(&t[0], &o1[0], &k2[0]);
    for i32 i = 0; i < 3; i++ { t[i] = s.th[i] + h2 * o1[i]; o2[i] = s.om[i] + h2 * k2[i]; }
    pend_accel_strict(&t[0], &o2[0], &k3[0]);
    for i32 i = 0; i < 3; i++ { t[i] = s.th[i] + h * o2[i]; o3[i] = s.om[i] + h * k3[i]; }
    pend_accel_strict(&t[0], &o3[0], &k4[0]);
    for i32 i = 0; i < 3; i++ {
        s.th[i] = s.th[i] + h6 * (s.om[i] + 2.0 * o1[i] + 2.0 * o2[i] + o3[i]);
        s.om[i] = s.om[i] + h6 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i]);
    }
}

// ---- canonical: the strict pair without the annotation ---------------

void pend_accel_canonical(f64* th, f64* om, f64* out) {
    f64[9] a;
    f64[3] b;
    for i32 i = 0; i < 3; i++ {
        f64 r = -GRAV * PEND_LEN[i] * PEND_MSUM[i] * sin(th[i]);
        for i32 j = 0; j < 3; j++ {
            i32 m = i;
            if j > i { m = j; }
            f64 c = PEND_MSUM[m] * PEND_LEN[i] * PEND_LEN[j];
            f64 d = th[i] - th[j];
            a[i * 3 + j] = c * cos(d);
            r = r - c * sin(d) * om[j] * om[j];
        }
        b[i] = r;
    }
    f64 c00 = a[4] * a[8] - a[5] * a[7];
    f64 c01 = a[3] * a[8] - a[5] * a[6];
    f64 c02 = a[3] * a[7] - a[4] * a[6];
    f64 det = a[0] * c00 - a[1] * c01 + a[2] * c02;
    f64 inv = 1.0 / det;
    out[0] = (b[0] * c00 - a[1] * (b[1] * a[8] - a[5] * b[2]) + a[2] * (b[1] * a[7] - a[4] * b[2])) * inv;
    out[1] = (a[0] * (b[1] * a[8] - a[5] * b[2]) - b[0] * c01 + a[2] * (a[3] * b[2] - b[1] * a[6])) * inv;
    out[2] = (a[0] * (a[4] * b[2] - b[1] * a[7]) - a[1] * (a[3] * b[2] - b[1] * a[6]) + b[0] * c02) * inv;
}

void pend_step_canonical(PendState* s) {
    f64[3] k1; f64[3] k2; f64[3] k3; f64[3] k4;
    f64[3] t;  f64[3] o1; f64[3] o2; f64[3] o3;
    f64 h = SIM_DT;
    f64 h2 = SIM_DT * 0.5;
    f64 h6 = SIM_DT / 6.0;
    pend_accel_canonical(&s.th[0], &s.om[0], &k1[0]);
    for i32 i = 0; i < 3; i++ { t[i] = s.th[i] + h2 * s.om[i]; o1[i] = s.om[i] + h2 * k1[i]; }
    pend_accel_canonical(&t[0], &o1[0], &k2[0]);
    for i32 i = 0; i < 3; i++ { t[i] = s.th[i] + h2 * o1[i]; o2[i] = s.om[i] + h2 * k2[i]; }
    pend_accel_canonical(&t[0], &o2[0], &k3[0]);
    for i32 i = 0; i < 3; i++ { t[i] = s.th[i] + h * o2[i]; o3[i] = s.om[i] + h * k3[i]; }
    pend_accel_canonical(&t[0], &o3[0], &k4[0]);
    for i32 i = 0; i < 3; i++ {
        s.th[i] = s.th[i] + h6 * (s.om[i] + 2.0 * o1[i] + 2.0 * o2[i] + o3[i]);
        s.om[i] = s.om[i] + h6 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i]);
    }
}

// ---- divergent: canonical with an estimated 1/det --------------------

// The mass matrix is positive definite, so det > 0 and 1/det is the
// square of its reciprocal square root. rsqrt4_fast is a hardware
// estimate: x64 vrsqrtps, arm64 FRSQRTE, exact on wasm.
f64 pend_inv_estimate(f64 det) {
    float4 r = rsqrt4_fast(splat4(cast(f32, det)));
    f64 q = cast(f64, r.x);
    return q * q;
}

void pend_accel_divergent(f64* th, f64* om, f64* out) {
    f64[9] a;
    f64[3] b;
    for i32 i = 0; i < 3; i++ {
        f64 r = -GRAV * PEND_LEN[i] * PEND_MSUM[i] * sin(th[i]);
        for i32 j = 0; j < 3; j++ {
            i32 m = i;
            if j > i { m = j; }
            f64 c = PEND_MSUM[m] * PEND_LEN[i] * PEND_LEN[j];
            f64 d = th[i] - th[j];
            a[i * 3 + j] = c * cos(d);
            r = r - c * sin(d) * om[j] * om[j];
        }
        b[i] = r;
    }
    f64 c00 = a[4] * a[8] - a[5] * a[7];
    f64 c01 = a[3] * a[8] - a[5] * a[6];
    f64 c02 = a[3] * a[7] - a[4] * a[6];
    f64 det = a[0] * c00 - a[1] * c01 + a[2] * c02;
    f64 inv = pend_inv_estimate(det);
    out[0] = (b[0] * c00 - a[1] * (b[1] * a[8] - a[5] * b[2]) + a[2] * (b[1] * a[7] - a[4] * b[2])) * inv;
    out[1] = (a[0] * (b[1] * a[8] - a[5] * b[2]) - b[0] * c01 + a[2] * (a[3] * b[2] - b[1] * a[6])) * inv;
    out[2] = (a[0] * (a[4] * b[2] - b[1] * a[7]) - a[1] * (a[3] * b[2] - b[1] * a[6]) + b[0] * c02) * inv;
}

void pend_step_divergent(PendState* s) {
    f64[3] k1; f64[3] k2; f64[3] k3; f64[3] k4;
    f64[3] t;  f64[3] o1; f64[3] o2; f64[3] o3;
    f64 h = SIM_DT;
    f64 h2 = SIM_DT * 0.5;
    f64 h6 = SIM_DT / 6.0;
    pend_accel_divergent(&s.th[0], &s.om[0], &k1[0]);
    for i32 i = 0; i < 3; i++ { t[i] = s.th[i] + h2 * s.om[i]; o1[i] = s.om[i] + h2 * k1[i]; }
    pend_accel_divergent(&t[0], &o1[0], &k2[0]);
    for i32 i = 0; i < 3; i++ { t[i] = s.th[i] + h2 * o1[i]; o2[i] = s.om[i] + h2 * k2[i]; }
    pend_accel_divergent(&t[0], &o2[0], &k3[0]);
    for i32 i = 0; i < 3; i++ { t[i] = s.th[i] + h * o2[i]; o3[i] = s.om[i] + h * k3[i]; }
    pend_accel_divergent(&t[0], &o3[0], &k4[0]);
    for i32 i = 0; i < 3; i++ {
        s.th[i] = s.th[i] + h6 * (s.om[i] + 2.0 * o1[i] + 2.0 * o2[i] + o3[i]);
        s.om[i] = s.om[i] + h6 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i]);
    }
}

// ---- state hash ------------------------------------------------------

u64 pend_bits(f64 v) { return *cast(u64*, &v); }

// Splitmix finalizer per entry, then an FNV multiply. A plain FNV
// multiply never diffuses the sign bit downward, so an even number of
// sign-only differences would cancel.
u64 pend_mix(u64 h, u64 b) {
    b = (b ^ (b >> 33)) * 0xff51afd7ed558ccd;
    b = (b ^ (b >> 33)) * 0xc4ceb9fe1a85ec53;
    b = b ^ (b >> 33);
    h = (h ^ b) * 0x100000001b3;
    return h ^ (h >> 29);
}

u64 pend_hash(PendState* s) {
    u64 h = 0xcbf29ce484222325;
    for i32 i = 0; i < 3; i++ { h = pend_mix(h, pend_bits(s.th[i])); }
    for i32 i = 0; i < 3; i++ { h = pend_mix(h, pend_bits(s.om[i])); }
    return h;
}

// Position of the last bob, in metres, y down.
void pend_tip(PendState* s, f64* x, f64* y) {
    f64 px = 0.0;
    f64 py = 0.0;
    for i32 i = 0; i < 3; i++ {
        px = px + PEND_LEN[i] * sin(s.th[i]);
        py = py + PEND_LEN[i] * cos(s.th[i]);
    }
    *x = px;
    *y = py;
}


// ---- palette ---------------------------------------------------------

const float3 COL_BLACK        = float3{0.071f, 0.012f, 0.239f};
const float3 COL_WHITE        = float3{1.0f, 1.0f, 1.0f};
const float3 COL_RED          = float3{0.898f, 0.141f, 0.188f};
const float3 COL_CYAN         = float3{0.341f, 0.796f, 0.949f};
const float3 COL_VIOLET       = float3{0.447f, 0.314f, 0.722f};
const float3 COL_DARK_BLUE    = float3{0.231f, 0.082f, 0.663f};
const float3 COL_ORANGE       = float3{0.925f, 0.314f, 0.180f};
const float3 COL_BLUE_LIGHT   = float3{0.529f, 0.576f, 1.0f};
const float3 COL_GREEN        = float3{0.251f, 0.741f, 0.388f};
const float3 COL_GREEN_BRIGHT = float3{0.267f, 0.890f, 0.757f};

// ---- layout, on a virtual 640x360 canvas ------------------------------

const f32 REACH_MAX_HUD = 126.0f;
const f32 REACH_MAX_BIG = 170.0f;
const f32 FLOOR_Y = 350.0f;

const f32 CHART_X = 448.0f;
const f32 CHART_Y = 236.0f;
const f32 CHART_W = 180.0f;
const f32 CHART_H = 104.0f;

// ---- simulation state ------------------------------------------------

const i32 KERNELS = 3;
const f64 PLAYBACK = 0.5;        // sim seconds per wall-clock second
PendState[3] g_s;
i32 g_step = 0;
f64 g_acc = 0.0;                 // wall-clock seconds not yet stepped
bool g_paused = false;
bool g_done = false;
f64 g_done_t = 0.0;              // seconds since the pin step
bool g_show_hud = true;
bool g_pin_ok_strict = false;
bool g_pin_ok_canon = false;

// Tip trails, one point every TRAIL_EVERY steps.
const i32 TRAIL_N = 512;
const i32 TRAIL_EVERY = 4;
f32[3 * TRAIL_N] g_trail_x;
f32[3 * TRAIL_N] g_trail_y;
i32[3] g_trail_head;
i32[3] g_trail_cnt;

// Tip distance from the strict pendulum for kernels 2 and 3, sampled
// every SER_EVERY steps for the chart.
const i32 SER_N = 200;
const i32 SER_EVERY = 50;        // SER_N * SER_EVERY == PIN_STEPS
const f64 SPLIT_DIST = 0.01;     // metres, ~1% of the reach
f32[2 * SER_N] g_ser;
i32 g_ser_cnt = 0;
f64[2] g_dist;
f64[2] g_split_t;

sg_pass_action g_pass_action;
f32 g_tsx = 1.0f;                // virtual -> device pixel scale
f32 g_tsy = 1.0f;

void step_kernel(i32 k) {
    if k == 0 { pend_step_strict(&g_s[0]); }
    else if k == 1 { pend_step_canonical(&g_s[1]); }
    else { pend_step_divergent(&g_s[2]); }
}

void trail_push(i32 k) {
    f64 x = 0.0;
    f64 y = 0.0;
    pend_tip(&g_s[k], &x, &y);
    i32 h = g_trail_head[k];
    g_trail_x[k * TRAIL_N + h] = cast(f32, x);
    g_trail_y[k * TRAIL_N + h] = cast(f32, y);
    g_trail_head[k] = (h + 1) % TRAIL_N;
    if g_trail_cnt[k] < TRAIL_N { g_trail_cnt[k]++; }
}

void measure() {
    f64 ax = 0.0;
    f64 ay = 0.0;
    pend_tip(&g_s[0], &ax, &ay);
    for i32 k = 1; k < KERNELS; k++ {
        f64 bx = 0.0;
        f64 by = 0.0;
        pend_tip(&g_s[k], &bx, &by);
        f64 dx = bx - ax;
        f64 dy = by - ay;
        g_dist[k - 1] = sqrt(dx * dx + dy * dy);
        if g_split_t[k - 1] < 0.0 && g_dist[k - 1] > SPLIT_DIST {
            g_split_t[k - 1] = g_step * SIM_DT;
        }
    }
}

void reset() {
    for i32 k = 0; k < KERNELS; k++ {
        pend_reset(&g_s[k]);
        g_trail_head[k] = 0;
        g_trail_cnt[k] = 0;
    }
    g_step = 0;
    g_acc = 0.0;
    g_done = false;
    g_done_t = 0.0;
    g_ser_cnt = 0;
    for i32 i = 0; i < 2; i++ { g_dist[i] = 0.0; g_split_t[i] = -1.0; }
}

void advance(f64 dt) {
    g_acc += dt;
    i32 n = cast(i32, g_acc / SIM_DT);
    if n > 60 { n = 60; }                   // after a stall, catch up gradually
    g_acc -= n * SIM_DT;
    for i32 s = 0; s < n && g_step < PIN_STEPS; s++ {
        for i32 k = 0; k < KERNELS; k++ { step_kernel(k); }
        g_step++;
        if g_step % TRAIL_EVERY == 0 {
            for i32 k = 0; k < KERNELS; k++ { trail_push(k); }
        }
        if g_step % SER_EVERY == 0 && g_ser_cnt < SER_N {
            measure();
            g_ser[g_ser_cnt] = cast(f32, g_dist[0]);
            g_ser[SER_N + g_ser_cnt] = cast(f32, g_dist[1]);
            g_ser_cnt++;
        }
    }
    if g_step >= PIN_STEPS && !g_done {
        g_done = true;
        g_pin_ok_strict = pend_hash(&g_s[0]) == PIN_STRICT;
        g_pin_ok_canon = pend_hash(&g_s[1]) == PIN_CANONICAL;
    }
}

// ---- events ----------------------------------------------------------

void on_event(sapp_event* ev) {
    if ev.type == SAPP_EVENTTYPE_KEY_DOWN && !ev.key_repeat {
        if ev.key_code == SAPP_KEYCODE_SPACE { reset(); }
        if ev.key_code == SAPP_KEYCODE_P && !g_done { g_paused = !g_paused; }
        if ev.key_code == SAPP_KEYCODE_H { g_show_hud = !g_show_hud; }
    }
    if ev.type == SAPP_EVENTTYPE_MOUSE_DOWN { reset(); }
    if ev.type == SAPP_EVENTTYPE_TOUCHES_BEGAN { reset(); }
}

// ---- drawing ---------------------------------------------------------

f32 tpx(f32 v) { return floorf(v * g_tsx + 0.5f); }
f32 tpy(f32 v) { return floorf(v * g_tsy + 0.5f); }

void sgl_color(float3 c) { sgl_c3f(c.r, c.g, c.b); }

void draw_rect(f32 x, f32 y, f32 w, f32 h, float3 c) {
    sgl_begin_quads();
    sgl_color(c);
    sgl_v2f(x, y);
    sgl_v2f(x + w, y);
    sgl_v2f(x + w, y + h);
    sgl_v2f(x, y + h);
    sgl_end();
}

// sokol_debugtext_font renders glyphs through this form.
void draw_rect(f32 x, f32 y, f32 w, f32 h, f32 r, f32 g, f32 b) {
    draw_rect(x, y, w, h, float3{r, g, b});
}

void text_at(f32 x, f32 y, f32 scale, u8* text, float3 color) {
    draw_text(x, y, scale, text, color.r, color.g, color.b);
}

// A rod as a quad of half-width hw.
void draw_rod(f32 x0, f32 y0, f32 x1, f32 y1, f32 hw, float3 c) {
    f32 dx = x1 - x0;
    f32 dy = y1 - y0;
    f32 len = sqrtf(dx * dx + dy * dy);
    if len < 0.0001f { return; }
    f32 nx = -dy / len * hw;
    f32 ny = dx / len * hw;
    sgl_begin_quads();
    sgl_color(c);
    sgl_v2f(x0 + nx, y0 + ny);
    sgl_v2f(x1 + nx, y1 + ny);
    sgl_v2f(x1 - nx, y1 - ny);
    sgl_v2f(x0 - nx, y0 - ny);
    sgl_end();
}

void draw_disc(f32 cx, f32 cy, f32 r, float3 c) {
    const i32 SEG = 20;
    sgl_begin_triangles();
    sgl_color(c);
    for i32 i = 0; i < SEG; i++ {
        f32 a0 = cast(f32, i) * (6.2831853f / cast(f32, SEG));
        f32 a1 = cast(f32, i + 1) * (6.2831853f / cast(f32, SEG));
        sgl_v2f(cx, cy);
        sgl_v2f(cx + r * cosf(a0), cy + r * sinf(a0));
        sgl_v2f(cx + r * cosf(a1), cy + r * sinf(a1));
    }
    sgl_end();
}

float3 kernel_color(i32 k) {
    if k == 0 { return COL_GREEN; }
    if k == 1 { return COL_CYAN; }
    return COL_ORANGE;
}

// Rod half-width and bob radius per kernel, widest at the bottom of
// the stack.
f32 rod_hw(i32 k) { if k == 0 { return 0.6f; } if k == 1 { return 1.3f; } return 2.0f; }
f32 bob_r(i32 k)  { if k == 0 { return 2.6f; } if k == 1 { return 4.0f; } return 5.5f; }

void draw_pendulum(i32 k, f32 px, f32 py, f32 lpx, f32 us) {
    PendState* s = &g_s[k];
    float3 c = kernel_color(k);
    f32 x = px;
    f32 y = py;
    for i32 i = 0; i < 3; i++ {
        f32 nx = x + cast(f32, PEND_LEN[i] * sin(s.th[i])) * lpx;
        f32 ny = y + cast(f32, PEND_LEN[i] * cos(s.th[i])) * lpx;
        draw_rod(x, y, nx, ny, rod_hw(k) * us, c);
        x = nx;
        y = ny;
    }
    x = px;
    y = py;
    for i32 i = 0; i < 3; i++ {
        x += cast(f32, PEND_LEN[i] * sin(s.th[i])) * lpx;
        y += cast(f32, PEND_LEN[i] * cos(s.th[i])) * lpx;
        draw_disc(x, y, bob_r(k) * us, c);
    }
}

// Trail as a line strip, faded toward the background with age.
void draw_trail(i32 k, f32 px, f32 py, f32 lpx) {
    i32 cnt = g_trail_cnt[k];
    if cnt < 2 { return; }
    float3 c = kernel_color(k);
    i32 start = (g_trail_head[k] - cnt + TRAIL_N) % TRAIL_N;
    sgl_begin_line_strip();
    for i32 i = 0; i < cnt; i++ {
        i32 idx = k * TRAIL_N + (start + i) % TRAIL_N;
        f32 age = cast(f32, i) / cast(f32, cnt);      // 0 oldest, 1 newest
        float3 col = COL_BLACK + (c - COL_BLACK) * (0.08f + 0.72f * age);
        sgl_v2f_c3f(px + g_trail_x[idx] * lpx, py + g_trail_y[idx] * lpx, col.r, col.g, col.b);
    }
    sgl_end();
}

// Chart: log10 tip distance from the strict pendulum over the run.
const f32 CH_LO = -16.0f;
const f32 CH_HI = 0.5f;
const f32 CH_PAD_L = 4.0f;
const f32 CH_PAD_T = 12.0f;
const f32 CH_PAD_B = 12.0f;
const f32 CH_LABEL_W = 36.0f;    // room for "1E-16"

f32 chart_y(f32 lg) {
    f32 gy = CHART_Y + CH_PAD_T;
    f32 gh = CHART_H - CH_PAD_T - CH_PAD_B;
    return gy + gh * (1.0f - (lg - CH_LO) / (CH_HI - CH_LO));
}
f32 chart_x(f32 t) {
    f32 gx = CHART_X + CH_PAD_L + CH_LABEL_W;
    f32 gw = CHART_W - CH_PAD_L - CH_LABEL_W - 6.0f;
    return gx + gw * t / 10.0f;
}

void draw_chart() {
    draw_rect(CHART_X, CHART_Y, CHART_W, CHART_H, COL_BLACK);
    sgl_begin_lines();
    sgl_color(COL_DARK_BLUE);
    for i32 e = -16; e <= 0; e += 4 {
        f32 y = chart_y(cast(f32, e));
        sgl_v2f(chart_x(0.0f), y);
        sgl_v2f(chart_x(10.0f), y);
    }
    sgl_color(COL_VIOLET);
    sgl_v2f(chart_x(10.0f), chart_y(CH_HI));
    sgl_v2f(chart_x(10.0f), chart_y(CH_LO));
    sgl_end();
    for i32 k = 0; k < 2; k++ {
        if g_ser_cnt < 2 { break; }
        sgl_begin_line_strip();
        sgl_color(kernel_color(k + 1));
        for i32 i = 0; i < g_ser_cnt; i++ {
            f64 d = g_ser[k * SER_N + i];
            f32 lg = CH_LO;
            if d > 0.0 { lg = cast(f32, log10(d)); }
            if lg < CH_LO { lg = CH_LO; }
            if lg > CH_HI { lg = CH_HI; }
            sgl_v2f(chart_x(cast(f32, i) * cast(f32, SER_EVERY) * cast(f32, SIM_DT)), chart_y(lg));
        }
        sgl_end();
    }
}

// ---- text helpers ----------------------------------------------------

// "1.2E-03" style, 7 chars; "0      " for zero.
void sci7(f64 d, u8* buf) {
    if d <= 0.0 {
        snprintf(buf, 8, "0      ");
        return;
    }
    i32 e = cast(i32, floor(log10(d)));
    f64 m = d / pow(10.0, e);
    i32 m10 = cast(i32, m * 10.0 + 0.5);
    if m10 >= 100 { m10 = 10; e++; }
    u8 sign = '+';
    if e < 0 { sign = '-'; e = -e; }
    buf[0] = cast(u8, '0' + m10 / 10);
    buf[1] = '.';
    buf[2] = cast(u8, '0' + m10 % 10);
    buf[3] = 'E';
    buf[4] = sign;
    buf[5] = cast(u8, '0' + e / 10);
    buf[6] = cast(u8, '0' + e % 10);
    buf[7] = 0;
}

// "06.34" style seconds.
void secs5(f64 t, u8* buf) {
    u32 c = cast(u32, t * 100.0 + 0.5);
    snprintf(buf, 6, "%02u.%02u", c / 100, c % 100);
}

void hud_row(i32 row, f32 tsf, u8* text, float3 c) {
    text_at(8.0f * tsf, (8.0f + cast(f32, row) * 10.0f) * tsf, tsf, text, c);
}

void hud_at(i32 col, i32 row, f32 tsf, u8* text, float3 c) {
    text_at((8.0f + cast(f32, col) * 8.0f) * tsf, (8.0f + cast(f32, row) * 10.0f) * tsf, tsf, text, c);
}

u8* target_name() {
    when os(wasm) { return "WASM"; }
    else when arch(arm64) { return "ARM64"; }
    else { return "X64"; }
}

void draw_hud(i32 w, i32 h, f32 tsf) {
    u8[96] line;
    u8[8] sc;
    u8[8] t1;
    u8[8] t2;

    hud_row(0, tsf, "CHAOS PENDULUM  3 LINKS  RK4 DT 0.001", COL_WHITE);
    secs5(g_step * SIM_DT, &t1[0]);
    snprintf(&line[0], cast(u64, sizeof(line)), "T %s/10.00 S   STEP %05u", &t1[0], cast(u32, g_step));
    hud_row(1, tsf, &line[0], COL_BLUE_LIGHT);

    // One row per kernel: hash, pin verdict, then the tip distance from
    // the strict pendulum and when it passed the visible threshold.
    hud_at(57, 2, tsf, "DIST VS 1", COL_BLUE_LIGHT);
    hud_at(67, 2, tsf, "SPLIT", COL_BLUE_LIGHT);
    snprintf(&line[0], cast(u64, sizeof(line)), "1 STRICT     %016llX", pend_hash(&g_s[0]));
    hud_row(3, tsf, &line[0], kernel_color(0));
    snprintf(&line[0], cast(u64, sizeof(line)), "2 CANONICAL  %016llX", pend_hash(&g_s[1]));
    hud_row(4, tsf, &line[0], kernel_color(1));
    snprintf(&line[0], cast(u64, sizeof(line)), "3 DIVERGENT  %016llX  NO PIN    TARGET-DEFINED", pend_hash(&g_s[2]));
    hud_row(5, tsf, &line[0], kernel_color(2));

    if g_done {
        if g_pin_ok_strict { hud_at(31, 3, tsf, "PIN OK    EVERYWHERE", COL_GREEN_BRIGHT); }
        else { hud_at(31, 3, tsf, "PIN BAD   EVERYWHERE", COL_RED); }
    } else {
        hud_at(31, 3, tsf, "PIN @10   EVERYWHERE", kernel_color(0));
    }
    when os(wasm) {
        hud_at(31, 4, tsf, "NO PIN    WASM: NO FMA", kernel_color(1));
    } else {
        if g_done {
            if g_pin_ok_canon { hud_at(31, 4, tsf, "PIN OK    NATIVE", COL_GREEN_BRIGHT); }
            else { hud_at(31, 4, tsf, "PIN BAD   NATIVE", COL_RED); }
        } else {
            hud_at(31, 4, tsf, "PIN @10   NATIVE", kernel_color(1));
        }
    }
    for i32 k = 0; k < 2; k++ {
        sci7(g_dist[k], &sc[0]);
        if g_split_t[k] < 0.0 { snprintf(&t2[0], 8, "--"); }
        else { secs5(g_split_t[k], &t2[0]); t2[5] = 'S'; t2[6] = 0; }
        hud_at(57, 4 + k, tsf, &sc[0], kernel_color(k + 1));
        hud_at(67, 4 + k, tsf, &t2[0], kernel_color(k + 1));
    }

    // footer
    i32 rows = h / (10 * cast(i32, tsf)) - 2;
    if g_done {
        f64 left = 3.0 - g_done_t;
        if left < 0.0 { left = 0.0; }
        secs5(left, &t1[0]);
        snprintf(&line[0], cast(u64, sizeof(line)), "RESTART IN %sS   SPACE NOW", &t1[0]);
        hud_row(rows, tsf, &line[0], COL_BLUE_LIGHT);
    } else if g_paused {
        hud_row(rows, tsf, "PAUSED  P RUN  SPACE RESTART  H HIDE TEXT", COL_BLUE_LIGHT);
    } else {
        hud_row(rows, tsf, "SPACE RESTART  P PAUSE  H HIDE TEXT", COL_BLUE_LIGHT);
    }
    snprintf(&line[0], cast(u64, sizeof(line)), "TARGET %s", target_name());
    i32 n = 0;
    while line[n] != 0 { n++; }
    text_at(cast(f32, w) - (8.0f + cast(f32, n) * 8.0f) * tsf, (8.0f + cast(f32, rows) * 10.0f) * tsf, tsf, &line[0], COL_BLUE_LIGHT);

    // chart labels
    for i32 e = -16; e <= 0; e += 4 {
        u8[8] lb;
        u8 sign = '-';
        i32 ae = -e;
        if e >= 0 { sign = '+'; ae = e; }
        snprintf(&lb[0], 8, "1E%c%02u", cast(i32, sign), cast(u32, ae));
        text_at(tpx(CHART_X + CH_PAD_L), tpy(chart_y(cast(f32, e))) - 4.0f * tsf, tsf, &lb[0], COL_BLUE_LIGHT);
    }
    text_at(tpx(chart_x(0.0f)), tpy(CHART_Y + 2.0f), tsf, "TIP DIST VS 1", COL_BLUE_LIGHT);
    text_at(tpx(chart_x(0.0f)), tpy(CHART_Y + CHART_H - 10.0f), tsf, "0S", COL_BLUE_LIGHT);
    text_at(tpx(chart_x(10.0f)) - 7.0f * 8.0f * tsf, tpy(CHART_Y + CHART_H - 10.0f), tsf, "PIN 10S", COL_BLUE_LIGHT);
}

void frame() {
    f64 dt = sapp_frame_duration();
    if dt > 0.1 { dt = 0.1; }
    if g_done {
        g_done_t += dt;
        if g_done_t > 3.0 { reset(); }
    } else if !g_paused {
        advance(dt * PLAYBACK);
    }
    measure();

    i32 w = sapp_width();
    i32 h = sapp_height();
    g_tsx = cast(f32, w) / 640.0f;
    g_tsy = cast(f32, h) / 360.0f;
    // Integer glyph scale, three quarters of the canvas scale: the
    // text block stays readable and leaves the pendulum most of the
    // height. 3 at 2560x1440, 2 at 1280x720.
    i32 ts = (w * 3 + 1280) / 2560;
    i32 tsh = (h * 3 + 720) / 1440;
    if tsh < ts { ts = tsh; }
    if ts < 1 { ts = 1; }
    f32 tsf = cast(f32, ts);

    // Pendulum in device pixels, one scale on both axes: the virtual canvas
    // stretches to the window and would draw the bobs as ellipses.
    f32 us = g_tsx;
    if g_tsy < us { us = g_tsy; }
    f32 top = 10.0f * g_tsy;
    f32 reach = REACH_MAX_BIG * us;
    if g_show_hud {
        top = (8.0f + 6.0f * 10.0f) * tsf + 6.0f * g_tsy;    // below the last text row
        reach = REACH_MAX_HUD * us;
    }
    f32 floor = FLOOR_Y * g_tsy;
    if (floor - top) * 0.5f < reach { reach = (floor - top) * 0.5f; }
    // Pivot centred in the band the text leaves.
    f32 px = cast(f32, w) * 0.5f;
    f32 py = (top + floor) * 0.5f;
    f32 lpx = reach / cast(f32, PEND_LEN[0] + PEND_LEN[1] + PEND_LEN[2]);

    sgl_defaults();
    sgl_viewport(0, 0, w, h, true);
    sgl_ortho(0.0f, cast(f32, w), cast(f32, h), 0.0f, -1.0f, 1.0f);

    draw_rect(px - 24.0f * us, py - 3.0f * us, 48.0f * us, 3.0f * us, COL_VIOLET);
    for i32 k = 0; k < KERNELS; k++ { draw_trail(k, px, py, lpx); }
    for i32 k = KERNELS - 1; k >= 0; k-- { draw_pendulum(k, px, py, lpx, us); }
    draw_disc(px, py, 2.0f * us, COL_BLACK);

    // chart, on the virtual canvas
    if g_show_hud {
        sgl_load_identity();
        sgl_ortho(0.0f, 640.0f, 360.0f, 0.0f, -1.0f, 1.0f);
        draw_chart();
    }

    // text, in device pixels
    sgl_load_identity();
    sgl_ortho(0.0f, cast(f32, w), cast(f32, h), 0.0f, -1.0f, 1.0f);
    if g_show_hud { draw_hud(w, h, tsf); }

    sg_begin_pass(&sg_pass{ .action = g_pass_action, .swapchain = sglue_swapchain() });
    sgl_draw();
    sg_end_pass();
    sg_commit();
}

// ---- headless check --------------------------------------------------

str hex_str(u64 v, u8* buf) {
    snprintf(buf, 17, "%016llx", v);
    return str_from_cstr(buf);
}

// Runs the three kernels to the pin step and prints the hashes in pin
// form. Returns 0 when every pin this target claims holds. To re-pin
// after a deliberate kernel change, paste the first two hashes into
// PIN_STRICT / PIN_CANONICAL above.
i32 run_check() {
    PendState a;
    PendState b;
    PendState c;
    pend_reset(&a);
    pend_reset(&b);
    pend_reset(&c);
    for i32 i = 0; i < PIN_STEPS; i++ {
        pend_step_strict(&a);
        pend_step_canonical(&b);
        pend_step_divergent(&c);
    }
    u64 ha = pend_hash(&a);
    u64 hb = pend_hash(&b);
    u64 hc = pend_hash(&c);

    print("chaos_pendulum check: {} steps, dt {}\n", PIN_STEPS, SIM_DT);
    i32 rc = 0;
    u8[18] hx;
    str va = "pin ok      every target";
    if ha != PIN_STRICT { va = "MISMATCH    every target"; rc = 1; }
    print("1 strict     0x{}  {}\n", hex_str(ha, &hx[0]), va);
    str vb = "pin ok      native";
    when os(wasm) {
        vb = "no pin      wasm computes mul+add where native fuses";
    } else {
        if hb != PIN_CANONICAL { vb = "MISMATCH    native"; rc = 2; }
    }
    print("2 canonical  0x{}  {}\n", hex_str(hb, &hx[0]), vb);
    print("3 divergent  0x{}  no pin      target-defined estimate\n", hex_str(hc, &hx[0]));
    print("strict final angles {} {} {}\n", a.th[0], a.th[1], a.th[2]);
    return rc;
}

// ---- lifecycle -------------------------------------------------------

void init() {
    sg_setup(&sg_desc{ .environment = sglue_environment(), .logger = sg_logger{ .func = slog_func } });
    sgl_setup(&sgl_desc_t{ .logger = sgl_logger_t{ .func = slog_func } });
    g_pass_action = sg_pass_action{
        .colors[0] = {
            .load_action = SG_LOADACTION_CLEAR,
            .clear_value = { COL_BLACK.r, COL_BLACK.g, COL_BLACK.b, 1.0f }
        },
    };
    reset();
}

void cleanup() {
    sgl_shutdown();
    sg_shutdown();
}

sapp_desc sokol_main() {
    when !os(wasm) {
        // headless check
        if get_argc() > 1 { exit(run_check()); }
    }
    sapp_desc d = {
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = on_event,
        .width = 1280,
        .height = 720,
        .high_dpi = true,
        .sample_count = 4,
        .window_title = "minc chaos pendulum"
    };
    return d;
}
