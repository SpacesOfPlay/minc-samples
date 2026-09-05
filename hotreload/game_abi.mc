// game_abi.mc — the engine <-> script contract.

const u32 GAME_ABI_VERSION = 2;

type Entity = u32;      // 0 = invalid
type World = void*;     // opaque

struct InputState {
    float2 move;
    bool   fire;
}

// Engine service api handed to the script
//
// get_state/set_state: script-private pointer that survives reloads.
//
// Rules:
//
// - allocate the block and sub-blocks with api.alloc / api.free
//   the engine's allocator outlives the script module.
//
// - stamp the block with a magic/version word. 
//   magic change == a layout change => re-inits instead of hot-reloading.
//
struct HostApi {
    u32 abi_version;
    fn(World, Entity): float2         get_pos;
    fn(World, Entity, float2): void   set_pos;
    fn(World, Entity): float2         get_vel;
    fn(World, Entity, float2): void   set_vel;
    fn(World): Entity                 player;
    fn(World, float2): Entity         spawn_bullet;
    fn(World): i32                    bullet_count;
    fn(u8*): void                     log;
    fn(): void*                       get_state;
    fn(void*): void                   set_state;
    fn(i64): void*                    alloc;
    fn(void*): void                   free;
}

// --- Portable / C-interop variant (for reference) ---
//
// For a C-callable module, or one built by another compiler, keep the
// seam to scalars and pointers.
//
//   struct HostApi {
//       u32 abi_version;
//       fn(World, Entity, float2*): void  get_pos;   // out-param
//       fn(World, Entity, float2*): void  set_pos;   // in-param
//       fn(World, Entity, float2*): void  get_vel;
//       fn(World, Entity, float2*): void  set_vel;
//       fn(World): Entity                 player;
//       fn(World, float2*): Entity        spawn_bullet;
//       fn(World): i32                    bullet_count;
//       fn(u8*): void                     log;
//   }
//
// C side:
//   struct V2 { float x, y; };  // float2 internal format matches this layout
//   void get_pos(void* world, uint32_t e, struct V2* out);   // etc.
//

// Passed by pointer so the script is stateless
struct ScriptCtx {
    HostApi*   api;
    World      world;
    f32        dt;
    InputState input;
}

// Script module entry points, resolved by name after a reload.
type ScriptHook    = fn(ScriptCtx*): void;   // script_update, script_reloaded
type ScriptVersion = fn(): u32;              // script_abi_version
