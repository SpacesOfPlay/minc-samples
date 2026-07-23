// Bouncing sphere physics — CPU vector math features

import sokol_all;
import math;
import linear;

// --- Constants ---
const i32 NUM_SPHERES   = 256;
const f32 GRAVITY       = -9.8f;
const f32 RESTITUTION   =   .7f;
const f32 WALL_X        =  3.75f;
const f32 WALL_Z        =  3.75f;
const f32 FLOOR_Y       = -2.0f;
const f32 CEILING_Y     = 17.0f;

// --- Sphere state (float4-packed for SIMD) ---
float4[NUM_SPHERES] g_pos_r;     // xyz=position, w=radius
float4[NUM_SPHERES] g_vel_m;     // xyz=velocity, w=mass
float4[NUM_SPHERES] g_color;

// --- Icosphere mesh (smooth shading — flat vertex array) ---
// For a unit sphere, vertex normal = vertex position (already normalized)
// Vertex format: float3 pos + float3 normal = 24 bytes per vertex
// 2 subdivisions → 320 faces × 3 verts = 960 flat vertices
f32[960 * 6] g_sphere_verts;  // 960 flat verts × 6 floats (pos+normal)
i32 g_sphere_nverts;

// Temp arrays for icosphere subdivision (indexed, before flattening)
f32[320 * 3] g_tmp_verts;    // up to 312 unique positions × 3 floats
i32[960] g_tmp_idx;          // up to 320 faces × 3 indices
i32 g_tmp_nv;
i32 g_tmp_ni;

void ico_normalize3(f32* x, f32* y, f32* z) {
    f32 len = sqrtf(*x * *x + *y * *y + *z * *z);
    if len > 0.0f { *x = *x / len; *y = *y / len; *z = *z / len; }
}
i32 ico_add_vert(f32 x, f32 y, f32 z) {
    ico_normalize3(&x, &y, &z);
    i32 i = g_tmp_nv * 3;
    g_tmp_verts[i] = x; g_tmp_verts[i+1] = y; g_tmp_verts[i+2] = z;
    g_tmp_nv++;
    return g_tmp_nv - 1;
}
void ico_add_tri(i32 a, i32 b, i32 c) {
    g_tmp_idx[g_tmp_ni] = a; g_tmp_idx[g_tmp_ni+1] = b; g_tmp_idx[g_tmp_ni+2] = c;
    g_tmp_ni = g_tmp_ni + 3;
}
i32 ico_midpoint(i32 a, i32 b) {
    f32 ax = g_tmp_verts[a*3]; f32 ay = g_tmp_verts[a*3+1]; f32 az = g_tmp_verts[a*3+2];
    f32 bx = g_tmp_verts[b*3]; f32 by = g_tmp_verts[b*3+1]; f32 bz = g_tmp_verts[b*3+2];
    return ico_add_vert((ax+bx)*.5f, (ay+by)*.5f, (az+bz)*.5f);
}

void build_sphere_mesh() {
    // Build icosphere with shared vertices (smooth shading)
    // For unit sphere, normal = vertex position (already normalized)
    g_tmp_nv = 0; g_tmp_ni = 0;
    f32 t = cast(f32, (1.0 + sqrt(5.0)) / 2.0);
    ico_add_vert(-1.0f, t, 0.0f); ico_add_vert(1.0f, t, 0.0f);
    ico_add_vert(-1.0f, -t, 0.0f); ico_add_vert(1.0f, -t, 0.0f);
    ico_add_vert(0.0f, -1.0f, t); ico_add_vert(0.0f, 1.0f, t);
    ico_add_vert(0.0f, -1.0f, -t); ico_add_vert(0.0f, 1.0f, -t);
    ico_add_vert(t, 0.0f, -1.0f); ico_add_vert(t, 0.0f, 1.0f);
    ico_add_vert(-t, 0.0f, -1.0f); ico_add_vert(-t, 0.0f, 1.0f);
    ico_add_tri(0,11,5); ico_add_tri(0,5,1); 
    ico_add_tri(0,1,7); ico_add_tri(0,7,10); 
    ico_add_tri(0,10,11); ico_add_tri(1,5,9); 
    ico_add_tri(5,11,4); ico_add_tri(11,10,2); 
    ico_add_tri(10,7,6); ico_add_tri(7,1,8);
    ico_add_tri(3,9,4); ico_add_tri(3,4,2); 
    ico_add_tri(3,2,6); ico_add_tri(3,6,8); 
    ico_add_tri(3,8,9); ico_add_tri(4,9,5); 
    ico_add_tri(2,4,11); ico_add_tri(6,2,10); 
    ico_add_tri(8,6,7); ico_add_tri(9,8,1);
    // Subdivide twice for smoother spheres
    for i32 sub = 0; sub < 2; sub++ {
        i32[960] new_idx;
        i32 ni = 0;
        for i32 f = 0; f < g_tmp_ni; f = f + 3 {
            i32 a = g_tmp_idx[f]; i32 b = g_tmp_idx[f+1]; i32 c = g_tmp_idx[f+2];
            i32 ab = ico_midpoint(a, b); i32 bc = ico_midpoint(b, c); i32 ca = ico_midpoint(c, a);
            new_idx[ni]=a; new_idx[ni+1]=ab; new_idx[ni+2]=ca; ni=ni+3;
            new_idx[ni]=b; new_idx[ni+1]=bc; new_idx[ni+2]=ab; ni=ni+3;
            new_idx[ni]=c; new_idx[ni+1]=ca; new_idx[ni+2]=bc; ni=ni+3;
            new_idx[ni]=ab; new_idx[ni+1]=bc; new_idx[ni+2]=ca; ni=ni+3;
        }
        g_tmp_ni = ni;
        for i32 i = 0; i < ni; i++ { g_tmp_idx[i] = new_idx[i]; }
    }
    // Flatten indexed mesh to flat vertex array with smooth normals
    // For unit sphere, normal = position (already normalized)
    i32 nfaces = g_tmp_ni / 3;
    g_sphere_nverts = nfaces * 3;
    for i32 f = 0; f < nfaces; f++ {
        i32 a = g_tmp_idx[f*3]; i32 b = g_tmp_idx[f*3+1]; i32 c = g_tmp_idx[f*3+2];
        i32 o = f * 18;  // 3 verts × 6 floats
        g_sphere_verts[o]    = g_tmp_verts[a*3]; g_sphere_verts[o+1]  = g_tmp_verts[a*3+1]; g_sphere_verts[o+2]  = g_tmp_verts[a*3+2];
        g_sphere_verts[o+3]  = g_tmp_verts[a*3]; g_sphere_verts[o+4]  = g_tmp_verts[a*3+1]; g_sphere_verts[o+5]  = g_tmp_verts[a*3+2];
        g_sphere_verts[o+6]  = g_tmp_verts[b*3]; g_sphere_verts[o+7]  = g_tmp_verts[b*3+1]; g_sphere_verts[o+8]  = g_tmp_verts[b*3+2];
        g_sphere_verts[o+9]  = g_tmp_verts[b*3]; g_sphere_verts[o+10] = g_tmp_verts[b*3+1]; g_sphere_verts[o+11] = g_tmp_verts[b*3+2];
        g_sphere_verts[o+12] = g_tmp_verts[c*3]; g_sphere_verts[o+13] = g_tmp_verts[c*3+1]; g_sphere_verts[o+14] = g_tmp_verts[c*3+2];
        g_sphere_verts[o+15] = g_tmp_verts[c*3]; g_sphere_verts[o+16] = g_tmp_verts[c*3+1]; g_sphere_verts[o+17] = g_tmp_verts[c*3+2];
    }
    return;
}

// --- PRNG ---
u32 g_rng = 98765;
f32 randf() {
    g_rng = g_rng ^ (g_rng << 13);
    g_rng = g_rng ^ (g_rng >> 17);
    g_rng = g_rng ^ (g_rng << 5);
    return cast(f32, g_rng & 65535) / 65535.0f;
}

// --- Vertex / instance data layouts ---
struct MeshVertex {
    float3 pos;
    float3 normal;
}

struct InstanceData {
    float4 pos_r;
    u8 r, g, b, a;      // UBYTE4N color
}

// --- Shaders ---

// Spotlight uniforms packed across two vec4s:
//   light_pos.xyz = world-space spotlight position
//   light_pos.w   = cos(outer cone angle) — cone hard cutoff
//   light_dir.xyz = normalized spot aim direction (unit vector pointing
//                   FROM the light toward what it illuminates)
//   light_dir.w   = cos(inner cone angle) — fully-lit centre
struct PerFrame {
    float4x4 mvp;
    float4 light_pos;
    float4 light_dir;
}

struct SphereVsOut {
    float4 pos;
    float4 color;
    float3 normal;
    float3 world_pos;
}

@shader vertex
SphereVsOut sphere_vs(
    @attr(0) float3 mesh_pos,
    @attr(1) float3 mesh_normal,
    @attr(2) float4 inst_pos_r,
    @attr(3) float4 inst_color,
    @uniform(0) PerFrame frame
) {
    // Scale mesh by radius, translate to instance position
    float3 world_pos = mesh_pos * inst_pos_r.w + inst_pos_r.xyz;
    SphereVsOut outp;
    outp.pos = mul(frame.mvp, float4{world_pos.x, world_pos.y, world_pos.z, 1.0f});
    outp.color = inst_color;
    outp.normal = mesh_normal;
    outp.world_pos = world_pos;
    return outp;
}

@shader fragment
float4 sphere_fs(SphereVsOut input, @uniform(0) PerFrame frame) {
    // Spotlight: cone-bounded point light. Inside the inner cone the
    // surface gets the full Lambert response; between inner and outer
    // it smooths to zero; outside the outer cone only ambient remains.
    float3 n = normalize(input.normal);
    float3 to_light = frame.light_pos.xyz - input.world_pos;
    f32 dist = length(to_light);
    float3 l = to_light / dist;

    // Cone factor: dot of (light-to-fragment) and aim direction.
    float3 spot_aim = normalize(frame.light_dir.xyz);
    f32 spot_cos = dot(-l, spot_aim);
    f32 cone = smoothstep(frame.light_pos.w, frame.light_dir.w, spot_cos);

    // Lambert + cone, no distance attenuation (scene is small).
    f32 ndl = max(dot(n, l), 0.0f);
    f32 ambient = .15f;
    f32 light = ambient + ndl * cone * 1.1f;
    float4 lit = input.color * light;
    lit.a = 1.0f;
    return lit;
}

// --- Floor shader (reuses SphereVsOut + sphere_fs for lighting) ---

@shader vertex
SphereVsOut floor_vs(
    @attr(0) float3 pos,
    @attr(1) float3 normal,
    @uniform(0) PerFrame frame
) {
    SphereVsOut outp;
    outp.pos = mul(frame.mvp, float4{pos.x, pos.y, pos.z, 1.0f});
    outp.color = float4{.3f, .3f, .35f, 1.0f};
    outp.normal = normal;
    outp.world_pos = pos;
    return outp;
}

// --- Shadow shader (flat disc projected onto floor, alpha-blended) ---

@shader vertex
SphereVsOut shadow_vs(
    @attr(0) float3 mesh_pos,
    @attr(1) float3 mesh_normal,
    @attr(2) float4 inst_pos_r,
    @attr(3) float4 inst_color,
    @uniform(0) PerFrame frame
) {
    // Place disc at sphere's xz position on the floor
    f32 r = inst_pos_r.w * .9f;
    float3 world_pos = float3{
        mesh_pos.x * r + inst_pos_r.x,
        -1.995f,
        mesh_pos.z * r + inst_pos_r.z
    };
    SphereVsOut outp;
    outp.pos = mul(frame.mvp, float4{world_pos.x, world_pos.y, world_pos.z, 1.0f});
    // Fade shadow with height: darker when sphere is closer to floor
    f32 h = inst_pos_r.y - inst_pos_r.w - (-2.0f);  // height above floor
    f32 alpha = .4f - h * .04f;
    if alpha < .05f { alpha = .05f; }
    // Fade shadow with the spotlight cone — no light reaching this
    // patch of floor means no shadow to cast. Also keeps the GLSL
    // linker from stripping light_pos/light_dir on the shadow program
    // (sokol would otherwise warn at shader-create time).
    float3 to_light = frame.light_pos.xyz - world_pos;
    float3 l = normalize(to_light);
    float3 spot_aim = normalize(frame.light_dir.xyz);
    f32 spot_cos = dot(-l, spot_aim);
    f32 cone = smoothstep(frame.light_pos.w, frame.light_dir.w, spot_cos);
    alpha = alpha * cone;
    outp.color = float4{0.0f, 0.0f, 0.0f, alpha};
    outp.normal = float3{0.0f, 1.0f, 0.0f};
    outp.world_pos = world_pos;
    return outp;
}

@shader fragment
float4 shadow_fs(SphereVsOut input) {
    return input.color;
}

// --- Shadow disc mesh ---
const i32 SHADOW_DISC_SEGS = 16;
f32[16 * 3 * 6] g_shadow_verts;  // 16 triangles × 3 verts × 6 floats
i32 g_shadow_nverts;

void build_shadow_disc() {
    f32 step = 2.0f * PI_F / cast(f32, SHADOW_DISC_SEGS);
    i32 vi = 0;
    for i32 i = 0; i < SHADOW_DISC_SEGS; i++ {
        f32 a0 = cast(f32, i) * step;
        f32 a1 = cast(f32, i + 1) * step;
        // Center vertex
        g_shadow_verts[vi]=0.0f; g_shadow_verts[vi+1]=0.0f; g_shadow_verts[vi+2]=0.0f;
        g_shadow_verts[vi+3]=0.0f; g_shadow_verts[vi+4]=1.0f; g_shadow_verts[vi+5]=0.0f;
        vi = vi + 6;
        // Edge vertex 0
        g_shadow_verts[vi]=cosf(a0); g_shadow_verts[vi+1]=0.0f; g_shadow_verts[vi+2]=sinf(a0);
        g_shadow_verts[vi+3]=0.0f; g_shadow_verts[vi+4]=1.0f; g_shadow_verts[vi+5]=0.0f;
        vi = vi + 6;
        // Edge vertex 1
        g_shadow_verts[vi]=cosf(a1); g_shadow_verts[vi+1]=0.0f; g_shadow_verts[vi+2]=sinf(a1);
        g_shadow_verts[vi+3]=0.0f; g_shadow_verts[vi+4]=1.0f; g_shadow_verts[vi+5]=0.0f;
        vi = vi + 6;
    }
    g_shadow_nverts = SHADOW_DISC_SEGS * 3;
    return;
}

// --- App state ---
sg_pipeline g_pip;
sg_pipeline g_floor_pip;
sg_pipeline g_shadow_pip;
sg_buffer g_mesh_buf;
sg_buffer g_inst_buf;
sg_buffer g_floor_buf;
sg_buffer g_shadow_buf;
f32 g_time;

void init_spheres() {
    // Color palette
    f32[8 * 3] palette = {
        0.94f, 0.27f, 0.30f,
        0.99f, 0.62f, 0.18f,
        0.99f, 0.85f, 0.20f,
        0.40f, 0.81f, 0.30f,
        0.30f, 0.70f, 0.85f,
        0.25f, 0.40f, 0.85f,
        0.65f, 0.30f, 0.85f,
        0.95f, 0.40f, 0.70f,
    };
    for i32 i = 0; i < NUM_SPHERES; i++ {
        f32 radius = .1f + randf() * .2f;
        f32 x = (randf() - .5f) * 4.0f;
        f32 y =  randf() * 8.0f + 1.0f;
        f32 z = (randf() - .5f) * 4.0f;
        g_pos_r[i] = float4{x, y, z, radius};

        f32 vx = (randf() - .5f) * 3.0f;
        f32 vy = randf() * 2.0f;
        f32 vz = (randf() - .5f) * 3.0f;
        g_vel_m[i] = float4{vx, vy, vz, 1.0f};

        i32 pi = (i % 8) * 3;
        g_color[i] = float4{palette[pi], palette[pi + 1], palette[pi + 2], 1.0f};
    }
    return;
}

void physics_step(f32 dt) {
    // Clamp dt to avoid explosion
    if dt > .033f { dt = .033f; }

    // --- Gravity + integration (float4 arithmetic + scalar broadcast) ---
    for i32 i = 0; i < NUM_SPHERES; i++ {
        float4 vel = g_vel_m[i];
        float4 pos = g_pos_r[i];

        // Gravity: float4 + float4 * scalar
        vel = vel + float4{0.0f, GRAVITY, 0.0f, 0.0f} * dt;

        // Damping: float4 * scalar
        vel = vel * .999f;

        // Integration: float4 + float4 * scalar
        pos = pos + float4{vel.x, vel.y, vel.z, 0.0f} * dt;

        // --- Wall bounces (component access + negation) ---
        f32 r = pos.w;

        // Floor
        if pos.y - r < FLOOR_Y {
            pos.y = FLOOR_Y + r;
            vel.y = -vel.y * RESTITUTION;  // negation + scalar
        }
        // Ceiling
        if pos.y + r > CEILING_Y {
            pos.y = CEILING_Y - r;
            vel.y = -vel.y * RESTITUTION;
        }
        // Walls X
        if pos.x - r < -WALL_X {
            pos.x = -WALL_X + r;
            vel.x = -vel.x * RESTITUTION;
        }
        if pos.x + r > WALL_X {
            pos.x = WALL_X - r;
            vel.x = -vel.x * RESTITUTION;
        }
        // Walls Z
        if pos.z - r < -WALL_Z {
            pos.z = -WALL_Z + r;
            vel.z = -vel.z * RESTITUTION;
        }
        if pos.z + r > WALL_Z {
            pos.z = WALL_Z - r;
            vel.z = -vel.z * RESTITUTION;
        }

        g_vel_m[i] = vel;
        g_pos_r[i] = pos;
    }

    // --- Sphere-sphere collisions (float3 math: length, normalize, dot) ---
    // Multiple passes to resolve overlaps in dense packing
    for i32 pass = 0; pass < 3; pass++ {
    for i32 i = 0; i < NUM_SPHERES; i++ {
        for i32 j = i + 1; j < NUM_SPHERES; j++ {
            // Swizzle: extract float3 from float4
            float3 pi = g_pos_r[i].xyz;
            float3 pj = g_pos_r[j].xyz;

            // float3 subtraction
            float3 delta = pj - pi;

            // length() from linear.mc
            f32 dist = length(delta);

            f32 ri = g_pos_r[i].w;
            f32 rj = g_pos_r[j].w;
            f32 min_dist = ri + rj;

            if dist < min_dist && dist > 0.001f {
                // normalize() from linear.mc
                float3 normal = normalize(delta);

                // dot() from linear.mc + float3 subtraction
                float3 vi = g_vel_m[i].xyz;
                float3 vj = g_vel_m[j].xyz;
                f32 rel_vel = dot(vi - vj, normal);

                if rel_vel > 0.0f {
                    // float3 * scalar (impulse)
                    float3 impulse = normal * rel_vel * RESTITUTION;

                    // float3 subtraction/addition
                    float3 new_vi = vi - impulse;
                    float3 new_vj = vj + impulse;

                    g_vel_m[i] = float4{new_vi.x, new_vi.y, new_vi.z, g_vel_m[i].w};
                    g_vel_m[j] = float4{new_vj.x, new_vj.y, new_vj.z, g_vel_m[j].w};
                }

                // Separate overlapping spheres
                f32 overlap = (min_dist - dist) * .5f;
                float3 sep = normal * overlap;

                // float3 negation
                float3 neg_sep = -sep;

                g_pos_r[i] = float4{pi.x + neg_sep.x, pi.y + neg_sep.y, pi.z + neg_sep.z, ri};
                g_pos_r[j] = float4{pj.x + sep.x, pj.y + sep.y, pj.z + sep.z, rj};
            }
        }
    }
    } // end collision passes

    // Re-clamp positions after collision resolution (collisions can push spheres out of bounds)
    for i32 i = 0; i < NUM_SPHERES; i++ {
        float4 pos = g_pos_r[i];
        f32 r = pos.w;
        if pos.y - r < FLOOR_Y   { pos.y = FLOOR_Y + r; }
        if pos.y + r > CEILING_Y  { pos.y = CEILING_Y - r; }
        if pos.x - r < -WALL_X   { pos.x = -WALL_X + r; }
        if pos.x + r > WALL_X    { pos.x = WALL_X - r; }
        if pos.z - r < -WALL_Z   { pos.z = -WALL_Z + r; }
        if pos.z + r > WALL_Z    { pos.z = WALL_Z - r; }
        g_pos_r[i] = pos;
    }
    return;
}

void init() {
    sg_desc gfx_desc;
    gfx_desc.environment = sglue_environment();
    when os(wasm) { gfx_desc.logger = sglue_logger(); }
    sg_setup(&gfx_desc);

    build_sphere_mesh();
    init_spheres();

    // Mesh vertex buffer (static)
    g_mesh_buf = sg_make_buffer(&sg_buffer_desc{
        .data.ptr = &g_sphere_verts,
        .data.size = g_sphere_nverts * sizeof(MeshVertex),
    });

    // Instance buffer (streaming — updated every frame)
    g_inst_buf = sg_make_buffer(&sg_buffer_desc{
        .size = NUM_SPHERES * sizeof(InstanceData),
        .usage.stream_update = true,
    });

    // Shader
    sg_shader shd = sokol_make_shader(&sphere_vs_shader, &sphere_fs_shader);

    // Pipeline with instancing. Buffer 0: mesh geometry (per-vertex);
    // buffer 1: instance data (per-instance).
    g_pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = shd,
        .layout.buffers[0].stride = cast(i32, sizeof(MeshVertex)),
        .layout.buffers[1].stride = cast(i32, sizeof(InstanceData)),
        .layout.buffers[1].step_func = SG_VERTEXSTEP_PER_INSTANCE,
        .layout.buffers[1].step_rate = 1,
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT3,   // mesh pos
        .layout.attrs[0].buffer_index = 0,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT3,   // mesh normal
        .layout.attrs[1].buffer_index = 0,
        .layout.attrs[2].format = SG_VERTEXFORMAT_FLOAT4,   // inst pos+radius
        .layout.attrs[2].buffer_index = 1,
        .layout.attrs[3].format = SG_VERTEXFORMAT_UBYTE4N,  // inst color (packed RGBA)
        .layout.attrs[3].buffer_index = 1,
        .face_winding = SG_FACEWINDING_CCW,
        .cull_mode = SG_CULLMODE_BACK,
        .depth.compare = SG_COMPAREFUNC_LESS_EQUAL,
        .depth.write_enabled = true,
    });

    // --- Floor quad ---
    f32[36] fv;  // 6 verts × 6 floats (pos + normal)
    f32 fx = WALL_X + 10.0f;
    f32 fz = WALL_Z + 10.0f;
    // Triangle 1 (CCW from above)
    fv[0]=-fx; fv[1]=FLOOR_Y; fv[2]=-fz; fv[3]=0.0f; fv[4]=1.0f; fv[5]=0.0f;
    fv[6]= fx; fv[7]=FLOOR_Y; fv[8]=-fz; fv[9]=0.0f; fv[10]=1.0f; fv[11]=0.0f;
    fv[12]=fx; fv[13]=FLOOR_Y; fv[14]=fz; fv[15]=0.0f; fv[16]=1.0f; fv[17]=0.0f;
    // Triangle 2 (CCW from above)
    fv[18]=-fx; fv[19]=FLOOR_Y; fv[20]=-fz; fv[21]=0.0f; fv[22]=1.0f; fv[23]=0.0f;
    fv[24]=fx; fv[25]=FLOOR_Y; fv[26]=fz; fv[27]=0.0f; fv[28]=1.0f; fv[29]=0.0f;
    fv[30]=-fx; fv[31]=FLOOR_Y; fv[32]=fz; fv[33]=0.0f; fv[34]=1.0f; fv[35]=0.0f;

    g_floor_buf = sg_make_buffer(&sg_buffer_desc{
        .data.ptr = &fv,
        .data.size = cast(i64, 36 * 4),
    });

    sg_shader floor_shd = sokol_make_shader(&floor_vs_shader, &sphere_fs_shader);
    g_floor_pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = floor_shd,
        .layout.buffers[0].stride = cast(i32, sizeof(MeshVertex)),
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT3,
        .layout.attrs[0].buffer_index = 0,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT3,
        .layout.attrs[1].buffer_index = 0,
        .depth.compare = SG_COMPAREFUNC_LESS_EQUAL,
        .depth.write_enabled = true,
    });

    // --- Shadow disc ---
    build_shadow_disc();
    g_shadow_buf = sg_make_buffer(&sg_buffer_desc{
        .data.ptr = &g_shadow_verts,
        .data.size = g_shadow_nverts * sizeof(MeshVertex),
    });

    sg_shader shadow_shd = sokol_make_shader(&shadow_vs_shader, &shadow_fs_shader);
    g_shadow_pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = shadow_shd,
        .layout.buffers[0].stride = cast(i32, sizeof(MeshVertex)),
        .layout.buffers[1].stride = cast(i32, sizeof(InstanceData)),
        .layout.buffers[1].step_func = SG_VERTEXSTEP_PER_INSTANCE,
        .layout.buffers[1].step_rate = 1,
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT3,
        .layout.attrs[0].buffer_index = 0,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT3,
        .layout.attrs[1].buffer_index = 0,
        .layout.attrs[2].format = SG_VERTEXFORMAT_FLOAT4,
        .layout.attrs[2].buffer_index = 1,
        .layout.attrs[3].format = SG_VERTEXFORMAT_UBYTE4N,
        .layout.attrs[3].buffer_index = 1,
        .depth.compare = SG_COMPAREFUNC_LESS_EQUAL,
        .depth.write_enabled = false,  // don't write depth for transparent shadows
        .colors[0].blend.enabled = true,
        .colors[0].blend.src_factor_rgb = SG_BLENDFACTOR_SRC_ALPHA,
        .colors[0].blend.dst_factor_rgb = SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .colors[0].blend.src_factor_alpha = SG_BLENDFACTOR_ZERO,
        .colors[0].blend.dst_factor_alpha = SG_BLENDFACTOR_ONE,
    });

    g_time = 0.0f;
    return;
}

void frame() {
    f32 dt = cast(f32, sapp_frame_duration());
    g_time = g_time + dt;

    // Physics (CPU vector math)
    physics_step(dt);

    // Build instance data array
    InstanceData[NUM_SPHERES] inst_data;
    for i32 i = 0; i < NUM_SPHERES; i++ {
        inst_data[i].pos_r = g_pos_r[i];
        inst_data[i].r = cast(u8, g_color[i].x * 255.0f);
        inst_data[i].g = cast(u8, g_color[i].y * 255.0f);
        inst_data[i].b = cast(u8, g_color[i].z * 255.0f);
        inst_data[i].a = cast(u8, g_color[i].w * 255.0f);
    }

    // Update instance buffer
    sg_update_buffer(g_inst_buf, &sg_range{.ptr = &inst_data, .size = NUM_SPHERES * sizeof(InstanceData)});

    // Camera: orbiting look_at + perspective (exercises float4x4 math)
    f32 aspect = cast(f32, sapp_width()) / cast(f32, sapp_height());
    float4x4 proj = perspective(60.0f * PI_F / 180.0f, aspect, 0.1f, 50.0f);
    f32 cam_dist = 8.0f;
    f32 cam_angle = g_time * .3f;
    float3 eye = float3{sinf(cam_angle) * cam_dist, 3.0f, cosf(cam_angle) * cam_dist};
    float3 target = float3{0.0f, 0.0f, 0.0f};
    float3 up = float3{0.0f, 1.0f, 0.0f};
    float4x4 view = look_at(eye, target, up);
    float4x4 mvp = mul(proj, view);

    // Per-frame uniforms — spotlight aimed from above-front at the
    // origin. Static for now; the camera orbits around it.
    PerFrame per_frame;
    per_frame.mvp = mvp;

    f32 sx = 2.5f; f32 sy = 9.0f; f32 sz = 2.5f;
    f32 sl = sqrtf(sx*sx + sy*sy + sz*sz);
    // aim FROM the spotlight TOWARD the origin → -pos / |pos|.
    f32 ax = -sx / sl; f32 ay = -sy / sl; f32 az = -sz / sl;
    f32 cos_inner = cosf(12.0f * PI_F / 180.0f);
    f32 cos_outer = cosf(16.0f * PI_F / 180.0f);
    per_frame.light_pos = float4{sx, sy, sz, cos_outer};
    per_frame.light_dir = float4{ax, ay, az, cos_inner};

    // Render
    sg_begin_pass(&sg_pass{
        .swapchain = sglue_swapchain(),
        .action.colors[0].load_action = SG_LOADACTION_CLEAR,
        .action.colors[0].clear_value = sg_color{.15f, .15f, .3f, 1.0f},
    });

    // Reused across every draw below, so it stays a named local.
    sg_range uni0 = sg_range{.ptr = &per_frame, .size = sizeof(per_frame)};

    // Draw floor first (opaque)
    sg_apply_pipeline(g_floor_pip);
    sg_apply_bindings(&sg_bindings{ .vertex_buffers[0] = g_floor_buf });
    sg_apply_uniforms(0, &uni0);
    sg_apply_uniforms(1, &uni0);
    sg_draw(0, 6, 1);

    // Draw shadows on floor (alpha-blended, no depth write)
    sg_apply_pipeline(g_shadow_pip);
    sg_apply_bindings(&sg_bindings{
        .vertex_buffers[0] = g_shadow_buf,
        .vertex_buffers[1] = g_inst_buf,
    });
    sg_apply_uniforms(0, &uni0);
    sg_draw(0, g_shadow_nverts, NUM_SPHERES);

    // Draw spheres last (opaque, overwrites shadows via depth)
    sg_apply_pipeline(g_pip);
    sg_apply_bindings(&sg_bindings{
        .vertex_buffers[0] = g_mesh_buf,
        .vertex_buffers[1] = g_inst_buf,
    });
    sg_apply_uniforms(0, &uni0);
    sg_apply_uniforms(1, &uni0);
    sg_draw(0, g_sphere_nverts, NUM_SPHERES);

    sg_end_pass();
    sg_commit();
    return;
}

void on_event(sapp_event* ev) {
    if ev.type == SAPP_EVENTTYPE_KEY_DOWN && ev.key_code == SAPP_KEYCODE_SPACE {
        g_rng = 98765;
        init_spheres();
    }
    return;
}

void cleanup() { sg_shutdown(); }

sapp_desc sokol_main() {
    return sapp_desc{
        .init_cb = init,
        .frame_cb = frame,
        .event_cb = on_event,
        .cleanup_cb = cleanup,
        .width = 1024,
        .height = 768,
        .high_dpi = true,
        .icon.sokol_default = true,
        .window_title = "sphere physics",
    };
}
