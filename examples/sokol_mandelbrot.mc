// sokol_mandelbrot.mc — Animated Mandelbrot via fragment shader.
//

import sokol_all;
import math;

// --- Shaders ---

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

// Fragment shader: animated Mandelbrot.
//
// u_params.x = u_time   seconds since start (loops every 16 s)
// u_params.y = u_aspect viewport width/height (for aspect-correct
//              c-plane mapping on non-square framebuffers)
//
// Packed into a single float4 uniform so the cbuffer slice stays on
// the 16-byte boundary every backend expects.
@shader fragment
float4 mandelbrot_fs(QuadVsOut input, @uniform float4 u_params) {
    f32 u_time   = u_params.x;
    f32 u_aspect = u_params.y;
    float2 uv = input.uv;

    // Aspect-correct mapping: width is constant along the shorter
    // axis, stretched along the longer one.
    f32 ar_x = 1.0f;
    f32 ar_y = 1.0f;
    if u_aspect >= 1.0f { ar_x = u_aspect; }
    else                { ar_y = 1.0f / u_aspect; }

    // Loop the time so the demo restarts once the zoom hits its end
    // point.
    f32 LOOP    = 16.0f;
    f32 t_loop  = u_time - floor(u_time / LOOP) * LOOP;
    f32 TARGET_CX = -0.7756838f;
    f32 TARGET_CY = 0.1364674f;
    f32 width = 4.0f * pow(0.6f, t_loop);

    float2 c = float2{TARGET_CX + (uv.x - 0.5f) * width * ar_x,
                      TARGET_CY + (uv.y - 0.5f) * width * ar_y};

    // Iteration budget grows with zoom (capped at 256).
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
    // Rainbow coloring via phase-shifted cosines.
    f32 r = 0.5f + 0.5f * cos(6.28f * (t * 2.0f + phase));
    f32 g = 0.5f + 0.5f * cos(6.28f * (t * 2.0f + phase + 0.33f));
    f32 b = 0.5f + 0.5f * cos(6.28f * (t * 2.0f + phase + 0.67f));
    if n >= cast(f32, iter_max) { r = 0.0f; g = 0.0f; b = 0.0f; }
    return float4{r, g, b, 1.0f};
}

// --- App state ---

sg_buffer quad_vbuf;
sg_pipeline render_pip;
f32 g_time = 0.0f;

void init() {
    sg_setup(&sg_desc{
        .environment = sglue_environment(),
        .logger = sglue_logger(),
    });

    // Fullscreen quad: 6 verts (two triangles), each carries NDC
    // position + uv passthrough for the fragment-shader Mandelbrot.
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

    sg_shader shd = sokol_make_shader(&quad_vs_shader, &mandelbrot_fs_shader);

    render_pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = shd,
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT2,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT2,
    });
}

void frame() {
    g_time = g_time + cast(f32, sapp_frame_duration());

    sg_begin_pass(&sg_pass{
        .action.colors[0].load_action = SG_LOADACTION_CLEAR,
        .action.colors[0].clear_value = sg_color{ 0.0f, 0.0f, 0.0f, 1.0f },
        .swapchain = sglue_swapchain(),
    });
    sg_apply_pipeline(render_pip);

    sg_apply_bindings(&sg_bindings{ .vertex_buffers[0] = quad_vbuf });

    // Uniforms: time + aspect packed into a float4 (z/w unused).
    f32 aspect = 1.0f;
    if sapp_height() > 0 {
        aspect = cast(f32, sapp_width()) / cast(f32, sapp_height());
    }
    float4 u_params = float4{g_time, aspect, 0.0f, 0.0f};
    sg_apply_uniforms(0, &sg_range{
        .ptr = &u_params,
        .size = sokol_uniform_size(&mandelbrot_fs_shader, 0),
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
        .window_title = "Mandelbrot — Fragment Shader",
    };
}
