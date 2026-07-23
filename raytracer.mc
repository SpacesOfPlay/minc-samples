// raytracer.mc — Whitted-style raytracer with sokol display

import sokol_all;
import math;
import linear;


// --- Constants

i32 IMG_W = 1280;
i32 IMG_H = 960;
i32 MAX_DEPTH = 2;
f32 EPSILON = 0.001f;


// --- float3 functions

float3 reflect_vec(float3 v, float3 n) {
    return v - n * (2.0f * dot(v, n));
}

float3 lerp3(float3 a, float3 b, f32 t) {
    return a * (1.0f - t) + b * t;
}


// --- Scene types

struct Ray { float3 origin; float3 dir; }

struct Material {
    float3 color;
    f32 reflectivity;  // 0.0 = matte, 1.0 = mirror
    f32 specular;      // specular exponent (0 = none, 64+ = shiny)
}

struct Sphere {
    float3 center;
    f32 radius;
    Material mat;
}

struct HitRecord {
    bool did_hit;
    f32 t;
    float3 point;
    float3 normal;
    Material mat;
}


// --- Scene

i32 NUM_SPHERES = 4;
Sphere[4] spheres;

float3 light_dir;
float3 light_color;
float3 ambient;
float3 cam_pos;

Sphere make_sphere(float3 center, f32 radius, float3 color, f32 refl, f32 spec) {
    Sphere s;
    s.center = center;
    s.radius = radius;
    s.mat.color = color;
    s.mat.reflectivity = refl;
    s.mat.specular = spec;
    return s;
}

void init_scene() {
    spheres[0] = make_sphere(float3{0.0f, 1.0f, 0.0f},   1.0f,  float3{0.9f, 0.9f, 0.9f}, 0.8f, 128.0f);
    spheres[1] = make_sphere(float3{-2.2f, 0.7f, 0.5f},  0.7f,  float3{0.9f, 0.15f, 0.15f}, 0.1f, 32.0f);
    spheres[2] = make_sphere(float3{1.8f, 0.5f, 1.0f},   0.5f,  float3{0.15f, 0.3f, 0.9f}, 0.05f, 16.0f);
    spheres[3] = make_sphere(float3{-0.5f, 0.35f, 2.5f}, 0.35f, float3{0.9f, 0.8f, 0.1f}, 0.3f, 64.0f);

    // Light: above and to the right
    light_dir = normalize(float3{1.0f, 1.5f, 0.8f});
    light_color = float3{1.0f, 0.95f, 0.9f};
    ambient = float3{0.12f, 0.15f, 0.2f};

    // Camera
    cam_pos = float3{0.0f, 2.0f, 6.0f};
}

// ============================================================================
// Intersection
// ============================================================================

HitRecord ray_sphere(Ray r, Sphere s) {
    HitRecord rec;
    rec.did_hit = false;
    float3 oc = r.origin - s.center;
    f32 a = dot(r.dir, r.dir);
    f32 b = dot(oc, r.dir);
    f32 c = dot(oc, oc) - s.radius * s.radius;
    f32 disc = b * b - a * c;
    if disc < 0.0f { return rec; }
    f32 sq = sqrtf(disc);
    f32 t = (-b - sq) / a;
    if t < EPSILON {
        t = (-b + sq) / a;
        if t < EPSILON { return rec; }
    }
    rec.did_hit = true;
    rec.t = t;
    rec.point = r.origin + r.dir * t;
    rec.normal = normalize(rec.point - s.center);
    rec.mat = s.mat;
    return rec;
}

HitRecord ray_plane(Ray r) {
    // Ground plane at y=0, facing up
    HitRecord rec;
    rec.did_hit = false;
    if fabsf(r.dir.y) < 0.0001f { return rec; }
    f32 t = -r.origin.y / r.dir.y;
    if t < EPSILON { return rec; }
    rec.did_hit = true;
    rec.t = t;
    rec.point = r.origin + r.dir * t;
    rec.normal = float3{0.0f, 1.0f, 0.0f};
    // Checkerboard pattern
    i32 cx = cast(i32, floorf(rec.point.x));
    i32 cz = cast(i32, floorf(rec.point.z));
    if rec.point.x < 0.0f { cx = cx - 1; }
    if rec.point.z < 0.0f { cz = cz - 1; }
    if (cx + cz) % 2 == 0 {
        rec.mat.color = float3{0.9f, 0.9f, 0.85f};
    } else {
        rec.mat.color = float3{0.3f, 0.3f, 0.35f};
    }
    rec.mat.reflectivity = 0.05f;
    rec.mat.specular = 0.0f;
    return rec;
}

HitRecord trace_scene(Ray r) {
    HitRecord closest;
    closest.did_hit = false;
    closest.t = 99999.0f;

    // Test spheres
    for i32 i = 0; i < NUM_SPHERES; i++ {
        HitRecord h = ray_sphere(r, spheres[i]);
        if h.did_hit && h.t < closest.t {
            closest = h;
        }
    }

    // Test ground plane
    HitRecord gnd = ray_plane(r);
    if gnd.did_hit && gnd.t < closest.t {
        closest = gnd;
    }
    return closest;
}


// --- Shading

float3 sky_color(float3 dir) {
    f32 t = clamp(dir.y * 0.5f + 0.5f, 0.0f, 1.0f);
    return lerp3(float3{0.8f, 0.85f, 0.9f}, float3{0.3f, 0.5f, 0.9f}, t);
}

float3 trace_ray(Ray r, i32 depth) {
    HitRecord hit = trace_scene(r);
    if hit.did_hit == false { return sky_color(r.dir); }
    return shade(r, hit, depth);
}

float3 shade(Ray r, HitRecord hit, i32 depth) {
    float3 color = hit.mat.color * ambient;

    // Shadow ray
    float3 shadow_origin = hit.point + hit.normal * EPSILON;
    Ray shadow_ray;
    shadow_ray.origin = shadow_origin;
    shadow_ray.dir = light_dir;
    HitRecord shadow_hit = trace_scene(shadow_ray);

    f32 in_light = 1.0f;
    if shadow_hit.did_hit { in_light = 0.0f; }

    // Diffuse (Lambert)
    f32 ndotl = max(dot(hit.normal, light_dir), 0.0f);
    float3 diffuse = hit.mat.color * light_color * (ndotl * in_light);
    color = color + diffuse;

    // Specular (Blinn-Phong)
    if hit.mat.specular > 0.0f && in_light > 0.0f {
        float3 view_dir = normalize(cam_pos - hit.point);
        float3 half_dir = normalize(light_dir + view_dir);
        f32 ndoth = max(dot(hit.normal, half_dir), 0.0f);
        f32 spec = powf(ndoth, hit.mat.specular);
        color = color + light_color * (spec * in_light);
    }

    // Reflection
    if depth > 0 && hit.mat.reflectivity > 0.01f {
        float3 refl_dir = reflect_vec(r.dir, hit.normal);
        Ray refl_ray;
        refl_ray.origin = shadow_origin;
        refl_ray.dir = refl_dir;
        float3 refl_color = trace_ray(refl_ray, depth - 1);
        color = lerp3(color, refl_color, hit.mat.reflectivity);
    }

    return color;
}


// --- Camera

Ray make_ray(i32 px, i32 py) {
    f32 fov = 60.0f * PI_F / 180.0f;
    f32 aspect = cast(f32, IMG_W) / cast(f32, IMG_H);
    f32 half_h = tanf(fov * 0.5f);
    f32 half_w = half_h * aspect;

    // Map pixel to [-1, 1] range
    f32 u = (cast(f32, px) + 0.5f) / cast(f32, IMG_W) * 2.0f - 1.0f;
    f32 v = 1.0f - (cast(f32, py) + 0.5f) / cast(f32, IMG_H) * 2.0f;

    // Camera looks toward -Z
    float3 target = float3{0.0f, 0.5f, 0.0f};
    float3 fwd = normalize(target - cam_pos);
    float3 world_up = float3{0.0f, 1.0f, 0.0f};
    float3 right = normalize(cross(fwd, world_up));
    float3 up = cross(right, fwd);

    float3 dir = normalize(fwd + right * (u * half_w) + up * (v * half_h));

    Ray r;
    r.origin = cam_pos;
    r.dir = dir;
    return r;
}


// --- Progressive render

u8* pixels;   // RGBA8 buffer
i32 render_y = 0;
bool render_done = false;

void render_scanlines(i32 count) {
    if render_done { return; }
    i32 end_y = render_y + count;
    if end_y > IMG_H { end_y = IMG_H; }

    for i32 y = render_y; y < end_y; y++ {
        for i32 x = 0; x < IMG_W; x++ {
            Ray r = make_ray(x, y);
            float3 col = trace_ray(r, MAX_DEPTH);

            // Clamp and convert to u8 RGBA
            i32 ri = cast(i32, clamp(col.x, 0.0f, 1.0f) * 255.0f);
            i32 gi = cast(i32, clamp(col.y, 0.0f, 1.0f) * 255.0f);
            i32 bi = cast(i32, clamp(col.z, 0.0f, 1.0f) * 255.0f);

            i32 idx = (y * IMG_W + x) * 4;
            *(pixels + idx + 0) = cast(u8, ri);
            *(pixels + idx + 1) = cast(u8, gi);
            *(pixels + idx + 2) = cast(u8, bi);
            *(pixels + idx + 3) = 255;
        }
    }

    render_y = end_y;
    if render_y >= IMG_H { render_done = true; }
}


// --- Shaders — textured full-screen quad

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


// --- Sokol state

sg_pipeline pip;
sg_buffer quad_vbuf;
sg_image tex_img;
sg_sampler tex_smp;
sg_view tex_view;


// --- Aspect-ratio-preserving viewport
//
// The full-screen quad covers NDC -1..1, so without a viewport the
// 4:3 raytraced image stretches to fill the canvas. Carve out the
// largest centered 4:3 sub-rectangle and draw into that — pillarbox
// when the canvas is wider than 4:3, letterbox when taller. The
// bars fall back to the pass clear color (black).

void apply_letterbox_viewport() {
    i32 cw = sapp_width();
    i32 ch = sapp_height();
    f64 ca = cast(f64, cw) / cast(f64, ch);
    f64 ga = cast(f64, IMG_W) / cast(f64, IMG_H);
    i32 vx;
    i32 vy;
    i32 vw;
    i32 vh;
    if ca > ga {
        vh = ch;
        vw = cast(i32, cast(f64, ch) * ga);
        vx = (cw - vw) / 2;
        vy = 0;
    } else {
        vw = cw;
        vh = cast(i32, cast(f64, cw) / ga);
        vx = 0;
        vy = (ch - vh) / 2;
    }
    sg_apply_viewport(vx, vy, vw, vh, true);
}


// --- Sokol callbacks

void init() {
    sg_setup(&sg_desc{ .environment = sglue_environment() });

    // Allocate pixel buffer (RGBA8)
    pixels = alloc<u8>(IMG_W * IMG_H * 4);
    memset(pixels, 0, IMG_W * IMG_H * 4);

    // Create streaming texture
    tex_img = sg_make_image(&sg_image_desc{
        .width = IMG_W,
        .height = IMG_H,
        .pixel_format = SG_PIXELFORMAT_RGBA8,
        .usage.stream_update = true,
    });

    // Create sampler (nearest neighbor for crisp pixels)
    tex_smp = sg_make_sampler(&sg_sampler_desc{
        .min_filter = SG_FILTER_NEAREST,
        .mag_filter = SG_FILTER_NEAREST,
    });

    // Create view from image
    tex_view = sg_make_view(&sg_view_desc{ .texture.image = tex_img });

    // Full-screen quad: 6 vertices (2 triangles), float2 pos + float2 uv
    f32[24] quad = {
        -1.0f,  1.0f, 0.0f, 0.0f,   // TL
         1.0f,  1.0f, 1.0f, 0.0f,   // TR
         1.0f, -1.0f, 1.0f, 1.0f,   // BR
        -1.0f,  1.0f, 0.0f, 0.0f,   // TL
         1.0f, -1.0f, 1.0f, 1.0f,   // BR
        -1.0f, -1.0f, 0.0f, 1.0f,   // BL
    };

    quad_vbuf = sg_make_buffer(&sg_buffer_desc{
        .data.ptr = &quad,
        .data.size = sizeof(quad),
    });

    // Shader
    sg_shader shd = sokol_make_shader(&quad_vs_shader, &quad_fs_shader);

    // Pipeline
    pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = shd,
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT2,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT2,
    });

    // Init scene
    init_scene();
}

void frame() {
    // Progressive render: 10 scanlines per frame
    render_scanlines(10);

    // Upload pixel data to texture
    sg_update_image(tex_img, &sg_image_data{
        .mip_levels[0].ptr = pixels,
        .mip_levels[0].size = IMG_W * IMG_H * 4,
    });

    // Render full-screen quad
    sg_begin_pass(&sg_pass{
        .action.colors[0].load_action = SG_LOADACTION_CLEAR,
        .action.colors[0].clear_value = sg_color{0.0f, 0.0f, 0.0f, 1.0f},
        .swapchain = sglue_swapchain(),
    });

    sg_apply_pipeline(pip);
    apply_letterbox_viewport();

    sg_apply_bindings(&sg_bindings{
        .vertex_buffers[0] = quad_vbuf,
        .views[0] = tex_view,
        .samplers[0] = tex_smp,
    });

    sg_draw(0, 6, 1);

    sg_end_pass();
    sg_commit();
}

void on_event(sapp_event* ev) {
    if ev.type == SAPP_EVENTTYPE_KEY_DOWN {
        if ev.key_code == SAPP_KEYCODE_ESCAPE { sapp_quit(); }
        if ev.key_code == SAPP_KEYCODE_R {
            // Re-render
            render_y = 0;
            render_done = false;
            memset(pixels, 0, IMG_W * IMG_H * 4);
        }
    }
    if ev.type == SAPP_EVENTTYPE_QUIT_REQUESTED { sapp_quit(); }
}

void cleanup() {
    free(pixels);
    sg_shutdown();
}

sapp_desc sokol_main() {
    return sapp_desc{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = on_event,
        .icon.sokol_default = true,
        .width = 1280,
        .height = 960,
        .sample_count = 1,
        .high_dpi = true,
        .window_title = "simple raytracer",
    };
}
