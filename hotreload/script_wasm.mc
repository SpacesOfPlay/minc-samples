// script_wasm.mc — hot-reloadable game logic, wasm variant. Stateless.
//
// The "engine" imports are bound by the JS host to the engine
// module's exports at instantiation; scalars only cross the seam
// (wasm modules share no memory). Edit + save while the host runs:
// the fresh module is swapped in, the world — and the engine-side
// state slot — carry over.

extern "engine" {
    u32  player();
    f32  get_pos_x(u32 e);
    f32  get_pos_y(u32 e);
    void set_pos(u32 e, f32 x, f32 y);
    void set_vel(u32 e, f32 x, f32 y);
    u32  spawn_bullet(f32 x, f32 y);
    i32  bullet_count();
    u32  get_state();
    void set_state(u32 v);
}

export {

u32 script_abi_version() { return 2; }   // must match the engine's GAME_ABI_VERSION

void script_update(f32 dt, f32 move_x, f32 move_y, i32 fire) {
    set_state(get_state() + 1);          // tick count, survives reloads engine-side

    u32 p = player();
    f32 speed = 10.0f;
    f32 vx = move_x * speed;
    f32 vy = move_y * speed;
    set_vel(p, vx, vy);
    set_pos(p, get_pos_x(p) + vx * dt, get_pos_y(p) + vy * dt);

    if fire != 0 { spawn_bullet(get_pos_x(p), get_pos_y(p)); }
}

}
