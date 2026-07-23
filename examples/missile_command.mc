// missile_command.mc — Missile Command clone, cross-platform sokol

import sokol_all;
import sokol_audio;
import math;
import linear;
import sokol_debugtext_font;
import "frame_timer.mc";

// ============================================================================
// Constants
// ============================================================================

// Game-space dimensions are f32 — used in pixel math throughout.
// Window/canvas size at sokol setup hardcodes 800/600 separately.
const f32 SCREEN_W = 800.0f;
const f32 SCREEN_H = 600.0f;
const i32 MAX_VERTS = 4096;
const i32 MAX_ENEMY = 24;
const i32 MAX_PLAYER = 12;
const i32 MAX_EXPLOSIONS = 24;
const i32 NUM_CITIES = 6;
const f32 CROSSHAIR_SPEED = 300.0f;
const f32 PLAYER_MISSILE_SPEED = 400.0f;
const f32 EXPLOSION_GROW_SPEED = 120.0f;
const f32 EXPLOSION_MAX_RADIUS = 40.0f;
const f32 GROUND_HEIGHT = 40.0f;
const f32 CITY_WIDTH = 30.0f;
const f32 CITY_HEIGHT = 20.0f;
const f32 BATTERY_RADIUS = 12.0f;

// CRT bloom — quarter-res bright-pass + iterated separable Gaussian blur.
const i32 BLOOM_W = 200;       // SCREEN_W / 4
const i32 BLOOM_H = 150;       // SCREEN_H / 4
const i32 BLOOM_ITERS = 6;     // ping-pong H/V pairs

// ============================================================================
// Shaders — simple 2D: ortho projection + vertex color
// ============================================================================

struct VsOut {
    float4 pos;
    float4 color;
}

@shader vertex
VsOut mc_vs(@attr(0) float4 position, @attr(1) float4 color, @uniform float4x4 mvp) {
    VsOut o;
    o.pos = mul(mvp, position);
    o.color = color;
    return o;
}

@shader fragment
float4 mc_fs(VsOut input) {
    return input.color;
}

// ============================================================================
// CRT post-process shaders, inspired by Mattias Gustavsson's CRT code
// ============================================================================

struct McBlitVsOut {
    float4 pos;
    float2 uv;
}

@shader vertex
McBlitVsOut mc_blit_vs(@attr(0) float2 position, @attr(1) float2 texcoord) {
    McBlitVsOut o;
    o.pos = float4{position.x, position.y, 0.0f, 1.0f};
    o.uv = texcoord;
    return o;
}

// ----- Bloom bright-pass -----
@shader fragment
float4 mc_bright_fs(McBlitVsOut input, @texture(0) Texture2D tex, @sampler(0) Sampler smp) {
    float4 c = sample(tex, smp, input.uv);
    f32 lum = c.x * 0.299f + c.y * 0.587f + c.z * 0.114f;
    f32 thresh = 0.22f;
    if lum < thresh { return float4{0.0f, 0.0f, 0.0f, 1.0f}; }
    f32 k = (lum - thresh) / (1.0f - thresh);
    return float4{c.x * k, c.y * k, c.z * k, 1.0f};
}

// ----- Bloom blur (gaussian, 9-tap) -----
@shader fragment
float4 mc_blur_h_fs(McBlitVsOut input, @texture(0) Texture2D tex, @sampler(0) Sampler smp) {
    f32 px = 1.0f / 200.0f;   // 1 / BLOOM_W
    f32 u = input.uv.x;
    f32 v = input.uv.y;
    float4 acc = sample(tex, smp, float2{u, v}) * 0.227f;
    acc = acc + sample(tex, smp, float2{u + px,        v}) * 0.194f;
    acc = acc + sample(tex, smp, float2{u - px,        v}) * 0.194f;
    acc = acc + sample(tex, smp, float2{u + px * 2.0f, v}) * 0.121f;
    acc = acc + sample(tex, smp, float2{u - px * 2.0f, v}) * 0.121f;
    acc = acc + sample(tex, smp, float2{u + px * 3.0f, v}) * 0.054f;
    acc = acc + sample(tex, smp, float2{u - px * 3.0f, v}) * 0.054f;
    acc = acc + sample(tex, smp, float2{u + px * 4.0f, v}) * 0.016f;
    acc = acc + sample(tex, smp, float2{u - px * 4.0f, v}) * 0.016f;
    return float4{acc.x, acc.y, acc.z, 1.0f};
}

@shader fragment
float4 mc_blur_v_fs(McBlitVsOut input, @texture(0) Texture2D tex, @sampler(0) Sampler smp) {
    f32 px = 1.0f / 150.0f;   // 1 / BLOOM_H
    f32 u = input.uv.x;
    f32 v = input.uv.y;
    float4 acc = sample(tex, smp, float2{u, v}) * 0.227f;
    acc = acc + sample(tex, smp, float2{u, v + px})        * 0.194f;
    acc = acc + sample(tex, smp, float2{u, v - px})        * 0.194f;
    acc = acc + sample(tex, smp, float2{u, v + px * 2.0f}) * 0.121f;
    acc = acc + sample(tex, smp, float2{u, v - px * 2.0f}) * 0.121f;
    acc = acc + sample(tex, smp, float2{u, v + px * 3.0f}) * 0.054f;
    acc = acc + sample(tex, smp, float2{u, v - px * 3.0f}) * 0.054f;
    acc = acc + sample(tex, smp, float2{u, v + px * 4.0f}) * 0.016f;
    acc = acc + sample(tex, smp, float2{u, v - px * 4.0f}) * 0.016f;
    return float4{acc.x, acc.y, acc.z, 1.0f};
}

@shader fragment
float4 mc_blit_fs(McBlitVsOut input,
                  @texture(0) Texture2D tex, @sampler(0) Sampler smp,
                  @texture(1) Texture2D bloomtex, @sampler(1) Sampler bloomsmp,
                  @uniform float4 fsparams) {   // x = time (s), y = noise amount
    // ----- Barrel distortion (screen-space uv) -----
    f32 cx = input.uv.x - 0.5f;
    f32 cy = input.uv.y - 0.5f;
    f32 r2 = cx * cx + cy * cy;
    f32 curvature = 0.10f;
    f32 wx = cx * (1.0f + r2 * curvature) + 0.5f;
    f32 wy = cy * (1.0f + r2 * curvature) + 0.5f;

    // ----- Border / bezel -----
    if wx < 0.0f { return float4{0.0f, 0.0f, 0.0f, 1.0f}; }
    if wx > 1.0f { return float4{0.0f, 0.0f, 0.0f, 1.0f}; }
    if wy < 0.0f { return float4{0.0f, 0.0f, 0.0f, 1.0f}; }
    if wy > 1.0f { return float4{0.0f, 0.0f, 0.0f, 1.0f}; }

    // ----- Sample scene -----
    // GL/WebGL (flipped) vs Metal/D3D (not flipped)    
    f32 scene_v = wy;
    if fsparams.z > 0.5f { scene_v = 1.0f - wy; }
    float4 c0 = sample(tex, smp, float2{wx, scene_v});
    f32 r = c0.x;
    f32 g = c0.y;
    f32 b = c0.z;

    // ----- Scanlines -----
    f32 lines = 300.0f;
    f32 s = sin(wy * lines * 3.14159265f);
    f32 scanline = 1.0f - 0.30f * (s * s);

    // ----- Bloom composite -----
    float4 bloom = sample(bloomtex, bloomsmp, float2{wx, wy});
    f32 bloom_strength = 2.0f;
    r = r + bloom.r * bloom_strength;
    g = g + bloom.g * bloom_strength;
    b = b + bloom.b * bloom_strength;

    // ----- RGB aperture mask -----
    f32 mask_width = 800.0f;
    f32 col = floor(wx * mask_width);
    f32 mod3 = col - floor(col * (1.0f / 3.0f)) * 3.0f;
    f32 mr = 0.95f;
    f32 mg = 0.85f;
    f32 mb = 0.85f;
    if mod3 < 0.5f { mr = 1.0f; }
    else if mod3 < 1.5f { mg = 1.0f; }
    else { mb = 1.0f; }

    // ----- Vignette -----
    f32 vig = 1.0f - 1.3f * r2;
    if vig < 0.0f { vig = 0.0f; }

    // ----- Time-based static noise -----
    float2 npx = float2{floor(wx*800.0f), floor(wy*600.0f)};
    f32 nz = frac(sin(dot(npx, float2{12.9898f, 78.233f}) + fsparams.x * 13.7f * 0.5f) * 43758.5453f);
    f32 noise = (nz - 0.5f) * fsparams.y * 2.0f;

    // ----- Compose ----
    f32 boost = 1.25f;
    return float4{r * scanline * mr * vig * boost + noise,
                  g * scanline * mg * vig * boost + noise,
                  b * scanline * mb * vig * boost + noise,
                  1.0f};
}

// ============================================================================
// Simple xorshift64 PRNG
// ============================================================================

i64 rng_state = 123456789;

i64 rng_next() {
    rng_state = rng_state ^ (rng_state << 13);
    rng_state = rng_state ^ (rng_state >> 7);
    rng_state = rng_state ^ (rng_state << 17);
    if rng_state < 0 { rng_state = 0 - rng_state; }
    return rng_state;
}

// Random float in [lo, hi)
f32 rng_range(f32 lo, f32 hi) {
    f32 t = cast(f32, rng_next() % 10000) / 10000.0f;
    return lo + t * (hi - lo);
}

// Random int in [lo, hi)
i32 rng_int(i32 lo, i32 hi) {
    if hi <= lo { return lo; }
    return lo + cast(i32, rng_next() % cast(i64, hi - lo));
}

// ============================================================================
// Vertex buffer — dynamic, rebuilt each frame
// ============================================================================

f32[MAX_VERTS * 8] verts;  // MAX_VERTS(4096) * 8 floats (pos4 + color4)
u32 vert_count = 0;

void push_vert(f32 x, f32 y, f32 r, f32 g, f32 b, f32 a) {
    var base = vert_count * 8;
    verts[base + 0] = x;
    verts[base + 1] = y;
    verts[base + 2] = 0.0f;
    verts[base + 3] = 1.0f;
    verts[base + 4] = r;
    verts[base + 5] = g;
    verts[base + 6] = b;
    verts[base + 7] = a;
    vert_count++;
}

void draw_rect(f32 x0, f32 y0, f32 w, f32 h, f32 r, f32 g, f32 b) {
    f32 x1 = x0 + w;
    f32 y1 = y0 + h;
    push_vert(x0, y0, r, g, b, 1.0f);
    push_vert(x1, y0, r, g, b, 1.0f);
    push_vert(x1, y1, r, g, b, 1.0f);
    push_vert(x0, y0, r, g, b, 1.0f);
    push_vert(x1, y1, r, g, b, 1.0f);
    push_vert(x0, y1, r, g, b, 1.0f);
}

void draw_circle(f32 cx, f32 cy, f32 radius, f32 r, f32 g, f32 b, i32 segs) {
    f32 step = TAU_F / cast(f32, segs);
    for i32 i = 0; i < segs; i++ {
        f32 a0 = cast(f32, i) * step;
        f32 a1 = cast(f32, i + 1) * step;
        f32 px0 = cx + cosf(a0) * radius;
        f32 py0 = cy + sinf(a0) * radius;
        f32 px1 = cx + cosf(a1) * radius;
        f32 py1 = cy + sinf(a1) * radius;
        push_vert(cx, cy, r, g, b, 1.0f);
        push_vert(px0, py0, r, g, b, 1.0f);
        push_vert(px1, py1, r, g, b, 1.0f);
    }
}

// Half-circle dome anchored at (cx, cy)
void draw_half_circle(f32 cx, f32 cy, f32 radius, f32 r, f32 g, f32 b, i32 segs) {
    f32 step = PI_F / cast(f32, segs);
    for i32 i = 0; i < segs; i++ {
        f32 a0 = cast(f32, i) * step;
        f32 a1 = cast(f32, i + 1) * step;
        f32 px0 = cx + cosf(a0) * radius;
        f32 py0 = cy - sinf(a0) * radius;
        f32 px1 = cx + cosf(a1) * radius;
        f32 py1 = cy - sinf(a1) * radius;
        push_vert(cx, cy, r, g, b, 1.0f);
        push_vert(px0, py0, r, g, b, 1.0f);
        push_vert(px1, py1, r, g, b, 1.0f);
    }
}

void draw_line(f32 x1, f32 y1, f32 x2, f32 y2, f32 thick, f32 r, f32 g, f32 b) {
    // Perpendicular direction for thickness
    f32 dx = x2 - x1;
    f32 dy = y2 - y1;
    f32 len = sqrtf(dx * dx + dy * dy);
    if len < 0.001f { return; }
    f32 nx = (0.0f - dy) / len * thick * 0.5f;
    f32 ny = dx / len * thick * 0.5f;
    f32 ax = x1 + nx; f32 ay = y1 + ny;
    f32 bx = x1 - nx; f32 by = y1 - ny;
    f32 cx = x2 - nx; f32 cy = y2 - ny;
    f32 ddx = x2 + nx; f32 ddy = y2 + ny;
    push_vert(ax, ay, r, g, b, 1.0f);
    push_vert(bx, by, r, g, b, 1.0f);
    push_vert(cx, cy, r, g, b, 1.0f);
    push_vert(ax, ay, r, g, b, 1.0f);
    push_vert(cx, cy, r, g, b, 1.0f);
    push_vert(ddx, ddy, r, g, b, 1.0f);
}

// ============================================================================
// Game state
// ============================================================================

// Cities
bool[NUM_CITIES] city_alive;
f32[NUM_CITIES]  city_x;

// Enemy missiles
bool[MAX_ENEMY]   em_active;
float2[MAX_ENEMY] em_start;
float2[MAX_ENEMY] em_target;
f32[MAX_ENEMY]    em_prog;   // progress 0..1
f32[MAX_ENEMY]    em_speed;  // pixels per second

// Player missiles
bool[MAX_PLAYER]   pm_active;
float2[MAX_PLAYER] pm_start;
float2[MAX_PLAYER] pm_target;
f32[MAX_PLAYER]    pm_prog;

// Explosions
bool[MAX_EXPLOSIONS]   ex_active;
float2[MAX_EXPLOSIONS] ex_pos;
f32[MAX_EXPLOSIONS]    ex_radius;
f32[MAX_EXPLOSIONS]    ex_max_r;
bool[MAX_EXPLOSIONS]   ex_growing; // true = expanding, false = shrinking

// Game
float2 crosshair = float2{ 400.0f, 300.0f };
i32 score = 0;
i32 wave = 0;
bool game_over = false;
bool game_started = false;  // start screen
f32 wave_delay = 0.0f;      // countdown before next wave
i32 enemies_alive = 0;

// Key state
bool key_left = false;
bool key_right = false;
bool key_up = false;
bool key_down = false;

// Battery position
const float2 battery = float2{ SCREEN_W / 2.0f, SCREEN_H - GROUND_HEIGHT };

// Graphics — game pipeline (Pass 1, into offscreen RT)
sg_pipeline pip;
sg_buffer vbuf;

// Graphics — offscreen render target (size = SCREEN_W × SCREEN_H, fixed)
sg_image rt_img;
sg_view rt_color_view;  // color-attachment view (Pass 1 writes here)
sg_view rt_tex_view;    // texture-sample view (Pass 2 reads here)
sg_sampler rt_smp;

// Graphics — blit pipeline (final pass, RT → swapchain via fullscreen quad)
sg_pipeline blit_pip;
sg_buffer blit_vbuf;

// Graphics — bloom (quarter-res ping-pong targets + pipelines)
sg_image bloom_a_img;
sg_image bloom_b_img;
sg_view bloom_a_color;   // color-attachment views (blur writes here)
sg_view bloom_b_color;
sg_view bloom_a_tex;     // texture-sample views (blur / composite read here)
sg_view bloom_b_tex;
sg_sampler bloom_smp;    // LINEAR + CLAMP — smooth downsample, blur, upscale
sg_pipeline bright_pip;
sg_pipeline blur_h_pip;
sg_pipeline blur_v_pip;

// CRT composite uniform — wall-clock time, for time-based noise.
f32 crt_time = 0.0f;
f32 crt_flip_v = 0.0f;


// ============================================================================
// Orthographic projection (pixel coords → NDC)
// ============================================================================

float4x4 make_ortho() {
    // Column-major: maps the SCREEN_W × SCREEN_H game space directly
    // to NDC, Y flipped (0=top).
    return float4x4{
        2.0f / SCREEN_W, 0.0f,                   0.0f, 0.0f,
        0.0f,            0.0f - 2.0f / SCREEN_H, 0.0f, 0.0f,
        0.0f,            0.0f,                   1.0f, 0.0f,
        -1.0f,           1.0f,                   0.0f, 1.0f
    };
}

// Reserve the largest centered 4:3 sub-rectangle of the canvas so
// the 800x600 game space scales without distortion.
void apply_letterbox_viewport() {
    i32 cw = sapp_width();
    i32 ch = sapp_height();
    f32 ca = cast(f32, cw) / cast(f32, ch);
    f32 ga = SCREEN_W / SCREEN_H;  // 4/3
    i32 vx, vy, vw, vh;
    if ca > ga {
        // canvas wider than 4:3 — pillarbox (left/right bars)
        vh = ch;
        vw = cast(i32, cast(f32, ch) * ga);
        vx = (cw - vw) / 2;
        vy = 0;
    }
    else {
        // canvas taller than 4:3 — letterbox (top/bottom bars)
        vw = cw;
        vh = cast(i32, cast(f32, cw) / ga);
        vx = 0;
        vy = (ch - vh) / 2;
    }
    sg_apply_viewport(vx, vy, vw, vh, true);
}

// ============================================================================
// Game logic
// ============================================================================

void init_game() {
    // Place cities evenly across the ground
    for i32 i = 0; i < NUM_CITIES; i++ {
        city_alive[i] = true;
        // Skip center for battery: cities at positions 1-3 left, 5-7 right of 9 slots
        i32 slot = i;
        if i >= 3 { slot = i + 1; } // skip slot 4 (battery)
        city_x[i] = cast(f32, 60 + slot * 80);
    }

    // Clear entities
    for i32 i = 0; i < MAX_ENEMY; i++ { em_active[i] = false; }
    for i32 i = 0; i < MAX_PLAYER; i++ { pm_active[i] = false; }
    for i32 i = 0; i < MAX_EXPLOSIONS; i++ { ex_active[i] = false; }

    crosshair = float2{ 400.0f, 250.0f };
    score = 0;
    wave = 0;
    game_over = false;
    wave_delay = 1.0f;
    enemies_alive = 0;
}

void spawn_wave() {
    wave++;
    i32 count = 4 + wave * 2;
    if count > MAX_ENEMY { count = MAX_ENEMY; }

    f32 base_speed = 30.0f + cast(f32, wave) * 8.0f;

    for i32 i = 0; i < count; i++ {
        if em_active[i] == false {
            em_active[i] = true;
            em_start[i] = float2{
                rng_range(50.0f, 750.0f),
                rng_range(0.0f - 50.0f, 0.0f - 10.0f) // start above screen
            };

            // Target a random alive city
            i32 target = rng_int(0, NUM_CITIES);
            i32 tries = 0;
            while city_alive[target] == false && tries < 12 {
                target = rng_int(0, NUM_CITIES);
                tries++;
            }
            em_target[i] = float2{ city_x[target], SCREEN_H - GROUND_HEIGHT };
            em_prog[i] = 0.0f;
            em_speed[i] = base_speed + rng_range(0.0f, 20.0f);
            enemies_alive++;
        }
    }
}

void fire_player_missile() {
    // Find free slot
    for i32 i = 0; i < MAX_PLAYER; i++ {
        if pm_active[i] == false {
            pm_active[i] = true;
            pm_start[i] = battery;
            pm_target[i] = crosshair;
            pm_prog[i] = 0.0f;
            play_sfx(SFX_FIRE);
            return;
        }
    }
}

void spawn_explosion(float2 pos, f32 max_r) {
    for i32 i = 0; i < MAX_EXPLOSIONS; i++ {
        if ex_active[i] == false {
            ex_active[i] = true;
            ex_pos[i] = pos;
            ex_radius[i] = 2.0f;
            ex_max_r[i] = max_r;
            ex_growing[i] = true;
            return;
        }
    }
}

float2 missile_current_pos(float2 s, float2 t, f32 prog) {
    return s + (t - s) * prog;
}

void update_game(f32 dt) {
    if game_over { return; }

    // Move crosshairhair
    if key_left  { crosshair.x = crosshair.x - CROSSHAIR_SPEED * dt; }
    if key_right { crosshair.x = crosshair.x + CROSSHAIR_SPEED * dt; }
    if key_up    { crosshair.y = crosshair.y - CROSSHAIR_SPEED * dt; }
    if key_down  { crosshair.y = crosshair.y + CROSSHAIR_SPEED * dt; }
    if crosshair.x < 10.0f  { crosshair.x = 10.0f; }
    if crosshair.x > 790.0f { crosshair.x = 790.0f; }
    if crosshair.y < 10.0f  { crosshair.y = 10.0f; }
    if crosshair.y > 550.0f { crosshair.y = 550.0f; }

    // Update player missiles
    for i32 i = 0; i < MAX_PLAYER; i++ {
        if pm_active[i] {
            f32 dist = length(pm_target[i] - pm_start[i]);
            if dist > 0.1f {
                pm_prog[i] = pm_prog[i] + (PLAYER_MISSILE_SPEED * dt) / dist;
            } else {
                pm_prog[i] = 1.0f;
            }
            if pm_prog[i] >= 1.0f {
                pm_active[i] = false;
                spawn_explosion(pm_target[i], EXPLOSION_MAX_RADIUS);
            }
        }
    }

    // Update enemy missiles
    f32 wave_factor = 1.0f + cast(f32, wave) * 0.25f;
    for i32 i = 0; i < MAX_ENEMY; i++ {
        if em_active[i] {
            f32 dist = length(em_target[i] - em_start[i]);
            if dist > 0.1f {
                em_prog[i] = em_prog[i] + (em_speed[i] * wave_factor * dt) / dist;
            } else {
                em_prog[i] = 1.0f;
            }
            if em_prog[i] >= 1.0f {
                em_active[i] = false;
                enemies_alive--;
                // Destroy the targeted city
                for i32 c = 0; c < NUM_CITIES; c = c + 1 {
                    f32 cdist = fabsf(em_target[i].x - city_x[c]);
                    if cdist < 30.0f && city_alive[c] {
                        city_alive[c] = false;
                    }
                }
                // Small enemy impact explosion + boom.
                spawn_explosion(em_target[i], 15.0f);
                play_sfx(SFX_EXPLODE);
            }
        }
    }

    // Update explosions
    for i32 i = 0; i < MAX_EXPLOSIONS; i++ {
        if ex_active[i] {
            if ex_growing[i] {
                ex_radius[i] = ex_radius[i] + EXPLOSION_GROW_SPEED * dt;
                if ex_radius[i] >= ex_max_r[i] {
                    ex_radius[i] = ex_max_r[i];
                    ex_growing[i] = false;
                }
            } else {
                ex_radius[i] = ex_radius[i] - EXPLOSION_GROW_SPEED * dt * 0.6f;
                if ex_radius[i] <= 0.0f {
                    ex_active[i] = false;
                }
            }

            // Check collision with enemy missiles
            for i32 j = 0; j < MAX_ENEMY; j = j + 1 {
                if em_active[j] {
                    float2 m = missile_current_pos(em_start[j], em_target[j], em_prog[j]);
                    f32 d = length(m - ex_pos[i]);
                    if d < ex_radius[i] {
                        em_active[j] = false;
                        enemies_alive--;
                        score = score + 17;
                        play_sfx(SFX_EXPLODE);
                    }
                }
            }
        }
    }

    // Wave management
    if enemies_alive <= 0 {
        // Check if any enemy missiles still active (shouldn't be, but safety)
        i32 still_active = 0;
        for i32 i = 0; i < MAX_ENEMY; i++ {
            if em_active[i] { still_active++; }
        }
        enemies_alive = still_active;

        if still_active == 0 {
            wave_delay = wave_delay - dt;
            if wave_delay <= 0.0f {
                spawn_wave();
                wave_delay = 2.0f;
            }
        }
    }

    // Check game over
    i32 alive_count = 0;
    for i32 i = 0; i < NUM_CITIES; i++ {
        if city_alive[i] { alive_count++; }
    }
    // Edge-trigger the game-over jingle
    if alive_count == 0 && !game_over {
        game_over = true;
        play_sfx(SFX_GAMEOVER);
    }
}

// ============================================================================
// Rendering
// ============================================================================

void render_game() {
    vert_count = 0;

    // Ground
    draw_rect(0.0f, SCREEN_H - GROUND_HEIGHT, SCREEN_W, GROUND_HEIGHT,
              0.2f, 0.6f, 0.2f);

    // Cities
    for i32 i = 0; i < NUM_CITIES; i++ {
        if city_alive[i] {
            f32 cx = city_x[i] - CITY_WIDTH * 0.5f;
            f32 cy = SCREEN_H - GROUND_HEIGHT - CITY_HEIGHT;
            draw_rect(cx, cy, CITY_WIDTH, CITY_HEIGHT, 0.3f, 0.3f, 0.9f);
            // Small roof
            draw_rect(cx + 4.0f, cy - 6.0f, CITY_WIDTH - 8.0f, 6.0f,
                      0.4f, 0.4f, 1.0f);
        }
    }

    // Enemy missile trails
    for i32 i = 0; i < MAX_ENEMY; i++ {
        if em_active[i] {
            float2 c = missile_current_pos(em_start[i], em_target[i], em_prog[i]);
            draw_line(em_start[i].x, em_start[i].y, c.x, c.y, 2.0f, 1.0f, 0.2f, 0.2f);
            // Missile head
            draw_circle(c.x, c.y, 3.0f, 1.0f, 0.4f, 0.4f, 8);
        }
    }

    // Player missile trails
    for i32 i = 0; i < MAX_PLAYER; i++ {
        if pm_active[i] {
            float2 c = missile_current_pos(pm_start[i], pm_target[i], pm_prog[i]);
            draw_line(pm_start[i].x, pm_start[i].y, c.x, c.y, 2.0f, 0.2f, 0.8f, 1.0f);
            // Missile head
            draw_circle(c.x, c.y, 3.0f, 0.4f, 0.9f, 1.0f, 8);
        }
    }

    // Battery — half-circle dome sitting on the ground line.
    draw_half_circle(battery.x, battery.y, BATTERY_RADIUS, 0.7f, 0.7f, 0.3f, 16);

    // Explosions
    for i32 i = 0; i < MAX_EXPLOSIONS; i++ {
        if ex_active[i] {
            // Orange-yellow expanding circle
            f32 er = 1.0f;
            f32 eg = 0.5f + ex_radius[i] / ex_max_r[i] * 0.5f;
            f32 eb = 0.1f;
            draw_circle(ex_pos[i].x, ex_pos[i].y, ex_radius[i], er, eg, eb, 16);
        }
    }

    // Crosshair
    if game_over == false {
        f32 cs = 12.0f; // crosshairhair half-size
        f32 ct = 2.0f;  // crosshairhair thickness
        // Horizontal bar
        draw_rect(crosshair.x - cs, crosshair.y - ct * 0.5f, cs * 2.0f, ct,
                  0.0f, 1.0f, 0.0f);
        // Vertical bar
        draw_rect(crosshair.x - ct * 0.5f, crosshair.y - cs, ct, cs * 2.0f,
                  0.0f, 1.0f, 0.0f);
    }

    // HUD — score, wave, cities
    f32 tx = draw_text(10.0f, 10.0f, 2.0f, "SCORE:", 0.8f, 0.8f, 0.8f);
    draw_int(tx, 10.0f, 2.0f, score, 1.0f, 1.0f, 0.3f);
    tx = draw_text(300.0f, 10.0f, 2.0f, "WAVE:", 0.8f, 0.8f, 0.8f);
    draw_int(tx, 10.0f, 2.0f, wave, 1.0f, 1.0f, 0.3f);

    i32 alive = 0;
    for i32 i = 0; i < NUM_CITIES; i++ {
        if city_alive[i] { alive++; }
    }
    tx = draw_text(560.0f, 10.0f, 2.0f, "CITIES:", 0.8f, 0.8f, 0.8f);
    draw_int(tx, 10.0f, 2.0f, alive, 0.3f, 1.0f, 0.3f);

    // Start screen
    if game_started == false {
        draw_rect(120.0f, 180.0f, 560.0f, 240.0f, 0.75f, 0.75f, 0.75f);
        draw_rect(130.0f, 190.0f, 540.0f, 220.0f, 0.05f, 0.02f, 0.75f);
        draw_text(162.0f, 230.0f, 4.0f, "MISSILE COMMAND", 1.0f, 0.4f, 0.2f);
        draw_text(190.0f, 310.0f, 2.0f, "WASD/ARROWS=AIM SPACE=FIRE", 0.5f, 0.5f, 0.5f);
        draw_text(230.0f, 350.0f, 2.0f, "PRESS SPACE TO START", 0.8f, 0.8f, 0.2f);
    }

    // Game over text
    if game_over && game_started {
        draw_rect(120.0f, 180.0f, 560.0f, 240.0f, 0.75f, 0.35f, 0.35f);
        draw_rect(130.0f, 190.0f, 540.0f, 220.0f, 0.15f, 0.0f, 0.0f);
        draw_text(255.0f, 250.0f, 4.0f, "GAME OVER", 1.0f, 0.2f, 0.2f);
        draw_text(255.0f, 335.0f, 2.0f, "PRESS R TO RESTART", 0.8f, 0.8f, 0.2f);
    }
}

// ============================================================================
// Audio
// ============================================================================
//
// Stream-callback mixer with hand-coded synthesis. The results of this very
// basic audio setup is pretty glitchy right now.
//
// The audio thread calls audio_cb() every buffer (~10-20 ms) and
// the game thread triggers SFX by claiming a voice slot via
// play_sfx(). Voices are mixed additively in audio_cb; no locks => 
// one frame of glitch at worst.
//

const i32 AUDIO_RATE = 44100;
const i32 NUM_VOICES = 8;
const i32 SFX_FIRE = 0;
const i32 SFX_EXPLODE = 1;
const i32 SFX_GAMEOVER = 2;

struct Voice {
    bool active;
    i32 kind;
    i32 pos;          // sample index within the SFX (0..length)
    i32 length;       // total samples for this trigger
    f32 phase;        // running sine phase (radians), tonal SFX only
    u32 noise_state;  // xorshift state, noise SFX only
}

Voice[8] voices;

u32 _noise_step(u32 s) {
    s = s ^ (s << 13);
    s = s ^ (s >> 17);
    s = s ^ (s << 5);
    return s;
}

// Fire: sine sweep 800 Hz → 200 Hz over the SFX duration with a
// linear amplitude decay.
f32 fire_render(Voice* v) {
    f32 t = cast(f32, v.pos) / cast(f32, v.length);
    f32 freq = 800.0f - 600.0f * t;
    v.phase = v.phase + freq * 6.2831853f / cast(f32, AUDIO_RATE);
    if v.phase > 6.2831853f { v.phase = v.phase - 6.2831853f; }
    f32 env = 1.0f - t;
    return sinf(v.phase) * env * 0.25f;
}

// Game-over: three descending sine notes (G4 → E4 → C4)
f32 gameover_render(Voice* v) {
    i32 n1 = (AUDIO_RATE * 18) / 100;   // end of note 1 (180 ms)
    i32 n2 = (AUDIO_RATE * 36) / 100;   // end of note 2 (180 ms)
    f32 freq;
    i32 seg_pos;
    i32 seg_len;
    if v.pos < n1 {
        freq = 392.0f;  // G4
        seg_pos = v.pos;
        seg_len = n1;
    } else if v.pos < n2 {
        freq = 330.0f;  // E4
        seg_pos = v.pos - n1;
        seg_len = n2 - n1;
    } else {
        freq = 262.0f;  // C4
        seg_pos = v.pos - n2;
        seg_len = v.length - n2;
    }
    if seg_pos == 0 { v.phase = 0.0f; }
    v.phase = v.phase + freq * 6.2831853f / cast(f32, AUDIO_RATE);
    if v.phase > 6.2831853f { v.phase = v.phase - 6.2831853f; }
    f32 nt = cast(f32, seg_pos) / cast(f32, seg_len);
    f32 env;
    if nt < 0.02f { env = nt * 50.0f; }              // 2% attack
    else if nt > 0.9f { env = (1.0f - nt) * 10.0f; } // 10% release
    else { env = 1.0f; }
    return sinf(v.phase) * env * 0.25f;
}

// Explode: low-pass-filtered white-noise rumble with a raw
// broadband crackle layered on top for a noisier blast.
f32 explode_render(Voice* v) {
    v.noise_state = _noise_step(v.noise_state);
    f32 noise = cast(f32, cast(i32, v.noise_state >> 8) & 0xFFFF) / 32768.0f - 1.0f;
    f32 t = cast(f32, v.pos) / cast(f32, v.length);
    f32 fc = 300.0f - 240.0f * t;
    f32 alpha = 6.2831853f * fc / cast(f32, AUDIO_RATE);
    v.phase = v.phase + alpha * (noise - v.phase);
    f32 env = (1.0f - t) * (1.0f - t);
    // Raw noise decays linearly (slower than the body) so the blast
    // keeps hissing into the long tail.
    f32 crackle = noise * (1.0f - t) * 0.28f;
    return v.phase * env * 0.7f + crackle;
}

void audio_cb(f32* buf, i32 nframes, i32 nchannels) {
    // Clear output — sokol doesn't guarantee a zero buffer.
    for i32 i = 0; i < nframes * nchannels; i++ { buf[i] = 0.0f; }
    // Mix active voices into the cleared buffer.
    for i32 vi = 0; vi < NUM_VOICES; vi++ {
        Voice* v = &voices[vi];
        if !v.active { continue; }
        for i32 i = 0; i < nframes; i++ {
            if v.pos >= v.length { v.active = false; break; }
            f32 s = 0.0f;
            if v.kind == SFX_FIRE     { s = fire_render(v); }
            if v.kind == SFX_EXPLODE  { s = explode_render(v); }
            if v.kind == SFX_GAMEOVER { s = gameover_render(v); }
            for i32 c = 0; c < nchannels; c++ {
                buf[i * nchannels + c] = buf[i * nchannels + c] + s;
            }
            v.pos = v.pos + 1;
        }
    }
}

void play_sfx(i32 kind) {
    // Find a free voice. If all 8 are busy, drop the trigger.
    for i32 vi = 0; vi < NUM_VOICES; vi++ {
        Voice* v = &voices[vi];
        if v.active { continue; }
        v.active = true;
        v.kind = kind;
        v.pos = 0;
        v.phase = 0.0f;
        v.noise_state = 0x9E3779B9;
        if kind == SFX_FIRE     { v.length = AUDIO_RATE / 8; }         // 125 ms
        if kind == SFX_EXPLODE  { v.length = (AUDIO_RATE * 7) / 10; }   // 700 ms
        if kind == SFX_GAMEOVER { v.length = (AUDIO_RATE * 8) / 10; }   // 800 ms (180+180+440)
        return;
    }
}

void init_audio() {
    saudio_desc desc;
    desc.sample_rate = AUDIO_RATE;
    desc.num_channels = 1;
    // 1024 frames = ~23 ms latency at 44.1 kHz on native.
    // On web, JS layer adds extra buffer which lands at around 50ms total latency.
    desc.buffer_frames = 1024;
    desc.stream_cb = audio_cb;
    saudio_setup(&desc);
}

// ============================================================================
// Sokol callbacks
// ============================================================================

void init() {
    sg_setup(&sg_desc{ .environment = sglue_environment() });
    init_audio();

    // Offscreen RTs sample V-flipped on bottom-left-origin backends (GL/WebGL).
    sg_features feats = sg_query_features();
    if !feats.origin_top_left { crt_flip_v = 1.0f; }

    // Dynamic vertex buffer (stream usage for per-frame updates)
    vbuf = sg_make_buffer(&sg_buffer_desc{
        .size = MAX_VERTS * 32, // 8 floats * 4 bytes each
        .usage.stream_update = true,
    });

    // Game pipeline — writes into the offscreen RT (RGBA8, no depth).
    sg_shader shd = sokol_make_shader(&mc_vs_shader, &mc_fs_shader);
    pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = shd,
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT4,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT4,
        .primitive_type = SG_PRIMITIVETYPE_TRIANGLES,
        .colors[0].pixel_format = SG_PIXELFORMAT_RGBA8,
        .depth.pixel_format = SG_PIXELFORMAT_NONE,
    });

    // ----- Offscreen render target at fixed SCREEN_W × SCREEN_H -----
    rt_img = sg_make_image(&sg_image_desc{
        .width = cast(i32, SCREEN_W),
        .height = cast(i32, SCREEN_H),
        .pixel_format = SG_PIXELFORMAT_RGBA8,
        .sample_count = 1,
        .usage.color_attachment = true,
    });
    rt_color_view = sg_make_view(&sg_view_desc{ .color_attachment.image = rt_img });
    rt_tex_view   = sg_make_view(&sg_view_desc{ .texture.image = rt_img });
    rt_smp = sg_make_sampler(&sg_sampler_desc{
        .min_filter = SG_FILTER_NEAREST,
        .mag_filter = SG_FILTER_NEAREST,
        .wrap_u = SG_WRAP_CLAMP_TO_EDGE,
        .wrap_v = SG_WRAP_CLAMP_TO_EDGE,
    });

    // Fullscreen quad: pos2 + uv2 = 4 floats per vertex, 6 verts (two triangles).
    // NDC coords; stays a local — the buffer desc points at it.
    f32[24] blit_data;
    blit_data[0]  = 0.0f - 1.0f; blit_data[1]  = 1.0f;        blit_data[2]  = 0.0f; blit_data[3]  = 0.0f;
    blit_data[4]  = 1.0f;        blit_data[5]  = 1.0f;        blit_data[6]  = 1.0f; blit_data[7]  = 0.0f;
    blit_data[8]  = 1.0f;        blit_data[9]  = 0.0f - 1.0f; blit_data[10] = 1.0f; blit_data[11] = 1.0f;
    blit_data[12] = 0.0f - 1.0f; blit_data[13] = 1.0f;        blit_data[14] = 0.0f; blit_data[15] = 0.0f;
    blit_data[16] = 1.0f;        blit_data[17] = 0.0f - 1.0f; blit_data[18] = 1.0f; blit_data[19] = 1.0f;
    blit_data[20] = 0.0f - 1.0f; blit_data[21] = 0.0f - 1.0f; blit_data[22] = 0.0f; blit_data[23] = 1.0f;
    blit_vbuf = sg_make_buffer(&sg_buffer_desc{ .data.ptr = &blit_data, .data.size = 24 * 4 });

    // Blit/composite pipeline (RT + bloom → swapchain).
    sg_shader blit_shd = sokol_make_shader(&mc_blit_vs_shader, &mc_blit_fs_shader);
    blit_pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = blit_shd,
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT2,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT2,
        .primitive_type = SG_PRIMITIVETYPE_TRIANGLES,
    });

    // ----- Bloom: two quarter-res ping-pong targets -----
    // ba_desc is reused for both images, so it stays a named local.
    sg_image_desc ba_desc = sg_image_desc{
        .width = BLOOM_W,
        .height = BLOOM_H,
        .pixel_format = SG_PIXELFORMAT_RGBA8,
        .sample_count = 1,
        .usage.color_attachment = true,
    };
    bloom_a_img = sg_make_image(&ba_desc);
    bloom_b_img = sg_make_image(&ba_desc);

    bloom_a_color = sg_make_view(&sg_view_desc{ .color_attachment.image = bloom_a_img });
    bloom_b_color = sg_make_view(&sg_view_desc{ .color_attachment.image = bloom_b_img });
    bloom_a_tex   = sg_make_view(&sg_view_desc{ .texture.image = bloom_a_img });
    bloom_b_tex   = sg_make_view(&sg_view_desc{ .texture.image = bloom_b_img });
    bloom_smp = sg_make_sampler(&sg_sampler_desc{
        .min_filter = SG_FILTER_LINEAR,
        .mag_filter = SG_FILTER_LINEAR,
        .wrap_u = SG_WRAP_CLAMP_TO_EDGE,
        .wrap_v = SG_WRAP_CLAMP_TO_EDGE,
    });

    // Bloom pipelines — same fullscreen-quad layout + RGBA8/no-depth target,
    // differing only by fragment shader.
    sg_shader bright_shd = sokol_make_shader(&mc_blit_vs_shader, &mc_bright_fs_shader);
    bright_pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = bright_shd,
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT2,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT2,
        .primitive_type = SG_PRIMITIVETYPE_TRIANGLES,
        .colors[0].pixel_format = SG_PIXELFORMAT_RGBA8,
        .depth.pixel_format = SG_PIXELFORMAT_NONE,
    });
    sg_shader bh_shd = sokol_make_shader(&mc_blit_vs_shader, &mc_blur_h_fs_shader);
    blur_h_pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = bh_shd,
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT2,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT2,
        .primitive_type = SG_PRIMITIVETYPE_TRIANGLES,
        .colors[0].pixel_format = SG_PIXELFORMAT_RGBA8,
        .depth.pixel_format = SG_PIXELFORMAT_NONE,
    });
    sg_shader bv_shd = sokol_make_shader(&mc_blit_vs_shader, &mc_blur_v_fs_shader);
    blur_v_pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = bv_shd,
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT2,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT2,
        .primitive_type = SG_PRIMITIVETYPE_TRIANGLES,
        .colors[0].pixel_format = SG_PIXELFORMAT_RGBA8,
        .depth.pixel_format = SG_PIXELFORMAT_NONE,
    });

    // Init game (don't spawn yet — wait for start screen)
    init_game();
    game_started = false;
}

void frame() {
    f32 dt = frame_dt();
    if dt > 0.033f { dt = 0.033f; }
    crt_time = crt_time + dt;

    if game_started {
        update_game(dt);
    }
    render_game();

    // Upload vertices
    sg_update_buffer(vbuf, &sg_range{ .ptr = &verts, .size = vert_count * 32 });

    // ----- Pass 1: render game into the offscreen RT (full RT, no viewport
    // shaping — the RT IS the SCREEN_W × SCREEN_H game space).
    sg_begin_pass(&sg_pass{
        .action.colors[0].load_action = SG_LOADACTION_CLEAR,
        .action.colors[0].clear_value = sg_color{ 0.02f, 0.02f, 0.08f, 1.0f },
        .attachments.colors[0] = rt_color_view,
    });
    sg_apply_pipeline(pip);
    sg_apply_bindings(&sg_bindings{ .vertex_buffers[0] = vbuf });
    float4x4 ortho = make_ortho();
    sg_apply_uniforms(0, &sg_range{ .ptr = &ortho, .size = sizeof(ortho) });
    sg_draw(0, vert_count, 1);
    sg_end_pass();

    // ----- Bloom bright-pass: scene RT → bloom_a (quarter-res) -----
    sg_begin_pass(&sg_pass{
        .action.colors[0].load_action = SG_LOADACTION_DONTCARE,  // fully overwritten
        .attachments.colors[0] = bloom_a_color,
    });
    sg_apply_pipeline(bright_pip);
    sg_apply_bindings(&sg_bindings{
        .vertex_buffers[0] = blit_vbuf,
        .views[0] = rt_tex_view,
        .samplers[0] = bloom_smp,
    });
    sg_draw(0, 6, 1);
    sg_end_pass();

    // ----- Bloom blur: ping-pong separable Gaussian, BLOOM_ITERS pairs -----
    for i32 i = 0; i < BLOOM_ITERS; i++ {
        // Horizontal: bloom_a → bloom_b
        sg_begin_pass(&sg_pass{
            .action.colors[0].load_action = SG_LOADACTION_DONTCARE,
            .attachments.colors[0] = bloom_b_color,
        });
        sg_apply_pipeline(blur_h_pip);
        sg_apply_bindings(&sg_bindings{
            .vertex_buffers[0] = blit_vbuf,
            .views[0] = bloom_a_tex,
            .samplers[0] = bloom_smp,
        });
        sg_draw(0, 6, 1);
        sg_end_pass();

        // Vertical: bloom_b → bloom_a
        sg_begin_pass(&sg_pass{
            .action.colors[0].load_action = SG_LOADACTION_DONTCARE,
            .attachments.colors[0] = bloom_a_color,
        });
        sg_apply_pipeline(blur_v_pip);
        sg_apply_bindings(&sg_bindings{
            .vertex_buffers[0] = blit_vbuf,
            .views[0] = bloom_b_tex,
            .samplers[0] = bloom_smp,
        });
        sg_draw(0, 6, 1);
        sg_end_pass();
    }

    // ----- Composite: scene RT (tex 0) + bloom_a (tex 1) → swapchain,
    // letterboxed into a 4:3 sub-rectangle, with the full CRT effect.
    sg_begin_pass(&sg_pass{
        .action.colors[0].load_action = SG_LOADACTION_CLEAR,
        .action.colors[0].clear_value = sg_color{ 0.0f, 0.0f, 0.0f, 1.0f },
        .swapchain = sglue_swapchain(),
    });
    apply_letterbox_viewport();
    sg_apply_pipeline(blit_pip);
    sg_apply_bindings(&sg_bindings{
        .vertex_buffers[0] = blit_vbuf,
        .views[0] = rt_tex_view,
        .samplers[0] = rt_smp,
        .views[1] = bloom_a_tex,
        .samplers[1] = bloom_smp,
    });

    // CRT composite uniform: x = time (drives noise), y = noise amount
    // (faded in over the first second). ortho/fsparams stay locals —
    // the sg_range points at them.
    f32 noise_fade = 0.0f;
    if (crt_time < 1.0f) {
        noise_fade = 10.0f * (1.0f - crt_time);
    }
    float4 fsparams = float4{ crt_time, 0.08f + noise_fade, crt_flip_v, 0.0f };
    sg_apply_uniforms(0, &sg_range{ .ptr = &fsparams, .size = sizeof(fsparams) });

    sg_draw(0, 6, 1);
    sg_end_pass();
    sg_commit();
}

// Tap / click handler. `sx, sy` are framebuffer pixels.
void handle_tap(f32 sx, f32 sy) {
    // Invert apply_letterbox_viewport to recover logical 800×600
    // game coords. Taps outside the playfield are ignored.
    i32 cw = sapp_width();
    i32 ch = sapp_height();
    f32 ca = cast(f32, cw) / cast(f32, ch);
    f32 ga = SCREEN_W / SCREEN_H;
    i32 vx; i32 vy; i32 vw; i32 vh;
    if ca > ga {
        vh = ch; vw = cast(i32, cast(f32, ch) * ga);
        vx = (cw - vw) / 2; vy = 0;
    } else {
        vw = cw; vh = cast(i32, cast(f32, cw) / ga);
        vx = 0; vy = (ch - vh) / 2;
    }
    f32 rx = (sx - cast(f32, vx)) / cast(f32, vw);
    f32 ry = (sy - cast(f32, vy)) / cast(f32, vh);
    if rx < 0.0f || rx > 1.0f || ry < 0.0f || ry > 1.0f { return; }
    f32 gx = rx * SCREEN_W;
    f32 gy = ry * SCREEN_H;
    if game_started == false || game_over {
        // Start (or restart on game-over). Mirrors the SPACE / R path.
        init_game();
        game_started = true;
        spawn_wave();
        return;
    }
    // Game running — aim + fire.
    crosshair.x = gx;
    crosshair.y = gy;
    fire_player_missile();
}

void on_event(sapp_event* ev) {
    if ev.type == SAPP_EVENTTYPE_MOUSE_DOWN {
        if ev.mouse_button == SAPP_MOUSEBUTTON_LEFT {
            handle_tap(ev.mouse_x, ev.mouse_y);
        }
    }
    if ev.type == SAPP_EVENTTYPE_TOUCHES_BEGAN {
        if ev.num_touches > 0 {
            // First finger only
            handle_tap(ev.touches[0].pos_x, ev.touches[0].pos_y);
        }
    }
    if ev.type == SAPP_EVENTTYPE_KEY_DOWN {
        if ev.key_code == SAPP_KEYCODE_LEFT  || ev.key_code == SAPP_KEYCODE_A { key_left = true; }
        if ev.key_code == SAPP_KEYCODE_RIGHT || ev.key_code == SAPP_KEYCODE_D { key_right = true; }
        if ev.key_code == SAPP_KEYCODE_UP    || ev.key_code == SAPP_KEYCODE_W { key_up = true; }
        if ev.key_code == SAPP_KEYCODE_DOWN  || ev.key_code == SAPP_KEYCODE_S { key_down = true; }
        if ev.key_code == SAPP_KEYCODE_SPACE {
            if game_started == false {
                // Start the game
                init_game();
                game_started = true;
                spawn_wave();
            } 
            else if game_over == false {
                // Fire
                fire_player_missile();
            }
        }
        if ev.key_code == SAPP_KEYCODE_R {
            init_game();
            game_started = true;
            spawn_wave();
        }
        if ev.key_code == SAPP_KEYCODE_ESCAPE { sapp_quit(); }
    }
    if ev.type == SAPP_EVENTTYPE_KEY_UP {
        if ev.key_code == SAPP_KEYCODE_LEFT  || ev.key_code == SAPP_KEYCODE_A { key_left = false; }
        if ev.key_code == SAPP_KEYCODE_RIGHT || ev.key_code == SAPP_KEYCODE_D { key_right = false; }
        if ev.key_code == SAPP_KEYCODE_UP    || ev.key_code == SAPP_KEYCODE_W { key_up = false; }
        if ev.key_code == SAPP_KEYCODE_DOWN  || ev.key_code == SAPP_KEYCODE_S { key_down = false; }
    }
    if ev.type == SAPP_EVENTTYPE_QUIT_REQUESTED { sapp_quit(); }
}

void cleanup() {
    sg_shutdown();
}

sapp_desc sokol_main() {
    return sapp_desc{
        .init_cb = init, 
        .frame_cb = frame, 
        .cleanup_cb = cleanup, 
        .event_cb = on_event,
        .width = 800, 
        .height = 600, 
        .sample_count = 1, 
        .high_dpi = true,
        .icon.sokol_default = true,
        .window_title = "Missile Command",
    };
}
