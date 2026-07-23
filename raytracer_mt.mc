// raytracer_mt.mc — multi-threaded Whitted raytracer.
//
// Architecture:
//   - Full re-render every display frame (orbit camera)
//   - Horizontal-stripe decomposition: N workers, each owns H/N rows
//     (disjoint writes → no synchronisation during render)
//
// Scene: Cornell-box-lite — red left wall, green right wall, white back wall
// and ceiling, checker floor. Three balls: mirror, metal, glass-look,
// plus a small gold ball orbiting the central mirror.

import sokol_all;
import math;
import linear;
import thread;
import atomic;

// ============================================================================
// Configuration — render resolution only hardcoded here.
// ============================================================================

when !os(ios) {
    i32 IMG_W = 800;
    i32 IMG_H = 600;
}
when os(ios) {
    // Widescreen 2:1 — closer to iPhone landscape (~2.17:1) so the
    // letterbox bars stay narrow, with ~33% fewer pixels than 800×600
    // for some headroom on the per-pixel cost. Camera frustum auto-
    // adapts via `half_w = half_h * IMG_W/IMG_H` (see line ~600).
    i32 IMG_W = 800;
    i32 IMG_H = 400;
}

i32 MAX_WORKERS = 16;
i32 MAX_DEPTH = 2;
f32 EPSILON = 0.001f;

// Tile-queue scheduler: IMG broken into TILE × TILE pixel tiles; workers
// pull tile indices via atomic_add. Small enough that load imbalance is
// bounded (a slow tile only stalls one worker), big enough to amortise
// the per-tile overhead (atomic + address computation).
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

// Sphere [3] is the orbiting ball — its position is rewritten every frame
// in frame() before workers wake.
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

// Per-frame camera state — written by main at start of frame(), read by
// every worker during render. Frame-to-frame boundary enforced by the
// semaphore handshake (workers wait for work_ready before reading).
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

// Tile queue: workers atomically increment g_next_tile to claim the
// next tile index; when they read a value >= g_frame.n_tiles they stop.
i32 g_next_tile;

Thread[16] g_threads;
i32      g_worker_count;   // determined at init() from cpu_count()

// Persistent thread pool:
//   - g_work_ready[i]: main → worker i; main releases one per frame, worker
//     waits on its own semaphore.
//   - g_all_done: workers → main; each worker releases once when its stripe
//     is finished; main waits N times to collect N signals.
//   - g_pool_shutdown: sticky flag the workers check after waking, used by
//     cleanup() to unwind the pool cleanly.
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
    // Three balls sitting on the floor (y = radius)
    // Mirror ball (chrome) — central, largest
    g_spheres[0] = make_sphere(
        float4{0.0f, 0.9f, -0.5f, 0.0f}, 0.9f,
        make_mat(float4{0.95f, 0.95f, 0.98f, 0.0f}, 0.9f, 256.0f));
    // Metal ball (warm copper) — left front
    g_spheres[1] = make_sphere(
        float4{-1.3f, 0.55f, 0.9f, 0.0f}, 0.55f,
        make_mat(float4{0.95f, 0.55f, 0.25f, 0.0f}, 0.45f, 64.0f));
    // Glass-look ball (pale blue, high specular + reflectivity — no refraction)
    g_spheres[2] = make_sphere(
        float4{1.3f, 0.55f, 0.9f, 0.0f}, 0.55f,
        make_mat(float4{0.75f, 0.85f, 0.95f, 0.0f}, 0.6f, 180.0f));
    // Small gold ball — placeholder position; rewritten each frame.
    g_spheres[3] = make_sphere(
        float4{0.0f, 1.6f, -0.5f, 0.0f}, 0.2f,
        make_mat(float4{1.0f, 0.78f, 0.2f, 0.0f}, 0.55f, 128.0f));

    Material white = make_mat(float4{0.6f, 0.6f, 0.58f, 0.0f}, 0.02f, 0.0f);
    Material red   = make_mat(float4{0.65f, 0.04f, 0.04f, 0.0f}, 0.02f, 0.0f);
    Material green = make_mat(float4{0.04f, 0.6f, 0.07f, 0.0f}, 0.02f, 0.0f);

    // Floor (checkerboard), facing up
    g_planes[0] = make_plane(
        float4{0.0f, 0.0f, 0.0f, 0.0f},
        float4{0.0f, 1.0f, 0.0f, 0.0f},
        white, true);
    // Back wall at z = -2.5, facing +z
    g_planes[1] = make_plane(
        float4{0.0f, 0.0f, -2.5f, 0.0f},
        float4{0.0f, 0.0f, 1.0f, 0.0f},
        white, false);
    // Left wall at x = -2.5, facing +x — RED
    g_planes[2] = make_plane(
        float4{-2.5f, 0.0f, 0.0f, 0.0f},
        float4{1.0f, 0.0f, 0.0f, 0.0f},
        red, false);
    // Right wall at x = 2.5, facing -x — GREEN
    g_planes[3] = make_plane(
        float4{2.5f, 0.0f, 0.0f, 0.0f},
        float4{-1.0f, 0.0f, 0.0f, 0.0f},
        green, false);

    // Two directional lights — a warm key from above-right and a cooler
    // fill from the opposite side. With a single overhead sun, each side
    // wall only catches ~cos(θ_wide) of the light; a second light aimed
    // across the scene puts direct illumination on both walls and brings
    // the red/green up to saturation.
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
    // |rec.point - s.center| == s.radius by construction, so we can
    // scale by 1/radius instead of calling normalize (saves a sqrt).
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

// Shadow-only trace — tests against sphere occluders only. Infinite wall
// planes would produce spurious occluder hits from any point whose shadow
// ray passes through them outside their visual footprint, which reads
// as "everything is in shadow". Walls are visual-only.
//
// Returns any-hit rather than closest-hit: callers only ask "is anything
// blocking the light" (directional light at infinity, so every sphere hit
// is a valid occluder), so stop at the first sphere that blocks.
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

// Shade a hit WITHOUT recursing — just local lighting (ambient + diffuse +
// specular + shadow). Reflection is driven by the outer trace loop so we
// can keep this function non-recursive (minc has no forward prototypes).
void add_light(float4* color_io, Ray shadow_ray_base, HitRecord hit, float4 eye,
               float4 light_dir, float4 light_color) {
    // Surface faces away from the light — no diffuse, no specular, no
    // shadow ray needed. Blinn-Phong specular on a back-facing surface
    // is a non-physical artifact anyway.
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

// Trace a primary ray with up to MAX_DEPTH-1 reflection bounces.
// Written as an iterative throughput accumulator instead of recursion.
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
        // Mix: add (1-k) * throughput * local to result, continue with k * throughput
        result = result + throughput * local * (1.0f - k);
        throughput = throughput * k * hit.mat.color;
        cur.origin = hit.point + hit.normal * EPSILON;
        cur.dir = reflect_vec(cur.dir, hit.normal);
    }
    return result;
}

// ============================================================================
// Worker: render a single TILE_W × TILE_H region, then loop pulling tiles
// from the shared atomic counter until the frame's tile queue is empty.
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
        // NDC-y goes +1 at top → -1 at bottom (flip image Y to match screen)
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

            // Clamp, then gamma ~2.0 via sqrt (cheap approximation of 2.2).
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

// Persistent worker thread — sleeps on its own work_ready semaphore,
// drains tiles from g_next_tile while any remain, signals all_done,
// and loops back. Exits when g_pool_shutdown is observed after a wake.
void worker_loop(void* arg) {
    i32 id = cast(i32, cast(i64, arg));
    while true {
        sem_wait(&g_work_ready[id]);
        if g_pool_shutdown { return; }
        // Pull tiles until the queue is empty. atomic_add returns the
        // OLD counter value (this worker's tile); the next worker sees
        // the incremented counter and claims the next tile. Relaxed
        // ordering is fine here — the only cross-thread dependency is
        // the increment itself, and there's no memory we need to
        // synchronise with the counter's writes.
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

    // Spawn the persistent pool — each worker sleeps on its own semaphore.
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

    // Fullscreen quad (pos.xy + uv), 6 verts. Dynamic so we can rewrite
    // it each resize to letterbox the 4:3 raytraced image on framebuffers
    // with a different aspect (e.g. iPhone landscape ≈ 19.5:9).
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

// Letterbox the 4:3 (IMG_W:IMG_H) raytraced image on a framebuffer
// with arbitrary aspect: shrink the quad on the long axis so it stays
// proportional. Black bars fill the rest (clear color shows through).
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

    // Camera sweeps a front arc (±32°) instead of a full orbit so it
    // never clips through the side walls at x=±2.5. At worst-case radius
    // (3.8) and amplitude (0.55 rad), max |x| = sin(0.55)*3.8 ≈ 1.99.
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

    // Orbit the small gold ball around the central mirror. xz orbit at the
    // mirror's footprint (radius 1.55), but the orbit plane sits at y=1.6
    // — high enough that even the bob's low point (y=1.25) clears the side
    // balls (whose centers sit at y=0.55). Updated single-threaded before
    // the workers wake; visibility is carried by the same semaphore release
    // as the camera state below.
    f32 orb_r = 1.55f;
    f32 orb_a = g_time * 0.9f;
    g_spheres[3].center = float4{
        g_spheres[0].center.x + orb_r * cosf(orb_a),
        1.6f + sinf(g_time * 1.7f) * 0.35f,
        g_spheres[0].center.z + orb_r * sinf(orb_a),
        0.0f
    };

    // Publish this frame's camera + tile dimensions. Workers read this
    // AFTER their work_ready semaphore wakes them, so the frame state is
    // safely visible through the semaphore's implicit release/acquire.
    g_frame.eye = eye;
    g_frame.forward = forward;
    g_frame.right = right;
    g_frame.up = up;
    g_frame.half_viewport_w = half_w;
    g_frame.half_viewport_h = half_h;
    g_frame.n_tiles_x = (IMG_W + TILE_W - 1) / TILE_W;
    g_frame.n_tiles_y = (IMG_H + TILE_H - 1) / TILE_H;
    g_frame.n_tiles = g_frame.n_tiles_x * g_frame.n_tiles_y;

    // Reset the tile counter. Plain store — workers aren't awake yet; the
    // sem_signal below provides the release-visibility barrier.
    g_next_tile = 0;

    // Wake all workers; each drains tiles from g_next_tile and then signals done.
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
