// engine_wasm.mc — the stable host, wasm variant.
//
// On wasm the loader half of libminc lives in the host page: JS
// compiles the script with the in-browser compiler (minc_web.wasm,
// fresh instance per compile), instantiates the fresh module, and
// binds its "engine" imports to this module's exports. This engine
// instance is never re-created, so the world survives every swap.
//
// The engine<->script seam is scalars only (integer handles + floats):
// wasm modules share no memory, so no pointer — and no struct — can
// cross. This is the wasm analogue of the "portable / C-interop
// variant" in game_abi.mc.
//
//   node scripts/test_hotreload_wasm.js    # automated demo

const u32 GAME_ABI_VERSION = 2;

const i32 MAX_ENT = 256;

// basic ECS
struct Ent {
    f32 px; f32 py;
    f32 vx; f32 vy;
    bool alive;
    i32 kind;       // kind 0 = player, 1 = bullet
}

struct EngineWorld {
    Ent[MAX_ENT] ents;
    i32 count;
    u32 player_id;
    i32 nbullets;
}
EngineWorld g_world;

u32 index_to_entity(i32 index) { return index + 1; }
i32 entity_to_index(u32 et) { return cast(i32, et) - 1; }

u32 ew_spawn(i32 kind, f32 x, f32 y) {
    if g_world.count >= MAX_ENT { return 0; }
    i32 ind = g_world.count;
    g_world.ents[ind] = {
        .px = x, .py = y,
        .vx = 0.0f, .vy = 0.0f,
        .alive = true,
        .kind = kind,
    };
    g_world.count++;
    return index_to_entity(ind);
}

// One engine-owned slot for state the script wants to survive reloads
// (its own memory dies with each instance) — the wasm shape of the
// native demo's get_state/set_state pointer slot.
u32 g_script_state = 0;

i32 main() {
    g_world.count = 0;
    g_world.nbullets = 0;
    g_script_state = 0;
    g_world.player_id = ew_spawn(0, 0.0f, 0.0f);
    return 0;
}

// --- the script-visible API ---
//
// The JS host hands these exports to the script instance as its
// "engine" import namespace; the extern block in script_wasm.mc must
// mirror the signatures exactly.
export {

u32 abi_version() { return GAME_ABI_VERSION; }

u32 player() { return g_world.player_id; }

f32 get_pos_x(u32 e) { return g_world.ents[entity_to_index(e)].px; }
f32 get_pos_y(u32 e) { return g_world.ents[entity_to_index(e)].py; }
void set_pos(u32 e, f32 x, f32 y) {
    i32 i = entity_to_index(e);
    g_world.ents[i].px = x;
    g_world.ents[i].py = y;
}

f32 get_vel_x(u32 e) { return g_world.ents[entity_to_index(e)].vx; }
f32 get_vel_y(u32 e) { return g_world.ents[entity_to_index(e)].vy; }
void set_vel(u32 e, f32 x, f32 y) {
    i32 i = entity_to_index(e);
    g_world.ents[i].vx = x;
    g_world.ents[i].vy = y;
}

u32 spawn_bullet(f32 x, f32 y) {
    u32 e = ew_spawn(1, x, y);
    if e != 0 { g_world.nbullets = g_world.nbullets + 1; }
    return e;
}
i32 bullet_count() { return g_world.nbullets; }

u32 get_state() { return g_script_state; }
void set_state(u32 v) { g_script_state = v; }

}
