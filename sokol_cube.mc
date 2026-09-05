// sokol_cube.mc — rotating cube with an SDF "mc" logo on each face.

import sokol_all;
import math;
import linear;
// Shader live reload; no-ops unless built with -DSHADER_LIVE=1
// (`minc run --shader-live sokol_cube.mc`).
import shader_live;

// --- Shaders ---

struct VsOut {
    float4 pos;
    float4 color;
    float2 uv;
    f32 time;
}

@shader vertex
VsOut cube_vs(
    @attr(0) float4 position,
    @attr(1) float4 color,
    @attr(2) float2 uv,
    @uniform float4x4 mvp,
    @uniform float4 params
) {
    VsOut o;
    o.pos = mul(mvp, position);
    o.color = color;
    o.uv = uv;
    o.time = params.x;
    return o;
}

@shader fragment
float4 cube_fs(VsOut input) {
    f32 t = input.time;
    f32 cu = input.uv.x - 0.5f;
    f32 cv = (1.0f - input.uv.y) - 0.5f;
    f32 sa = sin(t);
    f32 ca = cos(t);
    f32 u = cu * ca - cv * sa + 0.5f;
    f32 v = cu * sa + cv * ca + 0.5f;

    // "m" and "c" are 0.18 wide with a 0.06 gap: 0.42 total, centred
    // at 0.5, so "m" starts at 0.29.
    f32 mx = u - 0.29f;
    f32 my = v - 0.5f;
    f32 sw = 0.035f;      // stroke width
    f32 h = 0.15f;        // half height
    f32 m1 = max(abs(mx) - sw, abs(my) - h);
    f32 m2 = max(abs(mx - 0.09f) - sw, abs(my) - h);
    f32 m3 = max(abs(mx - 0.18f) - sw, abs(my) - h);
    f32 m4 = max(abs(mx - 0.045f) - 0.055f, abs(my + h - sw) - sw);
    f32 m5 = max(abs(mx - 0.135f) - 0.055f, abs(my + h - sw) - sw);
    f32 md = min(min(min(m1, m2), min(m3, m4)), m5);

    // "c": three sides of a box
    f32 cx = u - 0.62f;   // center of "c": 0.29 + 0.18 + 0.06 + 0.09 = 0.62
    f32 cy = v - 0.5f;
    f32 cw = 0.09f;       // half width of "c"
    // Top bar
    f32 ct = max(abs(cx) - cw, abs(cy - h + sw) - sw);
    // Bottom bar
    f32 cb = max(abs(cx) - cw, abs(cy + h - sw) - sw);
    // Left bar
    f32 cl = max(abs(cx + cw - sw) - sw, abs(cy) - h);
    f32 cd = min(min(ct, cb), cl);

    f32 letter = min(md, cd);
    // smaller value => sharper edge
    f32 text = smoothstep(0.002f, -0.002f, letter);

    // White text on face color
    f32 r = mix(input.color.x, 1.0f, text);
    f32 g = mix(input.color.y, 1.0f, text);
    f32 b = mix(input.color.z, 1.0f, text);

    return float4{r, g, b, 1.0f};
}


// --- globals

sg_pipeline g_pip;
sg_buffer g_vbuf;
sg_buffer g_ibuf;
float4 g_rot;
f32 g_time;

i32 quad([]i32 idx, i32 i, i32 a, i32 b, i32 c, i32 d) {
    idx[i..] = { a, b, c, a, c, d };
    return i + 6;
}

// Vertex: pos(4) + color(4) + uv(2) = 10 floats
i32 vert([]f32 buf, i32 i, f32 x, f32 y, f32 z, f32 r, f32 g, f32 b, f32 u, f32 v) {
    buf[i..] = { x, y, z, 1.0f, r, g, b, 1.0f, u, v };
    return i + 10;
}

i32 face([]f32 buf, i32 i, f32 x0, f32 y0, f32 z0,
                            f32 x1, f32 y1, f32 z1,
                            f32 x2, f32 y2, f32 z2,
                            f32 x3, f32 y3, f32 z3,
                            f32 r, f32 g, f32 b, 
                            bool flip) {
    f32 u0 = 0.0f; f32 u1 = 1.0f;
    if flip { u0 = 1.0f; u1 = 0.0f; }
    i = vert(buf, i, x0,y0,z0, r,g,b, u0, 0.0f);
    i = vert(buf, i, x1,y1,z1, r,g,b, u1, 0.0f);
    i = vert(buf, i, x2,y2,z2, r,g,b, u1, 1.0f);
    i = vert(buf, i, x3,y3,z3, r,g,b, u0, 1.0f);
    return i;
}


// --- sokol callbacks

void init() {
    sg_setup(&sg_desc{ .environment = sglue_environment(), .logger = sglue_logger() });

    f32 s = 0.5f;
    f32[6 * 4 * 10] v;
    i32 vi = 0;
    vi = face(v, vi, -s,-s,-s,  s,-s,-s,  s, s,-s, -s, s,-s, 1.0f, 0.2f, 0.2f, flip: true);  // front
    vi = face(v, vi, -s,-s, s,  s,-s, s,  s, s, s, -s, s, s, 0.2f, 1.0f, 0.2f, flip: false); // back
    vi = face(v, vi, -s,-s,-s, -s, s,-s, -s, s, s, -s,-s, s, 0.2f, 0.5f, 1.0f, flip: true);  // left
    vi = face(v, vi,  s,-s,-s,  s, s,-s,  s, s, s,  s,-s, s, 1.0f, 0.6f, 0.2f, flip: false); // right
    vi = face(v, vi, -s,-s,-s, -s,-s, s,  s,-s, s,  s,-s,-s, 1.0f, 1.0f, 0.2f, flip: true);  // bottom
    vi = face(v, vi, -s, s,-s, -s, s, s,  s, s, s,  s, s,-s, 0.6f, 0.2f, 1.0f, flip: false); // top

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

    sg_shader shd = sokol_make_shader(&cube_vs_shader, &cube_fs_shader);
    sg_pipeline_desc pip_desc = sg_pipeline_desc{
        .shader = shd,
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT4,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT4,
        .layout.attrs[2].format = SG_VERTEXFORMAT_FLOAT2,
        .index_type = SG_INDEXTYPE_UINT32,
        .cull_mode = SG_CULLMODE_BACK,
        .depth.compare = SG_COMPAREFUNC_LESS_EQUAL,
        .depth.write_enabled = true,
    };
    g_pip = sg_make_pipeline(&pip_desc);
    g_rot = quat_identity();

    shader_live_init();
    shader_live_register(&g_pip, &pip_desc, &cube_vs_shader, &cube_fs_shader);
}

void frame() {
    shader_live_frame();

    f32 dt = cast(f32, sapp_frame_duration());
    g_time = g_time + dt;
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

    float4 params = {g_time, 0.0f, 0.0f, 0.0f};

    sg_begin_pass(&sg_pass{
      .swapchain = sglue_swapchain(),
      .action.colors[0].load_action = SG_LOADACTION_CLEAR,
      .action.colors[0].clear_value = sg_color{ 0.1f, 0.1f, 0.2f, 1.0f },
    });

    sg_apply_pipeline(g_pip);
    sg_apply_bindings(&sg_bindings{
        .vertex_buffers[0] = g_vbuf, .index_buffer = g_ibuf,
    });
    sg_apply_uniforms(0, &sg_range{ .ptr = &mvp, .size = sizeof(mvp) });
    sg_apply_uniforms(1, &sg_range{ .ptr = &params, .size = sizeof(params) });
    sg_draw(0, 36, 1);

    sg_end_pass();
    sg_commit();
}

void on_event(sapp_event* ev) {
    if ev.type == SAPP_EVENTTYPE_QUIT_REQUESTED { 
        sapp_request_quit(); 
    }
    return;
}

void cleanup() { sg_shutdown(); }

sapp_desc sokol_main() {
    return sapp_desc{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = on_event,
        .width = 800,
        .height = 600,
        .high_dpi = true,
        .icon.sokol_default = true,
        .window_title = "sokol cube",
    };
}
