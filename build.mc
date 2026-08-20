// build.mc — build (and run) the minc samples.
//
// Usage, from this folder:
//   minc run <example>           build + run (sokol_cube, raytracer, ...)
//   minc run <file.mc>           build + run your own program
//   minc run                     list the examples
//   minc build <example>         compile only
//   minc wasm <example>          build + serve in the browser
//   minc bench [filter]          benchmark suite vs a reference C compiler
//   minc run macos-app <example> [--open]   double-clickable .app (macOS)
//   minc run ios-sim <example>   build + launch in the iOS Simulator
//   minc run ios <example>       build, sign, install on a connected device
//   minc run android <example>   build APK, install on device/emulator
//   minc clean
//
// `build` with a platform word packages without installing/launching.
// Special cases: `minc run shim_demo.mc` compiles the C shim first
// (needs a C compiler); `minc run hotreload [watch]` runs the
// hot-reload demo.
//
// The minc compiler is taken from MINC, then PATH, then this folder.
// Install minc from https://minc.dev.

@minc_min_version "0.9.11"

// Older minc ignores the tag above; this forces a clear error there.
when !defined(MINC_VERSION) || MINC_VERSION < 9011 {
    minc_0_9_11_or_newer_required please_update_minc;
}

import process;
import file;
import str;
import zip;

when os(windows) { str EXE_SUFFIX = ".exe"; }
when os(linux) || os(macos) { str EXE_SUFFIX = ""; }

void out(str s) {
    write(stdout(), s.data, s.len);
    return;
}

void say(str s) {
    out(s);
    write(stdout(), "\n", 1);
    return;
}

void die(str s) {
    write(stderr(), s.data, s.len);
    write(stderr(), "\n", 1);
    exit(1);
    return;
}

// "<dir>/<name><ext>", without leaking the joined name.
string join_named(str dir, str name, str ext) {
    string base = str_concat(name, ext);
    defer free(base);
    return path_join(dir, str_from(base.data, base.len));
}

// MINC first (an install dir or the binary itself), then PATH, then a
// binary sitting next to this script.
string find_minc() {
    string env = env_get("MINC");
    if env.len > 0 {
        str e = str_from(env.data, env.len);
        if path_is_dir(e) {
            string cand = join_named(e, "minc", EXE_SUFFIX);
            free(env);
            return cand;
        }
        return env;
    }
    free(env);

    string onpath = path_which("minc");
    if onpath.len > 0 { return onpath; }
    free(onpath);

    string local = str_concat("./minc", EXE_SUFFIX);
    if path_exists(str_from(local.data, local.len)) { return local; }
    free(local);

    return string{};
}

// The compiler binary, resolved once in main.
str g_cc = "";

// Run a command, streaming its output; returns the exit code.
i32 run_cmd(ProcCmd* c) {
    ProcResult r = proc_run(c);
    i32 rc = r.exit_code;
    proc_result_free(&r);
    return rc;
}

// --- Example resolution -----------------------------------------------

// Short aliases kept from the old build scripts.
str resolve_alias(str name) {
    if str_equal(name, "missile") { return "missile_command"; }
    if str_equal(name, "sphere_physics") { return "sokol_sphere_physics"; }
    return name;
}

// A name means "<name>.mc" next to this script; a .mc path is taken as
// given. Returns an owned path or empty when nothing matches.
string resolve_source(str target) {
    if str_ends_with(target, ".mc") { return str_concat(target, ""); }
    str name = resolve_alias(target);
    string cand = str_concat(name, ".mc");
    if path_exists(str_from(cand.data, cand.len)) { return cand; }
    free(cand);
    return string{};
}

void list_examples() {
    say("Examples in this folder:");
    DirList l = dir_list(".", ".mc", false);
    defer dir_list_free(&l);
    for i32 i = 0; i < l.count; i++ {
        str stem = path_stem(l.items[i]);
        if str_equal(stem, "build") { continue; }   // this script
        out("  ");
        say(stem);
    }
    say("  hotreload            (hot-reload demo; add `watch` for live editing)");
    say("");
    say("Usage:");
    say("  minc run <example>          minc wasm <example>");
    say("  minc build <example>        minc bench [filter]");
    say("  minc run ios|ios-sim|android|macos-app <example>");
    say("  minc clean");
    return;
}

// --- Reference C compiler ----------------------------------------------
// Used by the shim demo (and the benchmark suite) to compile C sources.

when os(linux) || os(macos) {
    // clang first on macOS, gcc first on Linux; either stands in for
    // the other.
    string find_ref_cc() {
        when os(macos) {
            string c = path_which("clang");
            if c.len > 0 { return c; }
            free(c);
            return path_which("gcc");
        }
        when os(linux) {
            string g = path_which("gcc");
            if g.len > 0 { return g; }
            free(g);
            return path_which("clang");
        }
    }
}

when os(windows) {
    // MSVC via vswhere: the modern -latest form does the version
    // selection the old build.ps1 did by hand. Stable first, then
    // prerelease. Returns the vcvarsall.bat path or empty.
    string find_vcvarsall() {
        string pf = env_get("ProgramFiles(x86)");
        if pf.len == 0 { return string{}; }
        string vsw = path_join(str_from(pf.data, pf.len),
                               "Microsoft Visual Studio\\Installer\\vswhere.exe");
        free(pf);
        defer free(vsw);
        str vswp = str_from(vsw.data, vsw.len);
        if !path_exists(vswp) { return string{}; }

        for i32 pass = 0; pass < 2; pass++ {
            ProcCmd c = { .args = {
                vswp, "-latest", "-products", "*",
                "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
                "-property", "installationPath"
            }, .capture = true };
            if pass == 1 { proc_arg(&c, "-prerelease"); }
            ProcResult r = proc_run(&c);
            defer proc_result_free(&r);
            if r.exit_code == 0 && r.out.len > 0 {
                str line = str_trim(str_from(r.out.data, r.out.len));
                if line.len > 0 {
                    string bat = path_join(line, "VC\\Auxiliary\\Build\\vcvarsall.bat");
                    str batp = str_from(bat.data, bat.len);
                    if path_exists(batp) { return bat; }
                    free(bat);
                }
            }
        }
        return string{};
    }

    // Run one cl command inside a vcvars x64 environment via a
    // generated batch file. Returns cl's exit code, or -1 with no
    // MSVC install.
    i32 run_cl(str vcvarsall, str cl_args) {
        // cmd.exe splits an unquoted command token at '/', so the bat
        // path must use backslashes.
        string bat = str_concat("build\\_cl_", "run.bat");
        defer free(bat);
        str batp = str_from(bat.data, bat.len);
        str_buf b;
        str_buf_init(&b);
        defer str_buf_free(&b);
        str_buf_add(&b, "@call \"");
        str_buf_add(&b, vcvarsall);
        str_buf_add(&b, "\" x64 >nul 2>&1\r\ncl /nologo ");
        str_buf_add(&b, cl_args);
        str_buf_add(&b, " >nul 2>&1\r\n");
        if !file_write_str(batp, str_buf_to_str(&b)) { return -1; }
        ProcCmd c = { .args = { "cmd.exe", "/c", batp } };
        return run_cmd(&c);
    }
}

// --- Benchmarks --------------------------------------------------------
// Same table and markers as the old build.sh/build.ps1: verify_release
// greps for MISMATCH / CERR / "minc compile failed" / "minc runtime
// error" and the TOTAL line.

private u8 lc_byte(u8 c) {
    if c >= 'A' && c <= 'Z' { return cast(u8, c + 32); }
    return c;
}

private bool str_contains_ci(str s, str needle) {
    if needle.len == 0 { return true; }
    for i32 i = 0; i + needle.len <= s.len; i++ {
        bool hit = true;
        for i32 j = 0; j < needle.len; j++ {
            if lc_byte(s.data[i + j]) != lc_byte(needle.data[j]) { hit = false; break; }
        }
        if hit { return true; }
    }
    return false;
}

private bool parse_i64(str s, i64* out_v) {
    i32 i = 0;
    bool neg = false;
    if i < s.len && s.data[i] == '-' { neg = true; i++; }
    if i >= s.len { return false; }
    i64 v = 0;
    while i < s.len {
        u8 c = s.data[i];
        if c < '0' || c > '9' { return false; }
        v = v * 10 + (c - '0');
        i++;
    }
    if neg { v = 0 - v; }
    *out_v = v;
    return true;
}

// The token following "<key>" up to whitespace, or empty.
private str token_after(str s, str key) {
    i32 at = str_find(s, key);
    if at < 0 { return ""; }
    i32 b = at + key.len;
    i32 e = b;
    while e < s.len {
        u8 c = s.data[e];
        if c == ' ' || c == '\t' || c == '\r' || c == '\n' { break; }
        e++;
    }
    return str_slice(s, b, e);
}

// Left-align into width w (pads right); right-align pads left.
private void col_l(str_buf* b, str s, i32 w) {
    str_buf_add(b, s);
    for i32 i = s.len; i < w; i++ { str_buf_add_byte(b, ' '); }
    return;
}

private void col_r(str_buf* b, str s, i32 w) {
    for i32 i = s.len; i < w; i++ { str_buf_add_byte(b, ' '); }
    str_buf_add(b, s);
    return;
}

// "123.4" KB with one decimal.
private string fmt_kb(i64 bytes) {
    i64 t = (bytes * 10 + 512) / 1024;
    return format("{}.{}", t / 10, t % 10);
}

// "0.94x" — mc/ref with two decimals.
private string fmt_ratio(i64 mc, i64 ref) {
    i64 h = (mc * 100 + ref / 2) / ref;
    string frac = format("{}", h % 100);
    defer free(frac);
    if h % 100 < 10 {
        return format("{}.0{}x", h / 100, h % 100);
    }
    return format("{}.{}x", h / 100, str_from(frac.data, frac.len));
}

private void bench_row(str name, str mc_t, str ref_t, str ratio,
                       str mc_kb, str ref_kb, str result) {
    str_buf b;
    str_buf_init(&b);
    defer str_buf_free(&b);
    col_l(&b, name, 16);
    str_buf_add_byte(&b, ' ');
    col_r(&b, mc_t, 12);
    str_buf_add_byte(&b, ' ');
    col_r(&b, ref_t, 12);
    str_buf_add_byte(&b, ' ');
    col_r(&b, ratio, 8);
    str_buf_add_byte(&b, ' ');
    col_r(&b, mc_kb, 10);
    str_buf_add_byte(&b, ' ');
    col_r(&b, ref_kb, 10);
    str_buf_add_byte(&b, ' ');
    str_buf_add(&b, result);
    say(str_buf_to_str(&b));
    return;
}

// Float benchmarks accumulate FMA rounding differences over millions
// of ops; the C references compile with -ffp-contract=off and results
// still differ by rounding, so those rows get a wider tolerance.
private bool bench_is_float(str name) {
    return str_contains(name, "f64") || str_equal(name, "mandelbrot") ||
           str_starts_with(name, "vec4_");
}

// Run one executable, capture output, extract result= and time=.
// False when the run produced no output.
private bool bench_run_exe(str exe, string* out_val, i64* out_time) {
    ProcCmd c = { .args = { exe }, .capture = true };
    ProcResult r = proc_run(&c);
    defer proc_result_free(&r);
    if !r.spawned || r.out.len == 0 { return false; }
    str o = str_from(r.out.data, r.out.len);
    str val = token_after(o, "result=");
    *out_val = str_concat(val, "");
    str t = token_after(o, "time=");
    i64 tv = 0;
    ignore parse_i64(t, &tv);
    *out_time = tv;
    return true;
}

i32 do_bench(str filter) {
    // Shipped benchmark list; deploy_samples substitutes it here.
    str[64] all = { "fib_iter", "sieve", "fib_rec", "qsort", "matmul", "lex_scan", "binary_tree", "hash_probe", "nbody", "bitcount", "histogram", "dp_edit", "mandelbrot", "strscan", "struct_traverse", "divconst", "bitops", "branch_chain", "cast_loop", "list_sum", "indirect_call", "u32_index", "matmul_f64", "nbody_f64", "dot_f64", "poly_f64", "particle_f64", "particle2_f64", "conv_f64", "conv_f64_v2", "conv_f64_v3", "conv_f64_v4", "vec4_transform", "mat4_mul" };
    i32 nall = 0;
    while nall < 64 && all[nall].data != null { nall++; }

    noinit str[64] benches;
    i32 nb = 0;
    if filter.len > 0 {
        for i32 i = 0; i < nall; i++ {
            if str_equal(all[i], filter) { benches[nb] = all[i]; nb++; }
        }
        if nb == 0 {
            for i32 i = 0; i < nall; i++ {
                if str_contains_ci(all[i], filter) { benches[nb] = all[i]; nb++; }
            }
        }
        if nb == 0 {
            out("No benchmark matches '");
            out(filter);
            say("'.");
            say("Available benchmarks:");
            for i32 i = 0; i < nall; i++ {
                out("  ");
                say(all[i]);
            }
            return 1;
        }
    } else {
        for i32 i = 0; i < nall; i++ { benches[i] = all[i]; }
        nb = nall;
    }

    // Reference compiler: gcc/clang from PATH on unix, MSVC on Windows.
    str ref_name = "";
    string ref_cc = string{};
    defer free(ref_cc);
    when os(linux) || os(macos) {
        ref_cc = find_ref_cc();
        if ref_cc.len > 0 {
            ref_name = path_stem(str_from(ref_cc.data, ref_cc.len));
        }
    }
    when os(windows) {
        ref_cc = find_vcvarsall();
        if ref_cc.len > 0 { ref_name = "MSVC"; }
    }
    bool has_ref = ref_cc.len > 0;

    say("=== minc benchmark suite ===");
    out("Compiler: ");
    say(g_cc);
    if has_ref {
        out("Reference: ");
        out(ref_name);
        say(" -O2");
    } else {
        say("Reference: not found (minc-only mode)");
    }
    if filter.len > 0 {
        out("Filter:   ");
        out(filter);
        string n = format(" ({} matched)", nb);
        defer free(n);
        say(str_from(n.data, n.len));
    }
    say("");
    bench_row("Benchmark", "minc (us)", "ref (us)", "Ratio", "minc (KB)", "ref (KB)", "Result");
    bench_row("---------", "---------", "--------", "-----", "---------", "--------", "------");

    i64 total_minc = 0;
    i64 total_ref = 0;
    i32 nbench = 0;

    for i32 bi = 0; bi < nb; bi++ {
        str name = benches[bi];
        string mc_src = format("bench/bench_{}.mc", name);
        defer free(mc_src);
        string mc_exe_s = format("build/bench_{}_minc{}", name, EXE_SUFFIX);
        defer free(mc_exe_s);
        str mc_exe = str_from(mc_exe_s.data, mc_exe_s.len);
        string c_src = format("bench/bench_{}.c", name);
        defer free(c_src);
        string c_exe_s = format("build/bench_{}_ref{}", name, EXE_SUFFIX);
        defer free(c_exe_s);
        str c_exe = str_from(c_exe_s.data, c_exe_s.len);

        ProcCmd mcc = { .args = {
            g_cc, str_from(mc_src.data, mc_src.len), "-o", mc_exe
        }, .capture = true };
        ProcResult mcr = proc_run(&mcc);
        i32 mc_rc = mcr.exit_code;
        proc_result_free(&mcr);
        if mc_rc != 0 || !path_exists(mc_exe) {
            bench_row(name, "CERR", "-", "-", "-", "-", "minc compile failed");
            continue;
        }
        string mc_kb = fmt_kb(file_stamp(mc_exe).size);
        defer free(mc_kb);

        string ref_kb_s = str_concat("-", "");
        defer free(ref_kb_s);
        if has_ref {
            bool built = false;
            when os(linux) || os(macos) {
                ProcCmd rc = { .args = {
                    str_from(ref_cc.data, ref_cc.len), "-O2", "-fwrapv"
                }, .capture = true };
                if bench_is_float(name) { proc_arg(&rc, "-ffp-contract=off"); }
                proc_arg(&rc, "-o");
                proc_arg(&rc, c_exe);
                proc_arg(&rc, str_from(c_src.data, c_src.len));
                proc_arg(&rc, "-lm");
                ProcResult rr = proc_run(&rc);
                built = rr.exit_code == 0;
                proc_result_free(&rr);
            }
            when os(windows) {
                string args = format("/O2 /Fo:\"build\\\\\" /Fe:\"{}\" \"{}\"",
                                     c_exe, str_from(c_src.data, c_src.len));
                defer free(args);
                ignore run_cl(str_from(ref_cc.data, ref_cc.len),
                              str_from(args.data, args.len));
                built = true;
            }
            if !built || !path_exists(c_exe) {
                bench_row(name, "-", "CERR", "-",
                          str_from(mc_kb.data, mc_kb.len), "-", "ref compile failed");
                continue;
            }
            free(ref_kb_s);
            ref_kb_s = fmt_kb(file_stamp(c_exe).size);
        }
        str ref_kb = str_from(ref_kb_s.data, ref_kb_s.len);

        string mc_val = string{};
        defer free(mc_val);
        i64 mc_time = 0;
        if !bench_run_exe(mc_exe, &mc_val, &mc_time) {
            bench_row(name, "FAIL", "-", "-",
                      str_from(mc_kb.data, mc_kb.len), ref_kb, "minc runtime error");
            continue;
        }
        string mc_t = format("{}", mc_time);
        defer free(mc_t);

        if !has_ref {
            total_minc = total_minc + mc_time;
            nbench++;
            string res = format("OK (result={})", str_from(mc_val.data, mc_val.len));
            defer free(res);
            bench_row(name, str_from(mc_t.data, mc_t.len), "-", "-",
                      str_from(mc_kb.data, mc_kb.len), "-", str_from(res.data, res.len));
            continue;
        }

        string ref_val = string{};
        defer free(ref_val);
        i64 ref_time = 0;
        if !bench_run_exe(c_exe, &ref_val, &ref_time) {
            bench_row(name, str_from(mc_t.data, mc_t.len), "FAIL", "-",
                      str_from(mc_kb.data, mc_kb.len), ref_kb, "ref runtime error");
            continue;
        }
        string ref_t = format("{}", ref_time);
        defer free(ref_t);

        // Same result, or integer results within tolerance.
        bool result_ok = str_equal(str_from(mc_val.data, mc_val.len),
                                   str_from(ref_val.data, ref_val.len));
        if !result_ok {
            i64 a = 0;
            i64 b = 0;
            if parse_i64(str_from(mc_val.data, mc_val.len), &a) &&
               parse_i64(str_from(ref_val.data, ref_val.len), &b) {
                i64 diff = a - b;
                if diff < 0 { diff = 0 - diff; }
                i64 tol = 1;
                if bench_is_float(name) { tol = 100; }
                if diff <= tol { result_ok = true; }
            }
        }
        if !result_ok {
            string mm = format("MISMATCH! minc={} ref={}",
                               str_from(mc_val.data, mc_val.len),
                               str_from(ref_val.data, ref_val.len));
            defer free(mm);
            bench_row(name, str_from(mc_t.data, mc_t.len), str_from(ref_t.data, ref_t.len),
                      "-", str_from(mc_kb.data, mc_kb.len), ref_kb,
                      str_from(mm.data, mm.len));
            continue;
        }

        string ratio = str_concat("-", "");
        defer free(ratio);
        if ref_time > 0 {
            free(ratio);
            ratio = fmt_ratio(mc_time, ref_time);
            total_minc = total_minc + mc_time;
            total_ref = total_ref + ref_time;
            nbench++;
        }
        bench_row(name, str_from(mc_t.data, mc_t.len), str_from(ref_t.data, ref_t.len),
                  str_from(ratio.data, ratio.len), str_from(mc_kb.data, mc_kb.len),
                  ref_kb, "OK");
    }

    say("");
    if has_ref && nbench > 0 && total_ref > 0 {
        string tm = format("{}", total_minc);
        defer free(tm);
        string tr = format("{}", total_ref);
        defer free(tr);
        string avg = fmt_ratio(total_minc, total_ref);
        defer free(avg);
        bench_row("TOTAL", str_from(tm.data, tm.len), str_from(tr.data, tr.len),
                  str_from(avg.data, avg.len), "", "", "");
    } else if nbench > 0 {
        string t = format("Total time: {} us (across {} benchmarks)", total_minc, nbench);
        defer free(t);
        say(str_from(t.data, t.len));
    }
    return 0;
}

// --- The C shim object (shim_demo) -------------------------------------
// shim_demo.mc @links "build/shim_demo_<plat>"; build that object with
// whatever C compiler is around before compiling the app.

void build_shim_object() {
    when os(windows) {
        str obj = "build/shim_demo_win.obj";
        ignore file_remove(obj);
        say("Compiling C shim...");
        // 1. MSVC cl. /GS- drops the stack cookie the freestanding
        //    object cannot resolve.
        string vcv = find_vcvarsall();
        defer free(vcv);
        if vcv.len > 0 {
            ignore run_cl(str_from(vcv.data, vcv.len),
                          "/c /GS- /Fo:\"build/shim_demo_win.obj\" \"shim_demo.c\"");
            if path_exists(obj) {
                say("  (cl)");
                return;
            }
        }
        // 2. clang (defaults to the -windows-msvc target on Windows).
        string clang = path_which("clang");
        defer free(clang);
        if clang.len > 0 {
            ProcCmd c = { .args = {
                str_from(clang.data, clang.len), "-c", "-fno-stack-protector",
                "shim_demo.c", "-o", obj
            } };
            ignore run_cmd(&c);
            if path_exists(obj) {
                say("  (clang)");
                return;
            }
        }
        // 3. zig cc; defaults to MinGW, so pin the MSVC target.
        string zig = path_which("zig");
        defer free(zig);
        if zig.len > 0 {
            ProcCmd c = { .args = {
                str_from(zig.data, zig.len), "cc", "-c", "-fno-stack-protector",
                "-target", "x86_64-windows-msvc", "shim_demo.c", "-o", obj
            } };
            ignore run_cmd(&c);
            if path_exists(obj) {
                say("  (zig cc)");
                return;
            }
        }
        die("shim demo needs MSVC, clang, or zig on PATH");
    }
    when os(linux) || os(macos) {
        string cc = find_ref_cc();
        defer free(cc);
        if cc.len == 0 { die("shim demo needs a C compiler (gcc or clang) on PATH"); }
        str obj = "build/shim_demo_macos.o";
        when os(linux) { obj = "build/shim_demo_linux.o"; }
        say("Compiling C shim...");
        ProcCmd c = { .args = {
            str_from(cc.data, cc.len), "-c", "-fno-stack-protector",
            "shim_demo.c", "-o", obj
        } };
        when os(linux) { proc_arg(&c, "-fno-pie"); }
        if run_cmd(&c) != 0 || !path_exists(obj) { die("C shim compile failed"); }
    }
    return;
}

// --- Hot-reload demo ---------------------------------------------------
// The engine loads libminc (the embeddable JIT) at launch; stage a copy
// from the compiler's directory next to the engine binary so the
// MINC-override and manual-zip layouts work.

i32 run_hotreload(bool watch) {
    string exe = join_named("build", "hotreload_engine", EXE_SUFFIX);
    defer free(exe);
    str exep = str_from(exe.data, exe.len);
    say("Compiling hotreload engine...");
    ProcCmd c = { .args = { g_cc, "hotreload/engine.mc", "-o", exep } };
    if run_cmd(&c) != 0 || !path_exists(exep) { die("minc compile failed"); }

    str cc_dir = path_dirname(g_cc);
    str libname = "libminc.so";
    when os(windows) { libname = "libminc.dll"; }
    when os(macos) { libname = "libminc.dylib"; }
    string lsrc = path_join(cc_dir, libname);
    defer free(lsrc);
    string ldst = path_join("build", libname);
    defer free(ldst);
    if path_exists(str_from(lsrc.data, lsrc.len)) {
        ignore file_copy(str_from(lsrc.data, lsrc.len), str_from(ldst.data, ldst.len));
    } else if !path_exists(str_from(ldst.data, ldst.len)) {
        say("warning: libminc not found next to minc; the engine may fail to start");
    }

    say("Running hotreload engine...");
    ProcCmd run = { .args = { exep } };
    if watch { proc_arg(&run, "watch"); }
    return run_cmd(&run);
}

// --- Platform packaging helpers ----------------------------------------

// Trimmed captured output of a command; empty on failure.
string capture_out(ProcCmd* c) {
    c.capture = true;
    ProcResult r = proc_run(c);
    defer proc_result_free(&r);
    if !r.spawned || r.exit_code != 0 {
        return string{};
    }
    str t = str_trim(str_from(r.out.data, r.out.len));
    return str_concat(t, "");
}

// The next line of s starting at *pos; advances *pos past it.
str next_line(str s, i32* pos) {
    i32 b = *pos;
    if b >= s.len { return ""; }
    i32 e = b;
    while e < s.len && s.data[e] != '\n' { e++; }
    *pos = e + 1;
    i32 stop = e;
    if stop > b && s.data[stop - 1] == '\r' { stop--; }
    return str_slice(s, b, stop);
}

// "com.minc.<name>" with '_' -> '-', lowercased. MINC_BUNDLE_PREFIX
// overrides the prefix.
string bundle_id_for(str name) {
    string prefix = env_get("MINC_BUNDLE_PREFIX");
    defer free(prefix);
    str p = "com.minc";
    if prefix.len > 0 { p = str_from(prefix.data, prefix.len); }
    str_buf b;
    str_buf_init(&b);
    defer str_buf_free(&b);
    str_buf_add(&b, p);
    str_buf_add_byte(&b, '.');
    for i32 i = 0; i < name.len; i++ {
        u8 c = lc_byte(name.data[i]);
        if c == '_' { c = '-'; }
        str_buf_add_byte(&b, c);
    }
    return str_concat(str_buf_to_str(&b), "");
}

bool is_media_asset(str name) {
    return str_ends_with(name, ".png") || str_ends_with(name, ".jpg") ||
           str_ends_with(name, ".jpeg") || str_ends_with(name, ".wav") ||
           str_ends_with(name, ".ogg") || str_ends_with(name, ".bin");
}

// Copy test/'s media files into <dst_root>/test so bundled examples
// find their assets at run time (same relative layout as the CLI).
void stage_assets_dir(str src_dir, str dst_dir) {
    DirList files = dir_list(src_dir, "", false);
    defer dir_list_free(&files);
    bool made = false;
    for i32 i = 0; i < files.count; i++ {
        if !is_media_asset(files.items[i]) { continue; }
        if !made {
            ignore dir_create(dst_dir);
            made = true;
        }
        string s = path_join(src_dir, files.items[i]);
        defer free(s);
        string d = path_join(dst_dir, files.items[i]);
        defer free(d);
        ignore file_copy(str_from(s.data, s.len), str_from(d.data, d.len));
    }
    DirList dirs = dir_list(src_dir, "", true);
    defer dir_list_free(&dirs);
    for i32 i = 0; i < dirs.count; i++ {
        string s = path_join(src_dir, dirs.items[i]);
        defer free(s);
        string d = path_join(dst_dir, dirs.items[i]);
        defer free(d);
        stage_assets_dir(str_from(s.data, s.len), str_from(d.data, d.len));
    }
    return;
}

void stage_assets(str dst_root) {
    if !path_is_dir("test") { return; }
    string dst = path_join(dst_root, "test");
    defer free(dst);
    stage_assets_dir("test", str_from(dst.data, dst.len));
    return;
}

// Fresh bundle dir at `path` with the compiled binary copied in as
// <name>; dies on failure.
void stage_bundle_binary(str app_dir, str sub, str exe, str name) {
    ignore dir_remove(app_dir);
    string bin_dir = path_join(app_dir, sub);
    defer free(bin_dir);
    if sub.len == 0 {
        free(bin_dir);
        bin_dir = str_concat(app_dir, "");
    }
    if !dir_create(str_from(bin_dir.data, bin_dir.len)) { die("cannot create bundle dir"); }
    string dst = path_join(str_from(bin_dir.data, bin_dir.len), name);
    defer free(dst);
    if !file_copy(exe, str_from(dst.data, dst.len)) { die("cannot stage binary into bundle"); }
    return;
}

// --- macOS / iOS bundles (macOS host only) -----------------------------

when os(macos) {

// Compile <src> for `target` into build/<name>; dies on failure.
void compile_for_target(str src, str target, str exe) {
    ProcCmd c = { .args = { g_cc, src, "--target", target, "-o", exe } };
    if run_cmd(&c) != 0 || !path_exists(exe) { die("minc compile failed"); }
    return;
}

i32 do_macos_app(str name, str src, bool do_run, bool open_flag) {
    out("Compiling ");
    out(name);
    say(" (macOS .app)...");
    string exe = join_named("build", name, "");
    defer free(exe);
    compile_for_target(src, "macos", str_from(exe.data, exe.len));

    string app_s = format("build/{}.app", name);
    defer free(app_s);
    str app_dir = str_from(app_s.data, app_s.len);
    string bid = bundle_id_for(name);
    defer free(bid);
    stage_bundle_binary(app_dir, "Contents/MacOS", str_from(exe.data, exe.len), name);

    str_buf p;
    str_buf_init(&p);
    defer str_buf_free(&p);
    str_buf_add(&p, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    str_buf_add(&p, "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n");
    str_buf_add(&p, "<plist version=\"1.0\"><dict>\n");
    string kv = format("    <key>CFBundleExecutable</key><string>{}</string>\n    <key>CFBundleName</key><string>{}</string>\n    <key>CFBundleIdentifier</key><string>{}</string>\n",
                       name, name, str_from(bid.data, bid.len));
    str_buf_add(&p, str_from(kv.data, kv.len));
    free(kv);
    str_buf_add(&p, "    <key>CFBundleVersion</key><string>1</string>\n");
    str_buf_add(&p, "    <key>CFBundleShortVersionString</key><string>1.0</string>\n");
    str_buf_add(&p, "    <key>CFBundlePackageType</key><string>APPL</string>\n");
    str_buf_add(&p, "    <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>\n");
    str_buf_add(&p, "    <key>LSMinimumSystemVersion</key><string>11.0</string>\n");
    str_buf_add(&p, "    <key>NSHighResolutionCapable</key><true/>\n");
    str_buf_add(&p, "</dict></plist>\n");
    string plist = path_join(app_dir, "Contents/Info.plist");
    defer free(plist);
    if !file_write_str(str_from(plist.data, plist.len), str_buf_to_str(&p)) {
        die("cannot write Info.plist");
    }

    string res = path_join(app_dir, "Contents/Resources");
    defer free(res);
    stage_assets(str_from(res.data, res.len));

    ProcCmd cs = { .args = { "codesign", "-s", "-", app_dir }, .capture = true };
    ignore run_cmd(&cs);
    out("Bundle: ");
    say(app_dir);
    if do_run || open_flag {
        say("Launching...");
        ProcCmd op = { .args = { "open", app_dir } };
        return run_cmd(&op);
    }
    return 0;
}

// UDID inside the "(...)" group right before the marker on any line
// of simctl's device listing, e.g.
//   "    iPhone 16 Pro (ABCD-...-1234) (Booted)".
string simctl_find_udid(str listing, str marker) {
    i32 pos = 0;
    while pos < listing.len {
        str line = next_line(listing, &pos);
        i32 m = str_find(line, marker);
        if m < 0 { continue; }
        if str_contains(line, "unavailable") { continue; }
        i32 close = -1;
        for i32 i = m - 1; i >= 0; i-- {
            if line.data[i] == ')' { close = i; break; }
        }
        if close < 0 { continue; }
        i32 open_at = -1;
        for i32 i = close - 1; i >= 0; i-- {
            if line.data[i] == '(' { open_at = i; break; }
        }
        if open_at < 0 { continue; }
        str udid = str_slice(line, open_at + 1, close);
        if udid.len < 8 { continue; }
        return str_concat(udid, "");
    }
    return string{};
}

// A booted simulator's UDID, booting one when necessary.
string ensure_booted_sim() {
    ProcCmd lb = { .args = { "xcrun", "simctl", "list", "devices", "booted" } };
    string booted_list = capture_out(&lb);
    defer free(booted_list);
    string udid = simctl_find_udid(str_from(booted_list.data, booted_list.len), "(Booted)");
    if udid.len > 0 { return udid; }
    free(udid);

    ProcCmd la = { .args = { "xcrun", "simctl", "list", "devices", "available" } };
    string avail = capture_out(&la);
    defer free(avail);
    udid = simctl_find_udid(str_from(avail.data, avail.len), "(Shutdown)");
    if udid.len == 0 { return udid; }

    say("Booting simulator...");
    ProcCmd boot = { .args = { "xcrun", "simctl", "boot", str_from(udid.data, udid.len) }, .capture = true };
    ignore run_cmd(&boot);
    ProcCmd op = { .args = { "open", "-a", "Simulator" }, .capture = true };
    ignore run_cmd(&op);
    thread_sleep(3000);
    return udid;
}

i32 do_ios_sim(str name, str src, bool do_run) {
    out("Compiling ");
    out(name);
    say(" (iOS Simulator)...");
    string exe = join_named("build", name, "");
    defer free(exe);
    compile_for_target(src, "ios-sim", str_from(exe.data, exe.len));

    string app_s = format("build/{}.app", name);
    defer free(app_s);
    str app_dir = str_from(app_s.data, app_s.len);
    string bid = bundle_id_for(name);
    defer free(bid);
    stage_bundle_binary(app_dir, "", str_from(exe.data, exe.len), name);

    str_buf p;
    str_buf_init(&p);
    defer str_buf_free(&p);
    str_buf_add(&p, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    str_buf_add(&p, "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n");
    str_buf_add(&p, "<plist version=\"1.0\"><dict>\n");
    string kv = format("    <key>CFBundleExecutable</key><string>{}</string>\n    <key>CFBundleIdentifier</key><string>{}</string>\n",
                       name, str_from(bid.data, bid.len));
    str_buf_add(&p, str_from(kv.data, kv.len));
    free(kv);
    str_buf_add(&p, "    <key>CFBundleVersion</key><string>1</string>\n");
    str_buf_add(&p, "    <key>CFBundleShortVersionString</key><string>1.0</string>\n");
    str_buf_add(&p, "    <key>CFBundlePackageType</key><string>APPL</string>\n");
    str_buf_add(&p, "    <key>MinimumOSVersion</key><string>15.0</string>\n");
    str_buf_add(&p, "    <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>\n");
    str_buf_add(&p, "    <key>DTPlatformName</key><string>iphonesimulator</string>\n");
    str_buf_add(&p, "</dict></plist>\n");
    string plist = path_join(app_dir, "Info.plist");
    defer free(plist);
    if !file_write_str(str_from(plist.data, plist.len), str_buf_to_str(&p)) {
        die("cannot write Info.plist");
    }
    stage_assets(app_dir);
    ProcCmd cs = { .args = { "codesign", "-s", "-", app_dir }, .capture = true };
    ignore run_cmd(&cs);
    out("Bundle: ");
    say(app_dir);
    if !do_run { return 0; }

    string udid = ensure_booted_sim();
    defer free(udid);
    if udid.len == 0 { die("No simulator available. Install one in Xcode."); }
    ProcCmd inst = { .args = { "xcrun", "simctl", "install", "booted", app_dir } };
    if run_cmd(&inst) != 0 { die("simctl install failed"); }
    thread_sleep(1000);
    ProcCmd launch = { .args = {
        "xcrun", "simctl", "launch", "booted", str_from(bid.data, bid.len)
    } };
    if run_cmd(&launch) != 0 { die("simctl launch failed"); }
    out(name);
    say(" running in iOS Simulator");
    return 0;
}

// First .mobileprovision in the usual profile folders, or empty.
string find_provisioning_profile() {
    string home = env_get("HOME");
    defer free(home);
    str h = str_from(home.data, home.len);
    str[2] dirs;
    dirs[0] = "Library/Developer/Xcode/UserData/Provisioning Profiles";
    dirs[1] = "Library/MobileDevice/Provisioning Profiles";
    for i32 i = 0; i < 2; i++ {
        string d = path_join(h, dirs[i]);
        defer free(d);
        DirList l = dir_list(str_from(d.data, d.len), ".mobileprovision", false);
        defer dir_list_free(&l);
        if l.count > 0 {
            return path_join(str_from(d.data, d.len), l.items[0]);
        }
    }
    return string{};
}

// The value between <key>TeamIdentifier</key>'s following <string> tags
// of a decoded provisioning profile.
string profile_team_id(str profile) {
    ProcCmd c = { .args = { "security", "cms", "-D", "-i", profile } };
    string xml = capture_out(&c);
    defer free(xml);
    str x = str_from(xml.data, xml.len);
    i32 at = str_find(x, "<key>TeamIdentifier</key>");
    if at < 0 { return string{}; }
    str rest = str_slice(x, at, x.len);
    i32 b = str_find(rest, "<string>");
    if b < 0 { return string{}; }
    str rest2 = str_slice(rest, b + 8, rest.len);
    i32 e = str_find(rest2, "</string>");
    if e < 0 { return string{}; }
    return str_concat(str_trim(str_slice(rest2, 0, e)), "");
}

// The OU (team id) of a codesigning certificate by name, via
// `security find-certificate` piped through `openssl x509` (with a
// temp PEM file standing in for the pipe).
string cert_team_ou(str cert_name) {
    ProcCmd c = { .args = { "security", "find-certificate", "-c", cert_name, "-p" } };
    string pem = capture_out(&c);
    defer free(pem);
    if pem.len == 0 { return string{}; }
    if !file_write_str("build/_cert.pem", str_from(pem.data, pem.len)) { return string{}; }
    ProcCmd o = { .args = {
        "openssl", "x509", "-noout", "-subject", "-nameopt", "multiline",
        "-in", "build/_cert.pem"
    } };
    string subj = capture_out(&o);
    defer free(subj);
    str s = str_from(subj.data, subj.len);
    i32 at = str_find(s, "organizationalUnitName");
    if at < 0 { return string{}; }
    str rest = str_slice(s, at, s.len);
    i32 eq = str_find_byte(rest, '=');
    if eq < 0 { return string{}; }
    i32 nl = str_find_byte(rest, '\n');
    if nl < 0 { nl = rest.len; }
    if nl <= eq { return string{}; }
    return str_concat(str_trim(str_slice(rest, eq + 1, nl)), "");
}

// "Apple Development" identity names from `security find-identity`,
// preferring one whose team matches; else the first.
string find_signing_identity(str want_team) {
    ProcCmd c = { .args = { "security", "find-identity", "-v", "-p", "codesigning" } };
    string ids = capture_out(&c);
    defer free(ids);
    str s = str_from(ids.data, ids.len);
    string first = string{};
    i32 pos = 0;
    while pos < s.len {
        str line = next_line(s, &pos);
        if !str_contains(line, "Apple Development") { continue; }
        i32 q1 = str_find_byte(line, '"');
        if q1 < 0 { continue; }
        str rest = str_slice(line, q1 + 1, line.len);
        i32 q2 = str_find_byte(rest, '"');
        if q2 < 0 { continue; }
        str cert_name = str_slice(rest, 0, q2);
        if first.len == 0 { first = str_concat(cert_name, ""); }
        if want_team.len > 0 {
            string ou = cert_team_ou(cert_name);
            defer free(ou);
            if str_equal(str_from(ou.data, ou.len), want_team) {
                free(first);
                return str_concat(cert_name, "");
            }
        }
    }
    return first;
}

i32 do_ios_device(str name, str src, bool do_run) {
    ProcCmd sdkc = { .args = { "xcrun", "--sdk", "iphoneos", "--show-sdk-path" } };
    string sdk = capture_out(&sdkc);
    defer free(sdk);
    if sdk.len == 0 { die("iOS SDK not found. Install Xcode."); }

    string prof = find_provisioning_profile();
    defer free(prof);
    string prof_team = string{};
    defer free(prof_team);
    if prof.len > 0 {
        prof_team = profile_team_id(str_from(prof.data, prof.len));
    }
    string sign_id = find_signing_identity(str_from(prof_team.data, prof_team.len));
    defer free(sign_id);
    if sign_id.len == 0 {
        die("No code signing identity found. Sign in to Xcode (Settings > Accounts).");
    }

    out("Compiling ");
    out(name);
    say(" (iOS device)...");
    string exe = join_named("build", name, "");
    defer free(exe);
    compile_for_target(src, "ios", str_from(exe.data, exe.len));

    string app_s = format("build/{}_device.app", name);
    defer free(app_s);
    str app_dir = str_from(app_s.data, app_s.len);
    string bid = bundle_id_for(name);
    defer free(bid);
    stage_bundle_binary(app_dir, "", str_from(exe.data, exe.len), name);

    // Landscape-only examples; everything else allows both.
    str orient = "<string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string>";
    if str_equal(name, "sokol_compute") || str_equal(name, "raytracer_mt") ||
       str_equal(name, "missile_command") {
        orient = "<string>UIInterfaceOrientationLandscapeRight</string><string>UIInterfaceOrientationLandscapeLeft</string>";
    }

    str_buf p;
    str_buf_init(&p);
    defer str_buf_free(&p);
    str_buf_add(&p, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    str_buf_add(&p, "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n");
    str_buf_add(&p, "<plist version=\"1.0\"><dict>\n");
    string kv = format("    <key>CFBundleExecutable</key><string>{}</string>\n    <key>CFBundleName</key><string>{}</string>\n    <key>CFBundleIdentifier</key><string>{}</string>\n",
                       name, name, str_from(bid.data, bid.len));
    str_buf_add(&p, str_from(kv.data, kv.len));
    free(kv);
    str_buf_add(&p, "    <key>CFBundleVersion</key><string>1</string>\n");
    str_buf_add(&p, "    <key>CFBundleShortVersionString</key><string>1.0</string>\n");
    str_buf_add(&p, "    <key>CFBundlePackageType</key><string>APPL</string>\n");
    str_buf_add(&p, "    <key>MinimumOSVersion</key><string>15.0</string>\n");
    str_buf_add(&p, "    <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>\n");
    str_buf_add(&p, "    <key>DTPlatformName</key><string>iphoneos</string>\n");
    string ok = format("    <key>UISupportedInterfaceOrientations</key><array>{}</array>\n", orient);
    str_buf_add(&p, str_from(ok.data, ok.len));
    free(ok);
    str_buf_add(&p, "    <key>UIApplicationSceneManifest</key><dict>\n");
    str_buf_add(&p, "        <key>UIApplicationSupportsMultipleScenes</key><false/>\n");
    str_buf_add(&p, "        <key>UISceneConfigurations</key><dict>\n");
    str_buf_add(&p, "            <key>UIWindowSceneSessionRoleApplication</key><array>\n");
    str_buf_add(&p, "                <dict>\n");
    str_buf_add(&p, "                    <key>UISceneConfigurationName</key><string>Default Configuration</string>\n");
    str_buf_add(&p, "                    <key>UISceneDelegateClassName</key><string>_sapp_scene_delegate</string>\n");
    str_buf_add(&p, "                </dict>\n");
    str_buf_add(&p, "            </array>\n");
    str_buf_add(&p, "        </dict>\n");
    str_buf_add(&p, "    </dict>\n");
    str_buf_add(&p, "    <key>UILaunchScreen</key><dict/>\n");
    str_buf_add(&p, "</dict></plist>\n");
    string plist = path_join(app_dir, "Info.plist");
    defer free(plist);
    if !file_write_str(str_from(plist.data, plist.len), str_buf_to_str(&p)) {
        die("cannot write Info.plist");
    }

    // Team for the entitlements: the signing cert's OU, the profile's
    // team, or an explicit MINC_TEAM_ID override.
    string team = env_get("MINC_TEAM_ID");
    if team.len == 0 {
        free(team);
        team = cert_team_ou(str_from(sign_id.data, sign_id.len));
    }
    if team.len == 0 {
        free(team);
        team = str_concat(str_from(prof_team.data, prof_team.len), "");
    }
    defer free(team);
    str_buf e;
    str_buf_init(&e);
    defer str_buf_free(&e);
    str_buf_add(&e, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    str_buf_add(&e, "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n");
    str_buf_add(&e, "<plist version=\"1.0\"><dict>\n");
    string ent = format("    <key>application-identifier</key><string>{}.{}</string>\n    <key>keychain-access-groups</key><array><string>{}.*</string></array>\n    <key>get-task-allow</key><true/>\n    <key>com.apple.developer.team-identifier</key><string>{}</string>\n",
                        str_from(team.data, team.len), str_from(bid.data, bid.len),
                        str_from(team.data, team.len), str_from(team.data, team.len));
    str_buf_add(&e, str_from(ent.data, ent.len));
    free(ent);
    str_buf_add(&e, "</dict></plist>\n");
    if !file_write_str("build/_entitlements.plist", str_buf_to_str(&e)) {
        die("cannot write entitlements");
    }

    if prof.len > 0 {
        string emb = path_join(app_dir, "embedded.mobileprovision");
        defer free(emb);
        ignore file_copy(str_from(prof.data, prof.len), str_from(emb.data, emb.len));
    } else {
        say("Warning: No provisioning profile found. Device install may fail.");
    }
    stage_assets(app_dir);

    out("Signing with: ");
    say(str_from(sign_id.data, sign_id.len));
    ProcCmd cs = { .args = {
        "codesign", "-s", str_from(sign_id.data, sign_id.len),
        "--entitlements", "build/_entitlements.plist", app_dir
    } };
    ignore run_cmd(&cs);
    out("Bundle: ");
    say(app_dir);
    if !do_run { return 0; }

    say("Looking for connected device...");
    ProcCmd dl = { .args = {
        "xcrun", "devicectl", "list", "devices", "--json-output", "build/_devices.json"
    }, .capture = true };
    ignore run_cmd(&dl);
    string dev = string{};
    defer free(dev);
    string js = file_read_str("build/_devices.json");
    defer free(js);
    str j = str_from(js.data, js.len);
    // devicectl emits keys alphabetically, so a device object's
    // "identifier" follows its connectionProperties.transportType.
    i32 scan = 0;
    while dev.len == 0 && scan < j.len {
        str rest = str_slice(j, scan, j.len);
        i32 tt = str_find(rest, "\"transportType\"");
        if tt < 0 { break; }
        str after = str_slice(rest, tt, rest.len);
        str window = str_slice(after, 0, 60);
        if after.len < 60 { window = after; }
        bool usable = str_contains(window, "wired") || str_contains(window, "localNetwork");
        i32 idk = str_find(after, "\"identifier\"");
        if usable && idk >= 0 {
            str v = str_slice(after, idk + 12, after.len);
            i32 q1 = str_find_byte(v, '"');
            if q1 >= 0 {
                str v2 = str_slice(v, q1 + 1, v.len);
                i32 q2 = str_find_byte(v2, '"');
                if q2 > 0 { dev = str_concat(str_slice(v2, 0, q2), ""); }
            }
        }
        scan = scan + tt + 15;
    }
    if dev.len == 0 {
        say("No iOS device connected.");
        out("Bundle ready at: ");
        say(app_dir);
        say("Connect a device, then:");
        say("  xcrun devicectl device install app --device <id> <bundle>");
        say("  xcrun devicectl device process launch --device <id> <bundle-id>");
        return 0;
    }
    out("  Device: ");
    say(str_from(dev.data, dev.len));
    say("Installing...");
    ProcCmd inst = { .args = {
        "xcrun", "devicectl", "device", "install", "app",
        "--device", str_from(dev.data, dev.len), app_dir
    } };
    if run_cmd(&inst) != 0 { die("device install failed"); }
    say("Launching...");
    ProcCmd launch = { .args = {
        "xcrun", "devicectl", "device", "process", "launch",
        "--device", str_from(dev.data, dev.len), str_from(bid.data, bid.len)
    } };
    if run_cmd(&launch) != 0 { die("device launch failed"); }
    out(name);
    say(" running on device");
    return 0;
}

}

// --- Android -----------------------------------------------------------

// Numeric-aware version compare for SDK folder names ("35.0.0",
// "27.2.12479018", "android-35"): digit runs compare numerically,
// everything else bytewise.
i32 ver_cmp(str a, str b) {
    i32 i = 0;
    i32 j = 0;
    while i < a.len && j < b.len {
        bool da = a.data[i] >= '0' && a.data[i] <= '9';
        bool db = b.data[j] >= '0' && b.data[j] <= '9';
        if da && db {
            i64 va = 0;
            i64 vb = 0;
            while i < a.len && a.data[i] >= '0' && a.data[i] <= '9' {
                va = va * 10 + (a.data[i] - '0');
                i++;
            }
            while j < b.len && b.data[j] >= '0' && b.data[j] <= '9' {
                vb = vb * 10 + (b.data[j] - '0');
                j++;
            }
            if va != vb {
                if va < vb { return -1; }
                return 1;
            }
        } else {
            if a.data[i] != b.data[j] {
                if a.data[i] < b.data[j] { return -1; }
                return 1;
            }
            i++;
            j++;
        }
    }
    if a.len - i == b.len - j { return 0; }
    if a.len - i < b.len - j { return -1; }
    return 1;
}

// "<base>/<highest version subdir>", or empty when none exist.
string pick_latest_dir(str base) {
    DirList l = dir_list(base, "", true);
    defer dir_list_free(&l);
    i32 best = -1;
    for i32 i = 0; i < l.count; i++ {
        if best < 0 || ver_cmp(l.items[i], l.items[best]) > 0 { best = i; }
    }
    if best < 0 { return string{}; }
    return path_join(base, l.items[best]);
}

string android_sdk_home() {
    string env = env_get("ANDROID_HOME");
    if env.len > 0 { return env; }
    free(env);
    when os(windows) {
        string lad = env_get("LOCALAPPDATA");
        defer free(lad);
        if lad.len > 0 {
            return path_join(str_from(lad.data, lad.len), "Android\\Sdk");
        }
        return string{};
    }
    when os(macos) || os(linux) {
        string home = env_get("HOME");
        defer free(home);
        str h = str_from(home.data, home.len);
        when os(macos) { return path_join(h, "Library/Android/sdk"); }
        when os(linux) { return path_join(h, "Android/Sdk"); }
    }
}

// keytool needs a JDK; find one and prepend it to PATH for every child
// this process spawns. macOS ships /usr/bin/java stubs that exist but
// fail without a JDK, so probe by RUNNING java, not by finding it.
void ensure_java_on_path() {
    ProcCmd jc = { .args = { "java", "-version" }, .capture = true };
    ProcResult jr = proc_run(&jc);
    bool ok = jr.spawned && jr.exit_code == 0;
    proc_result_free(&jr);
    if ok { return; }
    when os(macos) {
        string home = env_get("HOME");
        defer free(home);
        string jroot = path_join(str_from(home.data, home.len), "Library/Java");
        defer free(jroot);
        string jdk = pick_latest_dir(str_from(jroot.data, jroot.len));
        defer free(jdk);
        if jdk.len == 0 { return; }
        string jhome = path_join(str_from(jdk.data, jdk.len), "Contents/Home");
        defer free(jhome);
        string jbin = path_join(str_from(jhome.data, jhome.len), "bin");
        defer free(jbin);
        ignore env_set("JAVA_HOME", str_from(jhome.data, jhome.len));
        string cur = env_get("PATH");
        defer free(cur);
        string np = format("{}:{}", str_from(jbin.data, jbin.len), str_from(cur.data, cur.len));
        defer free(np);
        ignore env_set("PATH", str_from(np.data, np.len));
    }
    return;
}

// <build-tools>/<tool><exe suffix> as an owned path.
string bt_tool(str bt_dir, str tool) {
    when os(windows) {
        string t = str_concat(tool, ".exe");
        defer free(t);
        string cand = path_join(bt_dir, str_from(t.data, t.len));
        if path_exists(str_from(cand.data, cand.len)) { return cand; }
        free(cand);
        // apksigner is a .bat wrapper on Windows.
        string tb = str_concat(tool, ".bat");
        defer free(tb);
        return path_join(bt_dir, str_from(tb.data, tb.len));
    }
    return path_join(bt_dir, tool);
}

i32 do_android(str name, str src, bool do_run) {
    ensure_java_on_path();
    string sdk = android_sdk_home();
    defer free(sdk);
    if sdk.len == 0 || !path_is_dir(str_from(sdk.data, sdk.len)) {
        die("Android SDK not found. Set ANDROID_HOME (see README).");
    }
    str sdkp = str_from(sdk.data, sdk.len);

    string ndk_root = path_join(sdkp, "ndk");
    defer free(ndk_root);
    string ndk = pick_latest_dir(str_from(ndk_root.data, ndk_root.len));
    defer free(ndk);
    if ndk.len == 0 { die("Android NDK not found. See README."); }
    string bt_root = path_join(sdkp, "build-tools");
    defer free(bt_root);
    string bt = pick_latest_dir(str_from(bt_root.data, bt_root.len));
    defer free(bt);
    if bt.len == 0 { die("Android build-tools not found"); }
    string plat_root = path_join(sdkp, "platforms");
    defer free(plat_root);
    string plat = pick_latest_dir(str_from(plat_root.data, plat_root.len));
    defer free(plat);
    if plat.len == 0 { die("Android platform (android.jar) not found"); }

    // NDK sysroot: the single host dir under prebuilt/. API 26
    // (Android 8.0) is the floor for libaaudio, which sokol_audio
    // examples link.
    string prebuilt = path_join(str_from(ndk.data, ndk.len), "toolchains/llvm/prebuilt");
    defer free(prebuilt);
    string host = pick_latest_dir(str_from(prebuilt.data, prebuilt.len));
    defer free(host);
    if host.len == 0 { die("NDK prebuilt toolchain not found"); }
    string sysroot = path_join(str_from(host.data, host.len),
                               "sysroot/usr/lib/aarch64-linux-android/26");
    defer free(sysroot);
    str sr = str_from(sysroot.data, sysroot.len);
    if !path_is_dir(sr) { die("NDK sysroot (API 26, aarch64) not found"); }

    out("Compiling ");
    out(name);
    say(" (Android ARM64)...");
    ProcCmd cc = { .args = { g_cc, src, "--target", "android", "--shared" } };
    str[6] libs = { "libc.so", "libGLESv3.so", "libEGL.so",
                    "libandroid.so", "liblog.so", "libaaudio.so" };
    // ProcCmd stores the arg pointers, so the joined paths must stay
    // alive until proc_run — free them after, not per iteration.
    noinit string[6] libpaths;
    for i32 i = 0; i < 6; i++ {
        libpaths[i] = path_join(sr, libs[i]);
        proc_arg(&cc, "--link");
        proc_arg(&cc, str_from(libpaths[i].data, libpaths[i].len));
    }
    proc_arg(&cc, "-o");
    proc_arg(&cc, "build/libapp.so");
    i32 cc_rc = run_cmd(&cc);
    for i32 i = 0; i < 6; i++ { free(libpaths[i].data); }
    if cc_rc != 0 || !path_exists("build/libapp.so") { die("minc compile failed"); }

    say("Packaging APK...");
    string pkg_env = env_get("MINC_ANDROID_PACKAGE");
    defer free(pkg_env);
    str pkg = "com.minc.app";
    if pkg_env.len > 0 { pkg = str_from(pkg_env.data, pkg_env.len); }

    str_buf m;
    str_buf_init(&m);
    defer str_buf_free(&m);
    str_buf_add(&m, "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
    string mo = format("<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\"\n    package=\"{}\">\n", pkg);
    str_buf_add(&m, str_from(mo.data, mo.len));
    free(mo);
    str_buf_add(&m, "    <uses-sdk android:minSdkVersion=\"26\" android:targetSdkVersion=\"35\"/>\n");
    str_buf_add(&m, "    <uses-feature android:glEsVersion=\"0x00030000\" android:required=\"true\"/>\n");
    str_buf_add(&m, "    <application android:hasCode=\"false\">\n");
    str_buf_add(&m, "        <activity android:name=\"android.app.NativeActivity\"\n");
    str_buf_add(&m, "            android:exported=\"true\"\n");
    str_buf_add(&m, "            android:configChanges=\"orientation|keyboardHidden|screenSize\">\n");
    str_buf_add(&m, "            <meta-data android:name=\"android.app.lib_name\" android:value=\"app\"/>\n");
    str_buf_add(&m, "            <intent-filter>\n");
    str_buf_add(&m, "                <action android:name=\"android.intent.action.MAIN\"/>\n");
    str_buf_add(&m, "                <category android:name=\"android.intent.category.LAUNCHER\"/>\n");
    str_buf_add(&m, "            </intent-filter>\n");
    str_buf_add(&m, "        </activity>\n");
    str_buf_add(&m, "    </application>\n");
    str_buf_add(&m, "</manifest>\n");
    if !file_write_str("build/AndroidManifest.xml", str_buf_to_str(&m)) {
        die("cannot write AndroidManifest.xml");
    }

    // aapt2 compiles the manifest to binary XML; --output-to-dir so the
    // APK zip is built entirely by lib/zip. The dir must exist first.
    ignore dir_remove("build/apk_dir");
    ignore dir_create("build/apk_dir");
    string aapt2 = bt_tool(str_from(bt.data, bt.len), "aapt2");
    defer free(aapt2);
    string jar = path_join(str_from(plat.data, plat.len), "android.jar");
    defer free(jar);
    ProcCmd al = { .args = {
        str_from(aapt2.data, aapt2.len), "link", "-o", "build/apk_dir",
        "--output-to-dir", "--manifest", "build/AndroidManifest.xml",
        "-I", str_from(jar.data, jar.len)
    } };
    if run_cmd(&al) != 0 { die("aapt2 link failed"); }

    // resources.arsc must be stored (Android R+ rejects a compressed
    // one); the manifest and the native lib deflate.
    ZipWriter z;
    ignore zip_add_file(&z, "AndroidManifest.xml", "build/apk_dir/AndroidManifest.xml", true);
    if path_exists("build/apk_dir/resources.arsc") {
        ignore zip_add_file(&z, "resources.arsc", "build/apk_dir/resources.arsc", false);
    }
    ignore zip_add_file(&z, "lib/arm64-v8a/libapp.so", "build/libapp.so", true);
    if !zip_end(&z, "build/app-unsigned.apk") { die("APK packaging failed"); }

    string zipalign = bt_tool(str_from(bt.data, bt.len), "zipalign");
    defer free(zipalign);
    ProcCmd za = { .args = {
        str_from(zipalign.data, zipalign.len), "-f", "4",
        "build/app-unsigned.apk", "build/app.apk"
    }, .capture = true };
    if run_cmd(&za) != 0 { die("zipalign failed"); }

    if !path_exists("build/debug.keystore") {
        ProcCmd kt = { .args = {
            "keytool", "-genkey", "-v", "-keystore", "build/debug.keystore",
            "-alias", "debug", "-keyalg", "RSA", "-keysize", "2048",
            "-validity", "10000", "-storepass", "android", "-keypass", "android",
            "-dname", "CN=Debug,O=Debug,C=US"
        }, .capture = true };
        if run_cmd(&kt) != 0 { die("keytool failed (is a JDK installed?)"); }
    }
    string apksigner = bt_tool(str_from(bt.data, bt.len), "apksigner");
    defer free(apksigner);
    ProcCmd sg = { .args = {
        str_from(apksigner.data, apksigner.len), "sign",
        "--ks", "build/debug.keystore", "--ks-pass", "pass:android",
        "build/app.apk"
    } };
    if run_cmd(&sg) != 0 { die("apksigner failed"); }
    say("APK: build/app.apk");
    if !do_run { return 0; }

    string pt = path_join(sdkp, "platform-tools");
    defer free(pt);
    string adb = bt_tool(str_from(pt.data, pt.len), "adb");
    defer free(adb);
    str adbp = str_from(adb.data, adb.len);
    if !path_exists(adbp) {
        say("adb not found. Install: adb install build/app.apk");
        return 0;
    }

    // A device online? Otherwise boot the first emulator and wait.
    ProcCmd dc = { .args = { adbp, "devices" } };
    string devs = capture_out(&dc);
    bool have_dev = str_contains(str_from(devs.data, devs.len), "\tdevice");
    free(devs);
    if !have_dev {
        string emu_dir = path_join(sdkp, "emulator");
        defer free(emu_dir);
        string emu = bt_tool(str_from(emu_dir.data, emu_dir.len), "emulator");
        defer free(emu);
        ProcCmd la = { .args = { str_from(emu.data, emu.len), "-list-avds" } };
        string avds = capture_out(&la);
        defer free(avds);
        i32 lp = 0;
        str avd = next_line(str_from(avds.data, avds.len), &lp);
        if avd.len == 0 {
            say("No device/emulator found. Install: adb install build/app.apk");
            return 0;
        }
        out("Starting emulator (");
        out(avd);
        say(")...");
        // proc_run waits for its child, so detach through the shell: the
        // backgrounded emulator survives this script's exit.
        when os(windows) {
            string cl = format("start \"\" \"{}\" -avd {} -no-snapshot-load",
                               str_from(emu.data, emu.len), avd);
            defer free(cl);
            ProcCmd es = { .args = { "cmd.exe", "/c", str_from(cl.data, cl.len) } };
            ignore run_cmd(&es);
        }
        when os(linux) || os(macos) {
            string cl = format("\"{}\" -avd {} -no-snapshot-load >/dev/null 2>&1 &",
                               str_from(emu.data, emu.len), avd);
            defer free(cl);
            ProcCmd es = { .args = { "sh", "-c", str_from(cl.data, cl.len) } };
            ignore run_cmd(&es);
        }
        out("  Waiting for boot");
        for i32 i = 0; i < 60; i++ {
            ProcCmd chk = { .args = { adbp, "devices" } };
            string o = capture_out(&chk);
            bool up = str_contains(str_from(o.data, o.len), "\tdevice");
            free(o);
            if up { break; }
            out(".");
            thread_sleep(2000);
        }
        say("");
    }
    // Device online is not booted: launching before sys.boot_completed
    // gets "Activity class does not exist". Poll the property.
    for i32 i = 0; i < 30; i++ {
        ProcCmd bc = { .args = { adbp, "shell", "getprop", "sys.boot_completed" } };
        string o = capture_out(&bc);
        bool booted = str_contains(str_from(o.data, o.len), "1");
        free(o);
        if booted { break; }
        thread_sleep(2000);
    }

    say("Installing...");
    ProcCmd inst = { .args = { adbp, "install", "-r", "build/app.apk" } };
    if run_cmd(&inst) != 0 {
        // A re-generated debug keystore means a different signing key;
        // uninstall the old package and retry.
        say("Install failed; uninstalling old package and retrying...");
        ProcCmd un = { .args = { adbp, "uninstall", pkg }, .capture = true };
        ignore run_cmd(&un);
        ProcCmd inst2 = { .args = { adbp, "install", "build/app.apk" } };
        if run_cmd(&inst2) != 0 { die("adb install failed"); }
    }
    thread_sleep(1000);
    say("Launching...");
    string act = format("{}/android.app.NativeActivity", pkg);
    defer free(act);
    // `am start` exits 0 even when the activity is not found — the
    // failure is only in its output. Retry while the boot settles.
    bool launched = false;
    for i32 attempt = 0; attempt < 4 && !launched; attempt++ {
        if attempt > 0 { thread_sleep(3000); }
        ProcCmd am = { .args = {
            adbp, "shell", "am", "start", "-n", str_from(act.data, act.len)
        }, .capture = true };
        ProcResult ar = proc_run(&am);
        launched = ar.spawned && ar.exit_code == 0 &&
                   !str_contains(str_from(ar.out.data, ar.out.len), "Error");
        proc_result_free(&ar);
    }
    if !launched { die("am start failed — is the emulator fully booted?"); }
    out(name);
    say(" running on Android");
    return 0;
}

// Dispatch a platform word from the command line. `do_run` is false
// for the `build` verb (package only).
i32 do_platform(str platform, str target, bool do_run, bool open_flag) {
    if target.len == 0 { target = "sokol_cube"; }
    string src = resolve_source(target);
    defer free(src);
    if src.len == 0 {
        out("no such example: ");
        say(target);
        exit(1);
    }
    str srcp = str_from(src.data, src.len);
    str name = path_stem(srcp);

    if str_equal(platform, "android") { return do_android(name, srcp, do_run); }
    when os(macos) {
        if str_equal(platform, "macos-app") { return do_macos_app(name, srcp, do_run, open_flag); }
        if str_equal(platform, "ios-sim") { return do_ios_sim(name, srcp, do_run); }
        if str_equal(platform, "ios") { return do_ios_device(name, srcp, do_run); }
    }
    out(platform);
    die(": requires a macOS host");
    return 1;
}

// --- Verbs -------------------------------------------------------------

i32 do_build_run(str target, bool do_run, bool watch) {
    if str_equal(target, "hotreload") { return run_hotreload(watch); }

    string src = resolve_source(target);
    defer free(src);
    if src.len == 0 {
        out("no such example: ");
        say(target);
        say("");
        list_examples();
        exit(1);
    }
    str srcp = str_from(src.data, src.len);
    str stem = path_stem(srcp);

    if str_equal(stem, "shim_demo") { build_shim_object(); }

    string exe = join_named("build", stem, EXE_SUFFIX);
    defer free(exe);
    str exep = str_from(exe.data, exe.len);
    out("Compiling ");
    say(stem);
    ProcCmd c = { .args = { g_cc, srcp, "-o", exep } };
    if run_cmd(&c) != 0 || !path_exists(exep) { die("minc compile failed"); }
    out("Built ");
    say(exep);
    if do_run {
        ProcCmd run = { .args = { exep } };
        return run_cmd(&run);
    }
    return 0;
}

i32 do_wasm(str target, bool no_run) {
    if target.len == 0 {
        say("Usage: minc wasm <example>");
        say("  Any example that uses sokol_app for windowing.");
        say("  Verified: sokol_cube, sokol_texcube, sokol_mandelbrot,");
        say("            sphere_physics, raytracer, missile");
        exit(1);
    }
    str name = resolve_alias(target);
    if str_equal(name, "sokol_compute") || str_equal(name, "sokol_compute_rw") ||
       str_equal(name, "sokol_particles_compute") {
        die("compute-shader examples are not supported on wasm (WebGL2 has no compute)");
    }
    string src = resolve_source(name);
    defer free(src);
    if src.len == 0 {
        out("no such example: ");
        say(target);
        exit(1);
    }
    out("Building + serving ");
    out(path_stem(str_from(src.data, src.len)));
    say(" for the web (wasm)...");
    ProcCmd c = { .args = {
        g_cc, "run", "--target", "wasm", str_from(src.data, src.len)
    } };
    if no_run { proc_arg(&c, "--no-browser"); }
    return run_cmd(&c);
}

i32 main() {
    i32 argc = get_argc();
    str verb = "run";
    str platform = "";
    str target = "";
    bool no_run = false;
    bool open_flag = false;
    bool watch = false;

    for i32 i = 1; i < argc; i++ {
        str a = str_from_cstr(get_arg(i));
        if str_equal(a, "--no-run") { no_run = true; }
        else if str_equal(a, "--open") { open_flag = true; }
        else if str_equal(a, "watch") { watch = true; }
        else if i == 1 {
            // A .mc path in the verb slot means "run this".
            if str_ends_with(a, ".mc") { target = a; }
            else { verb = a; }
        } else if platform.len == 0 && target.len == 0 &&
                  (str_equal(a, "ios") || str_equal(a, "ios-sim") ||
                   str_equal(a, "android") || str_equal(a, "macos-app")) {
            platform = a;
        } else if target.len == 0 { target = a; }
    }

    if str_equal(verb, "clean") {
        ignore dir_remove("build");
        say("clean.");
        return 0;
    }
    if str_equal(verb, "test") {
        say("no tests in this project");
        return 0;
    }

    string minc = find_minc();
    defer free(minc);
    if minc.len == 0 {
        say("");
        say("minc compiler not found.");
        say("Install it:  https://minc.dev  (or set MINC, see install_minc.md)");
        die("See README.md (Quickstart).");
    }
    g_cc = str_from(minc.data, minc.len);

    if !path_exists("hello.mc") {
        die("run this from the minc-samples folder (hello.mc not found)");
    }

    ignore dir_create("build");

    if str_equal(verb, "wasm") { return do_wasm(target, no_run); }
    if str_equal(verb, "bench") { return do_bench(target); }

    bool is_run = str_equal(verb, "run");
    if !is_run && !str_equal(verb, "build") {
        list_examples();
        return 1;
    }

    if platform.len > 0 {
        return do_platform(platform, target, is_run && !no_run, open_flag);
    }

    if target.len == 0 {
        list_examples();
        return 0;
    }
    return do_build_run(target, is_run && !no_run, watch);
}
