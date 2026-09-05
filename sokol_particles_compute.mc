// sokol_particles_compute.mc — @rwbuffer storage buffers.
//
// 1024 particles bounce inside the viewport; a compute shader updates
// them in place through `@rwbuffer(0) []Particle`.

when os(wasm) { 
    @gpu "webgpu" 
    @define "SOKOL_WGPU" 
}

import sokol_all;
import math;

// --- Particle state (16 bytes per particle) ---

struct Particle {
    f32 px;
    f32 py;
    f32 vx;
    f32 vy;
}

const i32 N_PARTICLES = 1024;
const f32 PARTICLE_SIZE = 0.012f;   // half-extent in NDC

// --- Shaders ---

// Advance each particle and bounce it off the [-1, 1] walls.
@shader compute(64, 1, 1)
void update_cs(@rwbuffer(0) []Particle particles, @uniform f32 u_dt) {
    u32 id = thread_id().x;
    Particle p = particles[id];
    p.px = p.px + p.vx * u_dt;
    p.py = p.py + p.vy * u_dt;
    if p.px < -1.0f { p.px = -1.0f; p.vx = -p.vx; }
    if p.px >  1.0f { p.px =  1.0f; p.vx = -p.vx; }
    if p.py < -1.0f { p.py = -1.0f; p.vy = -p.vy; }
    if p.py >  1.0f { p.py =  1.0f; p.vy = -p.vy; }
    particles[id] = p;
}

struct PointVsOut {
    float4 pos;
}

@shader vertex
PointVsOut point_vs(@attr(0) float2 corner, @attr(1) float2 pos,
                    @uniform float4 u_corner_scale) {
    PointVsOut o;
    o.pos = float4{pos.x + corner.x * u_corner_scale.x,
                   pos.y + corner.y * u_corner_scale.y,
                   0.0f, 
                   1.0f};
    return o;
}

@shader fragment
float4 point_fs(PointVsOut input) {
    return float4{1.0f, 1.0f, 1.0f, 1.0f};
}

// --- App state ---

sg_buffer particle_buf;        // particle data — also bound as instance vbuf
sg_view   particle_sbv;        // storage-buffer view for the compute @rwbuffer
sg_buffer quad_vbuf;           // 4 corners of one quad (per-vertex)
sg_buffer quad_ibuf;           // 6 indices for the quad's two triangles
sg_pipeline compute_pip;
sg_pipeline render_pip;

// xorshift32: deterministic init
u32 _xor32(u32 s) {
    s = s ^ (s << 13);
    s = s ^ (s >> 17);
    s = s ^ (s << 5);
    return s;
}

f32 _rand_unit(u32* state) {
    *state = _xor32(*state);
    return cast(f32, cast(i32, *state >> 8) & 0xFFFF) / 32768.0f - 1.0f;
}

void init() {
    sg_setup(&sg_desc{
        .environment = sglue_environment(),
        .logger = sglue_logger(),
    });

    // Initial particle state; sg_make_buffer copies it.
    noinit Particle[N_PARTICLES] init_data;
    u32 rng = 0x9E3779B9;
    for i32 i = 0; i < N_PARTICLES; i++ {
        f32 angle = cast(f32, i) * (6.2831853f / cast(f32, N_PARTICLES));
        init_data[i].px = 0.5f * cosf(angle);
        init_data[i].py = 0.5f * sinf(angle);
        init_data[i].vx = 0.5f * _rand_unit(&rng);
        init_data[i].vy = 0.5f * _rand_unit(&rng);
    }

    // One buffer serves as compute storage buffer and per-instance
    // vertex buffer. A read/write storage buffer must be immutable.
    particle_buf = sg_make_buffer(&sg_buffer_desc{
        .usage.storage_buffer = true,
        .usage.vertex_buffer  = true,
        .usage.immutable      = true,
        .size      = sizeof(init_data),
        .data.ptr  = &init_data,
        .data.size = sizeof(init_data),
    });

    // view for the compute pass
    particle_sbv = sg_make_view(&sg_view_desc{ .storage_buffer.buffer = particle_buf });

    // quad corners, vertex buffer slot 0
    f32[8] corners = {
        -PARTICLE_SIZE, -PARTICLE_SIZE,
         PARTICLE_SIZE, -PARTICLE_SIZE,
        -PARTICLE_SIZE,  PARTICLE_SIZE,
         PARTICLE_SIZE,  PARTICLE_SIZE
    };
    quad_vbuf = sg_make_buffer(&sg_buffer_desc{
        .data.ptr  = &corners,
        .data.size = cast(i64, sizeof(corners)),
    });

    // two triangles per quad
    u16[6] indices;
    indices[0] = 0; indices[1] = 1; indices[2] = 2;
    indices[3] = 2; indices[4] = 1; indices[5] = 3;
    quad_ibuf = sg_make_buffer(&sg_buffer_desc{
        .usage.index_buffer = true,
        .data.ptr  = &indices,
        .data.size = cast(i64, sizeof(indices)),
    });

    sg_shader compute_shd = sokol_make_shader(&update_cs_shader);
    compute_pip = sg_make_pipeline(&sg_pipeline_desc{
        .compute = true,
        .shader  = compute_shd,
    });

    // slot 0: per-vertex corners; slot 1: per-instance particles
    sg_shader render_shd = sokol_make_shader(&point_vs_shader, &point_fs_shader);
    render_pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = render_shd,
        .layout.buffers[0].stride    = cast(i32, sizeof(f32) * 2),
        .layout.buffers[0].step_func = SG_VERTEXSTEP_PER_VERTEX,
        .layout.buffers[1].stride    = cast(i32, sizeof(Particle)),
        .layout.buffers[1].step_func = SG_VERTEXSTEP_PER_INSTANCE,
        .layout.attrs[0].buffer_index = 0,
        .layout.attrs[0].format       = SG_VERTEXFORMAT_FLOAT2,
        .layout.attrs[1].buffer_index = 1,
        .layout.attrs[1].format       = SG_VERTEXFORMAT_FLOAT2,
        .index_type = SG_INDEXTYPE_UINT16,
    });
}

void frame() {
    f32 dt = cast(f32, sapp_frame_duration());

    // compute pass: advance particles in place
    sg_begin_pass(&sg_pass{ .compute = true });
    sg_apply_pipeline(compute_pip);

    sg_apply_bindings(&sg_bindings{ .views[0] = particle_sbv });

    f32[4] ub_data;
    ub_data[0] = dt;
    sg_apply_uniforms(0, &sg_range{
        .ptr  = &ub_data,
        .size = sokol_uniform_size(&update_cs_shader, 0),
    });
    sg_dispatch(N_PARTICLES / 64, 1, 1);
    sg_end_pass();

    // render pass: the particle buffer as instance data
    sg_begin_pass(&sg_pass{
        .action.colors[0].load_action = SG_LOADACTION_CLEAR,
        .action.colors[0].clear_value = sg_color{ 0.05f, 0.05f, 0.1f, 1.0f },
        .swapchain = sglue_swapchain(),
    });
    sg_apply_pipeline(render_pip);

    sg_apply_bindings(&sg_bindings{
        .vertex_buffers[0] = quad_vbuf,
        .vertex_buffers[1] = particle_buf,
        .index_buffer      = quad_ibuf,
    });

    // u_corner_scale = min(w,h) / (w,h) keeps the quads square at any
    // aspect ratio.
    f32 fw = cast(f32, sapp_width());
    f32 fh = cast(f32, sapp_height());
    f32 mn = fw;
    if fh < mn { mn = fh; }
    f32[4] vs_ub;
    vs_ub[0] = mn / fw;
    vs_ub[1] = mn / fh;
    vs_ub[2] = 0.0f;
    vs_ub[3] = 0.0f;
    sg_apply_uniforms(0, &sg_range{
        .ptr  = &vs_ub,
        .size = sokol_uniform_size(&point_vs_shader, 0),
    });
    sg_draw(0, 6, N_PARTICLES);
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
        .init_cb    = init,
        .frame_cb   = frame,
        .cleanup_cb = cleanup,
        .event_cb   = on_event,
        .width      = 512,
        .height     = 512,
        .high_dpi   = true,
        .icon.sokol_default = true,
        .window_title = "Compute Particles — @rwbuffer test",
    };
}
