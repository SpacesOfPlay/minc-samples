#!/bin/bash
# build.sh — minc build script (Linux/macOS)
# Usage: ./build.sh <command> [args]
#   ./build.sh hello              — compile and run hello.mc
#   ./build.sh raytracer          — compile and launch raytracer
#   ./build.sh chip8              — compile and launch CHIP-8 emulator
#   ./build.sh missile            — compile and launch Missile Command
#   ./build.sh sokol_cube         — compile and launch sokol cube demo
#   ./build.sh hotreload [watch]  — compile and run the hot-reload demo
#   ./build.sh wasm sokol_cube    — compile to wasm and open in browser
#   ./build.sh bench              — run all benchmarks
#   ./build.sh bench <name>       — run a single benchmark
#   ./build.sh compile <file.mc>  — compile a .mc file

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"

# minc: $MINC override (install dir, or a direct binary path), else
# PATH (installed toolchain), else next to this script (manual zip
# layout).
if [ -n "${MINC:-}" ]; then
    if [ -d "$MINC" ]; then CC="$MINC/minc"; else CC="$MINC"; fi
elif command -v minc >/dev/null 2>&1; then
    CC="$(command -v minc)"
else
    CC="$SCRIPT_DIR/minc"
fi

if [ ! -f "$CC" ]; then
    echo -e "${RED}ERROR: minc not found. Install it (https://minc.dev) or set MINC to the install dir.${NC}"
    exit 1
fi
mkdir -p "$BUILD_DIR"

# Pick a reference C compiler for benchmarks: clang on macOS, gcc
# on Linux. Either can stand in for the other if one is missing.
OS=$(uname -s)
if [ "$OS" = "Darwin" ]; then
    if   command -v clang &>/dev/null; then REF_CC="clang"; REF_NAME="clang"
    elif command -v gcc   &>/dev/null; then REF_CC="gcc";   REF_NAME="gcc"
    else REF_CC=""; REF_NAME=""
    fi
else
    if   command -v gcc   &>/dev/null; then REF_CC="gcc";   REF_NAME="gcc"
    elif command -v clang &>/dev/null; then REF_CC="clang"; REF_NAME="clang"
    else REF_CC=""; REF_NAME=""
    fi
fi

build_console() {
    local name="$1" src="$2"
    local exe="$BUILD_DIR/$name"
    echo -e "${CYAN}Compiling $name...${NC}"
    "$CC" "$src" -o "$exe"
    chmod +x "$exe"
    local size
    size=$(du -k "$exe" | cut -f1)
    echo -e "${GREEN}Built: $exe (${size} KB)${NC}"
    echo -e "${CYAN}Running...${NC}"
    "$exe"
}

build_sokol() {
    local name="$1" src="$2"
    local exe="$BUILD_DIR/$name"
    echo -e "${CYAN}Compiling $name (sokol)...${NC}"
    "$CC" "$src" -o "$exe"
    chmod +x "$exe"
    local size
    size=$(du -k "$exe" | cut -f1)
    echo -e "${GREEN}Built: $exe (${size} KB)${NC}"
    echo -e "${CYAN}Launching...${NC}"
    "$exe" &
}

# Delegate to minc's built-in `run --target wasm`. minc.exe compiles
# the example, stages the harness from lib/wasm/, opens the browser,
# and serves on http://127.0.0.1:8080 until Ctrl+C or /__shutdown.
# No external server binary, no manual staging.
build_wasm() {
    local name="$1"
    local src="$EXAMPLES_DIR/$name.mc"
    if [ ! -f "$src" ]; then
        echo -e "${RED}example not found: $src${NC}"
        exit 1
    fi
    exec "$CC" run "$src" --target wasm
}

# Build the C-shim FFI example: compile the C object freestanding, then
# the minc app whose @link tag merges it in. The C compiler is the same
# one used for benchmark references (gcc on Linux, clang on macOS).
build_shim() {
    if [ -z "$REF_CC" ]; then
        echo -e "${RED}shim demo needs a C compiler (gcc or clang) on PATH${NC}"
        exit 1
    fi
    local cflags="-c -fno-stack-protector" obj
    if [ "$OS" = "Darwin" ]; then
        obj="$BUILD_DIR/shim_demo_macos.o"
    else
        obj="$BUILD_DIR/shim_demo_linux.o"
        cflags="$cflags -fno-pie"
    fi
    echo -e "${CYAN}Compiling C shim ($REF_CC)...${NC}"
    "$REF_CC" $cflags "$EXAMPLES_DIR/shim_demo.c" -o "$obj"
    build_console "shim_demo" "$EXAMPLES_DIR/shim_demo.mc"
}

# File size in bytes (Linux + macOS).
file_size() { stat -c%s "$1" 2>/dev/null || stat -f%z "$1"; }

do_bench() {
    local filter="${1:-}"
    local bench_dir="$SCRIPT_DIR/bench"
    local benchmarks=( fib_iter sieve fib_rec qsort matmul lex_scan binary_tree hash_probe nbody bitcount histogram dp_edit mandelbrot strscan struct_traverse divconst bitops branch_chain cast_loop list_sum indirect_call u32_index matmul_f64 nbody_f64 dot_f64 poly_f64 particle_f64 particle2_f64 conv_f64 conv_f64_v2 conv_f64_v3 conv_f64_v4 vec4_transform mat4_mul )

    if [ -n "$filter" ]; then
        local matched=()
        for b in "${benchmarks[@]}"; do
            if [ "$b" = "$filter" ]; then matched+=("$b"); fi
        done
        if [ ${#matched[@]} -eq 0 ]; then
            local lower_filter; lower_filter=$(echo "$filter" | tr '[:upper:]' '[:lower:]')
            for b in "${benchmarks[@]}"; do
                local lower_b; lower_b=$(echo "$b" | tr '[:upper:]' '[:lower:]')
                case "$lower_b" in *"$lower_filter"*) matched+=("$b") ;; esac
            done
        fi
        if [ ${#matched[@]} -eq 0 ]; then
            echo -e "${RED}No benchmark matches '$filter'.${NC}"
            echo "Available benchmarks:"
            for b in "${benchmarks[@]}"; do echo "  $b"; done
            return 1
        fi
        benchmarks=("${matched[@]}")
    fi

    echo "=== minc benchmark suite ==="
    echo "Compiler: $CC"
    if [ -n "$REF_CC" ]; then
        echo "Reference: $REF_NAME -O2"
    else
        echo "Reference: not found (minc-only mode)"
    fi
    if [ -n "$filter" ]; then echo "Filter:   $filter (${#benchmarks[@]} matched)"; fi
    echo ""

    local ref_label="${REF_NAME:-ref}"
    printf "%-16s %12s %12s %8s %10s %10s %s\n" \
        "Benchmark" "minc (us)" "$ref_label (us)" "Ratio" "minc (KB)" "$ref_label (KB)" "Result"
    printf "%-16s %12s %12s %8s %10s %10s %s\n" \
        "---------" "---------" "---------" "-----" "---------" "---------" "------"

    local total_minc=0 total_ref=0 nbench=0

    for name in "${benchmarks[@]}"; do
        local mc_src="$bench_dir/bench_$name.mc"
        local mc_exe="$BUILD_DIR/bench_${name}_minc"
        local c_src="$bench_dir/bench_$name.c"
        local c_exe="$BUILD_DIR/bench_${name}_ref"

        if ! "$CC" "$mc_src" -o "$mc_exe" 2>/dev/null; then
            printf "%-16s %12s %12s %8s %10s %10s %s\n" "$name" "CERR" "-" "-" "-" "-" "minc compile failed"
            continue
        fi
        chmod +x "$mc_exe"
        local mc_size
        mc_size=$(awk "BEGIN{printf \"%.1f\", $(file_size "$mc_exe") / 1024.0}")

        local ref_size="-"
        if [ -n "$REF_CC" ]; then
            local fp_flag=""
            if [[ "$name" == *f64* ]] || [[ "$name" == "mandelbrot" ]] || [[ "$name" == vec4_* ]]; then
                fp_flag="-ffp-contract=off"
            fi
            if ! $REF_CC -O2 -fwrapv $fp_flag -o "$c_exe" "$c_src" -lm 2>/dev/null; then
                printf "%-16s %12s %12s %8s %10s %10s %s\n" "$name" "-" "CERR" "-" "$mc_size" "-" "$REF_NAME compile failed"
                continue
            fi
            ref_size=$(awk "BEGIN{printf \"%.1f\", $(file_size "$c_exe") / 1024.0}")
        fi

        local mc_out
        mc_out=$("$mc_exe" 2>&1) || true
        if [ -z "$mc_out" ]; then
            printf "%-16s %12s %12s %8s %10s %10s %s\n" "$name" "FAIL" "-" "-" "$mc_size" "$ref_size" "minc runtime error"
            continue
        fi
        local mc_val mc_time
        mc_val=$(echo "$mc_out" | grep -o 'result=[^ ]*' | head -1 | cut -d= -f2)
        mc_time=$(echo "$mc_out" | grep -o 'time=[0-9]*' | head -1 | cut -d= -f2)

        if [ -z "$REF_CC" ]; then
            total_minc=$((total_minc + mc_time))
            nbench=$((nbench + 1))
            printf "%-16s %12s %12s %8s %10s %10s %s\n" "$name" "$mc_time" "-" "-" "$mc_size" "-" "OK (result=$mc_val)"
            continue
        fi

        local ref_out
        ref_out=$("$c_exe" 2>&1) || true
        if [ -z "$ref_out" ]; then
            printf "%-16s %12s %12s %8s %10s %10s %s\n" "$name" "$mc_time" "FAIL" "-" "$mc_size" "$ref_size" "$REF_NAME runtime error"
            continue
        fi
        local ref_val ref_time
        ref_val=$(echo "$ref_out" | grep -o 'result=[^ ]*' | head -1 | cut -d= -f2)
        ref_time=$(echo "$ref_out" | grep -o 'time=[0-9]*' | head -1 | cut -d= -f2)

        local result_ok="false"
        if [ "$mc_val" = "$ref_val" ]; then
            result_ok="true"
        elif [[ "$mc_val" =~ ^-?[0-9]+$ ]] && [[ "$ref_val" =~ ^-?[0-9]+$ ]]; then
            local diff=$(( mc_val > ref_val ? mc_val - ref_val : ref_val - mc_val ))
            local tol=1
            if [[ "$name" == *f64* ]] || [[ "$name" == "mandelbrot" ]] || [[ "$name" == vec4_* ]]; then tol=100; fi
            [ "$diff" -le "$tol" ] && result_ok="true"
        fi
        if [ "$result_ok" = "false" ]; then
            printf "%-16s %12s %12s %8s %10s %10s %s\n" \
                "$name" "$mc_time" "$ref_time" "-" "$mc_size" "$ref_size" "MISMATCH! minc=$mc_val $REF_NAME=$ref_val"
            continue
        fi

        local ratio_str="-"
        if [ -n "$ref_time" ] && [ "$ref_time" -gt 0 ] 2>/dev/null; then
            ratio_str=$(awk "BEGIN{printf \"%.2fx\", $mc_time / $ref_time}")
            total_minc=$((total_minc + mc_time))
            total_ref=$((total_ref + ref_time))
            nbench=$((nbench + 1))
        fi
        printf "%-16s %12s %12s %8s %10s %10s %s\n" "$name" "$mc_time" "$ref_time" "$ratio_str" "$mc_size" "$ref_size" "OK"
    done

    echo ""
    if [ -n "$REF_CC" ] && [ "$nbench" -gt 0 ] && [ "$total_ref" -gt 0 ]; then
        local avg; avg=$(awk "BEGIN{printf \"%.2fx\", $total_minc / $total_ref}")
        printf "%-16s %12s %12s %8s\n" "TOTAL" "$total_minc" "$total_ref" "$avg"
    elif [ "$nbench" -gt 0 ]; then
        echo "Total time: ${total_minc} us (across $nbench benchmarks)"
    fi
    echo ""
    local bin_size; bin_size=$(file_size "$CC")
    local bin_kb; bin_kb=$(awk "BEGIN{printf \"%.1f\", $bin_size / 1024.0}")
    echo "minc compiler: $bin_size bytes ($bin_kb KB)"
}

# --- Configurable via environment ---
MINC_TEAM_ID="${MINC_TEAM_ID:-}"
MINC_BUNDLE_PREFIX="${MINC_BUNDLE_PREFIX:-com.minc}"

# Copy test/ assets into an .app bundle so examples find them at
# runtime. Same layout as the CLI bundle, just relocated under the
# .app's resource directory.
_stage_app_assets() {
    local app_dir="$1" subpath="$2"
    if [ ! -d "$SCRIPT_DIR/test" ]; then return; fi
    mkdir -p "$app_dir/$subpath"
    # Media assets only (.png, .jpg, .wav, ...).
    find "$SCRIPT_DIR/test" -type f \
        \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \
        -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.bin" \) \
        -print0 2>/dev/null \
    | while IFS= read -r -d '' src; do
        local rel="${src#$SCRIPT_DIR/test/}"
        local dst="$app_dir/$subpath/$rel"
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
    done
}

# --- macOS .app ---
# Wrap an example as a double-clickable .app bundle. Optional —
# the regular `./build.sh <example>` route produces a plain CLI
# binary instead.
do_macos_app() {
    if [ "$OS" != "Darwin" ]; then echo -e "${RED}macos-app requires macOS${NC}"; exit 1; fi
    local app_name="${1:-sokol_cube}"
    local src="$EXAMPLES_DIR/$app_name.mc"
    if [ ! -f "$src" ]; then echo -e "${RED}Example not found: $src${NC}"; exit 1; fi

    echo -e "${CYAN}Compiling $app_name (macOS .app)...${NC}"
    "$CC" "$src" --target macos -o "$BUILD_DIR/$app_name"

    local app_dir="$BUILD_DIR/${app_name}.app"
    local bundle_id="${MINC_BUNDLE_PREFIX}.$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
    rm -rf "$app_dir"
    mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
    cp "$BUILD_DIR/$app_name" "$app_dir/Contents/MacOS/$app_name"
    chmod +x "$app_dir/Contents/MacOS/$app_name"

    cat > "$app_dir/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>$app_name</string>
    <key>CFBundleName</key><string>$app_name</string>
    <key>CFBundleIdentifier</key><string>$bundle_id</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

    _stage_app_assets "$app_dir/Contents/Resources" "test"
    codesign -s - "$app_dir" 2>/dev/null
    echo -e "${GREEN}Bundle: $app_dir${NC}"
    if [ "${2:-}" = "--open" ]; then
        echo -e "${CYAN}Launching...${NC}"
        open "$app_dir"
    fi
}

# --- iOS Simulator ---
do_ios_sim() {
    if [ "$OS" != "Darwin" ]; then echo -e "${RED}iOS simulator requires macOS${NC}"; exit 1; fi
    local app_name="${1:-sokol_cube}"
    local src="$EXAMPLES_DIR/$app_name.mc"
    if [ ! -f "$src" ]; then echo -e "${RED}Example not found: $src${NC}"; exit 1; fi

    echo -e "${CYAN}Compiling $app_name (iOS Simulator)...${NC}"
    "$CC" "$src" --target ios-sim -o "$BUILD_DIR/$app_name"

    local app_dir="$BUILD_DIR/${app_name}.app"
    local bundle_id="${MINC_BUNDLE_PREFIX}.$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
    rm -rf "$app_dir"; mkdir -p "$app_dir"
    cp "$BUILD_DIR/$app_name" "$app_dir/$app_name"
    chmod +x "$app_dir/$app_name"
    cat > "$app_dir/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>$app_name</string>
    <key>CFBundleIdentifier</key><string>$bundle_id</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>MinimumOSVersion</key><string>15.0</string>
    <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
    <key>DTPlatformName</key><string>iphonesimulator</string>
</dict></plist>
PLIST
    _stage_app_assets "$app_dir" "test"
    codesign -s - "$app_dir" 2>/dev/null

    local sim_id=$(xcrun simctl list devices booted -j 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('devices',{}).values():
    for dev in r:
        if dev.get('state')=='Booted': print(dev['udid']); sys.exit()
" 2>/dev/null)
    if [ -z "$sim_id" ]; then
        sim_id=$(xcrun simctl list devices available -j 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('devices',{}).values():
    for dev in r:
        if dev.get('isAvailable',False): print(dev['udid']); sys.exit()
" 2>/dev/null)
        if [ -n "$sim_id" ]; then
            echo -e "${CYAN}Booting simulator...${NC}"
            xcrun simctl boot "$sim_id" 2>/dev/null
            open -a Simulator 2>/dev/null
            sleep 3
        fi
    fi
    if [ -z "$sim_id" ]; then echo -e "${RED}No simulator available. Install one in Xcode.${NC}"; exit 1; fi

    xcrun simctl install booted "$app_dir" 2>&1
    sleep 1
    xcrun simctl launch booted "$bundle_id" 2>&1
    echo -e "${GREEN}$app_name running in iOS Simulator${NC}"
}

# --- iOS device ---
do_ios_device() {
    if [ "$OS" != "Darwin" ]; then echo -e "${RED}iOS device requires macOS${NC}"; exit 1; fi
    local app_name="${1:-sokol_cube}"
    local src="$EXAMPLES_DIR/$app_name.mc"
    if [ ! -f "$src" ]; then echo -e "${RED}Example not found: $src${NC}"; exit 1; fi
    local sdk_path=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
    if [ -z "$sdk_path" ]; then echo -e "${RED}iOS SDK not found. Install Xcode.${NC}"; exit 1; fi

    local prof_path
    prof_path=$(ls "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision 2>/dev/null | head -1)
    if [ -z "$prof_path" ]; then
        prof_path=$(ls "$HOME/Library/MobileDevice/Provisioning Profiles"/*.mobileprovision 2>/dev/null | head -1)
    fi
    local profile_team=""
    if [ -n "$prof_path" ]; then
        profile_team=$(python3 -c "
import plistlib, subprocess
p = subprocess.run(['security', 'cms', '-D', '-i', '$prof_path'], capture_output=True)
data = plistlib.loads(p.stdout)
teams = data.get('TeamIdentifier', [])
if teams: print(teams[0])
" 2>/dev/null)
    fi
    local sign_id=""
    if [ -n "$profile_team" ]; then
        while IFS= read -r line; do
            local cert_name=$(echo "$line" | sed 's/.*"\(.*\)"/\1/')
            if [ -z "$cert_name" ]; then continue; fi
            local cert_ou=$(security find-certificate -c "$cert_name" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | grep -o "OU = [^,]*" | sed 's/OU = //')
            if [ "$cert_ou" = "$profile_team" ]; then
                sign_id="$cert_name"
                break
            fi
        done < <(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development")
    fi
    if [ -z "$sign_id" ]; then
        sign_id=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/')
    fi
    if [ -z "$sign_id" ]; then
        echo -e "${RED}No code signing identity found. Sign in to Xcode (Settings > Accounts).${NC}"
        exit 1
    fi

    echo -e "${CYAN}Compiling $app_name (iOS device)...${NC}"
    "$CC" "$src" --target ios -o "$BUILD_DIR/$app_name"
    local app_dir="$BUILD_DIR/${app_name}_device.app"
    local bundle_id="${MINC_BUNDLE_PREFIX}.$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
    rm -rf "$app_dir"; mkdir -p "$app_dir"
    cp "$BUILD_DIR/$app_name" "$app_dir/$app_name"
    chmod +x "$app_dir/$app_name"

    local orientation_xml
    case "$app_name" in
        sokol_compute|raytracer_mt|missile_command)
            orientation_xml='<string>UIInterfaceOrientationLandscapeRight</string><string>UIInterfaceOrientationLandscapeLeft</string>'
            ;;
        *)
            orientation_xml='<string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string>'
            ;;
    esac

    cat > "$app_dir/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>$app_name</string>
    <key>CFBundleName</key><string>$app_name</string>
    <key>CFBundleIdentifier</key><string>$bundle_id</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>MinimumOSVersion</key><string>15.0</string>
    <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
    <key>DTPlatformName</key><string>iphoneos</string>
    <key>UISupportedInterfaceOrientations</key><array>${orientation_xml}</array>
    <key>UIApplicationSceneManifest</key><dict>
        <key>UIApplicationSupportsMultipleScenes</key><false/>
        <key>UISceneConfigurations</key><dict>
            <key>UIWindowSceneSessionRoleApplication</key><array>
                <dict>
                    <key>UISceneConfigurationName</key><string>Default Configuration</string>
                    <key>UISceneDelegateClassName</key><string>_sapp_scene_delegate</string>
                </dict>
            </array>
        </dict>
    </dict>
    <key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST

    local team_id
    team_id=$(security find-certificate -c "$sign_id" -p 2>/dev/null | openssl x509 -noout -subject -nameopt multiline 2>/dev/null | grep organizationalUnitName | sed 's/.*= //')
    if [ -z "$team_id" ]; then team_id="$profile_team"; fi
    cat > "$BUILD_DIR/_entitlements.plist" << ENTPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>application-identifier</key><string>${team_id}.${bundle_id}</string>
    <key>keychain-access-groups</key><array><string>${team_id}.*</string></array>
    <key>get-task-allow</key><true/>
    <key>com.apple.developer.team-identifier</key><string>${team_id}</string>
</dict></plist>
ENTPLIST

    if [ -n "$prof_path" ]; then
        cp "$prof_path" "$app_dir/embedded.mobileprovision"
    else
        echo -e "${YELLOW}Warning: No provisioning profile found. Device install may fail.${NC}"
    fi
    _stage_app_assets "$app_dir" "test"
    echo -e "${CYAN}Signing with: $sign_id${NC}"
    codesign -s "$sign_id" --entitlements "$BUILD_DIR/_entitlements.plist" "$app_dir" 2>&1
    echo -e "${GREEN}Bundle: $app_dir${NC}"

    echo -e "${CYAN}Looking for connected device...${NC}"
    local device_id
    xcrun devicectl list devices --json-output "$BUILD_DIR/_devices.json" 2>/dev/null
    device_id=$(python3 -c "
import json, sys
data = json.load(open('$BUILD_DIR/_devices.json'))
for d in data.get('result', {}).get('devices', []):
    if d.get('connectionProperties', {}).get('transportType') in ('wired', 'localNetwork'):
        print(d['identifier']); sys.exit(0)
" 2>/dev/null)
    if [ -z "$device_id" ]; then
        echo -e "${YELLOW}No iOS device connected.${NC}"
        echo "Bundle ready at: $app_dir"
        echo "Connect a device, then:"
        echo "  xcrun devicectl device install app --device <id> $app_dir"
        echo "  xcrun devicectl device process launch --device <id> $bundle_id"
        return
    fi
    echo "  Device: $device_id"
    echo -e "${CYAN}Installing...${NC}"
    xcrun devicectl device install app --device "$device_id" "$app_dir" 2>&1
    echo -e "${CYAN}Launching $app_name...${NC}"
    xcrun devicectl device process launch --device "$device_id" "$bundle_id" 2>&1
    echo -e "${GREEN}$app_name running on device${NC}"
}

# --- Android ---
do_android() {
    local app_name="${1:-sokol_cube}"
    local src="$EXAMPLES_DIR/$app_name.mc"
    if [ ! -f "$src" ]; then echo -e "${RED}Example not found: $src${NC}"; exit 1; fi

    if ! java -version >/dev/null 2>&1; then
        local jdk_dir=$(find "$HOME/Library/Java" -maxdepth 1 -name "jdk-*" -type d 2>/dev/null | sort -V | tail -1)
        if [ -n "$jdk_dir" ] && [ -f "$jdk_dir/Contents/Home/bin/java" ]; then
            export JAVA_HOME="$jdk_dir/Contents/Home"
            export PATH="$JAVA_HOME/bin:$PATH"
        fi
    fi
    local sdk_home="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
    if [ -d "$sdk_home/platform-tools" ] && ! command -v adb >/dev/null 2>&1; then
        export PATH="$sdk_home/platform-tools:$sdk_home/emulator:$PATH"
    fi
    local ndk_dir=$(ls -d "$sdk_home/ndk/"* 2>/dev/null | sort -V | tail -1)
    if [ -z "$ndk_dir" ]; then echo -e "${RED}Android NDK not found. See SETUP.md${NC}"; exit 1; fi
    local ndk_cc=""
    for ndk_arch in darwin-aarch64 darwin-x86_64 linux-x86_64; do
        local c="$ndk_dir/toolchains/llvm/prebuilt/$ndk_arch/bin/clang"
        if [ -f "$c" ]; then ndk_cc="$c"; break; fi
    done
    if [ -z "$ndk_cc" ]; then echo -e "${RED}NDK clang not found${NC}"; exit 1; fi
    local build_tools_dir=$(ls -d "$sdk_home/build-tools/"* 2>/dev/null | sort -V | tail -1)
    if [ -z "$build_tools_dir" ]; then echo -e "${RED}Android build-tools not found${NC}"; exit 1; fi
    local platform_dir=$(ls -d "$sdk_home/platforms/"* 2>/dev/null | sort -V | tail -1)

    # API 26 (Android 8.0 Oreo, Aug 2017) is the floor for libaaudio.so —
    # missile_command and any other example using sokol_audio links it
    # statically. Bump the manifest's minSdkVersion to match (below).
    local sysroot="$ndk_dir/toolchains/llvm/prebuilt/$(ls "$ndk_dir/toolchains/llvm/prebuilt/")/sysroot/usr/lib/aarch64-linux-android/26"
    echo -e "${CYAN}Compiling $app_name (Android ARM64)...${NC}"
    "$CC" "$src" --target android --shared \
        --link "$sysroot/libc.so" \
        --link "$sysroot/libGLESv3.so" \
        --link "$sysroot/libEGL.so" \
        --link "$sysroot/libandroid.so" \
        --link "$sysroot/liblog.so" \
        --link "$sysroot/libaaudio.so" \
        -o "$BUILD_DIR/libapp.so"

    echo -e "${CYAN}Packaging APK...${NC}"
    local android_pkg="${MINC_ANDROID_PACKAGE:-com.minc.app}"
    cat > "$BUILD_DIR/AndroidManifest.xml" << MANIFEST
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="$android_pkg">
    <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/>
    <uses-feature android:glEsVersion="0x00030000" android:required="true"/>
    <application android:hasCode="false">
        <activity android:name="android.app.NativeActivity"
            android:exported="true"
            android:configChanges="orientation|keyboardHidden|screenSize">
            <meta-data android:name="android.app.lib_name" android:value="app"/>
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
MANIFEST
    "$build_tools_dir/aapt2" link -o "$BUILD_DIR/app-unsigned.apk" \
        --manifest "$BUILD_DIR/AndroidManifest.xml" \
        -I "$platform_dir/android.jar" 2>/dev/null
    mkdir -p "$BUILD_DIR/apk_tmp/lib/arm64-v8a"
    cp "$BUILD_DIR/libapp.so" "$BUILD_DIR/apk_tmp/lib/arm64-v8a/"
    (cd "$BUILD_DIR/apk_tmp" && zip -r "$BUILD_DIR/app-unsigned.apk" lib/ >/dev/null)
    "$build_tools_dir/zipalign" -f 4 "$BUILD_DIR/app-unsigned.apk" "$BUILD_DIR/app-aligned.apk" 2>/dev/null
    local keystore="$BUILD_DIR/debug.keystore"
    if [ ! -f "$keystore" ]; then
        keytool -genkey -v -keystore "$keystore" -alias debug \
            -keyalg RSA -keysize 2048 -validity 10000 \
            -storepass android -keypass android \
            -dname "CN=Debug,O=Debug,C=US" 2>/dev/null
    fi
    "$build_tools_dir/apksigner" sign --ks "$keystore" --ks-pass pass:android "$BUILD_DIR/app-aligned.apk" 2>/dev/null
    mv "$BUILD_DIR/app-aligned.apk" "$BUILD_DIR/app.apk"
    echo -e "${GREEN}APK: $BUILD_DIR/app.apk${NC}"

    if ! command -v adb >/dev/null 2>&1; then
        echo "Install: adb install $BUILD_DIR/app.apk"
        return
    fi
    if ! adb devices 2>/dev/null | grep -q 'device$'; then
        local avd_name=$(emulator -list-avds 2>/dev/null | head -1)
        if [ -n "$avd_name" ]; then
            echo -e "${CYAN}Starting emulator ($avd_name)...${NC}"
            emulator -avd "$avd_name" -no-snapshot-load &>/dev/null &
            echo -n "  Waiting for boot"
            for i in $(seq 1 60); do
                if adb devices 2>/dev/null | grep -q 'device$'; then break; fi
                echo -n "."; sleep 2
            done
            echo ""; adb wait-for-device 2>/dev/null
            adb shell getprop sys.boot_completed 2>/dev/null | grep -q 1 || sleep 5
        else
            echo "No device/emulator found. Install: adb install $BUILD_DIR/app.apk"
            return
        fi
    fi
    echo -e "${CYAN}Installing...${NC}"
    # `set -e` at the top of this script makes the captured-output
    # form ($(adb install …)) exit silently on non-zero rc, which
    # hides the very INSTALL_FAILED_UPDATE_INCOMPATIBLE we want to
    # recover from. Invoke adb directly so its stdout/stderr reach
    # the terminal, and use `|| { … }` (set -e leaves the chain
    # intact) to uninstall and retry on any failure. Same shape as
    # host build.sh's do_sokol_android. Re-extracted release bundles
    # regenerate debug.keystore -> different signing key -> install
    # rejected; this auto-recovers.
    adb install -r "$BUILD_DIR/app.apk" || {
        echo -e "${YELLOW}Install failed; uninstalling old $android_pkg and retrying...${NC}"
        adb uninstall "$android_pkg" 2>/dev/null || true
        adb install "$BUILD_DIR/app.apk"
    }
    sleep 1
    echo -e "${CYAN}Launching...${NC}"
    adb shell am start -n "$android_pkg/android.app.NativeActivity" 2>&1
    echo -e "${GREEN}$app_name running on Android${NC}"
}

# --- Dispatch ---

# Example .mc files sit at the repo root, next to this script.
EXAMPLES_DIR="$SCRIPT_DIR"
CMD="${1:-help}"
ARG="${2:-}"

case "$CMD" in
    hello)          build_console "hello" "$EXAMPLES_DIR/hello.mc" ;;
    mandelbrot)     build_console "mandelbrot" "$EXAMPLES_DIR/mandelbrot.mc" ;;
    raytracer)      build_sokol "raytracer" "$EXAMPLES_DIR/raytracer.mc" ;;
    raytracer_mt)   build_sokol "raytracer_mt" "$EXAMPLES_DIR/raytracer_mt.mc" ;;
    chip8)          build_sokol "chip8" "$EXAMPLES_DIR/chip8.mc" ;;
    missile)        build_sokol "missile_command" "$EXAMPLES_DIR/missile_command.mc" ;;
    shim)           build_shim ;;
    sokol_cube)     build_sokol "sokol_cube" "$EXAMPLES_DIR/sokol_cube.mc" ;;
    sokol_texcube)  build_sokol "sokol_texcube" "$EXAMPLES_DIR/sokol_texcube.mc" ;;
    sokol_compute)  build_sokol "sokol_compute" "$EXAMPLES_DIR/sokol_compute.mc" ;;
    sokol_mandelbrot) build_sokol "sokol_mandelbrot" "$EXAMPLES_DIR/sokol_mandelbrot.mc" ;;
    sphere_physics) build_sokol "sokol_sphere_physics" "$EXAMPLES_DIR/sokol_sphere_physics.mc" ;;
    hotreload)
        # The engine loads libminc (the embeddable JIT) at launch and
        # its binary references it next to itself, so stage a copy from
        # the install dir alongside the exe. Newer minc releases also
        # fall back to the install dir on `minc run`, but the copy
        # keeps this working with any minc.
        exe="$BUILD_DIR/hotreload_engine"
        echo -e "${CYAN}Compiling hotreload engine...${NC}"
        "$CC" "$EXAMPLES_DIR/hotreload/engine.mc" -o "$exe"
        chmod +x "$exe"
        minc_dir="$(cd "$(dirname "$CC")" && pwd)"
        cp -f "$minc_dir"/libminc.dylib "$minc_dir"/libminc.so "$BUILD_DIR/" 2>/dev/null || true
        if [ ! -f "$BUILD_DIR/libminc.dylib" ] && [ ! -f "$BUILD_DIR/libminc.so" ]; then
            echo -e "${YELLOW}warning: libminc not found next to minc ($minc_dir); the engine may fail to start${NC}"
        fi
        echo -e "${CYAN}Running hotreload engine${ARG:+ ($ARG)}...${NC}"
        (cd "$EXAMPLES_DIR" && "$exe" $ARG)
        ;;
    wasm)
        if [ -z "$ARG" ]; then
            echo -e "${YELLOW}Usage: ./build.sh wasm <example>${NC}"
            echo "  Any example .mc that uses sokol_app for windowing."
            echo "  Verified: sokol_cube, sokol_texcube, sokol_mandelbrot, sphere_physics, raytracer, missile"
            echo "  Or pass your own: ./build.sh wasm my_app  (needs my_app.mc next to this script)"
            exit 1
        fi
        # Normalize known short aliases.
        case "$ARG" in
            sphere_physics)         ARG="sokol_sphere_physics" ;;
            missile)                ARG="missile_command" ;;
            sokol_compute|sokol_compute_rw|sokol_particles_compute)
                echo -e "${RED}$ARG is not supported on wasm (WebGL2 has no compute shaders).${NC}"
                exit 1 ;;
        esac
        # Reject anything with a path separator or unsafe characters.
        case "$ARG" in
            *[!a-zA-Z0-9_-]* | "")
                echo -e "${RED}invalid example name: $ARG${NC}"
                echo "  Use alphanumerics, underscore, hyphen only."
                exit 1 ;;
        esac
        build_wasm "$ARG"
        ;;
    bench)          do_bench "$ARG" ;;
    macos-app)      do_macos_app "$ARG" "${3:-}" ;;
    ios-sim)        do_ios_sim "$ARG" ;;
    ios)            do_ios_device "$ARG" ;;
    android)        do_android "$ARG" ;;
    compile)
        if [ -z "$ARG" ]; then
            echo -e "${YELLOW}Usage: ./build.sh compile <file.mc>${NC}"
            exit 1
        fi
        name=$(basename "$ARG" .mc)
        exe="$BUILD_DIR/$name"
        echo -e "${CYAN}Compiling $ARG...${NC}"
        "$CC" "$ARG" -o "$exe"
        chmod +x "$exe"
        size=$(du -k "$exe" | cut -f1)
        echo -e "${GREEN}Built: $exe (${size} KB)${NC}"
        ;;
    *)
        echo "minc build script"
        echo ""
        echo "Usage: ./build.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  hello              Compile and run hello.mc"
        echo "  mandelbrot         Compile and run animated ASCII Mandelbrot"
        echo "  raytracer          Compile and launch raytracer"
        echo "  raytracer_mt       Compile and launch multi-threaded raytracer"
        echo "  chip8              Compile and launch CHIP-8 emulator"
        echo "  missile            Compile and launch Missile Command"
        echo "  sokol_cube         Compile and launch sokol cube demo"
        echo "  sokol_texcube      Compile and launch textured cube demo"
        echo "  sokol_compute      Compile and launch compute shader demo"
        echo "  sokol_mandelbrot   Compile and launch fragment-shader Mandelbrot"
        echo "  sphere_physics     Compile and launch bouncing-spheres demo"
        echo "  hotreload [watch]  Compile and run the hot-reload demo (watch = live editing)"
        echo "  wasm <example>     Compile to wasm and open in browser"
        echo "                     (any example .mc that uses sokol_app;"
        echo "                      verified: sokol_cube, sokol_texcube,"
        echo "                      sokol_mandelbrot, sphere_physics, raytracer, missile)"
        echo "  shim               Compile and run the C-shim FFI example (needs gcc/clang)"
        echo "  bench [filter]     Run benchmarks (optionally filter by name)"
        echo "  compile <file.mc>  Compile a .mc file"
        echo "  macos-app [app] [--open]  Wrap example as a double-clickable Foo.app (macOS)"
        echo "  ios-sim [app]      Build and run in iOS Simulator (macOS)"
        echo "  ios [app]          Build, sign, install, and launch on connected iOS device"
        echo "  android [app]      Build APK and run on Android device/emulator"
        echo ""
        echo "Environment variables (see SETUP.md):"
        echo "  MINC_TEAM_ID       Apple Developer Team ID (for ios-device)"
        echo "  MINC_BUNDLE_PREFIX Bundle ID prefix (default: com.minc)"
        echo "  ANDROID_HOME       Android SDK path"
        ;;
esac