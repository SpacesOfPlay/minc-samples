# build.ps1 — minc build script (Windows)
# Usage: .\build.ps1 <command> [args]
#   .\build.ps1 hello              — compile and run hello.mc
#   .\build.ps1 raytracer          — compile and launch raytracer
#   .\build.ps1 sokol_cube         — compile and launch sokol cube demo
#   .\build.ps1 hotreload [watch]  — compile and run the hot-reload demo
#   .\build.ps1 wasm sokol_cube    — compile to wasm and open in browser
#   .\build.ps1 bench [filter]     — run benchmarks
#   .\build.ps1 compile <file.mc>  — compile a .mc file

param(
    [string]$Command = "help",
    [string]$Arg = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$BuildDir = Join-Path $ScriptDir "build"
# Example .mc files sit at the repo root, next to this script.
$ExamplesDir = $ScriptDir

# minc: $env:MINC override (install dir, or a direct binary path),
# else PATH (installed toolchain), else next to this script (manual
# zip layout).
$CC = $env:MINC
if ($CC -and (Test-Path $CC -PathType Container)) { $CC = Join-Path $CC "minc.exe" }
if (-not $CC) {
    $cmd = Get-Command minc -ErrorAction SilentlyContinue
    if ($cmd) { $CC = $cmd.Source }
}
if (-not $CC) { $CC = Join-Path $ScriptDir "minc.exe" }

if (-not (Test-Path $CC)) {
    Write-Host "ERROR: minc not found. Install it (https://minc.dev) or set MINC to the install dir." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $BuildDir)) { New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null }

function Find-VCVarsAll {
    # Highest installationVersion wins; stable beats Preview.
    $vsw = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vsw) {
        try {
            $installs = & $vsw -all -prerelease -products * `
                -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
                -format json 2>$null | ConvertFrom-Json
            $pick = $installs |
                Sort-Object @{ Expression = { [version]$_.installationVersion }; Descending = $true },
                            @{ Expression = { [bool]$_.isPrerelease }; Descending = $false } |
                Select-Object -First 1
            if ($pick) {
                $bat = Join-Path $pick.installationPath "VC\Auxiliary\Build\vcvarsall.bat"
                if (Test-Path $bat) { return $bat }
            }
        } catch { }
    }
    return $null
}

function Build-Console {
    param([string]$Name, [string]$Src)
    $exe = Join-Path $BuildDir "$Name.exe"
    Write-Host "Compiling $Name..." -ForegroundColor Cyan
    & $CC $Src -o $exe
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $sizeKb = "{0:F1}" -f ((Get-Item $exe).Length / 1024.0)
    Write-Host "Built: $exe ($sizeKb KB)" -ForegroundColor Green
    Write-Host "Running..." -ForegroundColor Cyan
    & $exe
}

function Build-Sokol {
    param([string]$Name, [string]$Src)
    $exe = Join-Path $BuildDir "$Name.exe"
    Write-Host "Compiling $Name (sokol)..." -ForegroundColor Cyan
    & $CC $Src -o $exe
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $sizeKb = "{0:F1}" -f ((Get-Item $exe).Length / 1024.0)
    Write-Host "Built: $exe ($sizeKb KB)" -ForegroundColor Green
    Write-Host "Launching..." -ForegroundColor Cyan
    Start-Process $exe
}

# Delegate to minc's built-in `run --target wasm`. minc.exe compiles
# the example, stages the harness from lib\wasm\, opens the browser,
# and serves on http://127.0.0.1:8080 until Ctrl+C or /__shutdown.
# No external server binary, no manual staging.
function Build-Wasm {
    param([string]$Name)
    $src = Join-Path $ExamplesDir "$Name.mc"
    if (-not (Test-Path $src)) {
        Write-Host "example not found: $src" -ForegroundColor Red
        exit 1
    }
    & $CC run $src --target wasm
    exit $LASTEXITCODE
}

function Build-Shim {
    # Compile the C shim to a freestanding COFF object, then the minc app
    # whose @link tag merges it in. minc links the object directly — no
    # external linker. Try the toolchains in order of how common they are on
    # a Windows box: MSVC cl, then clang, then zig cc.
    #
    # All three must emit the MSVC ABI so the MSVC-style stack-cookie stubs
    # in shim_demo.c resolve: cl is MSVC; clang on Windows defaults to the
    # -windows-msvc target; zig defaults to MinGW, so it needs an explicit
    # -target. /GS- (cl) / -fno-stack-protector (clang/zig) drop the cookie.
    $obj = Join-Path $BuildDir "shim_demo_win.obj"
    $cSrc = Join-Path $ExamplesDir "shim_demo.c"
    Remove-Item $obj -ErrorAction SilentlyContinue
    Write-Host "Compiling C shim..." -ForegroundColor Cyan

    # 1. MSVC cl (via vcvars).
    $vcvars = Find-VCVarsAll
    if ($vcvars) {
        $bat = Join-Path $BuildDir "_shim_build.bat"
        "@call `"$vcvars`" x64 >nul`r`ncl /nologo /c /GS- /Fo:`"$obj`" `"$cSrc`" >nul 2>&1`r`n" | Set-Content -Path $bat -Encoding ASCII
        cmd.exe /c $bat | Out-Null
        if (Test-Path $obj) { Write-Host "  (cl)" -ForegroundColor Gray }
    }
    # 2. clang.
    if ((-not (Test-Path $obj)) -and (Get-Command clang -ErrorAction SilentlyContinue)) {
        & clang -c -fno-stack-protector $cSrc -o $obj
        if (Test-Path $obj) { Write-Host "  (clang)" -ForegroundColor Gray }
    }
    # 3. zig cc.
    if ((-not (Test-Path $obj)) -and (Get-Command zig -ErrorAction SilentlyContinue)) {
        & zig cc -c -fno-stack-protector -target x86_64-windows-msvc $cSrc -o $obj
        if (Test-Path $obj) { Write-Host "  (zig cc)" -ForegroundColor Gray }
    }

    if (-not (Test-Path $obj)) {
        Write-Host "C shim needs MSVC, clang, or zig on PATH" -ForegroundColor Red
        exit 1
    }
    Build-Console "shim_demo" (Join-Path $ExamplesDir "shim_demo.mc")
}

function Run-Bench {
    param([string]$Filter = "")
    $benchDir = Join-Path $ScriptDir "bench"
    $benchmarks = @("fib_iter","sieve","fib_rec","qsort","matmul","lex_scan","binary_tree","hash_probe","nbody","bitcount","histogram","dp_edit","mandelbrot","strscan","struct_traverse","divconst","bitops","branch_chain","cast_loop","list_sum","indirect_call","u32_index","matmul_f64","nbody_f64","dot_f64","poly_f64","particle_f64","particle2_f64","conv_f64","conv_f64_v2","conv_f64_v3","conv_f64_v4","vec4_transform","mat4_mul")

    if ($Filter) {
        $exact = @($benchmarks | Where-Object { $_ -ieq $Filter })
        if ($exact.Count -gt 0) { $benchmarks = $exact }
        else {
            $matched = @($benchmarks | Where-Object { $_ -like "*$Filter*" })
            if ($matched.Count -eq 0) {
                Write-Host "No benchmark matches '$Filter'." -ForegroundColor Red
                Write-Host "Available benchmarks:"
                foreach ($b in $benchmarks) { Write-Host "  $b" }
                exit 1
            }
            $benchmarks = $matched
        }
    }

    # Detect MSVC for the reference compile.
    $vcvars = Find-VCVarsAll
    $hasMsvc = [bool]$vcvars

    Write-Host "=== minc benchmark suite ===" -ForegroundColor White
    Write-Host "Compiler: $CC"
    if ($hasMsvc) { Write-Host "Reference: MSVC -O2" } else { Write-Host "Reference: not found (minc-only mode)" }
    if ($Filter) { Write-Host "Filter:   $Filter ($($benchmarks.Count) matched)" }
    Write-Host ""

    $fmt = "{0,-16} {1,12} {2,12} {3,8} {4,10} {5,10} {6}"
    Write-Host ($fmt -f "Benchmark", "minc (us)", "MSVC (us)", "Ratio", "minc (KB)", "MSVC (KB)", "Result")
    Write-Host ($fmt -f "---------", "---------", "---------", "-----", "---------", "---------", "------")

    $totalMinc = 0; $totalRef = 0; $nbench = 0
    foreach ($name in $benchmarks) {
        $mcSrc = Join-Path $benchDir "bench_$name.mc"
        $mcExe = Join-Path $BuildDir "bench_${name}_minc.exe"
        $cSrc  = Join-Path $benchDir "bench_$name.c"
        $cExe  = Join-Path $BuildDir "bench_${name}_msvc.exe"

        & $CC $mcSrc -o $mcExe 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host ($fmt -f $name, "CERR", "-", "-", "-", "-", "minc compile failed") -ForegroundColor Red
            continue
        }
        $mcSize = "{0:F1}" -f ((Get-Item $mcExe).Length / 1024.0)

        $refSize = "-"
        if ($hasMsvc) {
            $bat = Join-Path $BuildDir "_msvc_build.bat"
            "@call `"$vcvars`" x64 >nul`r`ncl /nologo /O2 /Fe:`"$cExe`" `"$cSrc`" >nul 2>&1`r`n" | Set-Content -Path $bat -Encoding ASCII
            cmd.exe /c $bat | Out-Null
            if (-not (Test-Path $cExe)) {
                Write-Host ($fmt -f $name, "-", "CERR", "-", $mcSize, "-", "MSVC compile failed") -ForegroundColor Red
                continue
            }
            $refSize = "{0:F1}" -f ((Get-Item $cExe).Length / 1024.0)
        }

        $mcOut = & $mcExe 2>&1 | Out-String
        if (-not $mcOut) {
            Write-Host ($fmt -f $name, "FAIL", "-", "-", $mcSize, $refSize, "minc runtime error")
            continue
        }
        if ($mcOut -match 'result=(\S+)') { $mcVal = $Matches[1] } else { $mcVal = "" }
        if ($mcOut -match 'time=(\d+)')   { $mcTime = [int]$Matches[1] } else { $mcTime = 0 }

        if (-not $hasMsvc) {
            $totalMinc += $mcTime; $nbench++
            Write-Host ($fmt -f $name, $mcTime, "-", "-", $mcSize, "-", "OK (result=$mcVal)")
            continue
        }

        $refOut = & $cExe 2>&1 | Out-String
        if ($refOut -match 'result=(\S+)') { $refVal = $Matches[1] } else { $refVal = "" }
        if ($refOut -match 'time=(\d+)')   { $refTime = [int]$Matches[1] } else { $refTime = 0 }

        # Validate results match (allow tolerance for FMA rounding differences)
        $resultOk = ($mcVal -eq $refVal)
        if (-not $resultOk -and $mcVal -match '^-?\d+$' -and $refVal -match '^-?\d+$') {
            $diff = [Math]::Abs([long]$mcVal - [long]$refVal)
            # Float benchmarks accumulate FMA rounding over millions of ops
            $tol = if ($name -match 'f64|mandelbrot|vec4_') { 100 } else { 1 }
            if ($diff -le $tol) { $resultOk = $true }
        }
        if (-not $resultOk) {
            Write-Host ($fmt -f $name, $mcTime, $refTime, "-", $mcSize, $refSize, "MISMATCH! minc=$mcVal MSVC=$refVal") -ForegroundColor Yellow
            continue
        }

        if ($refTime -gt 0) {
            $ratio = "{0:F2}x" -f ($mcTime / $refTime)
            $totalMinc += $mcTime; $totalRef += $refTime; $nbench++
        } else { $ratio = "-" }
        Write-Host ($fmt -f $name, $mcTime, $refTime, $ratio, $mcSize, $refSize, "OK") -ForegroundColor Green
    }

    Write-Host ""
    if ($hasMsvc -and $nbench -gt 0 -and $totalRef -gt 0) {
        $avg = "{0:F2}x" -f ($totalMinc / $totalRef)
        Write-Host ("{0,-16} {1,12} {2,12} {3,8}" -f "TOTAL", $totalMinc, $totalRef, $avg)
    } elseif ($nbench -gt 0) {
        Write-Host "Total time: $totalMinc us (across $nbench benchmarks)"
    }
}

switch ($Command) {
    "hello"          { Build-Console "hello"               (Join-Path $ExamplesDir "hello.mc") }
    "mandelbrot"     { Build-Console "mandelbrot"          (Join-Path $ExamplesDir "mandelbrot.mc") }
    "raytracer"      { Build-Sokol "raytracer"             (Join-Path $ExamplesDir "raytracer.mc") }
    "raytracer_mt"   { Build-Sokol "raytracer_mt"          (Join-Path $ExamplesDir "raytracer_mt.mc") }
    "chip8"          { Build-Sokol "chip8"                 (Join-Path $ExamplesDir "chip8.mc") }
    "missile"        { Build-Sokol "missile_command"       (Join-Path $ExamplesDir "missile_command.mc") }
    "sokol_cube"     { Build-Sokol "sokol_cube"            (Join-Path $ExamplesDir "sokol_cube.mc") }
    "sokol_texcube"  { Build-Sokol "sokol_texcube"         (Join-Path $ExamplesDir "sokol_texcube.mc") }
    "sokol_compute"  { Build-Sokol "sokol_compute"         (Join-Path $ExamplesDir "sokol_compute.mc") }
    "sokol_mandelbrot" { Build-Sokol "sokol_mandelbrot"    (Join-Path $ExamplesDir "sokol_mandelbrot.mc") }
    "sphere_physics" { Build-Sokol "sokol_sphere_physics"  (Join-Path $ExamplesDir "sokol_sphere_physics.mc") }
    "hotreload" {
        # The engine loads libminc.dll (the embeddable JIT) at launch.
        # An installed minc resolves it via PATH; stage a copy next to
        # the exe so the MINC-override and manual-zip layouts work too.
        $exe = Join-Path $BuildDir "hotreload_engine.exe"
        Write-Host "Compiling hotreload engine..." -ForegroundColor Cyan
        & $CC (Join-Path $ExamplesDir "hotreload\engine.mc") -o $exe
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        $mincDir = Split-Path -Parent $CC
        $dll = Join-Path $mincDir "libminc.dll"
        if (Test-Path $dll) { Copy-Item $dll $BuildDir -Force }
        Write-Host "Running hotreload engine..." -ForegroundColor Cyan
        Push-Location $ExamplesDir
        try {
            if ($Arg) { & $exe $Arg } else { & $exe }
        } finally { Pop-Location }
        exit $LASTEXITCODE
    }
    "wasm" {
        if (-not $Arg) {
            Write-Host "Usage: .\build.ps1 wasm <example>" -ForegroundColor Yellow
            Write-Host "  Any .mc file under examples/ that uses sokol_app for windowing."
            Write-Host "  Verified: sokol_cube, sokol_texcube, sokol_mandelbrot, sphere_physics, raytracer, missile"
            Write-Host "  Or pass your own: .\build.ps1 wasm my_app  (needs examples\my_app.mc)"
            exit 1
        }
        # Normalize known short aliases.
        $name = switch ($Arg) {
            "sphere_physics" { "sokol_sphere_physics" }
            "missile"        { "missile_command" }
            default          { $Arg }
        }
        if ($name -in @("sokol_compute", "sokol_compute_rw", "sokol_particles_compute")) {
            Write-Host "$name is not supported on wasm (WebGL2 has no compute shaders)." -ForegroundColor Red
            exit 1
        }
        if ($name -notmatch '^[a-zA-Z0-9_-]+$') {
            Write-Host "invalid example name: $name" -ForegroundColor Red
            Write-Host "  Use alphanumerics, underscore, hyphen only."
            exit 1
        }
        Build-Wasm $name
    }
    "shim"           { Build-Shim }
    "bench"          { Run-Bench $Arg }
    "compile" {
        if (-not $Arg) {
            Write-Host "Usage: .\build.ps1 compile <file.mc>" -ForegroundColor Yellow
            exit 1
        }
        $name = [System.IO.Path]::GetFileNameWithoutExtension($Arg)
        $exe = Join-Path $BuildDir "$name.exe"
        Write-Host "Compiling $Arg..." -ForegroundColor Cyan
        & $CC $Arg -o $exe
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        $sizeKb = "{0:F1}" -f ((Get-Item $exe).Length / 1024.0)
        Write-Host "Built: $exe ($sizeKb KB)" -ForegroundColor Green
    }
    default {
        Write-Host "minc build script"
        Write-Host ""
        Write-Host "Usage: .\build.ps1 <command> [args]"
        Write-Host ""
        Write-Host "Commands:"
        Write-Host "  hello              Compile and run hello.mc"
        Write-Host "  mandelbrot         Compile and run animated ASCII Mandelbrot"
        Write-Host "  raytracer          Compile and launch raytracer"
        Write-Host "  raytracer_mt       Compile and launch multi-threaded raytracer"
        Write-Host "  chip8              Compile and launch CHIP-8 emulator"
        Write-Host "  missile            Compile and launch Missile Command"
        Write-Host "  sokol_cube         Compile and launch sokol cube demo"
        Write-Host "  sokol_texcube      Compile and launch textured cube demo"
        Write-Host "  sokol_compute      Compile and launch compute shader demo"
        Write-Host "  sokol_mandelbrot   Compile and launch fragment-shader Mandelbrot"
        Write-Host "  sphere_physics     Compile and launch bouncing-spheres demo"
        Write-Host "  hotreload [watch]  Compile and run the hot-reload demo (watch = live editing)"
        Write-Host "  wasm <example>     Compile to wasm and open in browser"
        Write-Host "                     (any .mc in examples\ that uses sokol_app;"
        Write-Host "                      verified: sokol_cube, sokol_texcube,"
        Write-Host "                      sokol_mandelbrot, sphere_physics, raytracer, missile)"
        Write-Host "  shim               Compile and run the C-shim FFI example (needs clang/MSVC)"
        Write-Host "  bench [filter]     Run benchmarks (optionally filter by name)"
        Write-Host "  compile <file.mc>  Compile a .mc file"
    }
}
