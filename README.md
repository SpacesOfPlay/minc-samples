# minc-samples

Example programs and benchmarks for the [minc](https://minc.dev)
compiler.

## Setup

Install minc first:

```
# Windows
powershell -c "irm minc.dev/install.ps1 | iex"

# macOS / Linux
curl -fsSL https://minc.dev/install | bash
```

Then clone this repo and run any example straight from the root:

```
git clone https://github.com/SpacesOfPlay/minc-samples
cd minc-samples
minc run hello.mc
minc run sokol_cube.mc
minc run raytracer.mc
```

`minc run` compiles to a temp file and launches it in one step.
`minc build <file.mc> -o <out>` produces a standalone executable.

## Examples

| Example | What it shows |
|---|---|
| `hello.mc` | smallest program |
| `mandelbrot.mc` | terminal Mandelbrot |
| `raytracer.mc`, `raytracer_mt.mc` | software raytracer, single- and multi-threaded |
| `chip8.mc` | CHIP-8 emulator (sokol) |
| `missile_command.mc` | small game (sokol) |
| `sokol_cube.mc`, `sokol_texcube.mc` | 3D basics, texturing |
| `sokol_mandelbrot.mc` | GPU Mandelbrot |
| `sokol_compute.mc`, `sokol_compute_rw.mc` | compute shaders |
| `sokol_particles_compute.mc`, `sokol_sphere_physics.mc` | compute-driven particles / physics |
| `imgui_demo.mc` | Dear ImGui |
| `audio_sine.mc`, `audio_push.mc` | audio output |
| `json_export.mc` | JSON writing |
| `web_server.mc` | HTTP server |
| `shim_demo.mc` | linking C code (`minc run shim_demo.mc`, needs a C compiler) |
| `hotreload/` | hot-reload minc scripts into a running engine via libminc |

Graphics examples read assets from `test/` relative to the cwd, so
run them from the repo root. `lib/` holds shared helper headers some
examples import (`frame_timer.mc`); everything else resolves against
the installed compiler's standard library.

The hot-reload demo lives in its own folder because it is three files
(engine, contract, script). Build steps in `hotreload/README.md`.

## Build script

This folder is a minc project: `build.mc` scripts the builds, and the
`minc` verbs drive it (same on Windows, macOS, and Linux). The compiler
is found on PATH; set `MINC` to point at an install dir or binary.

```
minc run                       # list the examples
minc run sokol_cube            # build + run an example
minc build sokol_cube          # compile only
minc bench                     # benchmark suite vs a reference C compiler
minc bench matmul              # single benchmark
minc run shim_demo.mc          # C-interop demo (needs a C compiler)
minc wasm sokol_cube           # compile to wasm, open in browser
minc run hotreload watch       # hot-reload demo with live editing
minc run macos-app sokol_cube  # .app bundle (macOS host)
minc run ios-sim sokol_cube    # iOS simulator (macOS host)
minc run ios sokol_cube        # iOS device (macOS host)
minc run android sokol_cube    # Android APK + install + launch
minc clean
```

`minc build <platform> <example>` packages without installing or
launching.

### iOS (macOS host)

Simulator needs Xcode with an iOS runtime. Device builds need an
Apple Developer account:

1. Get your Team ID (Xcode → Settings → Accounts).
2. Build any iOS app in Xcode once to generate a wildcard
   provisioning profile.
3. `export MINC_TEAM_ID=YOUR_TEAM_ID` (persist it in `~/.zprofile`).
4. `minc run ios sokol_cube`

Set `MINC_BUNDLE_PREFIX=com.yourcompany` to override the default
`com.minc` bundle-id prefix.

### Android

Needs an Android SDK with NDK plus a JDK for APK packaging:

```
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"
sdkmanager "ndk;27.2.12479018"
export ANDROID_HOME=~/Library/Android/sdk   # macOS default; Linux: ~/Android/Sdk
minc run android sokol_cube
```

The script auto-detects JDK, NDK, and build tools; with no device
attached it boots the first available emulator.

## License

MIT — see `LICENSE.md`.
