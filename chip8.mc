// chip8.mc — Chip-8 emulator with sokol display

import sokol_all;

// ============================================================================
// Constants
// ============================================================================

const i32 CHIP8_W = 64;
const i32 CHIP8_H = 32;
const i32 SCALE = 10;
const i32 RAM_SIZE = 4096;
const i32 PROG_START = 512;
const i32 FONT_ADDR = 80;
const i32 INSTR_PER_FRAME = 10;

// CHIP-8 register names. F is the carry / collision flag register.
const i32 VF = 0xF;

// 0x00 family — system instructions.
const i32 OP_CLS = 0x00E0;       // clear display
const i32 OP_RET = 0x00EE;       // return from subroutine

// 0xE family — input skips. nn-byte selectors.
const i32 OP_SKP   = 0x9E;       // skip next if key V[x] pressed
const i32 OP_SKNP  = 0xA1;       // skip next if key V[x] NOT pressed

// 0xF family — misc / I-register / timer / BCD / mem I/O. nn-byte selectors.
const i32 OP_LD_VX_DT = 0x07;    // V[x] = delay
const i32 OP_LD_VX_K  = 0x0A;    // wait for keypress, store in V[x]
const i32 OP_LD_DT_VX = 0x15;    // delay = V[x]
const i32 OP_LD_ST_VX = 0x18;    // sound = V[x]
const i32 OP_ADD_I_VX = 0x1E;    // I += V[x]
const i32 OP_LD_F_VX  = 0x29;    // I = font addr for digit V[x]
const i32 OP_LD_B_VX  = 0x33;    // BCD of V[x] -> mem[I..I+2]
const i32 OP_ST_V     = 0x55;    // store V0..V[x] to mem[I..]
const i32 OP_LD_V     = 0x65;    // load  V0..V[x] from mem[I..]

// ============================================================================
// Font data (0-F hex digits, 5 bytes each = 80 bytes)
// ============================================================================

const u8[80] chip8_font = {
    0xF0, 0x90, 0x90, 0x90, 0xF0,
    0x20, 0x60, 0x20, 0x20, 0x70,
    0xF0, 0x10, 0xF0, 0x80, 0xF0,
    0xF0, 0x10, 0xF0, 0x10, 0xF0,
    0x90, 0x90, 0xF0, 0x10, 0x10,
    0xF0, 0x80, 0xF0, 0x10, 0xF0,
    0xF0, 0x80, 0xF0, 0x90, 0xF0,
    0xF0, 0x10, 0x20, 0x40, 0x40,
    0xF0, 0x90, 0xF0, 0x90, 0xF0,
    0xF0, 0x90, 0xF0, 0x10, 0xF0,
    0xF0, 0x90, 0xF0, 0x90, 0x90,
    0xE0, 0x90, 0xE0, 0x90, 0xE0,
    0xF0, 0x80, 0x80, 0x80, 0xF0,
    0xE0, 0x90, 0x90, 0x90, 0xE0,
    0xF0, 0x80, 0xF0, 0x80, 0xF0,
    0xF0, 0x80, 0xF0, 0x80, 0x80
};

// Built-in test ROM: draws "0123" at top-left using font sprites, then loops
const u8[28] test_rom = {
    0x60, 0x00, 0x61, 0x00, 0xA0, 0x50, 0xD0, 0x15,
    0x60, 0x05, 0xA0, 0x55, 0xD0, 0x15,
    0x60, 0x0A, 0xA0, 0x5A, 0xD0, 0x15,
    0x60, 0x0F, 0xA0, 0x5F, 0xD0, 0x15,
    0x12, 0x1A
};

// ============================================================================
// CPU state
// ============================================================================

noinit u8[RAM_SIZE] mem;
noinit u8[2048] display;
u8[16] V;
i32 I_reg = 0;
i32 pc = 0;
i32[16] stack;
i32 sp = 0;
i32 delay_timer = 0;
i32 sound_timer = 0;
bool[16] keys;
bool draw_flag = false;
// -1 = CPU running normally; otherwise = index of register that
// will receive the next keypress (CPU is halted until then).
i32 wait_key_reg = -1;

// ============================================================================
// Sokol state
// ============================================================================

u8* pixels;
u8* rom_path;
sg_pipeline pip;
sg_buffer quad_vbuf;
sg_image tex_img;
sg_sampler tex_smp;
sg_view tex_view;

// ============================================================================
// RNG — Marsaglia xorshift64, shift triple (13, 7, 17)
// ============================================================================

// The state is unsigned so the middle shift stays logical.
u64 rng_state = 123456789;

u64 rng_next() {
    rng_state = rng_state ^ (rng_state << 13);
    rng_state = rng_state ^ (rng_state >> 7);
    rng_state = rng_state ^ (rng_state << 17);
    return rng_state;
}

// ============================================================================
// Initialization
// ============================================================================

void chip8_init() {
    memset(&mem, 0, RAM_SIZE);
    memset(&display, 0, 2048);
    memset(&V, 0, 16);
    memset(&keys, 0, 16);
    for i32 i = 0; i < 80; i++ {
        mem[FONT_ADDR + i] = chip8_font[i];
    }
    pc = PROG_START;
    sp = 0;
    I_reg = 0;
    delay_timer = 0;
    sound_timer = 0;
    draw_flag = true;
    wait_key_reg = -1;
}

void load_test_rom() {
    for i32 i = 0; i < 28; i++ {
        mem[PROG_START + i] = test_rom[i];
    }
}

void load_rom(u8* path) {
    i64 fd = open(path, 0);
    if fd < 0 {
        load_test_rom();
        return;
    }
    u8* dest = mem + PROG_START;
    read(fd, dest, RAM_SIZE - PROG_START);
    close(fd);
}

// ============================================================================
// Opcode handlers
// ============================================================================

void op_draw(i32 x, i32 y, i32 n) {
    i32 xpos = cast(i32, V[x]) & 0xFF;
    i32 ypos = cast(i32, V[y]) & 0xFF;
    V[VF] = 0;
    for i32 row = 0; row < n; row++ {
        if I_reg + row < 0 || I_reg + row >= RAM_SIZE { return; }
        i32 sprite_byte = cast(i32, mem[I_reg + row]) & 0xFF;
        for i32 col = 0; col < 8; col++ {
            // Sprite byte is MSB-first: bit 0x80 is the leftmost pixel of the row.
            if (sprite_byte & (0x80 >> col)) != 0 {
                i32 px = (xpos + col) % CHIP8_W;
                i32 py = (ypos + row) % CHIP8_H;
                i32 idx = py * CHIP8_W + px;
                if display[idx] == 1 { V[VF] = 1; }   // collision
                display[idx] = display[idx] ^ 1;
            }
        }
    }
    draw_flag = true;
}

void op_0(i32 opcode) {
    if opcode == OP_CLS {
        memset(&display, 0, CHIP8_W * CHIP8_H);
        draw_flag = true;
    }
    if opcode == OP_RET {
        sp--;
        pc = stack[sp];
    }
}

// 0x8XYN: register-to-register ALU ops. n selects the operation.
void op_8(i32 x, i32 y, i32 n) {
    i32 vx = cast(i32, V[x]) & 0xFF;
    i32 vy = cast(i32, V[y]) & 0xFF;
    switch n {
        case 0: { V[x] = V[y]; }                          // LD V[x], V[y]
        case 1: { V[x] = cast(u8, vx | vy); }             // OR
        case 2: { V[x] = cast(u8, vx & vy); }             // AND
        case 3: { V[x] = cast(u8, vx ^ vy); }             // XOR
        case 4: {                                         // ADD: VF = carry
            i32 sum = vx + vy;
            V[VF] = 0; if sum > 255 { V[VF] = 1; }
            V[x] = cast(u8, sum & 0xFF);
        }
        case 5: {                                         // SUB: VF = NOT borrow
            V[VF] = 0; if vx >= vy { V[VF] = 1; }
            V[x] = cast(u8, (vx - vy) & 0xFF);
        }
        case 6: {                                         // SHR: VF = LSB
            V[VF] = cast(u8, vx & 1);
            V[x] = cast(u8, (vx >> 1) & 0xFF);
        }
        case 7: {                                         // SUBN: VF = NOT borrow
            V[VF] = 0; if vy >= vx { V[VF] = 1; }
            V[x] = cast(u8, (vy - vx) & 0xFF);
        }
        case 0xE: {                                       // SHL: VF = MSB
            V[VF] = cast(u8, (vx >> 7) & 1);
            V[x] = cast(u8, (vx << 1) & 0xFF);
        }
    }
}

// 0xEXNN: input skips. nn selects pressed vs not-pressed.
void op_E(i32 x, i32 nn) {
    i32 key = cast(i32, V[x]) & 0xF;
    if nn == OP_SKP {
        if keys[key] { pc = (pc + 2) & 0xFFFF; }
    }
    if nn == OP_SKNP {
        if keys[key] == false { pc = (pc + 2) & 0xFFFF; }
    }
}

// 0xFXNN: timer / I-register / BCD / memory I/O. nn selects which.
void op_F(i32 x, i32 nn) {
    i32 vx = cast(i32, V[x]) & 0xFF;
    switch nn {
        case OP_LD_VX_DT: { V[x] = cast(u8, delay_timer & 0xFF); }
        case OP_LD_VX_K:  { wait_key_reg = x; }
        case OP_LD_DT_VX: { delay_timer = vx; }
        case OP_LD_ST_VX: { sound_timer = vx; }
        case OP_ADD_I_VX: { I_reg = (I_reg + vx) & 0xFFFF; }
        case OP_LD_F_VX:  { I_reg = FONT_ADDR + (vx & 0xF) * 5; }
        case OP_LD_B_VX: {                              // BCD: hundreds, tens, ones
            mem[I_reg]     = cast(u8, vx / 100);
            mem[I_reg + 1] = cast(u8, (vx / 10) % 10);
            mem[I_reg + 2] = cast(u8, vx % 10);
        }
        case OP_ST_V: {                                 // store V0..V[x]
            for i32 i = 0; i <= x; i++ { mem[I_reg + i] = V[i]; }
        }
        case OP_LD_V: {                                 // load V0..V[x]
            for i32 i = 0; i <= x; i++ { V[i] = mem[I_reg + i]; }
        }
    }
}

// ============================================================================
// CPU cycle
// ============================================================================

void chip8_cycle() {
    if wait_key_reg >= 0 { return; }
    if pc < 0 || pc >= 4094 { return; }

    i32 hi = cast(i32, mem[pc]) & 0xFF;
    i32 lo = cast(i32, mem[pc + 1]) & 0xFF;
    i32 opcode = (hi << 8) | lo;
    pc = (pc + 2) & 0xFFFF;

    i32 nib = (opcode >> 12) & 0xF;
    i32 x   = (opcode >> 8) & 0xF;
    i32 y   = (opcode >> 4) & 0xF;
    i32 n   = opcode & 0xF;
    i32 nn  = opcode & 0xFF;
    i32 nnn = opcode & 0xFFF;

    // Top-level dispatch keyed off the high nibble. Mnemonics follow
    // Cowgod's CHIP-8 reference (SE = skip if equal, JP = jump, etc.).
    switch nib {
        case 0:    { op_0(opcode); }                                                         // 0NNN: system (CLS / RET)
        case 1:    { pc = nnn; }                                                             // 1NNN: JP nnn
        case 2:    { stack[sp] = pc; sp++; pc = nnn; }                                       // 2NNN: CALL nnn
        case 3:    { if (cast(i32, V[x]) & 0xFF) == nn { pc = (pc + 2) & 0xFFFF; } }         // 3XNN: SE  V[x], nn
        case 4:    { if (cast(i32, V[x]) & 0xFF) != nn { pc = (pc + 2) & 0xFFFF; } }         // 4XNN: SNE V[x], nn
        case 5:    { if V[x] == V[y] { pc = (pc + 2) & 0xFFFF; } }                           // 5XY0: SE  V[x], V[y]
        case 6:    { V[x] = cast(u8, nn); }                                                  // 6XNN: LD  V[x], nn
        case 7:    { V[x] = cast(u8, ((cast(i32, V[x]) & 0xFF) + nn) & 0xFF); }              // 7XNN: ADD V[x], nn (no carry)
        case 8:    { op_8(x, y, n); }                                                        // 8XYN: register ALU
        case 9:    { if V[x] != V[y] { pc = (pc + 2) & 0xFFFF; } }                           // 9XY0: SNE V[x], V[y]
        case 0xA:  { I_reg = nnn; }                                                          // ANNN: LD  I, nnn
        case 0xB:  { pc = (nnn + (cast(i32, V[0]) & 0xFF)) & 0xFFFF; }                       // BNNN: JP  V0, nnn
        case 0xC:  { V[x] = cast(u8, (cast(i32, rng_next()) & nn) & 0xFF); }                 // CXNN: RND V[x], nn
        case 0xD:  { op_draw(x, y, n); }                                                     // DXYN: DRW V[x], V[y], n
        case 0xE:  { op_E(x, nn); }                                                          // EXNN: input skip (SKP / SKNP)
        case 0xF:  { op_F(x, nn); }                                                          // FXNN: misc (timer / I-reg / BCD / mem)
    }
}

// ============================================================================
// Display: 1-bit → RGBA8
// ============================================================================

void update_pixels() {
    for i32 y = 0; y < CHIP8_H; y++ {
        for i32 x = 0; x < CHIP8_W; x++ {
            i32 src = y * CHIP8_W + x;
            i32 dst = src * 4;
            u8 on = display[src];
            if on != 0 {
                pixels[dst]     = cast(u8, 204);
                pixels[dst + 1] = cast(u8, 255);
                pixels[dst + 2] = cast(u8, 102);
            } else {
                pixels[dst]     = cast(u8, 17);
                pixels[dst + 1] = cast(u8, 17);
                pixels[dst + 2] = cast(u8, 17);
            }
            pixels[dst + 3] = cast(u8, 255);
        }
    }
}

// ============================================================================
// Keyboard mapping: 1234/QWER/ASDF/ZXCV → Chip-8 hex keypad
// ============================================================================

i32 key_map(i32 kc) {
    if kc == SAPP_KEYCODE_1 { return 0x1; }
    if kc == SAPP_KEYCODE_2 { return 0x2; }
    if kc == SAPP_KEYCODE_3 { return 0x3; }
    if kc == SAPP_KEYCODE_4 { return 0xC; }
    if kc == SAPP_KEYCODE_Q { return 0x4; }
    if kc == SAPP_KEYCODE_W { return 0x5; }
    if kc == SAPP_KEYCODE_E { return 0x6; }
    if kc == SAPP_KEYCODE_R { return 0xD; }
    if kc == SAPP_KEYCODE_A { return 0x7; }
    if kc == SAPP_KEYCODE_S { return 0x8; }
    if kc == SAPP_KEYCODE_D { return 0x9; }
    if kc == SAPP_KEYCODE_F { return 0xE; }
    if kc == SAPP_KEYCODE_Z { return 0xA; }
    if kc == SAPP_KEYCODE_X { return 0x0; }
    if kc == SAPP_KEYCODE_C { return 0xB; }
    if kc == SAPP_KEYCODE_V { return 0xF; }
    return -1;
}

// ============================================================================
// Shaders — textured full-screen quad
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

// ============================================================================
// Sokol callbacks
// ============================================================================

void init() {
    sg_setup(&sg_desc{
        .environment = sglue_environment(),
        .logger = sglue_logger(),
    });

    pixels = alloc<u8>(CHIP8_W * CHIP8_H * 4);
    memset(pixels, 0, CHIP8_W * CHIP8_H * 4);

    // Streaming texture (64x32)
    tex_img = sg_make_image(&sg_image_desc{
        .width = CHIP8_W,
        .height = CHIP8_H,
        .pixel_format = SG_PIXELFORMAT_RGBA8,
        .usage.stream_update = true,
    });

    tex_smp = sg_make_sampler(&sg_sampler_desc{
        .min_filter = SG_FILTER_NEAREST,
        .mag_filter = SG_FILTER_NEAREST,
    });

    tex_view = sg_make_view(&sg_view_desc{ .texture.image = tex_img });

    // Full-screen quad: two triangles, each vertex is (pos.xy, uv.xy).
    f32[24] quad = {
        -1.0f,  1.0f, 0.0f, 0.0f,
         1.0f,  1.0f, 1.0f, 0.0f,
         1.0f, -1.0f, 1.0f, 1.0f,
        -1.0f,  1.0f, 0.0f, 0.0f,
         1.0f, -1.0f, 1.0f, 1.0f,
        -1.0f, -1.0f, 0.0f, 1.0f,
    };

    quad_vbuf = sg_make_buffer(&sg_buffer_desc{
        .data.ptr = &quad,
        .data.size = sizeof(quad),
    });

    // Shader
    sg_shader shd = sokol_make_shader(&quad_vs_shader, &quad_fs_shader);

    pip = sg_make_pipeline(&sg_pipeline_desc{
        .shader = shd,
        .layout.attrs[0].format = SG_VERTEXFORMAT_FLOAT2,
        .layout.attrs[1].format = SG_VERTEXFORMAT_FLOAT2,
    });

    // Init emulator and load ROM from global path set in main()
    chip8_init();
    if rom_path != null {
        load_rom(rom_path);
    } else {
        load_test_rom();
    }
}

void frame() {
    for i32 i = 0; i < INSTR_PER_FRAME; i++ {
        chip8_cycle();
    }
    if delay_timer > 0 { delay_timer--; }
    if sound_timer > 0 { sound_timer--; }

    update_pixels();

    sg_update_image(tex_img, &sg_image_data{
        .mip_levels[0].ptr = pixels,
        .mip_levels[0].size = CHIP8_W * CHIP8_H * 4,
    });

    sg_begin_pass(&sg_pass{
        .action.colors[0].load_action = SG_LOADACTION_CLEAR,
        .action.colors[0].clear_value = sg_color{ 0.0f, 0.0f, 0.0f, 1.0f },
        .swapchain = sglue_swapchain(),
    });
    sg_apply_pipeline(pip);
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
        i32 k = key_map(ev.key_code);
        if k >= 0 {
            keys[k] = true;
            if wait_key_reg >= 0 {
                V[wait_key_reg] = cast(u8, k);
                wait_key_reg = -1;
            }
        }
    }
    if ev.type == SAPP_EVENTTYPE_KEY_UP {
        i32 k = key_map(ev.key_code);
        if k >= 0 { keys[k] = false; }
    }
    if ev.type == SAPP_EVENTTYPE_QUIT_REQUESTED { sapp_quit(); }
}

void cleanup() {
    free(pixels);
    sg_shutdown();
}

sapp_desc sokol_main() {
    // Save ROM path for init callback
    rom_path = null;
    if get_argc() > 1 { rom_path = get_arg(1); }

    return sapp_desc{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = on_event,
        .icon.sokol_default = true,
        .width = CHIP8_W * SCALE,
        .height = CHIP8_H * SCALE,
        .sample_count = 1,
        .window_title = "CHIP-8",
    };
}
