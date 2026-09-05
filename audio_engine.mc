// audio_engine.mc — streamed music plus synthesized effects on sokol_audio.
//
//   frame thread                          audio thread (stream_cb)
//   stb_vorbis decodes ahead  --ring-->   reads music, runs synth
//   into an SPSC ring buffer              voices, mixes, clamps
//
// Music streams from test/tune.ogg; only the compressed bytes stay in
// memory. Pads 1-4 trigger synthesized voices mixed on top.

import sokol_all;
import sokol_gl;
import sokol_audio;
import stb_vorbis;
import sokol_debugtext_font;
import atomic;
import file;
import math;
import ext_libc;

const f32 TWO_PI = 6.2831853f;

// ---- music: SPSC ring, frame thread writes, audio thread reads ------

const i32 RING_SHIFT = 14;
const i32 RING_FRAMES = 1 << RING_SHIFT;  // 2^14 frames / 44100 Hz = ~0.37 s of decode-ahead
const u32 RING_MASK = RING_FRAMES - 1;    // power of two, so & wraps the cursors
f32[RING_FRAMES * 2] g_ring;              // stereo interleaved
u32 g_head = 0;                           // write cursor (frames, monotonic)
u32 g_tail = 0;                           // read cursor
i32 g_flush = 0;                          // 1 = audio thread must discard the ring
i32 g_paused = 0;
u32 g_underruns = 0;

// the ogg tune is mastered quiet, add a gain.
const f32 MUSIC_GAIN = 1.5f;

stb_vorbis* g_vorbis = null;
u32 g_song_len = 0;                       // frames
u32 g_song_rate = 0;
i64 g_decoded_total = 0;                  // decode position; frame thread only

// ---- synth voices: audio thread only, triggers cross via atomics ----

const i32 NUM_VOICES = 8;
struct Voice {
    i32 kind;                             // 0 free, 1 pluck, 2 hat, 3 zap, 4 chord
    f32 p1; f32 p2; f32 p3;               // phases
    f32 inc1; f32 inc2; f32 inc3;         // phase steps
    f32 sweep;                            // per-sample multiplier on inc1 (zap)
    f32 env; f32 decay;
}
Voice[NUM_VOICES] g_voices;
u32 g_rng = 0x9E3779B9;
i32 g_out_rate = 44100;

// Music gain ramp, audio thread only. Pause, unpause and seek would
// otherwise step the waveform and click.
f32 g_mgain = 1.0f;
const f32 MGAIN_STEP = 1.0f / (0.005f * 44100.0f);   // 5 ms ramp

u32[4] g_trig;                            // trigger counters, main thread bumps
u32[4] g_trig_seen;                       // audio thread's last-seen values

// ---- scope: audio thread writes, frame thread draws -----------------

const i32 SCOPE_N = 1 << 10;              // 1024 samples = ~23 ms at 44.1 kHz
const u32 SCOPE_MASK = SCOPE_N - 1;
f32[SCOPE_N] g_scope;
u32 g_scope_w = 0;

// ---- UI state: frame thread only ------------------------------------

f32[4] g_pad_flash;
sg_pass_action g_pass_action;
f32 g_ts = 1.0f;                          // virtual->device scale, set per frame
f32 g_ox = 0.0f;                          // device-pixel origin of the canvas
f32 g_oy = 0.0f;

// ---- palette ---------------------------------------------------------

const float3 COL_BLACK        = float3{0.071f, 0.012f, 0.239f};
const float3 COL_WHITE        = float3{1.0f, 1.0f, 1.0f};
const float3 COL_RED          = float3{0.898f, 0.141f, 0.188f};
const float3 COL_CYAN         = float3{0.341f, 0.796f, 0.949f};
const float3 COL_VIOLET       = float3{0.447f, 0.314f, 0.722f};
const float3 COL_GREEN        = float3{0.251f, 0.741f, 0.388f};
const float3 COL_DARK_BLUE    = float3{0.231f, 0.082f, 0.663f};
const float3 COL_YELLOW_WARM  = float3{1.0f, 0.855f, 0.106f};
const float3 COL_ORANGE       = float3{0.925f, 0.314f, 0.180f};
const float3 COL_PINK         = float3{1.0f, 0.459f, 0.784f};
const float3 COL_BLUE_MEDIUM  = float3{0.337f, 0.106f, 1.0f};
const float3 COL_BLUE_LIGHT   = float3{0.529f, 0.576f, 1.0f};
const float3 COL_GREEN_BRIGHT = float3{0.267f, 0.890f, 0.757f};
const float3 COL_CREAM        = float3{1.0f, 0.941f, 0.651f};

// ---- layout (virtual 640x360 canvas) --------------------------------

const f32 SC_X   =  16.0f; const f32 SC_Y   =  20.0f;
const f32 SC_W   = 608.0f; const f32 SC_H   =  96.0f;
const f32 BAR_X  =  80.0f; const f32 BAR_W  = 464.0f;
const f32 PBAR_Y = 132.0f; const f32 PBAR_H =  16.0f;
const f32 RBAR_Y = 158.0f; const f32 RBAR_H =   8.0f;
const f32 PAD_Y  = 196.0f; const f32 PAD_W  =  96.0f; const f32 PAD_H  =  96.0f;

f32 pad_cx(i32 i) { return 132.0f + cast(f32, i) * 124.0f; }

// The canvas keeps its aspect: uniform scale from the tighter axis,
// centered in the window. The clear color fills the rest.
void fit_canvas() {
    f32 w = cast(f32, sapp_width());
    f32 h = cast(f32, sapp_height());
    f32 s = w / 640.0f;
    if h / 360.0f < s { s = h / 360.0f; }
    g_ts = s;
    g_ox = floorf((w - 640.0f * s) * 0.5f);
    g_oy = floorf((h - 360.0f * s) * 0.5f);
}

// ---- audio thread ----------------------------------------------------

void spawn_voice(i32 pad) {
    i32 slot = -1;
    for i32 i = 0; i < NUM_VOICES; i++ {
        if g_voices[i].kind == 0 { slot = i; break; }
    }
    if slot < 0 {
        // steal the quietest
        slot = 0;
        for i32 i = 1; i < NUM_VOICES; i++ {
            if g_voices[i].env < g_voices[slot].env { slot = i; }
        }
    }
    Voice* v = &g_voices[slot];
    f32 sr = cast(f32, g_out_rate);
    v.p1 = 0.0f; v.p2 = 0.0f; v.p3 = 0.0f;
    v.sweep = 1.0f;
    if pad == 0 {                         // pluck: decaying sine
        v.kind = 1;
        v.inc1 = TWO_PI * 440.0f / sr;
        v.env = 0.6f; v.decay = 0.9996f;
    } else if pad == 1 {                  // hat: white noise burst
        v.kind = 2;
        v.env = 0.4f; v.decay = 0.9985f;
    } else if pad == 2 {                  // zap: downward pitch sweep
        v.kind = 3;
        v.inc1 = TWO_PI * 1400.0f / sr;
        v.sweep = 0.99975f;
        v.env = 0.6f; v.decay = 0.9996f;
    } else {                              // chord: C4 + E4 + G4
        v.kind = 4;
        v.inc1 = TWO_PI * 261.63f / sr;
        v.inc2 = TWO_PI * 329.63f / sr;
        v.inc3 = TWO_PI * 392.0f / sr;
        v.env = 0.4f; v.decay = 0.99982f;
    }
}

// xorshift32 white noise in [-1, 1)
f32 noise_sample() {
    g_rng ^= g_rng << 13;
    g_rng ^= g_rng >> 17;
    g_rng ^= g_rng << 5;
    return cast(f32, cast(i32, g_rng)) * (1.0f / 2147483648.0f);   // / 2^31
}

f32 run_voices() {
    f32 sum = 0.0f;
    for i32 i = 0; i < NUM_VOICES; i++ {
        Voice* v = &g_voices[i];
        if v.kind == 0 { continue; }
        f32 s = 0.0f;
        if v.kind == 1 {
            s = sinf(v.p1);
            v.p1 += v.inc1;
        } else if v.kind == 2 {
            s = noise_sample();
        } else if v.kind == 3 {
            s = sinf(v.p1);
            v.p1 += v.inc1;
            v.inc1 *= v.sweep;
        } else {
            s = (sinf(v.p1) + sinf(v.p2) + sinf(v.p3)) * 0.333f;
            v.p1 += v.inc1; v.p2 += v.inc2; v.p3 += v.inc3;
        }
        if v.p1 > TWO_PI { v.p1 -= TWO_PI; }
        if v.p2 > TWO_PI { v.p2 -= TWO_PI; }
        if v.p3 > TWO_PI { v.p3 -= TWO_PI; }
        sum += s * v.env;
        v.env *= v.decay;
        if v.env < 0.002f { v.kind = 0; }
    }
    return sum;
}

void stream_cb(f32* buf, i32 num_frames, i32 num_channels) {
    // A seek happened: throw away everything decoded before it.
    if atomic_load(&g_flush, ACQUIRE) == 1 {
        atomic_store(&g_tail, atomic_load(&g_head), RELAXED);
        atomic_store(&g_flush, 0, RELEASE);
        g_mgain = 0.0f;                   // fade the post-seek audio back in
    }
    // Latch pad triggers.
    for i32 p = 0; p < 4; p++ {
        u32 want = atomic_load(&g_trig[p]);
        while g_trig_seen[p] != want {
            spawn_voice(p);
            g_trig_seen[p] = g_trig_seen[p] + 1;
        }
    }
    u32 head = atomic_load(&g_head, ACQUIRE);
    u32 tail = atomic_load(&g_tail, RELAXED);
    bool paused = atomic_load(&g_paused) != 0;
    bool starved = false;
    u32 sw = atomic_load(&g_scope_w, RELAXED);
    f32 mtarget = 1.0f;
    if paused { mtarget = 0.0f; }
    for i32 i = 0; i < num_frames; i++ {
        f32 l = 0.0f;
        f32 r = 0.0f;
        if g_mgain < mtarget {
            g_mgain += MGAIN_STEP;
            if g_mgain > mtarget { g_mgain = mtarget; }
        } else if g_mgain > mtarget {
            g_mgain -= MGAIN_STEP;
            if g_mgain < mtarget { g_mgain = mtarget; }
        }
        // Keep consuming while the fade-out still needs samples.
        if g_mgain > 0.0f {
            if tail != head {
                i32 idx = cast(i32, tail & RING_MASK);
                l = g_ring[idx * 2] * (MUSIC_GAIN * g_mgain);
                r = g_ring[idx * 2 + 1] * (MUSIC_GAIN * g_mgain);
                tail++;
            } else if !paused {
                starved = true;
            }
        }
        f32 s = run_voices();
        l += s;
        r += s;
        if l > 1.0f { l = 1.0f; } else if l < -1.0f { l = -1.0f; }
        if r > 1.0f { r = 1.0f; } else if r < -1.0f { r = -1.0f; }
        if num_channels == 1 {
            buf[i] = (l + r) * 0.5f;
        } else {
            buf[i * num_channels] = l;
            buf[i * num_channels + 1] = r;
            for i32 c = 2; c < num_channels; c++ { buf[i * num_channels + c] = 0.0f; }
        }
        g_scope[sw & SCOPE_MASK] = (l + r) * 0.5f;
        sw++;
    }
    atomic_store(&g_tail, tail, RELEASE);
    atomic_store(&g_scope_w, sw, RELEASE);
    if starved { atomic_add(&g_underruns, 1); }
}

// ---- frame thread: producer ------------------------------------------

// Decode up to `budget` frames into the ring; the cap bounds per-frame work.
void fill_ring(i32 budget) {
    if g_vorbis == null { return; }
    if atomic_load(&g_flush, ACQUIRE) != 0 { return; }   // stale data not discarded yet
    u32 tail = atomic_load(&g_tail, ACQUIRE);
    i32 space = RING_FRAMES - cast(i32, g_head - tail);
    if budget > space { budget = space; }
    while budget > 0 {
        i32 idx = cast(i32, g_head & RING_MASK);
        i32 span = RING_FRAMES - idx;
        if span > budget { span = budget; }
        i32 got = stb_vorbis_get_samples_float_interleaved(g_vorbis, 2, &g_ring[idx * 2], span * 2);
        if got == 0 {
            // end of stream: loop the tune
            stb_vorbis_seek_start(g_vorbis);
            g_decoded_total = 0;
            got = stb_vorbis_get_samples_float_interleaved(g_vorbis, 2, &g_ring[idx * 2], span * 2);
            if got == 0 { break; }
        }
        g_decoded_total += got;
        atomic_store(&g_head, g_head + cast(u32, got), RELEASE);
        budget -= got;
    }
}

void do_seek(f32 frac) {
    if g_vorbis == null || g_song_len == 0 { return; }
    if frac < 0.0f { frac = 0.0f; }
    if frac > 1.0f { frac = 1.0f; }
    u32 target = cast(u32, frac * cast(f32, g_song_len));
    stb_vorbis_seek(g_vorbis, target);
    g_decoded_total = cast(i64, target);
    atomic_store(&g_flush, 1, RELEASE);
    // fill_ring waits for the flag to clear, so decoding resumes into an
    // empty ring.
}

// ---- input -----------------------------------------------------------

void trigger_pad(i32 pad) {
    atomic_add(&g_trig[pad], 1);
    g_pad_flash[pad] = 1.0f;
}

void click_at(f32 x, f32 y) {
    for i32 i = 0; i < 4; i++ {
        f32 px = pad_cx(i) - PAD_W * 0.5f;
        if x >= px && x < px + PAD_W && y >= PAD_Y && y < PAD_Y + PAD_H {
            trigger_pad(i);
            return;
        }
    }
    if x >= BAR_X && x < BAR_X + BAR_W && y >= PBAR_Y - 4.0f && y < PBAR_Y + PBAR_H + 4.0f {
        do_seek((x - BAR_X) / BAR_W);
    }
}

void on_event(sapp_event* ev) {
    if ev.type == SAPP_EVENTTYPE_KEY_DOWN && !ev.key_repeat {
        if ev.key_code == SAPP_KEYCODE_SPACE {
            if atomic_load(&g_paused) != 0 { atomic_store(&g_paused, 0); }
            else { atomic_store(&g_paused, 1); }
        }
        i32 pad = cast(i32, ev.key_code) - cast(i32, SAPP_KEYCODE_1);
        if pad >= 0 && pad < 4 { trigger_pad(pad); }
    }
    if ev.type == SAPP_EVENTTYPE_MOUSE_DOWN {
        fit_canvas();
        click_at((ev.mouse_x - g_ox) / g_ts, (ev.mouse_y - g_oy) / g_ts);
    }
    if ev.type == SAPP_EVENTTYPE_TOUCHES_BEGAN && ev.num_touches > 0 {
        fit_canvas();
        click_at((ev.touches[0].pos_x - g_ox) / g_ts, (ev.touches[0].pos_y - g_oy) / g_ts);
    }
}

// ---- drawing ---------------------------------------------------------

// Text is drawn in device pixels at integer scale. Map a canvas anchor
// to a whole device pixel.
f32 tpx(f32 v) { return g_ox + floorf(v * g_ts + 0.5f); }
f32 tpy(f32 v) { return g_oy + floorf(v * g_ts + 0.5f); }

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

// Text anchors: virtual x plus the virtual y of the glyph row's center.
void text_left(f32 vx, f32 vcy, f32 tsf, u8* text, float3 color) {
    text_at(tpx(vx), tpy(vcy) - 4.0f * tsf, tsf, text, color);
}
void text_right(f32 vx, f32 vcy, i32 n, f32 tsf, u8* text, float3 color) {
    text_at(tpx(vx) - cast(f32, n * 8) * tsf, tpy(vcy) - 4.0f * tsf, tsf, text, color);
}
void text_centered(f32 vcx, f32 vcy, i32 n, f32 tsf, u8* text, float3 color) {
    text_at(tpx(vcx) - cast(f32, n * 4) * tsf, tpy(vcy) - 4.0f * tsf, tsf, text, color);
}

void frame() {
    fill_ring(4096);
    for i32 i = 0; i < 4; i++ { g_pad_flash[i] *= 0.85f; }

    i32 w = sapp_width();
    i32 h = sapp_height();
    fit_canvas();
    // glyphs stay at an integer scale so they render crisp
    f32 tsf = floorf(g_ts);
    if tsf < 1.0f { tsf = 1.0f; }

    u32 head = atomic_load(&g_head);
    u32 tail = atomic_load(&g_tail);
    i64 fill = cast(i64, head - tail);
    bool paused = atomic_load(&g_paused) != 0;
    i64 pos = 0;
    if g_song_len > 0 {
        pos = g_decoded_total - fill;
        if pos < 0 { pos += cast(i64, g_song_len); }     // ring still holds pre-loop tail
    }

    sgl_defaults();
    sgl_viewport(0, 0, w, h, true);
    // the window's extent in virtual units, so the canvas lands at (g_ox, g_oy)
    sgl_ortho(-g_ox / g_ts, (cast(f32, w) - g_ox) / g_ts,
              (cast(f32, h) - g_oy) / g_ts, -g_oy / g_ts, -1.0f, 1.0f);

    // --- shapes, on the virtual 640x360 canvas ---

    // scope panel + trace. The trace is a triangle strip.
    draw_rect(SC_X, SC_Y, SC_W, SC_H, COL_DARK_BLUE);
    u32 sw = atomic_load(&g_scope_w);
    f32 hw = 0.5f * tsf / g_ts;                                     // half thickness, virtual units
    // Drawn slightly scaled up.
    f32 amp = SC_H * 0.805f;
    f32 lim = SC_H * 0.5f - hw;
    sgl_begin_triangle_strip();
    sgl_color(COL_GREEN_BRIGHT);
    for i32 i = 0; i < SCOPE_N; i++ {
        f32 s = g_scope[(sw + cast(u32, i)) & SCOPE_MASK];
        f32 x = SC_X + SC_W * cast(f32, i) / cast(f32, SCOPE_N - 1);
        f32 d = s * amp;
        if d > lim { d = lim; }
        if d < -lim { d = -lim; }
        f32 y = SC_Y + SC_H * 0.5f - d;
        sgl_v2f(x, y - hw);
        sgl_v2f(x, y + hw);
    }
    sgl_end();

    // progress bar (click to seek) + ring fill
    draw_rect(BAR_X, PBAR_Y, BAR_W, PBAR_H, COL_DARK_BLUE);
    if g_song_len > 0 {
        f32 frac = cast(f32, pos) / cast(f32, g_song_len);
        draw_rect(BAR_X, PBAR_Y, BAR_W * frac, PBAR_H, COL_YELLOW_WARM);
    }
    draw_rect(BAR_X, RBAR_Y, BAR_W, RBAR_H, COL_DARK_BLUE);
    f32 rfrac = cast(f32, fill) / cast(f32, RING_FRAMES);
    draw_rect(BAR_X, RBAR_Y, BAR_W * rfrac, RBAR_H, COL_CYAN);

    // pads: palette color at rest, blended toward white while flashing
    for i32 i = 0; i < 4; i++ {
        f32 fl = g_pad_flash[i];
        float3 c = COL_ORANGE;
        if i == 1 { c = COL_BLUE_MEDIUM; }
        if i == 2 { c = COL_PINK; }
        if i == 3 { c = COL_GREEN; }
        draw_rect(pad_cx(i) - PAD_W * 0.5f, PAD_Y, PAD_W, PAD_H, c + (COL_WHITE - c) * fl);
    }

    // --- text, in device pixels ---
    sgl_load_identity();
    sgl_ortho(0.0f, cast(f32, w), cast(f32, h), 0.0f, -1.0f, 1.0f);

    if g_vorbis == null {
        text_centered(SC_X + SC_W * 0.5f, SC_Y + SC_H * 0.5f, 23, tsf,
                      "TEST/TUNE.OGG NOT FOUND", COL_RED);
    }
    text_left(16.0f, PBAR_Y + PBAR_H * 0.5f, tsf, "MUSIC", COL_BLUE_LIGHT);
    if g_song_len > 0 {
        u32 ps = cast(u32, pos) / g_song_rate;
        u32 ls = g_song_len / g_song_rate;
        u8[24] t;
        i32 tp = snprintf(&t[0], cast(u64, sizeof(t)), "%u:%02u/%u:%02u",
                          ps / 60, ps % 60, ls / 60, ls % 60);
        text_right(624.0f, PBAR_Y + PBAR_H * 0.5f, tp, tsf, &t[0], COL_CREAM);
    }
    if paused {
        text_centered(BAR_X + BAR_W * 0.5f, PBAR_Y + PBAR_H * 0.5f, 6, tsf, "PAUSED", COL_WHITE);
    }
    text_left(16.0f, RBAR_Y + RBAR_H * 0.5f, tsf, "RING", COL_BLUE_LIGHT);
    u8[16] u;
    i32 up = snprintf(&u[0], cast(u64, sizeof(u)), "UR %u", atomic_load(&g_underruns));
    text_right(624.0f, RBAR_Y + RBAR_H * 0.5f, up, tsf, &u[0], COL_CREAM);

    f32 lbl_y = PAD_Y + PAD_H + 12.0f;
    text_centered(pad_cx(0), lbl_y, 7, tsf, "1 PLUCK", COL_BLUE_LIGHT);
    text_centered(pad_cx(1), lbl_y, 5, tsf, "2 HAT"  , COL_BLUE_LIGHT);
    text_centered(pad_cx(2), lbl_y, 5, tsf, "3 ZAP"  , COL_BLUE_LIGHT);
    text_centered(pad_cx(3), lbl_y, 7, tsf, "4 CHORD", COL_BLUE_LIGHT);

    text_left(16.0f, 334.0f, tsf,
              "1-4 OR CLICK PADS: SFX   SPACE: PAUSE   CLICK BAR: SEEK", COL_VIOLET);

    sg_begin_pass(&sg_pass{ .action = g_pass_action, .swapchain = sglue_swapchain() });
    sgl_draw();
    sg_end_pass();
    sg_commit();
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

    // The decoder reads these bytes for the whole run; never freed.
    FileData fd = file_read("test/tune.ogg");
    u32 rate = 44100;
    if fd.data != null && fd.len > 0 {
        i32 err = 0;
        g_vorbis = stb_vorbis_open_memory(fd.data, cast(i32, fd.len), &err, null);
        if g_vorbis == null {
            print("audio_engine: vorbis open failed ({})\n", err);
        } else {
            g_song_len = stb_vorbis_stream_length_in_samples(g_vorbis);
            g_song_rate = g_vorbis.sample_rate;
            rate = g_song_rate;
        }
    } else {
        print("audio_engine: cannot read test/tune.ogg (run from the samples root)\n");
    }
    if g_song_rate == 0 { g_song_rate = 44100; }

    // Prefill so startup counts no underruns.
    fill_ring(RING_FRAMES);

    saudio_desc desc;
    desc.sample_rate = cast(i32, rate);
    desc.num_channels = 2;
    desc.buffer_frames = 2048;
    desc.stream_cb = stream_cb;
    saudio_setup(&desc);
    if !saudio_isvalid() {
        print("audio_engine: saudio_setup failed (audio backend unavailable)\n");
    } else {
        g_out_rate = saudio_sample_rate();
    }
}

void cleanup() {
    saudio_shutdown();
    sgl_shutdown();
    sg_shutdown();
}

sapp_desc sokol_main() {
    sapp_desc d = {
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = on_event,
        .width = 1280,
        .height = 720,
        .high_dpi = true,
        .sample_count = 4,
        .window_title = "minc audio engine"
    };
    return d;
}
