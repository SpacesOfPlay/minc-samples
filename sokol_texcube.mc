// Sokol textured cube

import sokol_all;
import math;
import linear;
import zlib;
import file;
import png;


// --- Shaders (compiled to HLSL/MSL/GLSL automatically) ---

struct VsOut {
    float4 pos;
    float2 uv;
}

@shader vertex
VsOut texcube_vs(
    @attr(0) float4 position,
    @attr(1) float2 uv,
    @uniform float4x4 mvp
) {
    VsOut o;
    o.pos = mul(mvp, position);
    o.uv = uv;
    return o;
}

@shader fragment
float4 texcube_fs(
    VsOut input,
    @texture(0) Texture2D tex,
    @sampler(0) Sampler smp
) {
    return sample(tex, smp, input.uv);
}


// --- globals

sg_pipeline g_pip;
sg_buffer g_vbuf;
sg_buffer g_ibuf;
sg_view g_tex_view;
sg_sampler g_smp;
float4 g_rot;


// --- vertex / index buffer helpers (mirrors sokol_cube.mc patterns) ---

i32 quad([]i32 idx, i32 i, i32 a, i32 b, i32 c, i32 d) {
    idx[i..] = { a, b, c, a, c, d };
    return i + 6;
}

// Vertex layout: pos(4) + uv(2) = 6 floats. w=1 baked into the buffer
// matches the `@attr(0) float4 position` shader input.
i32 vert([]f32 buf, i32 i, f32 x, f32 y, f32 z, f32 u, f32 v) {
    buf[i..] = { x, y, z, 1.0f, u, v };
    return i + 6;
}

i32 face([]f32 buf, i32 i, f32 x0, f32 y0, f32 z0,
                            f32 x1, f32 y1, f32 z1,
                            f32 x2, f32 y2, f32 z2,
                            f32 x3, f32 y3, f32 z3,
                            bool flip) {
    f32 u0 = 0.0f; f32 u1 = 1.0f;
    if flip { u0 = 1.0f; u1 = 0.0f; }
    i = vert(buf, i, x0, y0, z0, u0, 0.0f);
    i = vert(buf, i, x1, y1, z1, u1, 0.0f);
    i = vert(buf, i, x2, y2, z2, u1, 1.0f);
    i = vert(buf, i, x3, y3, z3, u0, 1.0f);
    return i;
}


// --- sokol callbacks ---

void init() {
    sg_setup(&sg_desc{ .environment = sglue_environment(), .logger = sglue_logger() });

    // Load + decode PNG.
    FileData fd;
    fd.data = null;
    fd.len = 0;
    when os(android) {
        minc_android_load_asset("blue_marble_256.png", &fd);
    }
    when os(macos) || os(ios) {
        string path = str_concat(str_from_cstr(minc_get_bundle_path()), "/test/blue_marble_256.png");
        fd = file_read(path);
        free(path);
    }
    when os(linux) || os(windows) || os(wasm) {
        fd = file_read("test/blue_marble_256.png");
    }
    PngImage tex = png_decode(fd.data, fd.len);
    free(fd.data);
    print("texture loaded: {}x{}\n", tex.width, tex.height);

    sg_image img = sg_make_image(&sg_image_desc{
        .width = tex.width, .height = tex.height,
        .pixel_format = SG_PIXELFORMAT_RGBA8,
        .data.mip_levels[0].ptr = tex.pixels,
        .data.mip_levels[0].size = tex.width * tex.height * 4,
        .usage.immutable = true,
    });

    g_tex_view = sg_make_view(&sg_view_desc{ .texture.image = img });

    // Nearest-neighbour sampling.
    g_smp = sg_make_sampler(&sg_sampler_desc{
        .min_filter = SG_FILTER_NEAREST,
        .mag_filter = SG_FILTER_NEAREST,
        .wrap_u = SG_WRAP_CLAMP_TO_EDGE,
        .wrap_v = SG_WRAP_CLAMP_TO_EDGE,
    });

    // --- Vertex / index buffers ---
    f32 p = 0.5f;
    f32 n = -p;
    f32[6 * 4 * 6] v;
    i32 vi = 0;
    vi = face(v, vi, n,n,n,  p,n,n,  p,p,n, n,p,n, flip: true);   // front
    vi = face(v, vi, n,n,p,  p,n,p,  p,p,p, n,p,p, flip: false);  // back
    vi = face(v, vi, n,n,n,  n,p,n,  n,p,p, n,n,p, flip: true);   // left
    vi = face(v, vi, p,n,n,  p,p,n,  p,p,p, p,n,p, flip: false);  // right
    vi = face(v, vi, n,n,n,  n,n,p,  p,n,p, p,n,n, flip: true);   // bottom
    vi = face(v, vi, n,p,n,  n,p,p,  p,p,p, p,p,n, flip: false);  // top

    g_vbuf = sg_make_buffer(&sg_buffer_desc{ .data.ptr = &v, .data.size = sizeof(v) });

    i32[36] idx;
    i32 ii = 0;
    ii = quad(idx, ii,  0, 1, 2, 3);
    ii = quad(idx, ii,  6, 5, 4, 7);
    ii = quad(idx, ii,  8, 9,10,11);
    ii = quad(idx, ii, 14,13,12,15);
    ii = quad(idx, ii, 16,17,18,19);
    ii = quad(idx, ii, 22,21,20,23);

    g_ibuf = sg_make_buffer(&sg_buffer_desc{
        .usage.index_buffer = true, .data.ptr = &idx, .data.size = sizeof(idx),
    });

    // Shader + pipeline. sokol_make_shader populates the texture +
    // sampler bindings from the @shader-emitted ShaderMeta tables.
    sg_shader shd = sokol_make_shader(&texcube_vs_shader, &texcube_fs_shader);
    g_pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = shd,
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT4,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT2,
        .index_type = SG_INDEXTYPE_UINT32,
        .cull_mode = SG_CULLMODE_BACK,
        .depth.compare = SG_COMPAREFUNC_LESS_EQUAL,
        .depth.write_enabled = true,
    });

    g_rot = quat_identity();
}

void frame() {
    f32 dt = cast(f32, sapp_frame_duration());
    float4 qx = quat_axis_angle(float3{1.0f, 0.0f, 0.0f}, 0.3f * dt);
    float4 qy = quat_axis_angle(float3{0.0f, 1.0f, 0.0f}, 0.7f * dt);
    g_rot = normalize(quat_mul(quat_mul(qy, qx), g_rot));

    f32 aspect = sapp_widthf() / sapp_heightf();
    float4x4 proj = perspective(60.0f * PI_F / 180.0f, aspect, 0.01f, 10.0f);
    float3 eye = {0.0f, 1.0f, 2.0f};
    float3 tgt = {0.0f, 0.0f, 0.0f};
    float3 up  = {0.0f, 1.0f, 0.0f};
    float4x4 view = look_at(eye, tgt, up);
    float4x4 mvp = mul(mul(proj, view), quat_to_mat4(g_rot));

    sg_begin_pass(&sg_pass{
      .swapchain = sglue_swapchain(),
      .action.colors[0].load_action = SG_LOADACTION_CLEAR,
      .action.colors[0].clear_value = sg_color{ 0.2f, 0.3f, 0.4f, 1.0f },
    });

    sg_apply_pipeline(g_pip);
    sg_apply_bindings(&sg_bindings{
        .vertex_buffers[0] = g_vbuf, .index_buffer = g_ibuf,
        .views[0] = g_tex_view, .samplers[0] = g_smp,
    });
    sg_apply_uniforms(0, &sg_range{ .ptr = &mvp, .size = sizeof(mvp) });
    sg_draw(0, 36, 1);

    sg_end_pass();
    sg_commit();
}

void on_event(sapp_event* ev) {
    if ev.type == SAPP_EVENTTYPE_QUIT_REQUESTED { sapp_request_quit(); }
    return;
}

void cleanup() { sg_shutdown(); }

sapp_desc sokol_main() {
    return sapp_desc{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = on_event,
        .width = 800, .height = 600, .high_dpi = true,
        .icon.sokol_default = true,
        .window_title = "sokol textured cube",
    };
}
