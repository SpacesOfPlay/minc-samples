// sokol_compute_rw.mc — @storage(fmt, rw) read/write storage images.
//
// Not supported on WebGPU.


import sokol_all;
import math;
import frame_timer;


// --- Shaders ---

@shader compute(8, 8, 1)
void trails_cs(@storage(rgba8, rw) RWTexture2D img, @uniform float4 u_packed) {
    uint2 pixel = thread_id().xy;
    int2 size = img.size;
    if cast(i32, pixel.x) >= size.x || cast(i32, pixel.y) >= size.y { return; }

    f32 t      = u_packed.x;
    f32 dpi    = u_packed.y;    
    f32 cx     = cast(f32, size.x) * 0.5f;
    f32 cy     = cast(f32, size.y) * 0.5f;
    f32 radius = min(cx, cy) * 0.64f;

    // Decay the previous frame, then add each source to its own channel
    // with distance falloff.
    float4 prev = img[pixel];
    float3 acc  = prev.xyz * 0.94f;

    f32 fx = cast(f32, pixel.x);
    f32 fy = cast(f32, pixel.y);

    for i32 k = 0; k < 3; k++ {
        f32 phase = t + cast(f32, k) * 2.0944f;
        f32 sx = cx + radius * cos(phase);
        f32 sy = cy + radius * sin(1.7f * phase);
        f32 dx = fx - sx;
        f32 dy = fy - sy;
        f32 falloff = (dpi * 110.0f) / (dx * dx + dy * dy + 1.0f);
        if k == 0 { acc.x = acc.x + falloff; }
        if k == 1 { acc.y = acc.y + falloff; }
        if k == 2 { acc.z = acc.z + falloff; }
    }

    // clamp for the rgba8 backing
    acc = saturate(acc);
    img[pixel] = float4{acc.x, acc.y, acc.z, 1.0f};
}

struct QuadVsOut {
    float4 pos;
    float2 uv;
}

@shader vertex
QuadVsOut quad_vs(@attr(0) float2 position, @attr(1) float2 texcoord) {
    QuadVsOut o;
    o.pos = float4{position.x, position.y, 0.0f, 1.0f};
    o.uv  = texcoord;
    return o;
}

@shader fragment
float4 quad_fs(QuadVsOut input,
               @texture(0) Texture2D tex,
               @sampler(0) Sampler smp) {
    return sample(tex, smp, input.uv);
}

// --- App state ---

sg_image    acc_img;
sg_sampler  tex_smp;
sg_view     tex_view;
sg_view     simg_view;
sg_pipeline compute_pip;
sg_pipeline render_pip;
sg_buffer   quad_vbuf;

i32 g_tex_w = 0;
i32 g_tex_h = 0;
f32 g_time  = 0.0f;

// Round down to a multiple of the (8,8,1) threadgroup size.
i32 _floor8(i32 v) {
    if v < 8 { return 8; }
    return v - (v % 8);
}

void rebuild_image() {
    i32 want_w = _floor8(sapp_width());
    i32 want_h = _floor8(sapp_height());
    if want_w == g_tex_w && want_h == g_tex_h { return; }
    if g_tex_w != 0 {
        sg_destroy_view(tex_view);
        sg_destroy_view(simg_view);
        sg_destroy_image(acc_img);
    }
    acc_img = sg_make_image(&sg_image_desc{
        .width  = want_w,
        .height = want_h,
        .pixel_format = SG_PIXELFORMAT_RGBA8,
        .usage.storage_image = true,
    });

    tex_view = sg_make_view(&sg_view_desc{ .texture.image = acc_img });
    simg_view = sg_make_view(&sg_view_desc{ .storage_image.image = acc_img });

    g_tex_w = want_w;
    g_tex_h = want_h;
}

void init() {
    sg_setup(&sg_desc{
        .environment = sglue_environment(),
        .logger      = sglue_logger(),
    });

    tex_smp = sg_make_sampler(&sg_sampler_desc{
        .min_filter = SG_FILTER_LINEAR,
        .mag_filter = SG_FILTER_LINEAR,
    });
    rebuild_image();

    sg_shader compute_shd = sokol_make_shader(&trails_cs_shader);
    compute_pip = sg_make_pipeline(&sg_pipeline_desc{
        .compute = true,
        .shader  = compute_shd,
    });

    // fullscreen quad: x, y, u, v
    f32[24] quad = {
        -1.0f,  1.0f, 0.0f, 0.0f,
         1.0f,  1.0f, 1.0f, 0.0f,
         1.0f, -1.0f, 1.0f, 1.0f,
        -1.0f,  1.0f, 0.0f, 0.0f,
         1.0f, -1.0f, 1.0f, 1.0f,
        -1.0f, -1.0f, 0.0f, 1.0f,
    };
    quad_vbuf = sg_make_buffer(&sg_buffer_desc{
        .data.ptr  = &quad,
        .data.size = sizeof(quad),
    });

    sg_shader render_shd = sokol_make_shader(&quad_vs_shader, &quad_fs_shader);
    render_pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = render_shd,
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT2,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT2,
    });
}

void frame() {
    f32 dt = frame_dt();
    if dt > 0.1f { dt = 0.1f; }
    g_time = g_time + dt;

    sg_begin_pass(&sg_pass{ .compute = true });
    sg_apply_pipeline(compute_pip);

    sg_apply_bindings(&sg_bindings{ .views[0] = simg_view });

    f32 dpi = sapp_dpi_scale();
    f32[4] ub_data = { g_time, dpi, 0f, 0f };
    sg_apply_uniforms(0, &sg_range{
        .ptr  = &ub_data,
        .size = sokol_uniform_size(&trails_cs_shader, 0),
    });
    sg_dispatch(g_tex_w / 8, g_tex_h / 8, 1);
    sg_end_pass();

    sg_begin_pass(&sg_pass{
        .action.colors[0].load_action = SG_LOADACTION_CLEAR,
        .action.colors[0].clear_value = sg_color{ 0.0f, 0.0f, 0.0f, 1.0f },
        .swapchain = sglue_swapchain(),
    });
    sg_apply_pipeline(render_pip);

    sg_apply_bindings(&sg_bindings{
        .vertex_buffers[0] = quad_vbuf,
        .views[0]          = tex_view,
        .samplers[0]       = tex_smp,
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
        rebuild_image();
    }
}

sapp_desc sokol_main() {
    return sapp_desc{
        .init_cb    = init,
        .frame_cb   = frame,
        .cleanup_cb = cleanup,
        .event_cb   = on_event,
        .width      = 512,
        .height     = 512,
        .high_dpi   = true,
        .icon.sokol_default = true,
        .window_title = "Compute RW Image — fading trails",
    };
}
