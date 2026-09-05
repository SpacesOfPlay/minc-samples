// engine.mc — the stable host
//
// Three layers: this engine (owns the world + main loop), game_abi.mc, 
// and a script the engine recompiles via libminc.dll and hot-swaps. 
// The engine owns all persistent state. The script is a stateless 
// function, so a reload swaps code with the world untouched.
//
//   engine            -> automated demo: run v1, "edit" to v2.
//
//   engine watch      -> recompile script.mc on change
//

import libminc;
import file;

import game_abi;


bool f32_near(f32 a, f32 b, f32 eps) {
    f32 d = a - b;
    if d < 0.0f { d = -d; }
    return d < eps;
}

// FNV-1a of a file's contents; 0 when unreadable (change detection).
u64 hash_file(str path) {
    FileData fd = file_read(path);
    if fd.data == null { return 0; }
    u64 h = 0xCBF29CE484222325;
    for i32 i = 0; i < fd.len; i++ { h = (h ^ cast(u64, fd.data[i])) * 1099511628211; }
    free(fd.data);
    return h;
}

// --- engine-owned world (only the engine dereferences World) ---

const i32 MAX_ENT = 256;

// basic ECS
struct Ent {
    float2 pos; 
    float2 vel; 
    bool alive; 
    i32 kind;       // kind 0 = player, 1 = bullet
}

struct EngineWorld {
    Ent[MAX_ENT] ents;
    i32 count;
    Entity player_id;
    i32 nbullets;
}
EngineWorld g_world;

Entity ew_spawn(EngineWorld* w, i32 kind, f32 x, f32 y) {
    if w.count >= MAX_ENT { return 0; }
    i32 ind = w.count;
    w.ents[ind] = {
        .pos = {x, y},
        .vel = {0.0f, 0.0f},
        .alive = true,
        .kind = kind,
    };
    w.count++;
    return index_to_entity(ind);
}

Entity index_to_entity(i32 index) { return index + 1; }
i32 entity_to_index(Entity et) { return et - 1; }

// --- HostApi implementations (called by the script with fn-ptrs) ---

float2 eng_get_pos(World w, Entity e) {
    EngineWorld* wl = cast(EngineWorld*, w);
    return wl.ents[entity_to_index(e)].pos;
}
void eng_set_pos(World w, Entity e, float2 v) {
    EngineWorld* wl = cast(EngineWorld*, w);
    wl.ents[entity_to_index(e)].pos = v;
}
float2 eng_get_vel(World w, Entity e) {
    EngineWorld* wl = cast(EngineWorld*, w);
    return wl.ents[entity_to_index(e)].vel;
}
void eng_set_vel(World w, Entity e, float2 v) {
    EngineWorld* wl = cast(EngineWorld*, w);
    wl.ents[entity_to_index(e)].vel = v;
}
Entity eng_player(World w) {
    EngineWorld* wl = cast(EngineWorld*, w);
    return wl.player_id;
}
Entity eng_spawn_bullet(World w, float2 at) {
    EngineWorld* wl = cast(EngineWorld*, w);
    Entity e = ew_spawn(wl, 1, at.x, at.y);
    if e != 0 { wl.nbullets = wl.nbullets + 1; }
    return e;
}
i32 eng_bullet_count(World w) {
    EngineWorld* wl = cast(EngineWorld*, w);
    return wl.nbullets;
}
void eng_log(u8* s) { print("{}", str_from_cstr(s)); }

// Script-private state block: the engine owns the root pointer (so it
// survives module swaps), the script owns the block and its layout.
void* g_script_state = null;
void* eng_get_state() { return g_script_state; }
void eng_set_state(void* p) { g_script_state = p; }

// Engine-side allocator for script state. The engine image never
// unloads, so blocks from here outlive every script module — unlike
// the script's own alloc(), which is module-local on some targets (linux/wasm).
void* eng_alloc(i64 n) { return alloc(n); }
void eng_free(void* p) { free(p); }

HostApi g_api;
void build_api() {
    g_api.abi_version = GAME_ABI_VERSION;
    g_api.get_pos = eng_get_pos;
    g_api.set_pos = eng_set_pos;
    g_api.get_vel = eng_get_vel;
    g_api.set_vel = eng_set_vel;
    g_api.player = eng_player;
    g_api.spawn_bullet = eng_spawn_bullet;
    g_api.bullet_count = eng_bullet_count;
    g_api.log = eng_log;
    g_api.get_state = eng_get_state;
    g_api.set_state = eng_set_state;
    g_api.alloc = eng_alloc;
    g_api.free = eng_free;
}

// --- libminc binding (load-time linked via lib/libminc.mc) ---

void* g_ctx;

// Folder holding script.mc + game_abi.mc: hotreload/
str g_root;

str hr_root() {
    if file_stamp("hotreload/game_abi.mc").ok { return "hotreload"; }
    return ".";
}

bool engine_init_libminc() {
    if minc_abi_version() != MINC_ABI_VERSION {
        print("engine: libminc ABI mismatch\n");
        return false;
    }
    g_ctx = minc_create();
    if g_ctx == null { return false; }
    // anchor imports on the root so lib/ lookup works correctly.
    minc_set_root(g_ctx, str_to_cstr(g_root));
    return true;
}

// --- the reloadable script module ---

const i32 MAX_CLOSURE = 16;

struct ScriptModule {
    void*      handle;
    ScriptHook update;
    ScriptHook reloaded;
    u64        src_hash;    // FNV of the confirmed source; skips no-op recompiles
    FileStamp  stamp;       // last seen file metadata
    // import closure of the last successful compile; an edit to any
    // member recompiles
    u8*[MAX_CLOSURE]       cl_path;
    FileStamp[MAX_CLOSURE] cl_stamp;
    i32                    cl_count;
}

i32 g_reload_count = 0;

// Remember the import closure of a successful compile, with stamps.
void capture_closure(ScriptModule* mod) {
    for i32 i = 0; i < mod.cl_count; i++ { free(mod.cl_path[i]); }
    mod.cl_count = 0;
    i32 n = minc_closure_count(g_ctx);
    if n > MAX_CLOSURE { n = MAX_CLOSURE; }
    for i32 i = 0; i < n; i++ {
        u8* p = minc_closure_path(g_ctx, i);   // valid until the next compile
        if p == null { continue; }
        str ps = str_from_cstr(p);
        i32 k = mod.cl_count;
        mod.cl_path[k] = str_to_cstr(ps);
        mod.cl_stamp[k] = file_stamp(ps);
        mod.cl_count = k + 1;
    }
}

// Compile the script, validate its ABI, then swap create-before-destroy.
// Any failure keeps the previous module.
bool engine_reload(ScriptModule* mod, u8* path) {
    var newmod = minc_compile_file(g_ctx, path);
    if newmod == null {
        print("reload: compile failed:\n{}", str_from_cstr(minc_errors(g_ctx)));
        return false;
    }
    capture_closure(mod);

    var fn_version = cast(ScriptVersion, minc_sym(newmod, "script_abi_version"));
    var fn_update  = cast(ScriptHook,    minc_sym(newmod, "script_update"));
    if fn_version == null || fn_update == null {
        print("reload: missing script entry points\n");
        minc_module_free(newmod);
        return false;
    }
    if fn_version() != GAME_ABI_VERSION {
        print("reload: ABI mismatch — keeping previous\n");
        minc_module_free(newmod);
        return false;
    }
    var fn_reloaded = cast(ScriptHook, minc_sym(newmod, "script_reloaded"));  // optional

    minc_module_free(mod.handle);   // release old, null is ok
    mod.handle   = newmod;
    mod.update   = fn_update;
    mod.reloaded = fn_reloaded;     // either null or new fn ptr
    return true;
}

void engine_apply_reload(u8* path, ScriptModule* mod, InputState in) {
    if !engine_reload(mod, path) { return; }
    g_reload_count = g_reload_count + 1;
    if mod.reloaded != null {
        ScriptCtx rc = {
            .api = &g_api,
            .world = cast(World, &g_world),
            .dt = 0.0f,
            .input = in
        };
        mod.reloaded(&rc);
    }
}

// Reload if the script file changed, then run one frame.
void engine_tick(u8* path, ScriptModule* mod, InputState in) {
    str spath = str_from_cstr(path);
    // Cheap metadata gate: only read + hash when mtime or size moved.
    FileStamp st = file_stamp(spath);
    if st.ok && file_stamp_changed(st, mod.stamp) {
        mod.stamp = st;
        // Confirm a real content change. A no-op save bumps mtime but
        // not the hash, so this skips a needless recompile.
        u64 h = hash_file(spath);
        if h != 0 && h != mod.src_hash {
            mod.src_hash = h;
            engine_apply_reload(path, mod, in);
        }
    }
    engine_run_frame(mod, in);
}

// Imported files may live outside the watched directory, so poll their
// stamps directly.
void engine_check_closure(u8* path, ScriptModule* mod, InputState in) {
    for i32 i = 0; i < mod.cl_count; i++ {
        FileStamp st = file_stamp(str_from_cstr(mod.cl_path[i]));
        if st.ok && file_stamp_changed(st, mod.cl_stamp[i]) {
            mod.cl_stamp[i] = st;
            engine_apply_reload(path, mod, in);
            return;
        }
    }
}

// Run one simulation frame through the current script.
void engine_run_frame(ScriptModule* mod, InputState in) {
    if mod.update == null { return; }
    ScriptCtx c = {
        .api = &g_api,
        .world = cast(World, &g_world),
        .dt = 0.5f,
        .input = in
    };
    mod.update(&c);
}

f32 player_x() { return g_world.ents[entity_to_index(g_world.player_id)].pos.x; }

void print_frame(i32 f) {
    print("  frame {}: player.x={} bullets={}\n", f, player_x(), g_world.nbullets);
}

void world_init() {
    g_world.count = 0;
    g_world.nbullets = 0;
    g_world.player_id = ew_spawn(&g_world, 0, 0.0f, 0.0f);
}

// --- automated demo (default): prove reload swaps code, keeps state ---

str SCRIPT_PRIV =
    "struct Priv { u32 magic; i32 ticks; }\n"
    "const u32 PRIV_MAGIC = 0x51A7E001;\n"
    "Priv* priv(ScriptCtx* c) {\n"
    "    Priv* p = cast(Priv*, c.api.get_state());\n"
    "    if p == null || p.magic != PRIV_MAGIC {\n"
    "        if p != null { c.api.free(cast(void*, p)); }   // layout changed: reinit\n"
    "        p = cast(Priv*, c.api.alloc(sizeof(Priv)));\n"
    "        p.magic = PRIV_MAGIC;\n"
    "        p.ticks = 0;\n"
    "        c.api.set_state(cast(void*, p));\n"
    "    }\n"
    "    return p;\n"
    "}\n";

str SCRIPT_V1 =
    "import game_abi;\n"
    "u32 script_abi_version() { return GAME_ABI_VERSION; }\n"
    "void script_reloaded(ScriptCtx* c) { c.api.log(\"script: v1 loaded\\n\"); }\n"
    "void script_update(ScriptCtx* c) {\n"
    "    Priv* pv = priv(c);\n"
    "    pv.ticks++;\n"
    "    HostApi* api = c.api; World w = c.world; Entity p = api.player(w);\n"
    "    f32 speed = 10.0f;\n"
    "    float2 v = c.input.move * speed;\n"
    "    api.set_vel(w, p, v);\n"
    "    float2 np = api.get_pos(w, p) + v * c.dt;\n"
    "    api.set_pos(w, p, np);\n"
    "}\n";

str SCRIPT_V2 =
    "import game_abi;\n"
    "u32 script_abi_version() { return GAME_ABI_VERSION; }\n"
    "void script_reloaded(ScriptCtx* c) { c.api.log(\"script: v2 loaded\\n\"); }\n"
    "void script_update(ScriptCtx* c) {\n"
    "    Priv* pv = priv(c);\n"
    "    pv.ticks++;\n"
    "    HostApi* api = c.api; World w = c.world; Entity p = api.player(w);\n"
    "    f32 speed = 25.0f;\n"
    "    float2 v = c.input.move * -speed;\n"
    "    api.set_vel(w, p, v);\n"
    "    float2 np = api.get_pos(w, p) + v * c.dt;\n"
    "    api.set_pos(w, p, np);\n"
    "    if c.input.fire { api.spawn_bullet(w, np); }\n"
    "}\n";

// Write a script version plus the shared private-state helper.
void write_script(u8* path, str body) {
    string s = str_concat(body, SCRIPT_PRIV);
    file_write_str(str_from_cstr(path), s);
    free(s);
}

i32 run_demo() {
    if !engine_init_libminc() { return 1; }
    world_init();
    build_api();

    // Scratch file for the "live edit", written to the cwd.
    u8* live = "hotreload_live.mc";
    ScriptModule mod;
    mod.handle = null;  mod.update = null;  mod.reloaded = null;  mod.src_hash = 0;

    InputState in;
    in.move = float2{1.0f, 0.0f};  in.fire = true;

    print("=== minc hot-reload demo ===\n");
    print("-- script v1: move +x, speed 10 --\n");
    write_script(live, SCRIPT_V1);
    for i32 f = 0; f < 3; f++ { engine_tick(live, &mod, in); print_frame(f); }
    f32 px1 = player_x();

    print("-- edit -> script v2: move -x, speed 25, fire --\n");
    write_script(live, SCRIPT_V2);
    for i32 f = 3; f < 6; f++ { engine_tick(live, &mod, in); print_frame(f); }
    f32 px2 = player_x();
    i32 bullets = g_world.nbullets;

    // Script-private heap state: v1 ticked 3 times, v2 another 3 in the
    // same block. The engine only knows the leading magic/count words.
    i32 priv_ticks = 0;
    bool priv_magic_ok = false;
    if g_script_state != null {
        priv_magic_ok = *cast(u32*, g_script_state) == 0x51A7E001;
        priv_ticks = *cast(i32*, cast(u8*, g_script_state) + 4);
    }

    print("-- results --\n");
    print("  v1 end x = {} (expect 15)\n", px1);
    print("  v2 end x = {} (expect -22.5; a reset world would be -37.5)\n", px2);
    print("  bullets  = {} (expect 3)\n", bullets);
    print("  reloads  = {} (expect 2)\n", g_reload_count);
    print("  priv ticks = {} (expect 6, script-private state carried across swap)\n", priv_ticks);

    bool ok = true;
    if !f32_near(px1, 15.0f, 0.05f)  { print("FAIL: v1 end position wrong\n"); ok = false; }
    if !f32_near(px2, -22.5f, 0.05f) { print("FAIL: v2 end position wrong (state not persisted across reload?)\n"); ok = false; }
    if bullets != 3                  { print("FAIL: bullet count wrong (v2 fire not applied?)\n"); ok = false; }
    if g_reload_count != 2           { print("FAIL: reload count wrong\n"); ok = false; }
    if !priv_magic_ok || priv_ticks != 6 { print("FAIL: script-private state lost across reload\n"); ok = false; }

    if mod.handle != null { minc_module_free(mod.handle); }
    if ok { print("demo: all checks passed\n"); return 0; }
    return 1;
}

// --- interactive watch: recompile the real script file on change ---

i32 run_watch() {
    if !engine_init_libminc() { return 1; }
    world_init();
    build_api();

    u8* path = str_to_cstr(str_concat(g_root, "/script.mc"));
    ScriptModule mod;       // default zero init

    InputState in;
    in.move = {1.0f, 0.0f};
    in.fire = false;

    // Tier-2 watch: a kernel notification tells us when the script dir
    // changes, so quiet frames skip the per-tick file stamp. Falls back
    // to stamping every frame if the watch can't open.
    FileWatch w = file_watch_dir(g_root);
    defer file_watch_close(&w);

    engine_tick(path, &mod, in);   // initial load + first frame

    print("watching script.mc — edit + save to reload. ctrl+c quits\n");
    for i32 t = 0; t < 100000; t++ {
        if !w.ok || file_watch_poll(&w) { engine_tick(path, &mod, in); }
        else { engine_run_frame(&mod, in); }
        engine_check_closure(path, &mod, in);
        if t % 10 == 0 { print_frame(t); }
        thread_sleep(100);
    }
    return 0;
}

i32 main() {
    g_root = hr_root();
    if !file_stamp(str_concat(g_root, "/game_abi.mc")).ok {
        print("engine: game_abi.mc not found — run from the hotreload folder or its parent\n");
        return 1;
    }
    if get_argc() > 1 && str_equal(str_from_cstr(get_arg(1)), "watch") { return run_watch(); }
    return run_demo();
}
