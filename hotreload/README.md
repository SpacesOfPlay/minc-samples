
# minc hot-reload demo

A stable engine binary that recompiles and hot-swaps its game logic at
runtime via libminc, the embeddable minc JIT compiler.

- `game_abi.mc` - the frozen engine↔script contract. The script refers
  to engine data by integer handle, never a retained pointer.
- `script.mc` - the hot-reloadable game logic: a stateless function
  over engine data.
- `engine.mc` - the host. Owns all persistent state, recompiles the
  script on change, and swaps it in at a frame boundary
  (validate-then-swap: a broken compile keeps the previous module).

The engine owns 100% of the state, so a reload swaps code with the
world untouched. No state migration, no stale pointers.


## Build & run

In a minc-samples checkout (installed minc), from the checkout root
(same on Windows, macOS, Linux):

```
minc run hotreload            # automated demo
minc run hotreload watch      # live: edit script.mc + save
```

or directly:

```
minc run hotreload/engine.mc
```

`minc run` resolves libminc from the install dir (Windows via PATH,
macOS/Linux via the run fallback). A binary built with `-o` and run
by hand needs libminc next to it on macOS/Linux — copy it once:
```
cd hotreload
minc engine.mc -o hotreload_engine.exe
cp "$(dirname "$(command -v minc)")"/libminc.* .
./hotreload_engine.exe          # automated demo
./hotreload_engine.exe watch    # live: edit script.mc + save
```

The automated demo runs script v1, "edits" it to v2, and verifies the
world state persisted across the swap. `watch` goes live: edit
`script.mc`, save, and behavior changes on the next frame.

The engine finds its files relative to the cwd. Run it from inside
this folder or the parent folder.


## Wasm variant

`engine_wasm.mc` + `script_wasm.mc` are the same demo for the wasm
target. Wasm can't load code into a running instance, so the loader
half of libminc moves into the host: JS compiles the script with the
compiler-built-as-wasm (`minc.wasm`, shipped with the minc release),
instantiates the fresh module, and binds its `engine` imports to the
engine instance's exports. The engine instance is never re-created, so the world
survives every swap. The seam is scalars only — wasm modules share no
memory, so no pointer crosses (the wasm shape of the portable variant
below).

Needs node and an installed minc — `run_wasm.js` finds `minc` on
PATH and `minc.wasm` next to it (overrides: `MINC`, `MINC_WASM`):

```
node hotreload/run_wasm.js          # automated demo
node hotreload/run_wasm.js watch    # live: edit script_wasm.mc + save
```

The automated demo mirrors the native one, plus a broken edit that
must be rejected while the previous script keeps running.


## Boundary rules

`float2` crosses the engine <-> script boundary by value. That's safe
because engine and script are compiled by the same minc in lockstep;
vector builtins pass in registers under both the minc and C ABIs. For
a boundary a C program could call, pass vectors by pointer instead. 
See the "Portable / C-interop variant" in `game_abi.mc`.
