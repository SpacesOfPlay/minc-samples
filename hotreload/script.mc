// script.mc — hot-reloadable game logic. Stateless.
//
//
// Edit this file while the engine runs (`engine watch`) and the 
// behavior changes on the next frame. 
//
// A script is a pure function over engine data: read via the HostApi,
// write via the HostApi, keep nothing between calls.
//

import game_abi;

u32 script_abi_version() { return GAME_ABI_VERSION; }

void script_reloaded(ScriptCtx* c) {
    c.api.log("script: reloaded\n");
}

void script_update(ScriptCtx* c) {
    HostApi* api = c.api;
    World w = c.world;
    Entity p = api.player(w);

    // simulation
    f32 speed = 10.0f;
    float2 v = c.input.move * speed;
    api.set_vel(w, p, v);

    float2 np = api.get_pos(w, p) + v * c.dt;
    api.set_pos(w, p, np);

    if c.input.fire {
        api.spawn_bullet(w, np);
    }
}
