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

Don't clone this repo inside another minc source tree — imports
resolve against the nearest `lib/` on the cwd path, and a parent
tree's `lib/` would shadow the installed compiler's.

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
| `shim_demo.mc` | linking C code (see `build.sh shim`) |
| `hotreload/` | hot-reload minc scripts into a running engine via libminc |

Graphics examples read assets from `test/` relative to the cwd, so
run them from the repo root. `lib/` holds shared helper headers some
examples import (`frame_timer.mc`); everything else resolves against
the installed compiler's own standard library.

The hot-reload demo lives in its own folder because it is three files
(engine, contract, script) — build steps in `hotreload/README.md`.

## Build script

`build.sh` (macOS / Linux) and `build.ps1` (Windows) wrap the less
one-liner-able flows. The compiler is found on PATH; set `MINC` to
point at a specific binary.

```
./build.sh bench                   # benchmark suite vs a reference C compiler
./build.sh bench matmul            # single benchmark
./build.sh shim                    # C-interop demo (needs a C compiler)
./build.sh wasm sokol_cube         # compile to wasm, open in browser
./build.sh macos-app sokol_cube    # .app bundle (macOS host)
./build.sh ios-sim sokol_cube      # iOS simulator (macOS host)
./build.sh ios sokol_cube          # iOS device (macOS host)
./build.sh android sokol_cube      # Android APK + install + launch
```

### iOS (macOS host)

Simulator needs Xcode with an iOS runtime. Device builds need an
Apple Developer account:

1. Get your Team ID (Xcode → Settings → Accounts).
2. Build any iOS app in Xcode once to generate a wildcard
   provisioning profile.
3. `export MINC_TEAM_ID=YOUR_TEAM_ID` (persist it in `~/.zprofile`).
4. `./build.sh ios sokol_cube`

Set `MINC_BUNDLE_PREFIX=com.yourcompany` to override the default
`com.minc` bundle-id prefix.

### Android

Needs an Android SDK with NDK plus a JDK for APK packaging:

```
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"
sdkmanager "ndk;27.2.12479018"
export ANDROID_HOME=~/Library/Android/sdk   # macOS default; Linux: ~/Android/Sdk
./build.sh android sokol_cube
```

The script auto-detects JDK, NDK, and build tools; with no device
attached it boots the first available emulator.

## License

MIT — see `LICENSE.md`. Build freely on these.
