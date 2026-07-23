// web_server.mc — minimal HTTP/1.0 file server.
// Serves files from a configurable directory (default ./wwwroot) on
// a configurable port (default 8080). GET only, no concurrency.
// `/` falls back to a built-in page when the root has no index.html,
// so the example runs with no files present.
//
// Binds to the loopback interface (127.0.0.1) only. This keeps
// the listener invisible to LAN/external traffic and avoids the
// Windows Firewall prompt on first run. For a LAN-visible server,
// swap `net_listen_tcp_loopback` for `net_listen_tcp` below.
//
// Usage: web_server [--port <n>] [--root <dir>]

import net;
import file;
import str;

const i32 DEFAULT_PORT = 8080;
const i32 REQ_BUF_SIZE = 4096;

i32 g_port = DEFAULT_PORT;
str g_root = "wwwroot";

struct RequestLine {
    str method;
    str path;
}

bool parse_request_line(str line, RequestLine* out) {
    i32 sp1 = str_find_byte(line, 32);
    if sp1 < 0 { return false; }
    str rest = str_slice(line, sp1 + 1, line.len);
    i32 sp2 = str_find_byte(rest, 32);
    if sp2 < 0 { return false; }
    out.method = str_slice(line, 0, sp1);
    out.path = str_slice(rest, 0, sp2);
    return true;
}

// Reject anything that could escape wwwroot. ".." is the obvious one;
// "//" prefix is rejected because some clients/proxies treat it as a
// protocol-relative URL (//host/path) which would change semantics
// before we get to map it to disk.
bool path_is_safe(str path) {
    if path.len < 1 || path.data[0] != 47 { return false; }
    if path.len >= 2 && path.data[1] == 47 { return false; }
    for i32 i = 0; i < path.len - 1; i++ {
        if path.data[i] == 46 && path.data[i + 1] == 46 { return false; }
    }
    return true;
}

string url_to_filepath(str path) {
    i32 total = g_root.len + path.len;
    u8* buf = alloc<u8>(total + 1);
    memcpy(buf, g_root.data, g_root.len);
    memcpy(buf + g_root.len, path.data, path.len);
    buf[total] = 0;
    string s;
    s.data = buf;
    s.len = total;
    return s;
}

str content_type_for(str path) {
    i32 dot = -1;
    for i32 i = path.len - 1; i >= 0; i-- {
        if path.data[i] == 46 { dot = i; break; }
        if path.data[i] == 47 { break; }
    }
    if dot < 0 { return "application/octet-stream"; }
    str ext = str_slice(path, dot, path.len);
    if str_equal(ext, ".html") { return "text/html; charset=utf-8"; }
    if str_equal(ext, ".htm")  { return "text/html; charset=utf-8"; }
    if str_equal(ext, ".css")  { return "text/css; charset=utf-8"; }
    if str_equal(ext, ".js")   { return "application/javascript; charset=utf-8"; }
    if str_equal(ext, ".json") { return "application/json"; }
    if str_equal(ext, ".txt")  { return "text/plain; charset=utf-8"; }
    if str_equal(ext, ".png")  { return "image/png"; }
    if str_equal(ext, ".jpg")  { return "image/jpeg"; }
    if str_equal(ext, ".jpeg") { return "image/jpeg"; }
    if str_equal(ext, ".gif")  { return "image/gif"; }
    if str_equal(ext, ".svg")  { return "image/svg+xml"; }
    if str_equal(ext, ".ico")  { return "image/x-icon"; }
    if str_equal(ext, ".wasm") { return "application/wasm"; }
    return "application/octet-stream";
}

bool send_response(Socket c, str status, str content_type, str body) {
    string header = format(
        "HTTP/1.0 {}\r\nContent-Type: {}\r\nContent-Length: {}\r\nConnection: close\r\nServer: minc/web_server\r\n\r\n",
        status, content_type, body.len);
    defer free(header);
    if !net_send_all(c, header.data, header.len) { return false; }
    if body.len > 0 && !net_send_all(c, body.data, body.len) { return false; }
    return true;
}

void handle_connection(Socket c) {
    u8[REQ_BUF_SIZE] buf;
    i32 n = net_recv(c, &buf[0], REQ_BUF_SIZE);
    if n <= 0 { return; }
    str req = str_from(&buf[0], n);

    i32 line_end = str_find(req, "\r\n");
    if line_end < 0 {
        send_response(c, "400 Bad Request", "text/plain; charset=utf-8", "Bad Request\n");
        return;
    }
    str line = str_slice(req, 0, line_end);

    RequestLine rl;
    if !parse_request_line(line, &rl) {
        send_response(c, "400 Bad Request", "text/plain; charset=utf-8", "Bad Request\n");
        return;
    }

    str path = rl.path;
    i32 q = str_find_byte(path, 63);
    if q >= 0 { path = str_slice(path, 0, q); }

    if !str_equal(rl.method, "GET") {
        send_response(c, "405 Method Not Allowed", "text/plain; charset=utf-8",
                      "Only GET is supported\n");
        return;
    }

    // /__shutdown — exit cleanly. Loopback-only bind keeps this safe;
    // used by the VS Code extension's "Stop WASM server" command and
    // when auto-cleaning orphan servers from prior runs.
    if str_equal(path, "/__shutdown") {
        send_response(c, "200 OK", "text/plain; charset=utf-8", "shutting down\n");
        net_close(c);
        net_shutdown();
        exit(0);
    }

    if !path_is_safe(path) {
        send_response(c, "400 Bad Request", "text/plain; charset=utf-8", "Invalid path\n");
        return;
    }

    str eff_path = path;
    if path.len == 1 { eff_path = "/index.html"; }

    string fpath = url_to_filepath(eff_path);
    defer free(fpath);

    FileData fd = file_read(fpath);
    if fd.data == null {
        // No file. At the site root, serve a built-in welcome page so the
        // example works with no wwwroot present; otherwise 404.
        if path.len == 1 {
            print("  GET / -> 200 (built-in welcome page)\n");
            send_response(c, "200 OK", "text/html; charset=utf-8",
                "<!doctype html>\n"
                "<meta charset='utf-8'>\n"
                "<title>minc web_server</title>\n"
                "<h1>minc web_server is running</h1>\n"
                "<p>Served by <code>web_server.mc</code> over <code>lib/net.mc</code> on port 8080.</p>\n"
                "<p>No <code>wwwroot/index.html</code> found, so this built-in page is shown. "
                "Create a <code>wwwroot</code> folder next to the binary and add files to serve.</p>\n");
            return;
        }
        send_response(c, "404 Not Found", "text/plain; charset=utf-8", "Not Found\n");
        return;
    }
    defer free(fd.data);

    str body = str_from(fd.data, fd.len);
    print("  GET {} -> 200 ({} bytes)\n", path, body.len);
    send_response(c, "200 OK", content_type_for(eff_path), body);
}

// Parse a decimal integer from a null-terminated u8* arg.
// Returns -1 if the string contains anything other than digits.
i32 parse_decimal(u8* s) {
    if *s == 0 { return 0 - 1; }
    i32 n = 0;
    while *s != 0 {
        u8 c = *s;
        if c < 48 || c > 57 { return 0 - 1; }
        n = n * 10 + cast(i32, c) - 48;
        s = s + 1;
    }
    return n;
}

i32 main() {
    // Parse --port <n> and --root <dir>.
    i32 argc = get_argc();
    i32 i = 1;
    while i < argc {
        str a = str_from_cstr(get_arg(i));
        if str_equal(a, "--port") && i + 1 < argc {
            i32 p = parse_decimal(get_arg(i + 1));
            if p <= 0 || p > 65535 {
                print("error: --port expects 1..65535\n");
                return 1;
            }
            g_port = p;
            i = i + 2;
        } else if str_equal(a, "--root") && i + 1 < argc {
            g_root = str_from_cstr(get_arg(i + 1));
            i = i + 2;
        } else {
            print("usage: web_server [--port <n>] [--root <dir>]\n");
            return 1;
        }
    }

    if !net_init() {
        print("net_init failed\n");
        return 1;
    }
    Socket srv = net_listen_tcp_loopback(cast(u16, g_port));
    if !srv.valid {
        print("listen on port {} failed (already in use?)\n", g_port);
        net_shutdown();
        return 1;
    }
    print("web_server listening on http://localhost:{} (Ctrl+C to quit)\n", g_port);
    print("serving files from {}\n", g_root);

    while true {
        Socket c = net_accept(srv);
        if !c.valid { continue; }
        handle_connection(c);
        net_close(c);
    }

    net_close(srv);
    net_shutdown();
    return 0;
}
