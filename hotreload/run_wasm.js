// run_wasm.js — node host for the wasm hot-reload demo.
//
// Wasm can't load code into a running instance, so the loader half of
// the hot-reload story lives here: this host compiles script_wasm.mc
// with the compiler-as-wasm (minc.wasm, a fresh instance per compile),
// instantiates the fresh module, and binds its "engine" imports to the
// persistent engine instance. The engine module is never re-created,
// so the world survives every swap.
//
//   node run_wasm.js          automated demo: run v1, "edit" to v2,
//                             prove state persists across the swap
//   node run_wasm.js watch    live: edit script_wasm.mc + save;
//                             behavior changes on the next frame
//
// Needs node and an installed minc: the native compiler builds the
// engine module, and minc.wasm (shipped next to the minc binary)
// compiles the script at runtime. Overrides: MINC=<native compiler>,
// MINC_WASM=<wasm compiler>.
//
// User externs carry natural wasm types (matching exports), so the
// script's "engine" imports are satisfied by the engine instance's
// exports directly — the engine call path never leaves wasm.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const hrDir = __dirname;              // engine_wasm.mc + script_wasm.mc live here

function fail(msg) { console.error('error: ' + msg); process.exit(1); }

// --- locate the toolchain ---

function resolveExe(spec) {
  if (fs.existsSync(spec)) return spec;
  if (spec.includes(path.sep)) return null;
  const names = process.platform === 'win32' ? [spec + '.exe', spec] : [spec];
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    for (const n of names) {
      const p = path.join(dir, n);
      if (fs.existsSync(p)) return p;
    }
  }
  return null;
}

const nativeMinc = resolveExe(process.env.MINC || 'minc');
if (!nativeMinc) fail('minc not found on PATH (install: https://minc.dev, or set MINC)');

const wasmCompilerPath = process.env.MINC_WASM || path.join(path.dirname(nativeMinc), 'minc.wasm');
if (!fs.existsSync(wasmCompilerPath)) {
  fail('minc.wasm not found next to ' + nativeMinc + ' (it ships with the minc release; or set MINC_WASM)');
}

// --- build the engine module (native compiler, wasm target) ---

const enginePath = path.join(hrDir, 'hotreload_engine.wasm');
{
  const r = spawnSync(nativeMinc, ['engine_wasm.mc', '--target', 'wasm', '-o', enginePath],
    { cwd: hrDir, encoding: 'utf8' });
  if (r.error || r.status !== 0) {
    fail('engine compile failed:\n' + (r.stderr || r.stdout || String(r.error)));
  }
}

const compilerModule = new WebAssembly.Module(fs.readFileSync(wasmCompilerPath));
const engineModule = new WebAssembly.Module(fs.readFileSync(enginePath));

// --- in-wasm compiler: fresh instance per compile ---

const mathImports = {
  sin: Math.sin, cos: Math.cos, tan: Math.tan, sqrt: Math.sqrt,
  asin: Math.asin, acos: Math.acos, atan: Math.atan, atan2: Math.atan2,
  exp: Math.exp, log: Math.log, log2: Math.log2, log10: Math.log10,
  pow: Math.pow, fmod: (a, b) => a % b, fabs: Math.abs,
  floor: Math.floor, ceil: Math.ceil, trunc: Math.trunc, round: Math.round,
  sinf: Math.sin, cosf: Math.cos, tanf: Math.tan, sqrtf: Math.sqrt,
  asinf: Math.asin, acosf: Math.acos, atanf: Math.atan, atan2f: Math.atan2,
  expf: Math.exp, logf: Math.log, log2f: Math.log2, log10f: Math.log10,
  powf: Math.pow, fmodf: (a, b) => a % b, fabsf: Math.abs,
  floorf: Math.floor, ceilf: Math.ceil, truncf: Math.trunc, roundf: Math.round,
};

function readCStr(memory, ptr) {
  const u8 = new Uint8Array(memory.buffer);
  let end = Number(ptr);
  while (u8[end] !== 0) end++;
  return Buffer.from(u8.slice(Number(ptr), end)).toString('utf8');
}

// Compile `source` (as script_wasm.mc) over an in-memory VFS.
// Returns the .wasm bytes, or null with diagnostics on `log`.
function compileWeb(source) {
  const vfs = new Map([['script_wasm.mc', Buffer.from(source)]]);
  const argv = { args: ['minc', 'script_wasm.mc', '--target', 'wasm', '--no-color', '-o', 'script.wasm'], ptrs: [] };
  const fdMap = {};
  let nextFd = 10;
  let log = '';
  let inst = null;
  const env = {
    write: (fd, ptr, len) => {
      const u8 = new Uint8Array(inst.exports.memory.buffer);
      const data = Buffer.from(u8.slice(Number(ptr), Number(ptr) + Number(len)));
      const f = fdMap[Number(fd)];
      if (f && f.chunks) f.chunks.push(data);
      else log += data.toString('utf8');
      return BigInt(Number(len));
    },
    clock: () => BigInt(Math.round(performance.now() * 1e6)),
    open: (pathPtr, flags) => {
      const p = readCStr(inst.exports.memory, pathPtr).replace(/^\//, '');
      if (Number(flags) === 0) {
        const data = vfs.get(p);
        if (!data) return -1n;
        const fd = nextFd++;
        fdMap[fd] = { data, pos: 0 };
        return BigInt(fd);
      }
      const fd = nextFd++;
      fdMap[fd] = { chunks: [], path: p };
      return BigInt(fd);
    },
    read: (fd, bufPtr, len) => {
      const f = fdMap[Number(fd)];
      if (!f || !f.data) return 0n;
      const n = Math.min(Number(len), f.data.length - f.pos);
      if (n <= 0) return 0n;
      new Uint8Array(inst.exports.memory.buffer).set(f.data.subarray(f.pos, f.pos + n), Number(bufPtr));
      f.pos += n;
      return BigInt(n);
    },
    close: (fd) => {
      const f = fdMap[Number(fd)];
      if (f && f.chunks) vfs.set(f.path, Buffer.concat(f.chunks));
      delete fdMap[Number(fd)];
      return 0n;
    },
    get_argc: () => BigInt(argv.args.length),
    get_arg: (i) => BigInt(argv.ptrs[Number(i)] || 0),
    __sys_exit: (code) => { throw new Error('exit:' + Number(code)); },
  };
  inst = new WebAssembly.Instance(compilerModule, { env, math: mathImports });
  argv.ptrs = argv.args.map((a) => {
    const b = Buffer.from(a + '\0');
    const ptr = Number(inst.exports.__wasm_alloc(BigInt(b.length)));
    new Uint8Array(inst.exports.memory.buffer).set(b, ptr);
    return ptr;
  });
  let ret = 0;
  try { ret = Number(inst.exports.main()); }
  catch (e) {
    if (e.message && e.message.startsWith('exit:')) ret = parseInt(e.message.substring(5), 10) || 0;
    else throw e;
  }
  if (ret !== 0 || !vfs.get('script.wasm')) return { bytes: null, log };
  return { bytes: vfs.get('script.wasm'), log };
}

// --- the persistent engine instance ---

const stubEnv = { write: (fd, p, n) => n, clock: () => 0n };
const engine = new WebAssembly.Instance(engineModule, { env: stubEnv });
engine.exports.main();   // world_init: spawn the player at the origin

// The script's "engine" imports carry the same natural signatures as
// the engine's exports — the exports object IS the import namespace.
// This direct link is the wasm analogue of the HostApi fn-ptr table,
// and calls through it never cross into JS.
const engineApi = engine.exports;

// --- validate-then-swap (mirrors engine_reload in engine.mc) ---

let script = null;      // current script instance
let reloads = 0;

function reload(source) {
  const r = compileWeb(source);
  if (!r.bytes) {
    console.log('reload: compile failed:\n' + r.log.trimEnd().split('\n').map(l => '    ' + l).join('\n'));
    return false;
  }
  let cand;
  try {
    cand = new WebAssembly.Instance(new WebAssembly.Module(r.bytes), { engine: engineApi, env: stubEnv });
  } catch (e) {
    console.log('reload: instantiation failed — keeping previous (' + e.message + ')');
    return false;
  }
  if (!cand.exports.script_update || !cand.exports.script_abi_version) {
    console.log('reload: missing script entry points — keeping previous');
    return false;
  }
  if (cand.exports.script_abi_version() !== engine.exports.abi_version()) {
    console.log('reload: ABI mismatch — keeping previous');
    return false;
  }
  script = cand;
  reloads++;
  return true;
}

const playerX = () => engine.exports.get_pos_x(engine.exports.player());
const frame = (fire) => script.exports.script_update(0.5, 1.0, 0.0, fire);
const printFrame = (f) => console.log(`  frame ${f}: player.x=${playerX()} bullets=${engine.exports.bullet_count()}`);
const scriptPath = path.join(hrDir, 'script_wasm.mc');

// --- automated demo (default): mirrors run_demo in engine.mc ---

function runDemo() {
  const near = (a, b) => Math.abs(a - b) < 0.05;
  const v1 = fs.readFileSync(scriptPath, 'utf8');
  const v2 = v1.replace('f32 speed = 10.0f;', 'f32 speed = -25.0f;');
  if (v2 === v1) fail('v2 edit did not apply (script_wasm.mc changed?)');

  console.log('=== minc hot-reload demo (wasm) ===');
  console.log('-- script v1: move +x, speed 10 --');
  if (!reload(v1)) fail('v1 compile/swap failed');
  for (let f = 0; f < 3; f++) { frame(0); printFrame(f); }
  const px1 = playerX();

  console.log('-- broken edit: compile fails, previous module kept --');
  if (reload(v2 + '\nthis is not minc;')) fail('broken script was accepted');

  console.log('-- edit -> script v2: move -x, speed 25, fire --');
  if (!reload(v2)) fail('v2 compile/swap failed');
  for (let f = 3; f < 6; f++) { frame(1); printFrame(f); }
  const px2 = playerX();
  const bullets = Number(engine.exports.bullet_count());
  const ticks = Number(engine.exports.get_state());

  console.log('-- results --');
  console.log(`  v1 end x = ${px1} (expect 15)`);
  console.log(`  v2 end x = ${px2} (expect -22.5; a reset world would be -37.5)`);
  console.log(`  bullets  = ${bullets} (expect 3)`);
  console.log(`  reloads  = ${reloads} (expect 2)`);
  console.log(`  ticks    = ${ticks} (expect 6, engine-side state slot carried across swap)`);

  let ok = true;
  if (!near(px1, 15.0)) { console.log('FAIL: v1 end position wrong'); ok = false; }
  if (!near(px2, -22.5)) { console.log('FAIL: v2 end position wrong (state not persisted across reload?)'); ok = false; }
  if (bullets !== 3) { console.log('FAIL: bullet count wrong (v2 fire not applied?)'); ok = false; }
  if (reloads !== 2) { console.log('FAIL: reload count wrong'); ok = false; }
  if (ticks !== 6) { console.log('FAIL: engine-side script state lost across reload'); ok = false; }

  if (!ok) process.exit(1);
  console.log('demo: all checks passed');
}

// --- watch mode: recompile the real script file on change ---

function runWatch() {
  let lastSrc = null;
  const tryReload = () => {
    let src;
    try { src = fs.readFileSync(scriptPath, 'utf8'); } catch { return; }
    if (src === lastSrc) return;       // no-op save
    lastSrc = src;
    if (reload(src)) console.log('script: reloaded');
  };
  tryReload();
  fs.watchFile(scriptPath, { interval: 200 }, tryReload);
  console.log('watching script_wasm.mc — edit + save to reload. ctrl+c quits');
  let t = 0;
  setInterval(() => {
    if (script) frame(0);
    if (t % 10 === 0) printFrame(t);
    t++;
  }, 100);
}

if (process.argv[2] === 'watch') runWatch();
else runDemo();
