// sokol_compute.mc — Compute shader with storage image output
//
// A compute shader generates an animated Mandelbrot pattern into a
// storage image, then a render pass displays it as a textured fullscreen quad.
// Uses @shader for cross-platform shader compilation (HLSL/GLSL/Metal).

when os(wasm) { 
    @gpu "webgpu" 
    @define "SOKOL_WGPU" 
}

import sokol_all;
import math;

// --- Shaders (compiled to HLSL/GLSL/Metal automatically) ---

// Compute shader: animated Mandelbrot → storage image.
@shader compute(8, 8, 1)
void mandelbrot_cs(@storage(rgba8) RWTexture2D img, @uniform f32 u_time) {
    uint2 pixel = thread_id().xy;
    int2 size = img.size;
    float2 uv = float2{cast(f32, pixel.x) / cast(f32, size.x),
                       cast(f32, pixel.y) / cast(f32, size.y)};
    f32 ar_x = 1.0f;
    f32 ar_y = 1.0f;
    if size.x >= size.y { ar_x = cast(f32, size.x) / cast(f32, size.y); }
    else                { ar_y = cast(f32, size.y) / cast(f32, size.x); }

    f32 LOOP    = 16.0f;
    f32 t_loop  = u_time - floor(u_time / LOOP) * LOOP;

    f32 TARGET_CX = -0.7756838f;
    f32 TARGET_CY = 0.1364674f;
    f32 width = 4.0f * pow(0.6f, t_loop);

    float2 c = float2{TARGET_CX + (uv.x - 0.5f) * width * ar_x,
                      TARGET_CY + (uv.y - 0.5f) * width * ar_y};

    // Iteration budget grows with zoom:
    // log2(4 / width) * 32.0f, capped at 256
    i32 iter_max = 64 + cast(i32, log2(4.0f / width) * 32.0f);
    if iter_max > 256 { iter_max = 256; }

    float2 z = float2{0.0f, 0.0f};
    f32 n = 0.0f;
    for i32 i = 0; i < iter_max; i++ {
        z = float2{ z.x * z.x - z.y * z.y + c.x,
                    2.0f * z.x * z.y + c.y };
        if dot(z, z) > 4.0f { break; }
        n = n + 1.0f;
    }
    f32 t = n / cast(f32, iter_max);
    f32 phase = u_time * 0.33f;
    // Rainbow coloring via phase-shifted cosines
    f32 r = 0.5f + 0.5f * cos(6.28f * (t * 2.0f + phase));
    f32 g = 0.5f + 0.5f * cos(6.28f * (t * 2.0f + phase + 0.33f));
    f32 b = 0.5f + 0.5f * cos(6.28f * (t * 2.0f + phase + 0.67f));
    if n >= cast(f32, iter_max) { r = 0.0f; g = 0.0f; b = 0.0f; }
    img[pixel] = float4{r, g, b, 1.0f};
}

// Render shaders: fullscreen quad with texture
struct QuadVsOut {
    float4 pos;
    float2 uv;
}

@shader vertex
QuadVsOut quad_vs(@attr(0) float2 position, @attr(1) float2 texcoord) {
    QuadVsOut o;
    o.pos = float4{position.x, position.y, 0.0f, 1.0f};
    o.uv = texcoord;
    return o;
}

@shader fragment
float4 quad_fs(
    QuadVsOut input,
    @texture(0) Texture2D tex,
    @sampler(0) Sampler smp
) {
    return sample(tex, smp, input.uv);
}

// --- App state ---

sg_image tex_img;
sg_sampler tex_smp;
sg_view tex_view;
sg_view tex_simg_view;

sg_pipeline compute_pip;
sg_buffer quad_vbuf;
sg_pipeline render_pip;

// Compute storage image dimensions — recreated to match the
// framebuffer aspect ratio (and current size) on every resize so the
// Mandelbrot doesn't get stretched on non-square viewports. Always
// rounded down to a multiple of 8 to match the compute threadgroup.
i32 g_tex_w = 0;
i32 g_tex_h = 0;
f32 g_time = 0.0f;

i32 _ceil8(i32 v) {
    if v < 8 { return 8; }
    return v - (v % 8);
}

void rebuild_storage_image() {
    i32 want_w = _ceil8(sapp_width());
    i32 want_h = _ceil8(sapp_height());
    if want_w == g_tex_w && want_h == g_tex_h { return; }
    if g_tex_w != 0 {
        sg_destroy_view(tex_view);
        sg_destroy_view(tex_simg_view);
        sg_destroy_image(tex_img);
    }
    tex_img = sg_make_image(&sg_image_desc{
        .width = want_w,
        .height = want_h,
        .pixel_format = SG_PIXELFORMAT_RGBA8,
        .usage.storage_image = true,
    });

    tex_view = sg_make_view(&sg_view_desc{ .texture.image = tex_img });
    tex_simg_view = sg_make_view(&sg_view_desc{ .storage_image.image = tex_img });
    g_tex_w = want_w;
    g_tex_h = want_h;
}

void init() {
    sg_setup(&sg_desc{
        .environment = sglue_environment(),
        .logger = sglue_logger(),
    });

    // Sampler is fixed; the storage image + its views are (re)built by
    // rebuild_storage_image() to match the current framebuffer size.
    tex_smp = sg_make_sampler(&sg_sampler_desc{
        .min_filter = SG_FILTER_LINEAR,
        .mag_filter = SG_FILTER_LINEAR,
    });
    rebuild_storage_image();

    // --- Compute pipeline ---
    sg_shader compute_shd = sokol_make_shader(&mandelbrot_cs_shader);
    compute_pip = sg_make_pipeline(&sg_pipeline_desc{
        .compute = true,
        .shader = compute_shd,
    });

    // --- Render pipeline ---
    f32[24] quad = {
        -1.0f,  1.0f, 0.0f, 0.0f,
         1.0f,  1.0f, 1.0f, 0.0f,
         1.0f, -1.0f, 1.0f, 1.0f,
        -1.0f,  1.0f, 0.0f, 0.0f,
         1.0f, -1.0f, 1.0f, 1.0f,
        -1.0f, -1.0f, 0.0f, 1.0f,
    };

    quad_vbuf = sg_make_buffer(&sg_buffer_desc{
        .data.ptr = &quad,
        .data.size = sizeof(quad),
    });

    // Render shader
    sg_shader render_shd = sokol_make_shader(&quad_vs_shader, &quad_fs_shader);

    render_pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = render_shd,
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT2,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT2,
    });
}

void frame() {
    g_time = g_time + cast(f32, sapp_frame_duration());

    // Compute pass: generate texture
    sg_begin_pass(&sg_pass{ .compute = true });
    sg_apply_pipeline(compute_pip);

    sg_apply_bindings(&sg_bindings{ .views[0] = tex_simg_view });

    // CPU-side buffer is padded to 16 bytes — HLSL/MSL read the full
    // cbuffer slice, GL reads only the first f32.
    f32[4] ub_data;
    ub_data[0] = g_time;
    sg_apply_uniforms(0, &sg_range{
        .ptr = &ub_data,
        .size = sokol_uniform_size(&mandelbrot_cs_shader, 0),
    });
    sg_dispatch(g_tex_w / 8, g_tex_h / 8, 1);
    sg_end_pass();

    // Render pass: display texture on fullscreen quad
    sg_begin_pass(&sg_pass{
        .action.colors[0].load_action = SG_LOADACTION_CLEAR,
        .action.colors[0].clear_value = sg_color{ 0.0f, 0.0f, 0.0f, 1.0f },
        .swapchain = sglue_swapchain(),
    });
    sg_apply_pipeline(render_pip);

    sg_apply_bindings(&sg_bindings{
        .vertex_buffers[0] = quad_vbuf,
        .views[0] = tex_view,
        .samplers[0] = tex_smp,
    });

    sg_draw(0, 6, 1);
    sg_end_pass();
    sg_commit();
}

void cleanup() { sg_shutdown(); }

void on_event(sapp_event* ev) {
    if ev.type == SAPP_EVENTTYPE_KEY_DOWN {
        if ev.key_code == SAPP_KEYCODE_ESCAPE { sapp_quit(); }
    }
    if ev.type == SAPP_EVENTTYPE_RESIZED {
        rebuild_storage_image();
    }
}

sapp_desc sokol_main() {
    return sapp_desc{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = on_event,
        .width = 512,
        .height = 512,
        .high_dpi = true,
        .icon.sokol_default = true,
        .window_title = "Compute Shader — Mandelbrot",
    };
}
