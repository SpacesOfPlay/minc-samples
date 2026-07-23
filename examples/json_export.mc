// Write a JSON document with numbers that round-trip exactly, using
// lib/format_f64 and lib/format_f32. Each value prints as the shortest
// decimal that reads back as the same f64 or f32.
//
//   minc json_export.mc -o json_export.exe
//   ./json_export.exe > bodies.json

import format_f64;
import format_f32;
import str;

// --- a small pretty-printing JSON writer over str_buf -----------------
//

struct Json {
    str_buf sb;
    i32 depth;
    bool after_key;    // the next value follows a key — skip the element prefix
    bool[64] first;    // per depth: still empty (no element written yet)
}

void json_init(Json* j) {
    str_buf_init(&j.sb);
    j.depth = 0;
    j.after_key = false;
    j.first[0] = true;
}

void json_indent(Json* j) {
    str_buf_add_byte(&j.sb, '\n');
    for i32 i = 0; i < j.depth; i = i + 1 {
        str_buf_add(&j.sb, "  ");
    }
}

// Comma + newline + indent before an array element or object member.
void json_before_item(Json* j) {
    if j.depth == 0 { j.first[0] = false; return; }
    if !j.first[j.depth] { str_buf_add_byte(&j.sb, ','); }
    j.first[j.depth] = false;
    json_indent(j);
}

// Every value writer starts here. A value right after a key reuses the
// key's prefix; otherwise it is an array element and gets its own.
void json_value_prefix(Json* j) {
    if j.after_key { j.after_key = false; return; }
    json_before_item(j);
}

void json_key(Json* j, str name) {
    json_before_item(j);
    str_buf_add_byte(&j.sb, '"');
    str_buf_add(&j.sb, name);
    str_buf_add_byte(&j.sb, '"');
    str_buf_add(&j.sb, ": ");
    j.after_key = true;
}

void json_begin_obj(Json* j) {
    json_value_prefix(j);
    str_buf_add_byte(&j.sb, '{');
    j.depth = j.depth + 1;
    j.first[j.depth] = true;
}

void json_end_obj(Json* j) {
    bool empty = j.first[j.depth];
    j.depth = j.depth - 1;
    if !empty { json_indent(j); }
    str_buf_add_byte(&j.sb, '}');
}

void json_begin_arr(Json* j) {
    json_value_prefix(j);
    str_buf_add_byte(&j.sb, '[');
    j.depth = j.depth + 1;
    j.first[j.depth] = true;
}

void json_end_arr(Json* j) {
    bool empty = j.first[j.depth];
    j.depth = j.depth - 1;
    if !empty { json_indent(j); }
    str_buf_add_byte(&j.sb, ']');
}

void json_str(Json* j, str s) {
    json_value_prefix(j);
    str_buf_add_byte(&j.sb, '"');
    for i32 i = 0; i < s.len; i = i + 1 {
        u8 c = *(s.data + i);
        if c == '"' || c == '\\' { str_buf_add_byte(&j.sb, '\\'); }
        str_buf_add_byte(&j.sb, c);
    }
    str_buf_add_byte(&j.sb, '"');
}

void json_int(Json* j, i64 v) {
    json_value_prefix(j);
    string s = format("{}", v);    // {} is exact for integers
    str_buf_add(&j.sb, s);
    free(s);
}

void json_f64(Json* j, f64 v) {
    json_value_prefix(j);
    string s = format_f64(v);
    str_buf_add(&j.sb, s);
    free(s);
}

void json_f32(Json* j, f32 v) {
    json_value_prefix(j);
    string s = format_f32(v);
    str_buf_add(&j.sb, s);
    free(s);
}

void json_bool(Json* j, bool b) {
    json_value_prefix(j);
    if b { str_buf_add(&j.sb, "true"); } else { str_buf_add(&j.sb, "false"); }
}

// --- the data ---------------------------------------------------------

// f64 for masses/radii/gravity (large values land in scientific form),
// f32 for albedo (~3 significant digits is all the source data has).
void emit_body(Json* j, str name, f64 mass_kg, f64 radius_km,
               f64 gravity, f32 albedo, i64 moons, bool rings) {
    json_begin_obj(j);
    json_key(j, "name");                 json_str(j, name);
    json_key(j, "mass_kg");              json_f64(j, mass_kg);
    json_key(j, "mean_radius_km");       json_f64(j, radius_km);
    json_key(j, "surface_gravity_ms2");  json_f64(j, gravity);
    json_key(j, "albedo");               json_f32(j, albedo);
    json_key(j, "moons");                json_int(j, moons);
    json_key(j, "has_rings");            json_bool(j, rings);
    json_end_obj(j);
}

i32 main() {
    Json j;
    json_init(&j);

    json_begin_obj(&j);
    json_key(&j, "generator");  json_str(&j, "minc format_f64 / format_f32");
    json_key(&j, "round_trip"); json_bool(&j, true);
    json_key(&j, "bodies");

    json_begin_arr(&j);
    emit_body(&j, "Mercury", 3.3011e23, 2439.7,  3.7,     0.142f, 0,   false);
    emit_body(&j, "Earth",   5.972e24,  6371.0,  9.80665, 0.306f, 1,   false);
    emit_body(&j, "Jupiter", 1.8982e27, 69911.0, 24.79,   0.503f, 95,  true);
    emit_body(&j, "Saturn",  5.6834e26, 58232.0, 10.44,   0.342f, 146, true);
    json_end_arr(&j);

    json_end_obj(&j);
    str_buf_add_byte(&j.sb, '\n');

    str out = str_buf_to_str(&j.sb);
    print("{}", out);
    str_buf_free(&j.sb);
    return 0;
}
