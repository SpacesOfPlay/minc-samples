// raytracer_mt.mc — multi-threaded Whitted raytracer.
//
// Every frame is rendered in full. A persistent worker pool pulls
// 32x32 tiles from an atomic counter; tiles are disjoint, so the
// render needs no locks.
//
// Scene: red left wall, green right wall, white back wall, checker
// floor. Three balls (mirror, metal, glass-look) and a small gold ball
// orbiting the central mirror.

import sokol_all;
import math;
import linear;
import thread;
import atomic;

// ============================================================================
// Configuration
// ============================================================================

when !os(ios) {
    i32 IMG_W = 800;
    i32 IMG_H = 600;
}
when os(ios) {
    // 2:1 is close to iPhone landscape, so the letterbox bars stay
    // narrow, and has a third fewer pixels than 800x600. The camera
    // frustum follows IMG_W/IMG_H.
    i32 IMG_W = 800;
    i32 IMG_H = 400;
}

i32 MAX_WORKERS = 16;
i32 MAX_DEPTH = 2;
f32 EPSILON = 0.001f;

// Tile size: small enough that one slow tile stalls only one worker,
// large enough to amortize the per-tile atomic.
i32 TILE_W = 32;
i32 TILE_H = 32;

// ============================================================================
// Scene data
// ============================================================================

struct Material {
    float4 color;
    f32    reflectivity;  // 0 = matte, 1 = mirror
    f32    specular;      // Blinn-Phong exponent (0 = no highlight)
}

struct Sphere {
    float4   center;
    f32      radius;
    Material mat;
}

struct Plane {
    float4   point;       // any point on the plane
    float4   normal;      // unit outward normal (faces into the room)
    Material mat;
    bool     checker;     // true → override mat.color with checker pattern
}

struct Ray {
    float4 origin;
    float4 dir;
}

struct HitRecord {
    bool     did_hit;
    f32      t;
    float4   point;
    float4   normal;
    Material mat;
}

// Sphere 3 is the orbiting ball; frame() repositions it before the
// workers wake.
Sphere[4] g_spheres;
Plane[4]  g_planes;   // floor, back, left, right

i32 SPHERE_COUNT = 4;

float4 g_light_dir;
float4 g_light_color;
float4 g_light2_dir;     // fill light from opposite side
float4 g_light2_color;
float4 g_ambient;

// ============================================================================
// Per-frame camera + worker scheduling
// ============================================================================

// Per-frame camera state. Written by frame() before the workers are
// woken, read by every worker; the semaphore handshake orders the two.
struct FrameState {
    float4 eye;
    float4 forward;
    float4 right;
    float4 up;
    f32    half_viewport_w;
    f32    half_viewport_h;
    i32    n_tiles_x;
    i32    n_tiles_y;
    i32    n_tiles;       // = n_tiles_x * n_tiles_y
}
FrameState g_frame;

// Tile queue: workers claim indices with atomic_add and stop at n_tiles.
i32 g_next_tile;

Thread[16] g_threads;
i32      g_worker_count;   // determined at init() from cpu_count()

// Persistent thread pool. g_work_ready[i] wakes worker i once per
// frame; each worker signals g_all_done when the queue is empty and
// main waits N times. g_pool_shutdown is checked after every wake so
// cleanup() can end the loops.
Semaphore[16]  g_work_ready;
Semaphore      g_all_done;
bool           g_pool_shutdown;

u8* g_pixels;
f32 g_time;

// ============================================================================
// Scene setup
// ============================================================================

Material make_mat(float4 color, f32 refl, f32 spec) {
    Material m;
    m.color = color;
    m.reflectivity = refl;
    m.specular = spec;
    return m;
}

Sphere make_sphere(float4 center, f32 radius, Material mat) {
    Sphere s;
    s.center = center;
    s.radius = radius;
    s.mat = mat;
    return s;
}

Plane make_plane(float4 point, float4 normal, Material mat, bool checker) {
    Plane p;
    p.point = point;
    p.normal = normal;
    p.mat = mat;
    p.checker = checker;
    return p;
}

void init_scene() {
    // Three balls on the floor (y = radius).
    // mirror ball, center
    g_spheres[0] = make_sphere(
        float4{0.0f, 0.9f, -0.5f, 0.0f}, 0.9f,
        make_mat(float4{0.95f, 0.95f, 0.98f, 0.0f}, 0.9f, 256.0f));
    // copper ball, left front
    g_spheres[1] = make_sphere(
        float4{-1.3f, 0.55f, 0.9f, 0.0f}, 0.55f,
        make_mat(float4{0.95f, 0.55f, 0.25f, 0.0f}, 0.45f, 64.0f));
    // glass-look ball: high specular and reflectivity, no refraction
    g_spheres[2] = make_sphere(
        float4{1.3f, 0.55f, 0.9f, 0.0f}, 0.55f,
        make_mat(float4{0.75f, 0.85f, 0.95f, 0.0f}, 0.6f, 180.0f));
    // gold ball; repositioned every frame
    g_spheres[3] = make_sphere(
        float4{0.0f, 1.6f, -0.5f, 0.0f}, 0.2f,
        make_mat(float4{1.0f, 0.78f, 0.2f, 0.0f}, 0.55f, 128.0f));

    Material white = make_mat(float4{0.6f, 0.6f, 0.58f, 0.0f}, 0.02f, 0.0f);
    Material red   = make_mat(float4{0.65f, 0.04f, 0.04f, 0.0f}, 0.02f, 0.0f);
    Material green = make_mat(float4{0.04f, 0.6f, 0.07f, 0.0f}, 0.02f, 0.0f);

    // floor, checkered, facing up
    g_planes[0] = make_plane(
        float4{0.0f, 0.0f, 0.0f, 0.0f},
        float4{0.0f, 1.0f, 0.0f, 0.0f},
        white, true);
    // back wall at z = -2.5, facing +z
    g_planes[1] = make_plane(
        float4{0.0f, 0.0f, -2.5f, 0.0f},
        float4{0.0f, 0.0f, 1.0f, 0.0f},
        white, false);
    // left wall at x = -2.5, facing +x, red
    g_planes[2] = make_plane(
        float4{-2.5f, 0.0f, 0.0f, 0.0f},
        float4{1.0f, 0.0f, 0.0f, 0.0f},
        red, false);
    // right wall at x = 2.5, facing -x, green
    g_planes[3] = make_plane(
        float4{2.5f, 0.0f, 0.0f, 0.0f},
        float4{-1.0f, 0.0f, 0.0f, 0.0f},
        green, false);

    // Two directional lights: a warm key from above right and a cool
    // fill from the other side, so both side walls get direct light.
    g_light_dir   = normalize(float4{0.6f, 1.1f, 0.3f, 0.0f});
    g_light_color = float4{1.15f, 1.1f, 0.95f, 0.0f};
    g_light2_dir  = normalize(float4{-0.6f, 0.6f, 0.2f, 0.0f});
    g_light2_color = float4{0.5f, 0.55f, 0.65f, 0.0f};
    g_ambient     = float4{0.08f, 0.08f, 0.1f, 0.0f};
}

// ============================================================================
// Intersection
// ============================================================================

HitRecord ray_sphere(Ray r, Sphere s) {
    HitRecord rec;
    rec.did_hit = false;
    float4 oc = r.origin - s.center;
    f32 b = dot(oc, r.dir);
    f32 c = dot(oc, oc) - s.radius * s.radius;
    f32 disc = b * b - c;  // ray.dir is unit, so a = 1
    if disc < 0.0f { return rec; }
    f32 sq = sqrtf(disc);
    f32 t = -b - sq;
    if t < EPSILON {
        t = -b + sq;
        if t < EPSILON { return rec; }
    }
    rec.did_hit = true;
    rec.t = t;
    rec.point = r.origin + r.dir * t;
    // |point - center| == radius, so scaling by 1/radius avoids a sqrt.
    rec.normal = (rec.point - s.center) * (1.0f / s.radius);
    rec.mat = s.mat;
    return rec;
}

HitRecord ray_plane(Ray r, Plane p) {
    HitRecord rec;
    rec.did_hit = false;
    f32 denom = dot(p.normal, r.dir);
    if denom > -0.0001f && denom < 0.0001f { return rec; }
    f32 t = dot(p.point - r.origin, p.normal) / denom;
    if t < EPSILON { return rec; }
    rec.did_hit = true;
    rec.t = t;
    rec.point = r.origin + r.dir * t;
    rec.normal = p.normal;
    rec.mat = p.mat;
    if p.checker {
        i32 cx = cast(i32, floorf(rec.point.x));
        i32 cz = cast(i32, floorf(rec.point.z));
        if (cx + cz) % 2 == 0 {
            rec.mat.color = float4{0.85f, 0.85f, 0.82f, 0.0f};
        } else {
            rec.mat.color = float4{0.22f, 0.22f, 0.25f, 0.0f};
        }
    }
    return rec;
}

HitRecord trace_scene(Ray r) {
    HitRecord closest;
    closest.did_hit = false;
    closest.t = 1000000000.0f;

    for i32 i = 0; i < SPHERE_COUNT; i++ {
        HitRecord h = ray_sphere(r, g_spheres[i]);
        if h.did_hit && h.t < closest.t { closest = h; }
    }
    for i32 i = 0; i < 4; i++ {
        HitRecord h = ray_plane(r, g_planes[i]);
        if h.did_hit && h.t < closest.t { closest = h; }
    }
    return closest;
}

// Shadow test against the spheres only: the infinite wall planes would
// occlude from outside their visible extent. Any hit blocks a
// directional light, so the first hit is returned.
HitRecord trace_occluder(Ray r) {
    HitRecord rec;
    rec.did_hit = false;
    for i32 i = 0; i < SPHERE_COUNT; i++ {
        HitRecord h = ray_sphere(r, g_spheres[i]);
        if h.did_hit { return h; }
    }
    return rec;
}

// ============================================================================
// Shading
// ============================================================================

float4 reflect_vec(float4 v, float4 n) {
    return v - n * (2.0f * dot(v, n));
}

float4 sky_color(float4 dir) {
    f32 t = dir.y * 0.5f + 0.5f;
    if t < 0.0f { t = 0.0f; }
    if t > 1.0f { t = 1.0f; }
    return float4{0.55f, 0.7f, 0.95f, 0.0f} * t + float4{0.85f, 0.88f, 0.92f, 0.0f} * (1.0f - t);
}

// Local lighting only (ambient, diffuse, specular, shadow); reflection
// is handled by the trace loop.
void add_light(float4* color_io, Ray shadow_ray_base, HitRecord hit, float4 eye,
               float4 light_dir, float4 light_color) {
    // Back-facing to the light: no diffuse, specular or shadow ray.
    f32 ndotl = dot(hit.normal, light_dir);
    if ndotl <= 0.0f { return; }

    Ray shadow_ray;
    shadow_ray.origin = shadow_ray_base.origin;
    shadow_ray.dir = light_dir;
    if trace_occluder(shadow_ray).did_hit { return; }

    float4 diffuse = hit.mat.color * light_color * ndotl;
    *color_io = *color_io + diffuse;

    if hit.mat.specular > 0.0f {
        float4 view_dir = normalize(eye - hit.point);
        float4 half_dir = normalize(light_dir + view_dir);
        f32 ndoth = dot(hit.normal, half_dir);
        if ndoth < 0.0f { ndoth = 0.0f; }
        f32 s = powf(ndoth, hit.mat.specular);
        *color_io = *color_io + light_color * s;
    }
    return;
}

float4 shade_local(Ray r, HitRecord hit, float4 eye) {
    float4 color = hit.mat.color * g_ambient;

    Ray shadow_ray_base;
    shadow_ray_base.origin = hit.point + hit.normal * EPSILON;
    shadow_ray_base.dir = float4{0.0f, 0.0f, 0.0f, 0.0f};

    add_light(&color, shadow_ray_base, hit, eye, g_light_dir,  g_light_color);
    add_light(&color, shadow_ray_base, hit, eye, g_light2_dir, g_light2_color);

    return color;
}

// Trace a primary ray with up to MAX_DEPTH-1 reflection bounces,
// iteratively.
float4 trace_path(Ray r, float4 eye) {
    float4 result = float4{0.0f, 0.0f, 0.0f, 0.0f};
    float4 throughput = float4{1.0f, 1.0f, 1.0f, 0.0f};
    Ray cur = r;
    for i32 bounce = 0; bounce < MAX_DEPTH; bounce++ {
        HitRecord hit = trace_scene(cur);
        if !hit.did_hit {
            result = result + throughput * sky_color(cur.dir);
            return result;
        }
        float4 local = shade_local(cur, hit, eye);
        f32 k = hit.mat.reflectivity;
        if k < 0.01f || bounce == MAX_DEPTH - 1 {
            result = result + throughput * local;
            return result;
        }
        // blend: (1-k) of local now, k carried into the bounce
        result = result + throughput * local * (1.0f - k);
        throughput = throughput * k * hit.mat.color;
        cur.origin = hit.point + hit.normal * EPSILON;
        cur.dir = reflect_vec(cur.dir, hit.normal);
    }
    return result;
}

// ============================================================================
// Worker: render tiles from the shared queue until it is empty.
// ============================================================================

void render_tile(i32 tile_idx) {
    i32 tx = tile_idx % g_frame.n_tiles_x;
    i32 ty = tile_idx / g_frame.n_tiles_x;
    i32 x0 = tx * TILE_W;
    i32 y0 = ty * TILE_H;
    i32 x1 = x0 + TILE_W; if x1 > IMG_W { x1 = IMG_W; }
    i32 y1 = y0 + TILE_H; if y1 > IMG_H { y1 = IMG_H; }

    f32 inv_w = 1.0f / cast(f32, IMG_W);
    f32 inv_h = 1.0f / cast(f32, IMG_H);

    for i32 y = y0; y < y1; y++ {
        // NDC y is +1 at the top; image rows go down
        f32 sy = 1.0f - 2.0f * (cast(f32, y) + 0.5f) * inv_h;
        for i32 x = x0; x < x1; x++ {
            f32 sx = 2.0f * (cast(f32, x) + 0.5f) * inv_w - 1.0f;

            // View-space ray direction
            float4 dir = normalize(
                g_frame.forward
                + g_frame.right * (sx * g_frame.half_viewport_w)
                + g_frame.up    * (sy * g_frame.half_viewport_h));

            Ray r;
            r.origin = g_frame.eye;
            r.dir = dir;
            float4 col = trace_path(r, g_frame.eye);

            // clamp, then gamma 2.0 via sqrt
            if col.x < 0.0f { col.x = 0.0f; } if col.x > 1.0f { col.x = 1.0f; }
            if col.y < 0.0f { col.y = 0.0f; } if col.y > 1.0f { col.y = 1.0f; }
            if col.z < 0.0f { col.z = 0.0f; } if col.z > 1.0f { col.z = 1.0f; }
            col.x = sqrtf(col.x);
            col.y = sqrtf(col.y);
            col.z = sqrtf(col.z);

            i32 idx = (y * IMG_W + x) * 4;
            g_pixels[idx + 0] = cast(u8, cast(i32, col.x * 255.0f));
            g_pixels[idx + 1] = cast(u8, cast(i32, col.y * 255.0f));
            g_pixels[idx + 2] = cast(u8, cast(i32, col.z * 255.0f));
            g_pixels[idx + 3] = 255;
        }
    }
    return;
}

// Worker thread: wait for work_ready, drain the tile queue, signal
// all_done. Exits when g_pool_shutdown is set.
void worker_loop(void* arg) {
    i32 id = cast(i32, cast(i64, arg));
    while true {
        sem_wait(&g_work_ready[id]);
        if g_pool_shutdown { return; }
        // atomic_add returns the claimed index. Relaxed ordering
        // suffices: the counter carries no other data.
        while true {
            i32 t = atomic_add(&g_next_tile, 1, RELAXED);
            if t >= g_frame.n_tiles { break; }
            render_tile(t);
        }
        sem_signal(&g_all_done);
    }
    return;
}

// ============================================================================
// Fullscreen-quad shader + sokol state
// ============================================================================

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

sg_pipeline g_pip;
sg_buffer   g_quad_vbuf;
sg_image    g_tex_img;
sg_sampler  g_tex_smp;
sg_view     g_tex_view;

// ============================================================================
// Sokol callbacks
// ============================================================================

void init() {
    sg_setup(&sg_desc{
        .environment = sglue_environment(),
        .logger = sglue_logger(),
    });

    g_pixels = alloc<u8>(IMG_W * IMG_H * 4);
    memset(g_pixels, 32, IMG_W * IMG_H * 4);  // dark grey until first frame

    init_scene();

    // Worker count: one per core, capped at MAX_WORKERS, and at IMG_H rows.
    i32 n = cpu_count();
    if n > MAX_WORKERS { n = MAX_WORKERS; }
    if n > IMG_H { n = IMG_H; }
    if n < 1 { n = 1; }
    g_worker_count = n;

    // Start the pool; each worker waits on its own semaphore.
    sem_init(&g_all_done, 0);
    for i32 i = 0; i < g_worker_count; i++ {
        sem_init(&g_work_ready[i], 0);
        thread_create(&g_threads[i], worker_loop, cast(void*, cast(i64, i)));
    }

    // Streaming texture for the rendered image
    g_tex_img = sg_make_image(&sg_image_desc{
        .width = IMG_W,
        .height = IMG_H,
        .pixel_format = SG_PIXELFORMAT_RGBA8,
        .usage.stream_update = true,
    });

    g_tex_smp = sg_make_sampler(&sg_sampler_desc{
        .min_filter = SG_FILTER_LINEAR,
        .mag_filter = SG_FILTER_LINEAR,
    });

    g_tex_view = sg_make_view(&sg_view_desc{ .texture.image = g_tex_img });

    // Fullscreen quad (pos.xy + uv), 6 verts; rewritten on resize to
    // letterbox the image.
    g_quad_vbuf = sg_make_buffer(&sg_buffer_desc{
        .size = 24 * 4,
        .usage.stream_update = true,
    });

    sg_shader shd = sokol_make_shader(&quad_vs_shader, &quad_fs_shader);
    g_pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = shd,
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT2,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT2,
    });

    update_quad_for_aspect();
}

// Letterbox: shrink the quad along the framebuffer's long axis so the
// image keeps its aspect; the clear color fills the bars.
void update_quad_for_aspect() {
    f32 fb_w = cast(f32, sapp_width());
    f32 fb_h = cast(f32, sapp_height());
    f32 img_aspect = cast(f32, IMG_W) / cast(f32, IMG_H);
    f32 fb_aspect = fb_w / fb_h;
    f32 sx = 1.0f;
    f32 sy = 1.0f;
    if fb_aspect > img_aspect { sx = img_aspect / fb_aspect; }
    else                       { sy = fb_aspect / img_aspect; }
    f32[24] quad = {
        -sx,  sy, 0.0f, 0.0f,
         sx,  sy, 1.0f, 0.0f,
         sx, -sy, 1.0f, 1.0f,
        -sx,  sy, 0.0f, 0.0f,
         sx, -sy, 1.0f, 1.0f,
        -sx, -sy, 0.0f, 1.0f,
    };
    sg_range data = sg_range{ .ptr = &quad, .size = sizeof(quad) };
    sg_update_buffer(g_quad_vbuf, &data);
}

void frame() {
    g_time = g_time + cast(f32, sapp_frame_duration());

    // The camera sweeps a 32 deg front arc rather than a full orbit, so it
    // stays inside the side walls (max |x| = sin(0.55)*3.8 = 1.99 < 2.5).
    f32 angle = sinf(g_time * 0.35f) * 0.55f;       // ≈ ±32°
    f32 radius = 3.6f + cosf(g_time * 0.7f) * 0.2f; // subtle dolly
    float4 eye = float4{
        sinf(angle) * radius,
        1.3f + sinf(g_time * 0.23f) * 0.25f,        // small vertical drift
        cosf(angle) * radius,
        0.0f
    };
    float4 target = float4{0.0f, 0.9f, 0.0f, 0.0f};
    float4 world_up = float4{0.0f, 1.0f, 0.0f, 0.0f};
    float4 forward = normalize(target - eye);
    float4 right = normalize(cross(forward, world_up));
    float4 up = cross(right, forward);

    // Viewport half-extents (60° vertical FOV)
    f32 fov = 60.0f * 3.14159265f / 180.0f;
    f32 half_h = tanf(fov * 0.5f);
    f32 half_w = half_h * cast(f32, IMG_W) / cast(f32, IMG_H);

    // Orbit the gold ball around the mirror at y=1.6, high enough to
    // clear the side balls at its lowest point (y=1.25). Written before
    // the workers wake, like the camera state.
    f32 orb_r = 1.55f;
    f32 orb_a = g_time * 0.9f;
    g_spheres[3].center = float4{
        g_spheres[0].center.x + orb_r * cosf(orb_a),
        1.6f + sinf(g_time * 1.7f) * 0.35f,
        g_spheres[0].center.z + orb_r * sinf(orb_a),
        0.0f
    };

    // Publish the camera and tile layout; the semaphore release below
    // makes it visible to the workers.
    g_frame.eye = eye;
    g_frame.forward = forward;
    g_frame.right = right;
    g_frame.up = up;
    g_frame.half_viewport_w = half_w;
    g_frame.half_viewport_h = half_h;
    g_frame.n_tiles_x = (IMG_W + TILE_W - 1) / TILE_W;
    g_frame.n_tiles_y = (IMG_H + TILE_H - 1) / TILE_H;
    g_frame.n_tiles = g_frame.n_tiles_x * g_frame.n_tiles_y;

    // Plain store: the workers are asleep, and sem_signal publishes it.
    g_next_tile = 0;

    // Wake the workers, then collect one done signal each.
    i32 n = g_worker_count;
    for i32 i = 0; i < n; i++ { sem_signal(&g_work_ready[i]); }
    for i32 i = 0; i < n; i++ { sem_wait(&g_all_done); }

    // Upload + draw
    sg_update_image(g_tex_img, &sg_image_data{
        .mip_levels[0].ptr = g_pixels,
        .mip_levels[0].size = IMG_W * IMG_H * 4,
    });

    sg_begin_pass(&sg_pass{
        .action.colors[0].load_action = SG_LOADACTION_CLEAR,
        .action.colors[0].clear_value = sg_color{0.05f, 0.05f, 0.07f, 1.0f},
        .swapchain = sglue_swapchain(),
    });
    sg_apply_pipeline(g_pip);
    sg_apply_bindings(&sg_bindings{
        .vertex_buffers[0] = g_quad_vbuf,
        .views[0] = g_tex_view,
        .samplers[0] = g_tex_smp,
    });
    sg_draw(0, 6, 1);
    sg_end_pass();
    sg_commit();
}

void on_event(sapp_event* ev) {
    if ev.type == SAPP_EVENTTYPE_QUIT_REQUESTED { sapp_request_quit(); }
    if ev.type == SAPP_EVENTTYPE_RESIZED { update_quad_for_aspect(); }
    return;
}

void cleanup() {
    // Tear down the pool: tell workers to exit, then join them.
    g_pool_shutdown = true;
    for i32 i = 0; i < g_worker_count; i++ { sem_signal(&g_work_ready[i]); }
    for i32 i = 0; i < g_worker_count; i++ { thread_join(&g_threads[i]); }
    for i32 i = 0; i < g_worker_count; i++ { sem_destroy(&g_work_ready[i]); }
    sem_destroy(&g_all_done);
    sg_shutdown();
    return;
}

sapp_desc sokol_main() {
    return sapp_desc{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = on_event,
        .width = IMG_W,
        .height = IMG_H,
        .high_dpi = false,
        .icon.sokol_default = true,
        .window_title = "minc — multi-threaded raytracer",
    };
}
