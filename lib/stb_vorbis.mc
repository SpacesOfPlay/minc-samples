// =====================================================================
// Derived from stb_vorbis.c v1.22 (http://nothings.org/stb_vorbis/)
// by Sean Barrett - public domain (dual-licensed MIT).
//
// Altered source: transpiled to minc.
// =====================================================================
// stb_vorbis - Ogg Vorbis decoder, memory API only (no file I/O in the
// module; loading is the caller's). Decode a whole file:
//
//   import stb_vorbis;
//
//   i32 channels; i32 rate; i16* pcm;
//   i32 frames = stb_vorbis_decode_memory(data, len, &channels, &rate, &pcm);
//   // frames * channels interleaved s16 samples in pcm; free(pcm) when done.
//
// Or stream: stb_vorbis_open_memory + stb_vorbis_get_frame_short_interleaved
// / stb_vorbis_get_samples_float_interleaved, stb_vorbis_seek,
// stb_vorbis_stream_length_in_samples, stb_vorbis_close.
// examples/audio_vorbis.mc plays a file through sokol_audio.

import ext_libc;
// transminc: C stdlib constants referenced by source
const u32 UINT_MAX = 4294967295;

////////   ERROR CODES
enum STBVorbisError {
    VORBIS__no_error = 0,
    VORBIS_need_more_data = 1,
    VORBIS_invalid_api_mixing = 2,
    VORBIS_outofmem = 3,
    VORBIS_feature_not_supported = 4,
    VORBIS_too_many_channels = 5,
    VORBIS_file_open_failure = 6,
    VORBIS_seek_without_length = 7,
    VORBIS_unexpected_eof = 10,
    VORBIS_seek_invalid = 11,
    VORBIS_invalid_setup = 20,
    VORBIS_invalid_stream = 21,
    VORBIS_missing_capture_pattern = 30,
    VORBIS_invalid_stream_structure_version = 31,
    VORBIS_continued_packet_flag_invalid = 32,
    VORBIS_incorrect_stream_serial_number = 33,
    VORBIS_invalid_first_page = 34,
    VORBIS_bad_packet_type = 35,
    VORBIS_cant_find_last_page = 36,
    VORBIS_seek_failed = 37,
    VORBIS_ogg_skeleton_not_supported = 38,
}

enum __enum_VORBIS_packet_id {
    VORBIS_packet_id = 1,
    VORBIS_packet_comment = 3,
    VORBIS_packet_setup = 5,
}

// find definition of alloca if it's not in stdlib.h:
type uint8 = u8;
type int8 = i8;
type uint16 = u16;
type int16 = i16;
type uint32 = u32;
type int32 = i32;
type codetype = f32;
type vorb = stb_vorbis;
when !(defined(STB_VORBIS_NO_DEFER_FLOOR)) {
    type YTYPE = int16;
} else {
    type YTYPE = i32;
}
when !(defined(STB_VORBIS_NO_PULLDATA_API)) {
    when !(defined(STB_VORBIS_NO_INTEGER_CONVERSION)) {
        type stb_vorbis_float_size_test = u8[1];
    }
}
// Ogg Vorbis audio decoder - v1.22 - public domain
// http://nothings.org/stb_vorbis/
//
// Original version written by Sean Barrett in 2007.
//
// Originally sponsored by RAD Game Tools. Seeking implementation
// sponsored by Phillip Bennefall, Marc Andersen, Aaron Baker,
// Elias Software, Aras Pranckevicius, and Sean Barrett.
//
// LICENSE
//
//   See end of file for license information.
//
// Limitations:
//
//   - floor 0 not supported (used in old ogg vorbis files pre-2004)
//   - lossless sample-truncation at beginning ignored
//   - cannot concatenate multiple vorbis streams
//   - sample positions are 32-bit, limiting seekable 192Khz
//       files to around 6 hours (Ogg supports 64-bit)
//
// Feature contributors:
//    Dougall Johnson (sample-exact seeking)
//
// Bugfix/warning contributors:
//    Terje Mathisen     Niklas Frykholm     Andy Hill
//    Casey Muratori     John Bolton         Gargaj
//    Laurent Gomila     Marc LeBlanc        Ronny Chevalier
//    Bernhard Wodo      Evan Balster        github:alxprd
//    Tom Beaumont       Ingo Leitgeb        Nicolas Guillemot
//    Phillip Bennefall  Rohit               Thiago Goulart
//    github:manxorist   Saga Musix          github:infatum
//    Timur Gagiev       Maxwell Koo         Peter Waller
//    github:audinowho   Dougall Johnson     David Reid
//    github:Clownacy    Pedro J. Estebanez  Remi Verschelde
//    AnthoFoxo          github:morlat       Gabriel Ravier
//
// Partial history:
//    1.22    - 2021-07-11 - various small fixes
//    1.21    - 2021-07-02 - fix bug for files with no comments
//    1.20    - 2020-07-11 - several small fixes
//    1.19    - 2020-02-05 - warnings
//    1.18    - 2020-02-02 - fix seek bugs; parse header comments; misc warnings etc.
//    1.17    - 2019-07-08 - fix CVE-2019-13217..CVE-2019-13223 (by ForAllSecure)
//    1.16    - 2019-03-04 - fix warnings
//    1.15    - 2019-02-07 - explicit failure if Ogg Skeleton data is found
//    1.14    - 2018-02-11 - delete bogus dealloca usage
//    1.13    - 2018-01-29 - fix truncation of last frame (hopefully)
//    1.12    - 2017-11-21 - limit residue begin/end to blocksize/2 to avoid large temp allocs in bad/corrupt files
//    1.11    - 2017-07-23 - fix MinGW compilation
//    1.10    - 2017-03-03 - more robust seeking; fix negative ilog(); clear error in open_memory
//    1.09    - 2016-04-04 - back out 'truncation of last frame' fix from previous version
//    1.08    - 2016-04-02 - warnings; setup memory leaks; truncation of last frame
//    1.07    - 2015-01-16 - fixes for crashes on invalid files; warning fixes; const
//    1.06    - 2015-08-31 - full, correct support for seeking API (Dougall Johnson)
//                           some crash fixes when out of memory or with corrupt files
//                           fix some inappropriately signed shifts
//    1.05    - 2015-04-19 - don't define __forceinline if it's redundant
//    1.04    - 2014-08-27 - fix missing const-correct case in API
//    1.03    - 2014-08-07 - warning fixes
//    1.02    - 2014-07-09 - declare qsort comparison as explicitly _cdecl in Windows
//    1.01    - 2014-06-18 - fix stb_vorbis_get_samples_float (interleaved was correct)
//    1.0     - 2014-05-26 - fix memory leaks; fix warnings; fix bugs in >2-channel;
//                           (API change) report sample rate for decode-full-file funcs
//
// See end of file for full version history.
//////////////////////////////////////////////////////////////////////////////
//
//  HEADER BEGINS HERE
//
///////////   THREAD SAFETY
// Individual stb_vorbis* handles are not thread-safe; you cannot decode from
// them from multiple threads at the same time. However, you can have multiple
// stb_vorbis* handles and decode from them independently in multiple thrads.
///////////   MEMORY ALLOCATION
// normally stb_vorbis uses malloc() to allocate memory at startup,
// and alloca() to allocate temporary memory during a frame on the
// stack. (Memory consumption will depend on the amount of setup
// data in the file and how you set the compile flags for speed
// vs. size. In my test files the maximal-size usage is ~150KB.)
//
// You can modify the wrapper functions in the source (setup_malloc,
// setup_temp_malloc, temp_malloc) to change this behavior, or you
// can use a simpler allocation model: you pass in a buffer from
// which stb_vorbis will allocate _all_ its memory (including the
// temp memory). "open" may fail with a VORBIS_outofmem if you
// do not pass in enough data; there is no way to determine how
// much you do need except to succeed (at which point you can
// query get_info to find the exact amount required. yes I know
// this is lame).
//
// If you pass in a non-NULL buffer of the type below, allocation
// will occur from it as described above. Otherwise just pass NULL
// to use malloc()/alloca()
struct stb_vorbis_alloc {
    u8* alloc_buffer;
    i32 alloc_buffer_length_in_bytes;
}

struct stb_vorbis_info {
    u32 sample_rate;
    i32 channels;
    u32 setup_memory_required;
    u32 setup_temp_memory_required;
    u32 temp_memory_required;
    i32 max_frame_size;
}

struct stb_vorbis_comment {
    u8* vendor;
    i32 comment_list_length;
    u8** comment_list;
}

// @NOTE
//
// Some arrays below are tagged "//varies", which means it's actually
// a variable-sized piece of data, but rather than malloc I assume it's
// small enough it's better to just allocate it all together with the
// main thing
//
// Most of the variables are specified with the smallest size I could pack
// them into. It might give better performance to make them all full-sized
// integers. It should be safe to freely rearrange the structures or change
// the sizes larger--nothing relies on silently truncating etc., nor the
// order of variables.
struct Codebook {
    i32 dimensions;
    i32 entries;
    uint8* codeword_lengths;
    f32 minimum_value;
    f32 delta_value;
    uint8 value_bits;
    uint8 lookup_type;
    uint8 sequence_p;
    uint8 sparse;
    uint32 lookup_values;
    codetype* multiplicands;
    uint32* codewords;
    int16[1 << 10] fast_huffman;
    uint32* sorted_codewords;
    i32* sorted_values;
    i32 sorted_entries;
}

struct Floor0 {
    uint8 order;
    uint16 rate;
    uint16 bark_map_size;
    uint8 amplitude_bits;
    uint8 amplitude_offset;
    uint8 number_of_books;
    uint8[16] book_list;
}

struct Floor1 {
    uint8 partitions;
    uint8[32] partition_class_list;
    uint8[16] class_dimensions;
    uint8[16] class_subclasses;
    uint8[16] class_masterbooks;
    int16:[16][8] subclass_books;
    uint16[31 * 8 + 2] Xlist;
    uint8[31 * 8 + 2] sorted_order;
    uint8:[31 * 8 + 2][2] neighbors;
    uint8 floor1_multiplier;
    uint8 rangebits;
    i32 values;
}

unsafe_union Floor {
    Floor0 floor0;
    Floor1 floor1;
}

struct Residue {
    uint32 begin;
    uint32 end;
    uint32 part_size;
    uint8 classifications;
    uint8 classbook;
    uint8** classdata;
    int16* residue_books;
}

struct MappingChannel {
    uint8 magnitude;
    uint8 angle;
    uint8 mux;
}

struct Mapping {
    uint16 coupling_steps;
    MappingChannel* chan;
    uint8 submaps;
    uint8[15] submap_floor;
    uint8[15] submap_residue;
}

struct Mode {
    uint8 blockflag;
    uint8 mapping;
    uint16 windowtype;
    uint16 transformtype;
}

struct CRCscan {
    uint32 goal_crc;
    i32 bytes_left;
    uint32 crc_so_far;
    i32 bytes_done;
    uint32 sample_loc;
}

struct ProbedPage {
    uint32 page_start;
    uint32 page_end;
    uint32 last_decoded_sample;
}

/* transminc: pushdata API disabled in this build — committed */
struct stb_vorbis {
    u32 sample_rate;
    i32 channels;
    u32 setup_memory_required;
    u32 temp_memory_required;
    u32 setup_temp_memory_required;
    u8* vendor;
    i32 comment_list_length;
    u8** comment_list;
    uint8* stream;
    uint8* stream_start;
    uint8* stream_end;
    uint32 stream_len;
    uint8 push_mode;
    uint32 first_audio_page_offset;
    ProbedPage p_first;
    ProbedPage p_last;
    stb_vorbis_alloc alloc;
    i32 setup_offset;
    i32 temp_offset;
    i32 eof;
    STBVorbisError error;
    i32[2] blocksize;
    i32 blocksize_0;
    i32 blocksize_1;
    i32 codebook_count;
    Codebook* codebooks;
    i32 floor_count;
    uint16[64] floor_types;
    Floor* floor_config;
    i32 residue_count;
    uint16[64] residue_types;
    Residue* residue_config;
    i32 mapping_count;
    Mapping* mapping;
    i32 mode_count;
    Mode[64] mode_config;
    uint32 total_samples;
    f32*[16] channel_buffers;
    f32*[16] outputs;
    f32*[16] previous_window;
    i32 previous_length;
    int16*[16] finalY;
    f32*[16] floor_buffers;
    uint32 current_loc;
    i32 current_loc_valid;
    f32*[2] A;
    f32*[2] B;
    f32*[2] C;
    f32*[2] window;
    uint16*[2] bit_reverse;
    uint32 serial;
    i32 last_page;
    i32 segment_count;
    uint8[255] segments;
    uint8 page_flag;
    uint8 bytes_in_seg;
    uint8 first_decode;
    i32 next_seg;
    i32 last_seg;
    i32 last_seg_which;
    uint32 acc;
    i32 valid_bits;
    i32 packet_bytes;
    i32 end_seg_with_known_loc;
    uint32 known_loc_for_packet;
    i32 discard_samples_deferred;
    uint32 samples_output;
    i32 page_crc_tests;
    i32 channel_buffer_start;
    i32 channel_buffer_end;
}

// this has been repurposed so y is now the original index instead of y
struct stbv__floor_ordering {
    uint16 x;
    uint16 id;
}

unsafe_union float_conv {
    f32 f;
    i32 i;
}

///////////   PUSHDATA API
//////////   PULLING INPUT API
when !(defined(STB_VORBIS_NO_PULLDATA_API)) {
// decode the next frame and return the number of samples. the number of
// channels returned are stored in *channels (which can be NULL--it is always
// the same as the number of channels reported by get_info). *output will
// contain an array of float* buffers, one per channel. These outputs will
// be overwritten on the next call to stb_vorbis_get_frame_*.
//
// You generally should not intermix calls to stb_vorbis_get_frame_*()
// and stb_vorbis_get_samples_*(), since the latter calls the former.
when !(defined(STB_VORBIS_NO_INTEGER_CONVERSION)) {
}
// gets num_samples samples, not necessarily on a frame boundary--this requires
// buffering so you have to supply the buffers. DOES NOT APPLY THE COERCION RULES.
// Returns the number of samples stored per channel; it may be less than requested
// at the end of the file. If there are no more samples in the file, returns 0.
when !(defined(STB_VORBIS_NO_INTEGER_CONVERSION)) {
}
}
//
//  HEADER ENDS HERE
//
//////////////////////////////////////////////////////////////////////////////
// global configuration settings (e.g. set these in the project/makefile),
// or just set them in this file at the top (although ideally the first few
// should be visible when the header file is compiled too, although it's not
// crucial)
// STB_VORBIS_NO_PUSHDATA_API
//     does not compile the code for the various stb_vorbis_*_pushdata()
//     functions
// #define STB_VORBIS_NO_PUSHDATA_API
// STB_VORBIS_NO_PULLDATA_API
//     does not compile the code for the non-pushdata APIs
// #define STB_VORBIS_NO_PULLDATA_API
// STB_VORBIS_NO_STDIO
//     does not compile the code for the APIs that use FILE *s internally
//     or externally (implied by STB_VORBIS_NO_PULLDATA_API)
// #define STB_VORBIS_NO_STDIO
// STB_VORBIS_NO_INTEGER_CONVERSION
//     does not compile the code for converting audio sample data from
//     float to integer (implied by STB_VORBIS_NO_PULLDATA_API)
// #define STB_VORBIS_NO_INTEGER_CONVERSION
// STB_VORBIS_NO_FAST_SCALED_FLOAT
//      does not use a fast float-to-int trick to accelerate float-to-int on
//      most platforms which requires endianness be defined correctly.
//#define STB_VORBIS_NO_FAST_SCALED_FLOAT
// STB_VORBIS_MAX_CHANNELS [number]
//     globally define this to the maximum number of channels you need.
//     The spec does not put a restriction on channels except that
//     the count is stored in a byte, so 255 is the hard limit.
//     Reducing this saves about 16 bytes per value, so using 16 saves
//     (255-16)*16 or around 4KB. Plus anything other memory usage
//     I forgot to account for. Can probably go as low as 8 (7.1 audio),
//     6 (5.1 audio), or 2 (stereo only).
// STB_VORBIS_PUSHDATA_CRC_COUNT [number]
//     after a flush_pushdata(), stb_vorbis begins scanning for the
//     next valid page, without backtracking. when it finds something
//     that looks like a page, it streams through it and verifies its
//     CRC32. Should that validation fail, it keeps scanning. But it's
//     possible that _while_ streaming through to check the CRC32 of
//     one candidate page, it sees another candidate page. This #define
//     determines how many "overlapping" candidate pages it can search
//     at once. Note that "real" pages are typically ~4KB to ~8KB, whereas
//     garbage pages could be as big as 64KB, but probably average ~16KB.
//     So don't hose ourselves by scanning an apparent 64KB page and
//     missing a ton of real ones in the interim; so minimum of 2
// STB_VORBIS_FAST_HUFFMAN_LENGTH [number]
//     sets the log size of the huffman-acceleration table.  Maximum
//     supported value is 24. with larger numbers, more decodings are O(1),
//     but the table size is larger so worse cache missing, so you'll have
//     to probe (and try multiple ogg vorbis files) to find the sweet spot.
// STB_VORBIS_FAST_BINARY_LENGTH [number]
//     sets the log size of the binary-search acceleration table. this
//     is used in similar fashion to the fast-huffman size to set initial
//     parameters for the binary search
// STB_VORBIS_FAST_HUFFMAN_INT
//     The fast huffman tables are much more efficient if they can be
//     stored as 16-bit results instead of 32-bit results. This restricts
//     the codebooks to having only 65535 possible outcomes, though.
//     (At least, accelerated by the huffman table.)
// STB_VORBIS_NO_HUFFMAN_BINARY_SEARCH
//     If the 'fast huffman' search doesn't succeed, then stb_vorbis falls
//     back on binary searching for the correct one. This requires storing
//     extra tables with the huffman codes in sorted order. Defining this
//     symbol trades off space for speed by forcing a linear search in the
//     non-fast case, except for "sparse" codebooks.
// #define STB_VORBIS_NO_HUFFMAN_BINARY_SEARCH
// STB_VORBIS_DIVIDES_IN_RESIDUE
//     stb_vorbis precomputes the result of the scalar residue decoding
//     that would otherwise require a divide per chunk. you can trade off
//     space for time by defining this symbol.
// #define STB_VORBIS_DIVIDES_IN_RESIDUE
// STB_VORBIS_DIVIDES_IN_CODEBOOK
//     vorbis VQ codebooks can be encoded two ways: with every case explicitly
//     stored, or with all elements being chosen from a small range of values,
//     and all values possible in all elements. By default, stb_vorbis expands
//     this latter kind out to look like the former kind for ease of decoding,
//     because otherwise an integer divide-per-vector-element is required to
//     unpack the index. If you define STB_VORBIS_DIVIDES_IN_CODEBOOK, you can
//     trade off storage for speed.
//#define STB_VORBIS_DIVIDES_IN_CODEBOOK
// STB_VORBIS_DIVIDE_TABLE
//     this replaces small integer divides in the floor decode loop with
//     table lookups. made less than 1% difference, so disabled by default.
// STB_VORBIS_NO_INLINE_DECODE
//     disables the inlining of the scalar codebook fast-huffman decode.
//     might save a little codespace; useful for debugging
// #define STB_VORBIS_NO_INLINE_DECODE
// STB_VORBIS_NO_DEFER_FLOOR
//     Normally we only decode the floor without synthesizing the actual
//     full curve. We can instead synthesize the curve immediately. This
//     requires more memory and is very likely slower, so I don't think
//     you'd ever want to do it except for debugging.
// #define STB_VORBIS_NO_DEFER_FLOOR
//////////////////////////////////////////////////////////////////////////////
when !(defined(STB_VORBIS_NO_INTEGER_CONVERSION)) {
}

private {
i32 error(vorb* f, STBVorbisError e) {
    f.error = e;
    if !f.eof && e != VORBIS_need_more_data {
        f.error = e;
    }
    return 0;
}

// these functions are used for allocating temporary memory
// while decoding. if you can afford the stack space, use
// alloca(); otherwise, provide a temp buffer and it will
// allocate out of those.
/* transminc: no alloca in minc — temp allocs go through setup_temp_malloc
   (malloc fallback); temp_free releases the malloc path */
// given a sufficiently large block of memory, make an array of pointers to subblocks of it
void* make_block_array(void* mem, i32 count, i32 size) {
    i32 i;
    var p = cast(void**, mem);
    var q = cast(u8*, p + count);
    for i = 0; i < count; ++i {
        p[i] = q;
        q += size;
    }
    return p;
}

void* setup_malloc(vorb* f, i32 sz) {
    sz = sz + 7 & ~7;
    f.setup_memory_required += cast(u32, sz);
    if f.alloc.alloc_buffer != null {
        void* p = f.alloc.alloc_buffer + f.setup_offset;
        if f.setup_offset + sz > f.temp_offset {
            return null;
        }
        f.setup_offset += sz;
        return p;
    }
    return sz != 0 ? alloc(cast(i64, sz)) : null;
}

void setup_free(vorb* f, void* p) {
    if f.alloc.alloc_buffer != null {
        return;
    }
    free(p);
}

void* setup_temp_malloc(vorb* f, i32 sz) {
    sz = sz + 7 & ~7;
    if f.alloc.alloc_buffer != null {
        if f.temp_offset - sz < f.setup_offset {
            return null;
        }
        f.temp_offset -= sz;
        return f.alloc.alloc_buffer + f.temp_offset;
    }
    return alloc(cast(i64, sz));
}

void setup_temp_free(vorb* f, void* p, i32 sz) {
    if f.alloc.alloc_buffer != null {
        f.temp_offset += sz + 7 & ~7;
        return;
    }
    free(p);
}
uint32[256] crc_table;

void crc32_init() {
    i32 i;
    i32 j;
    uint32 s;
    for i = 0; i < 256; i++ {
        {
            s = cast(uint32, i) << 24;
            for j = 0; j < 8; ++j {
                s = s << 1 ^ cast(u32, s >= cast(u32, 1 << 31) ? 0x04c11db7 : 0);
            }
        }
        crc_table[i] = s;
    }
}

uint32 crc32_update(uint32 crc, uint8 byte) {
    return crc << 8 ^ crc_table[byte ^ crc >> 24];
}

// used in setup, and for huffman that doesn't go fast path
u32 bit_reverse(u32 n) {
    n = (n & 0xAAAAAAAA) >> 1 | (n & 0x55555555) << 1;
    n = (n & 0xCCCCCCCC) >> 2 | (n & 0x33333333) << 2;
    n = (n & 0xF0F0F0F0) >> 4 | (n & 0x0F0F0F0F) << 4;
    n = (n & 0xFF00FF00) >> 8 | (n & 0x00FF00FF) << 8;
    return n >> 16 | n << 16;
}

f32 square(f32 x) {
    return x * x;
}

// this is a weird definition of log2() for which log2(1) = 1, log2(2) = 2, log2(4) = 3
// as required by the specification. fast(?) implementation from stb.h
// @OPTIMIZE: called multiple times per-packet with "constants"; move to setup
i32 ilog(int32 n) {
    if n < 0 {
        return 0;
    }
    if n < 1 << 14 {
        if n < 1 << 4 {
            return 0 + ilog__log2_4[n];
        } else if n < 1 << 9 {
            return 5 + ilog__log2_4[n >> 5];
        } else {
            return 10 + ilog__log2_4[n >> 10];
        }
    } else if n < 1 << 24 {
        if n < 1 << 19 {
            return 15 + ilog__log2_4[n >> 15];
        } else {
            return 20 + ilog__log2_4[n >> 20];
        }
    } else if n < 1 << 29 {
        return 25 + ilog__log2_4[n >> 25];
    } else {
        return 30 + ilog__log2_4[n >> 30];
    }
}

// code length assigned to a value with no huffman encoding
/////////////////////// LEAF SETUP FUNCTIONS //////////////////////////
//
// these functions are only called at setup, and only a few times
// per file
f32 float32_unpack(uint32 x) {
    uint32 mantissa = x & 0x1fffff;
    uint32 sign = x & 0x80000000;
    uint32 exp = (x & 0x7fe00000) >> 21;
    f64 res = sign != 0 ? -cast(f64, mantissa) : cast(f64, mantissa);
    return cast(f32, ldexp(cast(f32, res), cast(i32, exp) - 788));
}

// zlib & jpeg huffman tables assume that the output symbols
// can either be arbitrarily arranged, or have monotonically
// increasing frequencies--they rely on the lengths being sorted;
// this makes for a very simple generation algorithm.
// vorbis allows a huffman table with non-sorted lengths. This
// requires a more sophisticated construction, since symbols in
// order do not map to huffman codes "in order".
void add_entry(Codebook* c, uint32 huff_code, i32 symbol, i32 count, i32 len, uint32* values) {
    if c.sparse == 0 {
        c.codewords[symbol] = huff_code;
    } else {
        c.codewords[count] = huff_code;
        c.codeword_lengths[count] = cast(uint8, len);
        values[count] = cast(uint32, symbol);
    }
}

i32 compute_codewords(Codebook* c, uint8* len, i32 n, uint32* values) {
    i32 i;
    i32 k;
    i32 m = 0;
    uint32[32] available;
    for k = 0; k < n; ++k {
        if len[k] < 255 {
            break;
        }
    }
    if k == n {
        assert(c.sorted_entries == 0);
        return 1;
    }
    assert(len[k] < 32);
    add_entry(c, 0, k, m++, cast(i32, len[k]), values);
    for i = 1; i <= cast(i32, len[k]); ++i {
        available[i] = cast(uint32, 1 << 32 - i);
    }
    for i = k + 1; i < n; ++i {
        uint32 res;
        var z = cast(i32, len[i]);
        i32 y;
        if z == 255 {
            continue;
        }
        assert(z < 32);
        while z > 0 && !available[z] {
            --z;
        }
        if z == 0 {
            return 0;
        }
        res = available[z];
        available[z] = 0;
        add_entry(c, bit_reverse(res), i, m++, cast(i32, len[i]), values);
        if z != cast(i32, len[i]) {
            for y = cast(i32, len[i]); y > z; --y {
                assert(available[y] == 0);
                available[y] = res + cast(u32, 1 << 32 - y);
            }
        }
    }
    return 1;
}

// accelerated huffman table allows fast O(1) match of all symbols
// of length <= STB_VORBIS_FAST_HUFFMAN_LENGTH
void compute_accelerated_huffman(Codebook* c) {
    i32 i;
    i32 len;
    for i = 0; i < 1 << 10; ++i {
        c.fast_huffman[i] = cast(int16, -1);
    }
    len = c.sparse != 0 ? c.sorted_entries : c.entries;
    when defined(STB_VORBIS_FAST_HUFFMAN_SHORT) {
        if len > 32767 {
            len = 32767;
        }
    }
    for i = 0; i < len; ++i {
        if c.codeword_lengths[i] <= 10 {
            uint32 z = c.sparse != 0 ? bit_reverse(c.sorted_codewords[i]) : c.codewords[i];
            while z < cast(u32, 1 << 10) {
                c.fast_huffman[z] = cast(int16, i);
                z += cast(u32, 1 << cast(i32, c.codeword_lengths[i]));
            }
        }
    }
}

i32 uint32_compare(void* p, void* q) {
    uint32 x = *cast(uint32*, p);
    uint32 y = *cast(uint32*, q);
    return x < y ? -1 : x > y;
}

i32 include_in_sort(Codebook* c, uint8 len) {
    if c.sparse != 0 {
        assert(len != 255);
        return 1;
    }
    if len == 255 {
        return 0;
    }
    if len > 10 {
        return 1;
    }
    return 0;
}

// if the fast table above doesn't work, we want to binary
// search them... need to reverse the bits
void compute_sorted_huffman(Codebook* c, uint8* lengths, uint32* values) {
    i32 i;
    i32 len;
    if c.sparse == 0 {
        i32 k = 0;
        for i = 0; i < c.entries; ++i {
            if include_in_sort(c, lengths[i]) != 0 {
                c.sorted_codewords[k++] = bit_reverse(c.codewords[i]);
            }
        }
        assert(k == c.sorted_entries);
    } else {
        for i = 0; i < c.sorted_entries; ++i {
            c.sorted_codewords[i] = bit_reverse(c.codewords[i]);
        }
    }
    qsort(c.sorted_codewords, c.sorted_entries, sizeof(c.sorted_codewords[0]), uint32_compare);
    c.sorted_codewords[c.sorted_entries] = 0xffffffff;
    len = c.sparse != 0 ? c.sorted_entries : c.entries;
    for i = 0; i < len; ++i {
        var huff_len = cast(i32, c.sparse != 0 ? lengths[values[i]] : lengths[i]);
        if include_in_sort(c, cast(uint8, huff_len)) != 0 {
            uint32 code = bit_reverse(c.codewords[i]);
            i32 x = 0;
            i32 n = c.sorted_entries;
            while n > 1 {
                i32 m = x + (n >> 1);
                if c.sorted_codewords[m] <= code {
                    x = m;
                    n -= n >> 1;
                } else {
                    n >>= 1;
                }
            }
            assert(c.sorted_codewords[x] == code);
            if c.sparse != 0 {
                c.sorted_values[x] = cast(i32, values[i]);
                c.codeword_lengths[x] = cast(uint8, huff_len);
            } else {
                c.sorted_values[x] = i;
            }
        }
    }
}

// only run while parsing the header (3 times)
i32 vorbis_validate(uint8* data) {
    return memcmp(data, vorbis_validate__vorbis, cast(u64, 6)) == 0;
}

// called from setup only, once per code book
// (formula implied by specification)
i32 lookup1_values(i32 entries, i32 dim) {
    var r = cast(i32, floor(exp(cast(f64, cast(f32, log(cast(f64, cast(f32, entries)))) / cast(f32, dim)))));
    if cast(i32, floor(pow(cast(f64, cast(f32, r) + 1.0f), dim))) <= entries {
        ++r;
    }
    if pow(cast(f64, cast(f32, r) + 1.0f), dim) <= cast(f64, entries) {
        return -1;
    }
    if cast(i32, floor(pow(cast(f64, cast(f32, r)), dim))) > entries {
        return -1;
    }
    return r;
}

// called twice per file
void compute_twiddle_factors(i32 n, f32* A, f32* B, f32* C) {
    i32 n4 = n >> 2;
    i32 n8 = n >> 3;
    i32 k;
    i32 k2;
            k2 = 0;
    for k = k2; k < n4; ++k {
        A[k2] = cast(f32, cos(cast(f64, cast(f32, 4 * k) * 3.141592653589793f / cast(f32, n))));
        A[k2 + 1] = cast(f32, -sin(cast(f64, cast(f32, 4 * k) * 3.141592653589793f / cast(f32, n))));
        B[k2] = cast(f32, cos(cast(f64, cast(f32, k2 + 1) * 3.141592653589793f / cast(f32, n) / 2.0f))) * 0.5f;
        B[k2 + 1] = cast(f32, sin(cast(f64, cast(f32, k2 + 1) * 3.141592653589793f / cast(f32, n) / 2.0f))) * 0.5f;
        k2 += 2;
    }
            k2 = 0;
    for k = k2; k < n8; ++k {
        C[k2] = cast(f32, cos(cast(f64, cast(f32, 2 * (k2 + 1)) * 3.141592653589793f / cast(f32, n))));
        C[k2 + 1] = cast(f32, -sin(cast(f64, cast(f32, 2 * (k2 + 1)) * 3.141592653589793f / cast(f32, n))));
        k2 += 2;
    }
}

void compute_window(i32 n, f32* window) {
    i32 n2 = n >> 1;
    i32 i;
    for i = 0; i < n2; ++i {
        window[i] = cast(f32, sin(0.5 * 3.141592653589793f * cast(f64, square(cast(f32, sin((cast(f64, i - 0) + 0.5) / cast(f64, n2) * 0.5 * 3.141592653589793f))))));
    }
}

void compute_bitreverse(i32 n, uint16* rev) {
    i32 ld = ilog(n) - 1;
    i32 i;
    i32 n8 = n >> 3;
    for i = 0; i < n8; ++i {
        rev[i] = cast(uint16, bit_reverse(cast(u32, i)) >> cast(u32, 32 - ld + 3) << 2);
    }
}

i32 init_blocksize(vorb* f, i32 b, i32 n) {
    i32 n2 = n >> 1;
    i32 n4 = n >> 2;
    i32 n8 = n >> 3;
    f.A[b] = cast(f32*, setup_malloc(f, cast(i32, sizeof(f32) * n2)));
    f.B[b] = cast(f32*, setup_malloc(f, cast(i32, sizeof(f32) * n2)));
    f.C[b] = cast(f32*, setup_malloc(f, cast(i32, sizeof(f32) * n4)));
    if !f.A[b] || !f.B[b] || !f.C[b] {
        return error(f, VORBIS_outofmem);
    }
    compute_twiddle_factors(n, f.A[b], f.B[b], f.C[b]);
    f.window[b] = cast(f32*, setup_malloc(f, cast(i32, sizeof(f32) * n2)));
    if f.window[b] == null {
        return error(f, VORBIS_outofmem);
    }
    compute_window(n, f.window[b]);
    f.bit_reverse[b] = cast(uint16*, setup_malloc(f, cast(i32, sizeof(uint16) * n8)));
    if f.bit_reverse[b] == null {
        return error(f, VORBIS_outofmem);
    }
    compute_bitreverse(n, f.bit_reverse[b]);
    return 1;
}

void neighbors(uint16* x, i32 n, i32* plow, i32* phigh) {
    i32 low = -1;
    i32 high = 65536;
    i32 i;
    for i = 0; i < n; ++i {
        if cast(i32, x[i]) > low && x[i] < x[n] {
            *plow = i;
            low = cast(i32, x[i]);
        }
        if cast(i32, x[i]) < high && x[i] > x[n] {
            *phigh = i;
            high = cast(i32, x[i]);
        }
    }
}

i32 point_compare(void* p, void* q) {
    var a = cast(stbv__floor_ordering*, p);
    var b = cast(stbv__floor_ordering*, q);
    return a.x < b.x ? -1 : a.x > b.x;
}

//
/////////////////////// END LEAF SETUP FUNCTIONS //////////////////////////
uint8 get8(vorb* z) {
    if 1 != 0 {
        if z.stream >= z.stream_end {
            z.eof = 1;
            return 0;
        }
        return *z.stream++;
    }
    return 0;
}

uint32 get32(vorb* f) {
    uint32 x;
    x = get8(f);
    x += cast(u32, cast(i32, get8(f)) << 8);
    x += cast(u32, cast(i32, get8(f)) << 16);
    x += cast(uint32, get8(f)) << 24;
    return x;
}

i32 getn(vorb* z, uint8* data, i32 n) {
    if 1 != 0 {
        if z.stream + n > z.stream_end {
            z.eof = 1;
            return 0;
        }
        memcpy(data, z.stream, cast(u64, n));
        z.stream += n;
        return 1;
    }
    return 0;
}

void skip(vorb* z, i32 n) {
    if 1 != 0 {
        z.stream += n;
        if z.stream >= z.stream_end {
            z.eof = 1;
        }
        return;
    }
}

i32 set_file_offset(stb_vorbis* f, u32 loc) {
    f.eof = 0;
    if 1 != 0 {
        if f.stream_start + loc >= f.stream_end || f.stream_start + loc < f.stream_start {
            f.stream = f.stream_end;
            f.eof = 1;
            return 0;
        } else {
            f.stream = f.stream_start + loc;
            return 1;
        }
    }
    return 0;
}
uint8[4] ogg_page_header = {0x4f, 0x67, 0x67, 0x53};

i32 capture_pattern(vorb* f) {
    if 0x4f != get8(f) {
        return 0;
    }
    if 0x67 != get8(f) {
        return 0;
    }
    if 0x67 != get8(f) {
        return 0;
    }
    if 0x53 != get8(f) {
        return 0;
    }
    return 1;
}

i32 start_page_no_capturepattern(vorb* f) {
    uint32 loc0;
    uint32 loc1;
    uint32 n;
    if f.first_decode && !0 {
        f.p_first.page_start = stb_vorbis_get_file_offset(f) - 4;
    }
    if 0 != get8(f) {
        return error(f, VORBIS_invalid_stream_structure_version);
    }
    f.page_flag = get8(f);
    loc0 = get32(f);
    loc1 = get32(f);
    get32(f);
    n = get32(f);
    f.last_page = cast(i32, n);
    get32(f);
    f.segment_count = cast(i32, get8(f));
    if getn(f, f.segments, f.segment_count) == 0 {
        return error(f, VORBIS_unexpected_eof);
    }
    f.end_seg_with_known_loc = -2;
    if loc0 != cast(u32, ~0) || loc1 != cast(u32, ~0) {
        i32 i;
        for i = f.segment_count - 1; i >= 0; --i {
            if f.segments[i] < 255 {
                break;
            }
        }
        if i >= 0 {
            f.end_seg_with_known_loc = i;
            f.known_loc_for_packet = loc0;
        }
    }
    if f.first_decode != 0 {
        i32 i;
        i32 len;
        len = 0;
        for i = 0; i < f.segment_count; ++i {
            len += cast(i32, f.segments[i]);
        }
        len += 27 + f.segment_count;
        f.p_first.page_end = f.p_first.page_start + cast(u32, len);
        f.p_first.last_decoded_sample = loc0;
    }
    f.next_seg = 0;
    return 1;
}

i32 start_page(vorb* f) {
    if capture_pattern(f) == 0 {
        return error(f, VORBIS_missing_capture_pattern);
    }
    return start_page_no_capturepattern(f);
}

i32 start_packet(vorb* f) {
    while f.next_seg == -1 {
        if start_page(f) == 0 {
            return 0;
        }
        if (f.page_flag & 1) != 0 {
            return error(f, VORBIS_continued_packet_flag_invalid);
        }
    }
    f.last_seg = 0;
    f.valid_bits = 0;
    f.packet_bytes = 0;
    f.bytes_in_seg = 0;
    return 1;
}

i32 maybe_start_packet(vorb* f) {
    if f.next_seg == -1 {
        var x = cast(i32, get8(f));
        if f.eof != 0 {
            return 0;
        }
        if 0x4f != x {
            return error(f, VORBIS_missing_capture_pattern);
        }
        if 0x67 != get8(f) {
            return error(f, VORBIS_missing_capture_pattern);
        }
        if 0x67 != get8(f) {
            return error(f, VORBIS_missing_capture_pattern);
        }
        if 0x53 != get8(f) {
            return error(f, VORBIS_missing_capture_pattern);
        }
        if start_page_no_capturepattern(f) == 0 {
            return 0;
        }
        if (f.page_flag & 1) != 0 {
            f.last_seg = 0;
            f.bytes_in_seg = 0;
            return error(f, VORBIS_continued_packet_flag_invalid);
        }
    }
    return start_packet(f);
}

i32 next_segment(vorb* f) {
    i32 len;
    if f.last_seg != 0 {
        return 0;
    }
    if f.next_seg == -1 {
        f.last_seg_which = f.segment_count - 1;
        if start_page(f) == 0 {
            f.last_seg = 1;
            return 0;
        }
        if (f.page_flag & 1) == 0 {
            return error(f, VORBIS_continued_packet_flag_invalid);
        }
    }
    len = cast(i32, f.segments[f.next_seg++]);
    if len < 255 {
        f.last_seg = 1;
        f.last_seg_which = f.next_seg - 1;
    }
    if f.next_seg >= f.segment_count {
        f.next_seg = -1;
    }
    assert(f.bytes_in_seg == 0);
    f.bytes_in_seg = cast(uint8, len);
    return len;
}

i32 get8_packet_raw(vorb* f) {
    if f.bytes_in_seg == 0 {
        if f.last_seg != 0 {
            return -1;
        } else if next_segment(f) == 0 {
            return -1;
        }
    }
    assert(f.bytes_in_seg > 0);
    --f.bytes_in_seg;
    ++f.packet_bytes;
    return cast(i32, get8(f));
}

i32 get8_packet(vorb* f) {
    i32 x = get8_packet_raw(f);
    f.valid_bits = 0;
    return x;
}

i32 get32_packet(vorb* f) {
    uint32 x;
    x = cast(u32, get8_packet(f));
    x += cast(u32, get8_packet(f) << 8);
    x += cast(u32, get8_packet(f) << 16);
    x += cast(uint32, get8_packet(f)) << 24;
    return cast(i32, x);
}

void flush_packet(vorb* f) {
    while get8_packet_raw(f) != -1 {
    }
}

// @OPTIMIZE: this is the secondary bit decoder, so it's probably not as important
// as the huffman decoder?
uint32 get_bits(vorb* f, i32 n) {
    uint32 z;
    if f.valid_bits < 0 {
        return 0;
    }
    if f.valid_bits < n {
        if n > 24 {
            z = get_bits(f, 24);
            z += get_bits(f, n - 24) << 24;
            return z;
        }
        if f.valid_bits == 0 {
            f.acc = 0;
        }
        while f.valid_bits < n {
            i32 z = get8_packet_raw(f);
            if z == -1 {
                f.valid_bits = -1;
                return 0;
            }
            f.acc += cast(uint32, z << f.valid_bits);
            f.valid_bits += 8;
        }
    }
    assert(f.valid_bits >= n);
    z = f.acc & cast(u32, (1 << n) - 1);
    f.acc >>= cast(uint32, n);
    f.valid_bits -= n;
    return z;
}

// @OPTIMIZE: primary accumulator for huffman
// expand the buffer to as many bits as possible without reading off end of packet
// it might be nice to allow f->valid_bits and f->acc to be stored in registers,
// e.g. cache them locally and decode locally
void prep_huffman(vorb* f) {
    if f.valid_bits <= 24 {
        if f.valid_bits == 0 {
            f.acc = 0;
        }
        while true {
            i32 z;
            if f.last_seg && !f.bytes_in_seg {
                return;
            }
            z = get8_packet_raw(f);
            if z == -1 {
                return;
            }
            f.acc += cast(u32, z) << cast(u32, f.valid_bits);
            f.valid_bits += 8;
            if !(f.valid_bits <= 24) { break; }
        }
    }
}

i32 codebook_decode_scalar_raw(vorb* f, Codebook* c) {
    i32 i;
    prep_huffman(f);
    if c.codewords == null && c.sorted_codewords == null {
        return -1;
    }
    if (c.entries > 8 ? c.sorted_codewords != null : !c.codewords) != 0 {
        uint32 code = bit_reverse(f.acc);
        i32 x = 0;
        i32 n = c.sorted_entries;
        i32 len;
        while n > 1 {
            i32 m = x + (n >> 1);
            if c.sorted_codewords[m] <= code {
                x = m;
                n -= n >> 1;
            } else {
                n >>= 1;
            }
        }
        if c.sparse == 0 {
            x = c.sorted_values[x];
        }
        len = cast(i32, c.codeword_lengths[x]);
        if f.valid_bits >= len {
            f.acc >>= cast(uint32, len);
            f.valid_bits -= len;
            return x;
        }
        f.valid_bits = 0;
        return -1;
    }
    assert(cast(i64, !c.sparse));
    for i = 0; i < c.entries; ++i {
        if c.codeword_lengths[i] == 255 {
            continue;
        }
        if c.codewords[i] == (f.acc & cast(u32, (1 << cast(i32, c.codeword_lengths[i])) - 1)) {
            if f.valid_bits >= cast(i32, c.codeword_lengths[i]) {
                f.acc >>= c.codeword_lengths[i];
                f.valid_bits -= cast(i32, c.codeword_lengths[i]);
                return i;
            }
            f.valid_bits = 0;
            return -1;
        }
    }
    error(f, VORBIS_invalid_stream);
    f.valid_bits = 0;
    return -1;
}
}

/* transminc: DIVIDES_IN_CODEBOOK is never defined here — committed to the
   DECODE_RAW form (the dual-branch chain resolved to the wrong side, mapping
   z through sorted_values and firing the sparse-codebook assert on music) */
// CODEBOOK_ELEMENT_FAST is an optimization for the CODEBOOK_FLOATS case
// where we avoid one addition
private {
i32 codebook_decode_start(vorb* f, Codebook* c) {
    i32 z = -1;
    if c.lookup_type == 0 {
        error(f, VORBIS_invalid_stream);
    } else {
        if f.valid_bits < 10 {
            prep_huffman(f);
        }
        z = cast(i32, f.acc & cast(u32, (1 << 10) - 1));
        z = c.fast_huffman[z];
        if z >= 0 {
            var n = cast(i32, c.codeword_lengths[z]);
            f.acc >>= cast(uint32, n);
            f.valid_bits -= n;
            if f.valid_bits < 0 {
                f.valid_bits = 0;
                z = -1;
            }
        } else {
            z = codebook_decode_scalar_raw(f, c);
        }
        if c.sparse != 0 {
            assert(z < c.sorted_entries);
        }
        if z < 0 {
            if f.bytes_in_seg == 0 {
                if f.last_seg != 0 {
                    return z;
                }
            }
            error(f, VORBIS_invalid_stream);
        }
    }
    return z;
}

i32 codebook_decode(vorb* f, Codebook* c, f32* output, i32 len) {
    i32 i;
    i32 z = codebook_decode_start(f, c);
    if z < 0 {
        return 0;
    }
    if len > c.dimensions {
        len = c.dimensions;
    }
    when defined(STB_VORBIS_DIVIDES_IN_CODEBOOK) {
        if c.lookup_type == 1 {
            f32 last = 0.0f;
            i32 div = 1;
            for i = 0; i < len; ++i {
                var off = cast(i32, cast(u32, z / div) % c.lookup_values);
                f32 val = cast(f32, c.multiplicands[off]) + last;
                output[i] += val;
                if c.sequence_p != 0 {
                    last = val + c.minimum_value;
                }
                div *= cast(i32, c.lookup_values);
            }
            return 1;
        }
    }
    z *= c.dimensions;
    if c.sequence_p != 0 {
        f32 last = 0.0f;
        for i = 0; i < len; ++i {
            f32 val = cast(f32, c.multiplicands[z + i]) + last;
            output[i] += val;
            last = val + c.minimum_value;
        }
    } else {
        f32 last = 0.0f;
        for i = 0; i < len; ++i {
            output[i] += cast(f32, c.multiplicands[z + i]) + last;
        }
    }
    return 1;
}

i32 codebook_decode_step(vorb* f, Codebook* c, f32* output, i32 len, i32 step) {
    i32 i;
    i32 z = codebook_decode_start(f, c);
    f32 last = 0.0f;
    if z < 0 {
        return 0;
    }
    if len > c.dimensions {
        len = c.dimensions;
    }
    when defined(STB_VORBIS_DIVIDES_IN_CODEBOOK) {
        if c.lookup_type == 1 {
            i32 div = 1;
            for i = 0; i < len; ++i {
                var off = cast(i32, cast(u32, z / div) % c.lookup_values);
                f32 val = cast(f32, c.multiplicands[off]) + last;
                output[i * step] += val;
                if c.sequence_p != 0 {
                    last = val;
                }
                div *= cast(i32, c.lookup_values);
            }
            return 1;
        }
    }
    z *= c.dimensions;
    for i = 0; i < len; ++i {
        f32 val = cast(f32, c.multiplicands[z + i]) + last;
        output[i * step] += val;
        if c.sequence_p != 0 {
            last = val;
        }
    }
    return 1;
}

i32 codebook_decode_deinterleave_repeat(vorb* f, Codebook* c, f32** outputs, i32 ch, i32* c_inter_p, i32* p_inter_p, i32 len, i32 total_decode) {
    i32 c_inter = *c_inter_p;
    i32 p_inter = *p_inter_p;
    i32 i;
    i32 z;
    i32 effective = c.dimensions;
    if c.lookup_type == 0 {
        return error(f, VORBIS_invalid_stream);
    }
    while total_decode > 0 {
        f32 last = 0.0f;
        if f.valid_bits < 10 {
            prep_huffman(f);
        }
        z = cast(i32, f.acc & cast(u32, (1 << 10) - 1));
        z = c.fast_huffman[z];
        if z >= 0 {
            var n = cast(i32, c.codeword_lengths[z]);
            f.acc >>= cast(uint32, n);
            f.valid_bits -= n;
            if f.valid_bits < 0 {
                f.valid_bits = 0;
                z = -1;
            }
        } else {
            z = codebook_decode_scalar_raw(f, c);
        }
        when !(defined(STB_VORBIS_DIVIDES_IN_CODEBOOK)) {
            assert(!c.sparse || z < c.sorted_entries);
        }
        if z < 0 {
            if f.bytes_in_seg == 0 {
                if f.last_seg != 0 {
                    return 0;
                }
            }
            return error(f, VORBIS_invalid_stream);
        }
        if c_inter + p_inter * ch + effective > len * ch {
            effective = len * ch - (p_inter * ch - c_inter);
        }
        {
            z *= c.dimensions;
            if c.sequence_p != 0 {
                for i = 0; i < effective; ++i {
                    f32 val = cast(f32, c.multiplicands[z + i]) + last;
                    if outputs[c_inter] != null {
                        outputs[c_inter][p_inter] += val;
                    }
                    if ++c_inter == ch {
                        c_inter = 0;
                        ++p_inter;
                    }
                    last = val;
                }
            } else {
                for i = 0; i < effective; ++i {
                    f32 val = cast(f32, c.multiplicands[z + i]) + last;
                    if outputs[c_inter] != null {
                        outputs[c_inter][p_inter] += val;
                    }
                    if ++c_inter == ch {
                        c_inter = 0;
                        ++p_inter;
                    }
                }
            }
        }
        total_decode -= effective;
    }
    *c_inter_p = c_inter;
    *p_inter_p = p_inter;
    return 1;
}

i32 predict_point(i32 x, i32 x0, i32 x1, i32 y0, i32 y1) {
    i32 dy = y1 - y0;
    i32 adx = x1 - x0;
    i32 err = abs(dy) * (x - x0);
    i32 off = err / adx;
    return dy < 0 ? y0 - off : y0 + off;
}
// the following table is block-copied from the specification
f32[256] inverse_db_table = {
    1.0649862999999999e-7f, 1.1341950999999999e-7f, 1.2079015e-7f, 1.2863978000000002e-7f,
    1.3699951000000002e-7f, 1.4590251e-7f, 1.5538408e-7f, 1.6548181e-7f, 1.7623575e-7f,
    1.8768855e-7f, 1.9988561e-7f, 2.128753e-7f, 2.2670913000000002e-7f, 2.4144196999999997e-7f,
    2.5713222999999996e-7f, 2.7384212999999997e-7f, 2.9163793e-7f, 3.1059021e-7f,
    3.3077410999999997e-7f, 3.5226967999999997e-7f, 3.7516214e-7f, 3.9954229e-7f, 4.255068e-7f,
    4.5315862999999997e-7f, 4.8260743e-7f, 5.1396998e-7f, 5.4737065e-7f, 5.8294187e-7f,
    6.208247199999999e-7f, 6.6116941e-7f, 7.041359199999999e-7f, 7.4989464e-7f, 7.9862701e-7f,
    8.505263e-7f, 9.0579828e-7f, 9.6466216e-7f, 1.0273513e-6f, 1.0941144e-6f, 1.1652161e-6f,
    1.2409384e-6f, 1.3215816e-6f, 1.4074654e-6f, 1.4989304999999998e-6f, 1.5963394e-6f,
    1.7000785e-6f, 1.8105592e-6f, 1.9282195e-6f, 2.0535261e-6f, 2.1869758e-6f, 2.3290978e-6f,
    2.4804556999999996e-6f, 2.6416496999999997e-6f, 2.8133189999999997e-6f, 2.9961443e-6f,
    3.1908506e-6f, 3.3982101e-6f, 3.6190449e-6f, 3.8542308e-6f, 4.1047004e-6f, 4.371447e-6f,
    4.6555282e-6f, 4.9580707e-6f, 5.280274000000001e-6f, 5.623416e-6f, 5.9888572e-6f, 6.3780469e-6f,
    6.7925282999999995e-6f, 7.2339451e-6f, 7.7040476e-6f, 8.204700000000001e-6f, 8.7378876e-6f,
    9.3057248e-6f, 9.910463200000001e-6f, 1.0554501000000001e-5f, 1.1240392e-5f, 1.1970856e-5f,
    1.2748789e-5f, 1.3577278e-5f, 1.4459606000000001e-5f, 1.5399272e-5f, 1.6400004e-5f,
    1.7465768e-5f, 1.8600791999999998e-5f, 1.9809576e-5f, 2.1096914e-5f, 2.2467911e-5f,
    2.3928002e-5f, 2.5482978e-5f, 2.7139006000000002e-5f, 2.8902651000000003e-5f, 3.0780908e-5f,
    3.2781225e-5f, 3.4911534e-5f, 3.7180282e-5f, 3.9596466e-5f, 4.216966700000001e-5f, 4.491009e-5f,
    4.7828600999999994e-5f, 5.0936773e-5f, 5.4246930999999995e-5f, 5.7772202e-5f, 6.1526565e-5f,
    6.5524908e-5f, 6.978308499999999e-5f, 7.4317983e-5f, 7.9147585e-5f, 8.429104e-5f, 8.9768747e-5f,
    9.5602426e-5f, 0.00010181521f, 0.00010843174f, 0.00011547824f, 0.00012298267f, 0.00013097477f,
    0.00013948625f, 0.00014855085f, 0.00015820453f, 0.00016848555f, 0.00017943469f, 0.00019109536f,
    0.00020351382f, 0.00021673929f, 0.00023082423f, 0.00024582449f, 0.00026179955f, 0.00027881276f,
    0.00029693158f, 0.00031622787f, 0.00033677814f, 0.00035866388f, 0.00038197188f, 0.00040679456f,
    0.00043323036f, 0.00046138411f, 0.00049136745f, 0.00052329927f, 0.00055730621f, 0.00059352311f,
    0.00063209358f, 0.00067317058f, 0.000716917f, 0.0007635063f, 0.00081312324f, 0.00086596457f,
    0.00092223983f, 0.00098217216f, 0.0010459992f, 0.0011139742f, 0.0011863665f, 0.0012634633f,
    0.0013455702f, 0.0014330129f, 0.0015261382f, 0.0016253153f, 0.0017309374f, 0.0018434235f,
    0.0019632195f, 0.0020908006f, 0.0022266726f, 0.0023713743f, 0.0025254795f, 0.0026895994f,
    0.0028643847f, 0.0030505286f, 0.0032487691f, 0.0034598925f, 0.0036847358f, 0.0039241906f,
    0.0041792066f, 0.004450795f, 0.0047400328f, 0.0050480668f, 0.0053761186f, 0.0057254891f,
    0.0060975636f, 0.0064938176f, 0.0069158225f, 0.0073652516f, 0.0078438871f, 0.0083536271f,
    0.0088964928f, 0.009474637f, 0.010090352f, 0.01074608f, 0.011444421f, 0.012188144f,
    0.012980198f, 0.013823725f, 0.014722068f, 0.015678791f, 0.016697687f, 0.017782797f,
    0.018938423f, 0.020169149f, 0.021479854f, 0.022875735f, 0.02436233f, 0.025945531f, 0.027631618f,
    0.029427276f, 0.031339626f, 0.033376252f, 0.035545228f, 0.037855157f, 0.040315199f,
    0.042935108f, 0.045725273f, 0.048696758f, 0.051861348f, 0.055231591f, 0.05882085f, 0.062643361f,
    0.066714279f, 0.071049749f, 0.075666962f, 0.080584227f, 0.085821044f, 0.091398179f,
    0.097337747f, 0.1036633f, 0.11039993f, 0.11757434f, 0.12521498f, 0.13335215f, 0.14201813f,
    0.15124727f, 0.16107617f, 0.1715438f, 0.18269168f, 0.19456402f, 0.20720788f, 0.22067342f,
    0.23501402f, 0.25028656f, 0.26655159f, 0.28387361f, 0.30232132f, 0.32196786f, 0.34289114f,
    0.36517414f, 0.38890521f, 0.41417847f, 0.44109412f, 0.4697589f, 0.50028648f, 0.53279791f,
    0.56742212f, 0.6042964f, 0.64356699f, 0.68538959f, 0.72993007f, 0.77736504f, 0.8278826f,
    0.88168307f, 0.9389798f, 1.0f,
};
}
// @OPTIMIZE: if you want to replace this bresenham line-drawing routine,
// note that you must produce bit-identical output to decode correctly;
// this specific sequence of operations is specified in the spec (it's
// drawing integer-quantized frequency-space lines that the encoder
// expects to be exactly the same)
//     ... also, isn't the whole point of Bresenham's algorithm to NOT
// have to divide in the setup? sigh.
/* transminc: committed to the DEFER_FLOOR form — the dual-branch chain
   resolved to the wrong side (a = b), overwriting the residue with the bare
   floor envelope instead of applying it (audibly broken decode) */
when defined(STB_VORBIS_DIVIDE_TABLE) {
/* transminc: divide-table dims 32x64 inlined as literals */
int8:[32][64] integer_divide_table;
}

private {
void draw_line(f32* output, i32 x0, i32 y0, i32 x1, i32 y1, i32 n) {
    i32 dy = y1 - y0;
    i32 adx = x1 - x0;
    i32 ady = abs(dy);
    i32 base;
    i32 x = x0;
    i32 y = y0;
    i32 err = 0;
    i32 sy;
    when defined(STB_VORBIS_DIVIDE_TABLE) {
        if adx < 64 && ady < 32 {
            if dy < 0 {
                base = -integer_divide_table[ady][adx];
                sy = base - 1;
            } else {
                base = integer_divide_table[ady][adx];
                sy = base + 1;
            }
        } else {
            base = dy / adx;
            if dy < 0 {
                sy = base - 1;
            } else {
                sy = base + 1;
            }
        }
    } else {
        base = dy / adx;
        if dy < 0 {
            sy = base - 1;
        } else {
            sy = base + 1;
        }
    }
    ady -= abs(base) * adx;
    if x1 > n {
        x1 = n;
    }
    if x < x1 {
        output[x] *= inverse_db_table[y & 255];
        for ++x; x < x1; ++x {
            err += ady;
            if err >= adx {
                err -= adx;
                y += sy;
            } else {
                y += base;
            }
            output[x] *= inverse_db_table[y & 255];
        }
    }
}

i32 residue_decode(vorb* f, Codebook* book, f32* target, i32 offset, i32 n, i32 rtype) {
    i32 k;
    if rtype == 0 {
        i32 step = n / book.dimensions;
        for k = 0; k < step; ++k {
            if codebook_decode_step(f, book, target + offset + k, n - offset - k, step) == 0 {
                return 0;
            }
        }
    } else {
        k = 0;
        while k < n {
            if codebook_decode(f, book, target + offset, n - k) == 0 {
                return 0;
            }
            k += book.dimensions;
            offset += book.dimensions;
        }
    }
    return 1;
}

// n is 1/2 of the blocksize --
// specification: "Correct per-vector decode length is [n]/2"
void decode_residue(vorb* f, f32** residue_buffers, i32 ch, i32 n, i32 rn, uint8* do_not_decode) {
    i32 temp_alloc_point = 0;
    uint8*** part_classdata = null;
    i32** classifications = null;
    ignore classifications;   // only used when defined(STB_VORBIS_DIVIDES_IN_RESIDUE)
    defer {
        when !(defined(STB_VORBIS_DIVIDES_IN_RESIDUE)) {
            setup_temp_free(f, part_classdata, 0);
        } else {
            setup_temp_free(f, classifications, 0);
        }
        f.temp_offset = temp_alloc_point;
    }
    i32 i;
    i32 j;
    i32 pass;
    Residue* r = f.residue_config + rn;
    var rtype = cast(i32, f.residue_types[rn]);
    var c = cast(i32, r.classbook);
    i32 classwords = f.codebooks[c].dimensions;
    var actual_size = cast(u32, rtype == 2 ? n * 2 : n);
    u32 limit_r_begin = r.begin < actual_size ? r.begin : actual_size;
    u32 limit_r_end = r.end < actual_size ? r.end : actual_size;
    var n_read = cast(i32, limit_r_end - limit_r_begin);
    var part_read = cast(i32, cast(u32, n_read) / r.part_size);
    temp_alloc_point = f.temp_offset;
    when !(defined(STB_VORBIS_DIVIDES_IN_RESIDUE)) {
        part_classdata = cast(uint8***, make_block_array(setup_temp_malloc(f, cast(i32, f.channels * (sizeof(void*) + part_read * sizeof(**part_classdata)))), f.channels, cast(i32, part_read * sizeof(**part_classdata))));
    } else {
        classifications = cast(i32**, make_block_array(setup_temp_malloc(f, cast(i32, f.channels * (sizeof(void*) + part_read * sizeof(**classifications)))), f.channels, cast(i32, part_read * sizeof(**classifications))));
    }
    for i = 0; i < ch; ++i {
        if do_not_decode[i] == 0 {
            memset(residue_buffers[i], 0, cast(u64, sizeof(f32) * n));
        }
    }
    if rtype == 2 && ch != 1 {
        for j = 0; j < ch; ++j {
            if do_not_decode[j] == 0 {
                break;
            }
        }
        if j == ch {
            return;
        }
        for pass = 0; pass < 8; ++pass {
            i32 pcount = 0;
            i32 class_set = 0;
            if ch == 2 {
                while pcount < part_read {
                    var z = cast(i32, r.begin + cast(u32, pcount) * r.part_size);
                    i32 c_inter = z & 1;
                    i32 p_inter = z >> 1;
                    if pass == 0 {
                        Codebook* c = f.codebooks + r.classbook;
                        i32 q;
                        if f.valid_bits < 10 {
                            prep_huffman(f);
                        }
                        q = cast(i32, f.acc & cast(u32, (1 << 10) - 1));
                        q = c.fast_huffman[q];
                        if q >= 0 {
                            var n = cast(i32, c.codeword_lengths[q]);
                            f.acc >>= cast(uint32, n);
                            f.valid_bits -= n;
                            if f.valid_bits < 0 {
                                f.valid_bits = 0;
                                q = -1;
                            }
                        } else {
                            q = codebook_decode_scalar_raw(f, c);
                        }
                        if c.sparse != 0 {
                            q = c.sorted_values[q];
                        }
                        if q == -1 {
                            return;
                        }
                        when !(defined(STB_VORBIS_DIVIDES_IN_RESIDUE)) {
                            part_classdata[0][class_set] = r.classdata[q];
                        } else {
                            for i = classwords - 1; i >= 0; --i {
                                classifications[0][i + pcount] = q % r.classifications;
                                q /= cast(i32, r.classifications);
                            }
                        }
                    }
                    for i = 0; i < classwords && pcount < part_read; ++i {
                        var z = cast(i32, r.begin + cast(u32, pcount) * r.part_size);
                        i32 c;
                        when !(defined(STB_VORBIS_DIVIDES_IN_RESIDUE)) {
                            c = cast(i32, part_classdata[0][class_set][i]);
                        } else {
                            c = classifications[0][pcount];
                        }
                        i32 b = r.residue_books[c * 8 + pass];
                        if b >= 0 {
                            Codebook* book = f.codebooks + b;
                            when defined(STB_VORBIS_DIVIDES_IN_CODEBOOK) {
                                if codebook_decode_deinterleave_repeat(f, book, residue_buffers, ch, &c_inter, &p_inter, n, cast(i32, r.part_size)) == 0 {
                                    return;
                                }
                            } else {
                                if codebook_decode_deinterleave_repeat(f, book, residue_buffers, ch, &c_inter, &p_inter, n, cast(i32, r.part_size)) == 0 {
                                    return;
                                }
                            }
                        } else {
                            z += cast(i32, r.part_size);
                            c_inter = z & 1;
                            p_inter = z >> 1;
                        }
                        ++pcount;
                    }
                    when !(defined(STB_VORBIS_DIVIDES_IN_RESIDUE)) {
                        ++class_set;
                    }
                }
            } else if ch > 2 {
                while pcount < part_read {
                    var z = cast(i32, r.begin + cast(u32, pcount) * r.part_size);
                    i32 c_inter = z % ch;
                    i32 p_inter = z / ch;
                    if pass == 0 {
                        Codebook* c = f.codebooks + r.classbook;
                        i32 q;
                        if f.valid_bits < 10 {
                            prep_huffman(f);
                        }
                        q = cast(i32, f.acc & cast(u32, (1 << 10) - 1));
                        q = c.fast_huffman[q];
                        if q >= 0 {
                            var n = cast(i32, c.codeword_lengths[q]);
                            f.acc >>= cast(uint32, n);
                            f.valid_bits -= n;
                            if f.valid_bits < 0 {
                                f.valid_bits = 0;
                                q = -1;
                            }
                        } else {
                            q = codebook_decode_scalar_raw(f, c);
                        }
                        if c.sparse != 0 {
                            q = c.sorted_values[q];
                        }
                        if q == -1 {
                            return;
                        }
                        when !(defined(STB_VORBIS_DIVIDES_IN_RESIDUE)) {
                            part_classdata[0][class_set] = r.classdata[q];
                        } else {
                            for i = classwords - 1; i >= 0; --i {
                                classifications[0][i + pcount] = q % r.classifications;
                                q /= cast(i32, r.classifications);
                            }
                        }
                    }
                    for i = 0; i < classwords && pcount < part_read; ++i {
                        var z = cast(i32, r.begin + cast(u32, pcount) * r.part_size);
                        i32 c;
                        when !(defined(STB_VORBIS_DIVIDES_IN_RESIDUE)) {
                            c = cast(i32, part_classdata[0][class_set][i]);
                        } else {
                            c = classifications[0][pcount];
                        }
                        i32 b = r.residue_books[c * 8 + pass];
                        if b >= 0 {
                            Codebook* book = f.codebooks + b;
                            if codebook_decode_deinterleave_repeat(f, book, residue_buffers, ch, &c_inter, &p_inter, n, cast(i32, r.part_size)) == 0 {
                                return;
                            }
                        } else {
                            z += cast(i32, r.part_size);
                            c_inter = z % ch;
                            p_inter = z / ch;
                        }
                        ++pcount;
                    }
                    when !(defined(STB_VORBIS_DIVIDES_IN_RESIDUE)) {
                        ++class_set;
                    }
                }
            }
        }
        return;
    }
    for pass = 0; pass < 8; ++pass {
        i32 pcount = 0;
        i32 class_set = 0;
        while pcount < part_read {
            if pass == 0 {
                for j = 0; j < ch; ++j {
                    if do_not_decode[j] == 0 {
                        Codebook* c = f.codebooks + r.classbook;
                        i32 temp;
                        if f.valid_bits < 10 {
                            prep_huffman(f);
                        }
                        temp = cast(i32, f.acc & cast(u32, (1 << 10) - 1));
                        temp = c.fast_huffman[temp];
                        if temp >= 0 {
                            var n = cast(i32, c.codeword_lengths[temp]);
                            f.acc >>= cast(uint32, n);
                            f.valid_bits -= n;
                            if f.valid_bits < 0 {
                                f.valid_bits = 0;
                                temp = -1;
                            }
                        } else {
                            temp = codebook_decode_scalar_raw(f, c);
                        }
                        if c.sparse != 0 {
                            temp = c.sorted_values[temp];
                        }
                        if temp == -1 {
                            return;
                        }
                        when !(defined(STB_VORBIS_DIVIDES_IN_RESIDUE)) {
                            part_classdata[j][class_set] = r.classdata[temp];
                        } else {
                            for i = classwords - 1; i >= 0; --i {
                                classifications[j][i + pcount] = temp % r.classifications;
                                temp /= cast(i32, r.classifications);
                            }
                        }
                    }
                }
            }
            for i = 0; i < classwords && pcount < part_read; ++i {
                for j = 0; j < ch; ++j {
                    if do_not_decode[j] == 0 {
                        i32 c;
                        when !(defined(STB_VORBIS_DIVIDES_IN_RESIDUE)) {
                            c = cast(i32, part_classdata[j][class_set][i]);
                        } else {
                            c = classifications[j][pcount];
                        }
                        i32 b = r.residue_books[c * 8 + pass];
                        if b >= 0 {
                            f32* target = residue_buffers[j];
                            var offset = cast(i32, r.begin + cast(u32, pcount) * r.part_size);
                            var n = cast(i32, r.part_size);
                            Codebook* book = f.codebooks + b;
                            if residue_decode(f, book, target, offset, n, rtype) == 0 {
                                return;
                            }
                        }
                    }
                }
                ++pcount;
            }
            when !(defined(STB_VORBIS_DIVIDES_IN_RESIDUE)) {
                ++class_set;
            }
        }
    }
    return;
}

// the following were split out into separate functions while optimizing;
// they could be pushed back up but eh. __forceinline showed no change;
// they're probably already being inlined.
void imdct_step3_iter0_loop(i32 n, f32* e, i32 i_off, i32 k_off, f32* A) {
    f32* ee0 = e + i_off;
    f32* ee2 = ee0 + k_off;
    i32 i;
    assert((n & 3) == 0);
    for i = n >> 2; i > 0; --i {
        f32 k00_20;
        f32 k01_21;
        k00_20 = ee0[0] - ee2[0];
        k01_21 = ee0[-1] - ee2[-1];
        ee0[0] += ee2[0];
        ee0[-1] += ee2[-1];
        ee2[0] = k00_20 * A[0] - k01_21 * A[1];
        ee2[-1] = k01_21 * A[0] + k00_20 * A[1];
        A += 8;
        k00_20 = ee0[-2] - ee2[-2];
        k01_21 = ee0[-3] - ee2[-3];
        ee0[-2] += ee2[-2];
        ee0[-3] += ee2[-3];
        ee2[-2] = k00_20 * A[0] - k01_21 * A[1];
        ee2[-3] = k01_21 * A[0] + k00_20 * A[1];
        A += 8;
        k00_20 = ee0[-4] - ee2[-4];
        k01_21 = ee0[-5] - ee2[-5];
        ee0[-4] += ee2[-4];
        ee0[-5] += ee2[-5];
        ee2[-4] = k00_20 * A[0] - k01_21 * A[1];
        ee2[-5] = k01_21 * A[0] + k00_20 * A[1];
        A += 8;
        k00_20 = ee0[-6] - ee2[-6];
        k01_21 = ee0[-7] - ee2[-7];
        ee0[-6] += ee2[-6];
        ee0[-7] += ee2[-7];
        ee2[-6] = k00_20 * A[0] - k01_21 * A[1];
        ee2[-7] = k01_21 * A[0] + k00_20 * A[1];
        A += 8;
        ee0 -= 8;
        ee2 -= 8;
    }
}

void imdct_step3_inner_r_loop(i32 lim, f32* e, i32 d0, i32 k_off, f32* A, i32 k1) {
    i32 i;
    f32 k00_20;
    f32 k01_21;
    f32* e0 = e + d0;
    f32* e2 = e0 + k_off;
    for i = lim >> 2; i > 0; --i {
        k00_20 = e0[-0] - e2[-0];
        k01_21 = e0[-1] - e2[-1];
        e0[-0] += e2[-0];
        e0[-1] += e2[-1];
        e2[-0] = k00_20 * A[0] - k01_21 * A[1];
        e2[-1] = k01_21 * A[0] + k00_20 * A[1];
        A += k1;
        k00_20 = e0[-2] - e2[-2];
        k01_21 = e0[-3] - e2[-3];
        e0[-2] += e2[-2];
        e0[-3] += e2[-3];
        e2[-2] = k00_20 * A[0] - k01_21 * A[1];
        e2[-3] = k01_21 * A[0] + k00_20 * A[1];
        A += k1;
        k00_20 = e0[-4] - e2[-4];
        k01_21 = e0[-5] - e2[-5];
        e0[-4] += e2[-4];
        e0[-5] += e2[-5];
        e2[-4] = k00_20 * A[0] - k01_21 * A[1];
        e2[-5] = k01_21 * A[0] + k00_20 * A[1];
        A += k1;
        k00_20 = e0[-6] - e2[-6];
        k01_21 = e0[-7] - e2[-7];
        e0[-6] += e2[-6];
        e0[-7] += e2[-7];
        e2[-6] = k00_20 * A[0] - k01_21 * A[1];
        e2[-7] = k01_21 * A[0] + k00_20 * A[1];
        e0 -= 8;
        e2 -= 8;
        A += k1;
    }
}

void imdct_step3_inner_s_loop(i32 n, f32* e, i32 i_off, i32 k_off, f32* A, i32 a_off, i32 k0) {
    i32 i;
    f32 A0 = A[0];
    f32 A1 = A[0 + 1];
    f32 A2 = A[0 + a_off];
    f32 A3 = A[0 + a_off + 1];
    f32 A4 = A[0 + a_off * 2 + 0];
    f32 A5 = A[0 + a_off * 2 + 1];
    f32 A6 = A[0 + a_off * 3 + 0];
    f32 A7 = A[0 + a_off * 3 + 1];
    f32 k00;
    f32 k11;
    f32* ee0 = e + i_off;
    f32* ee2 = ee0 + k_off;
    for i = n; i > 0; --i {
        k00 = ee0[0] - ee2[0];
        k11 = ee0[-1] - ee2[-1];
        ee0[0] = ee0[0] + ee2[0];
        ee0[-1] = ee0[-1] + ee2[-1];
        ee2[0] = k00 * A0 - k11 * A1;
        ee2[-1] = k11 * A0 + k00 * A1;
        k00 = ee0[-2] - ee2[-2];
        k11 = ee0[-3] - ee2[-3];
        ee0[-2] = ee0[-2] + ee2[-2];
        ee0[-3] = ee0[-3] + ee2[-3];
        ee2[-2] = k00 * A2 - k11 * A3;
        ee2[-3] = k11 * A2 + k00 * A3;
        k00 = ee0[-4] - ee2[-4];
        k11 = ee0[-5] - ee2[-5];
        ee0[-4] = ee0[-4] + ee2[-4];
        ee0[-5] = ee0[-5] + ee2[-5];
        ee2[-4] = k00 * A4 - k11 * A5;
        ee2[-5] = k11 * A4 + k00 * A5;
        k00 = ee0[-6] - ee2[-6];
        k11 = ee0[-7] - ee2[-7];
        ee0[-6] = ee0[-6] + ee2[-6];
        ee0[-7] = ee0[-7] + ee2[-7];
        ee2[-6] = k00 * A6 - k11 * A7;
        ee2[-7] = k11 * A6 + k00 * A7;
        ee0 -= k0;
        ee2 -= k0;
    }
}

void iter_54(f32* z) {
    f32 k00;
    f32 k11;
    f32 k22;
    f32 k33;
    f32 y0;
    f32 y1;
    f32 y2;
    f32 y3;
    k00 = z[0] - z[-4];
    y0 = z[0] + z[-4];
    y2 = z[-2] + z[-6];
    k22 = z[-2] - z[-6];
    z[-0] = y0 + y2;
    z[-2] = y0 - y2;
    k33 = z[-3] - z[-7];
    z[-4] = k00 + k33;
    z[-6] = k00 - k33;
    k11 = z[-1] - z[-5];
    y1 = z[-1] + z[-5];
    y3 = z[-3] + z[-7];
    z[-1] = y1 + y3;
    z[-3] = y1 - y3;
    z[-5] = k11 - k22;
    z[-7] = k11 + k22;
}

void imdct_step3_inner_s_loop_ld654(i32 n, f32* e, i32 i_off, f32* A, i32 base_n) {
    i32 a_off = base_n >> 3;
    f32 A2 = A[0 + a_off];
    f32* z = e + i_off;
    f32* base = z - 16 * n;
    while z > base {
        f32 k00;
        f32 k11;
        f32 l00;
        f32 l11;
        k00 = z[-0] - z[-8];
        k11 = z[-1] - z[-9];
        l00 = z[-2] - z[-10];
        l11 = z[-3] - z[-11];
        z[-0] = z[-0] + z[-8];
        z[-1] = z[-1] + z[-9];
        z[-2] = z[-2] + z[-10];
        z[-3] = z[-3] + z[-11];
        z[-8] = k00;
        z[-9] = k11;
        z[-10] = (l00 + l11) * A2;
        z[-11] = (l11 - l00) * A2;
        k00 = z[-4] - z[-12];
        k11 = z[-5] - z[-13];
        l00 = z[-6] - z[-14];
        l11 = z[-7] - z[-15];
        z[-4] = z[-4] + z[-12];
        z[-5] = z[-5] + z[-13];
        z[-6] = z[-6] + z[-14];
        z[-7] = z[-7] + z[-15];
        z[-12] = k11;
        z[-13] = -k00;
        z[-14] = (l11 - l00) * A2;
        z[-15] = (l00 + l11) * -A2;
        iter_54(z);
        iter_54(z - 8);
        z -= 16;
    }
}

void inverse_mdct(f32* buffer, i32 n, vorb* f, i32 blocktype) {
    i32 n2 = n >> 1;
    i32 n4 = n >> 2;
    i32 n8 = n >> 3;
    i32 l;
    i32 ld;
    i32 save_point = f.temp_offset;
    var buf2 = cast(f32*, setup_temp_malloc(f, cast(i32, n2 * sizeof(f32))));
    f32* u = null;
    f32* v = null;
    f32* A = f.A[blocktype];
    {
        f32* d;
        f32* e;
        f32* AA;
        f32* e_stop;
        d = &buf2[n2 - 2];
        AA = A;
        e = &buffer[0];
        e_stop = &buffer[n2];
        while e != e_stop {
            d[1] = e[0] * AA[0] - e[2] * AA[1];
            d[0] = e[0] * AA[1] + e[2] * AA[0];
            d -= 2;
            AA += 2;
            e += 4;
        }
        e = &buffer[n2 - 3];
        while d >= buf2 {
            d[1] = -e[2] * AA[0] - -e[0] * AA[1];
            d[0] = -e[2] * AA[1] + -e[0] * AA[0];
            d -= 2;
            AA += 2;
            e -= 4;
        }
    }
    u = buffer;
    v = buf2;
    {
        f32* AA = &A[n2 - 8];
        f32* d0;
        f32* d1;
        f32* e0;
        f32* e1;
        e0 = &v[n4];
        e1 = &v[0];
        d0 = &u[n4];
        d1 = &u[0];
        while AA >= A {
            f32 v40_20;
            f32 v41_21;
            v41_21 = e0[1] - e1[1];
            v40_20 = e0[0] - e1[0];
            d0[1] = e0[1] + e1[1];
            d0[0] = e0[0] + e1[0];
            d1[1] = v41_21 * AA[4] - v40_20 * AA[5];
            d1[0] = v40_20 * AA[4] + v41_21 * AA[5];
            v41_21 = e0[3] - e1[3];
            v40_20 = e0[2] - e1[2];
            d0[3] = e0[3] + e1[3];
            d0[2] = e0[2] + e1[2];
            d1[3] = v41_21 * AA[0] - v40_20 * AA[1];
            d1[2] = v40_20 * AA[0] + v41_21 * AA[1];
            AA -= 8;
            d0 += 4;
            d1 += 4;
            e0 += 4;
            e1 += 4;
        }
    }
    ld = ilog(n) - 1;
    imdct_step3_iter0_loop(n >> 4, u, n2 - 1 - n4 * 0, -(n >> 3), A);
    imdct_step3_iter0_loop(n >> 4, u, n2 - 1 - n4 * 1, -(n >> 3), A);
    imdct_step3_inner_r_loop(n >> 5, u, n2 - 1 - n8 * 0, -(n >> 4), A, 16);
    imdct_step3_inner_r_loop(n >> 5, u, n2 - 1 - n8 * 1, -(n >> 4), A, 16);
    imdct_step3_inner_r_loop(n >> 5, u, n2 - 1 - n8 * 2, -(n >> 4), A, 16);
    imdct_step3_inner_r_loop(n >> 5, u, n2 - 1 - n8 * 3, -(n >> 4), A, 16);
    l = 2;
    for ; l < ld - 3 >> 1; ++l {
        i32 k0 = n >> l + 2;
        i32 k0_2 = k0 >> 1;
        i32 lim = 1 << l + 1;
        i32 i;
        for i = 0; i < lim; ++i {
            imdct_step3_inner_r_loop(n >> l + 4, u, n2 - 1 - k0 * i, -k0_2, A, 1 << l + 3);
        }
    }
    for ; l < ld - 6; ++l {
        i32 k0 = n >> l + 2;
        i32 k1 = 1 << l + 3;
        i32 k0_2 = k0 >> 1;
        i32 rlim = n >> l + 6;
        i32 r;
        i32 lim = 1 << l + 1;
        i32 i_off;
        f32* A0 = A;
        i_off = n2 - 1;
        for r = rlim; r > 0; --r {
            imdct_step3_inner_s_loop(lim, u, i_off, -k0_2, A0, k1, k0);
            A0 += k1 * 4;
            i_off -= 8;
        }
    }
    imdct_step3_inner_s_loop_ld654(n >> 5, u, n2 - 1, A, n);
    {
        uint16* bitrev = f.bit_reverse[blocktype];
        f32* d0 = &v[n4 - 4];
        f32* d1 = &v[n2 - 4];
        while d0 >= v {
            i32 k4;
            k4 = cast(i32, bitrev[0]);
            d1[3] = u[k4 + 0];
            d1[2] = u[k4 + 1];
            d0[3] = u[k4 + 2];
            d0[2] = u[k4 + 3];
            k4 = cast(i32, bitrev[1]);
            d1[1] = u[k4 + 0];
            d1[0] = u[k4 + 1];
            d0[1] = u[k4 + 2];
            d0[0] = u[k4 + 3];
            d0 -= 4;
            d1 -= 4;
            bitrev += 2;
        }
    }
    assert(v == buf2);
    {
        f32* C = f.C[blocktype];
        f32* d;
        f32* e;
        d = v;
        e = v + n2 - 4;
        while d < e {
            f32 a02;
            f32 a11;
            f32 b0;
            f32 b1;
            f32 b2;
            f32 b3;
            a02 = d[0] - e[2];
            a11 = d[1] + e[3];
            b0 = C[1] * a02 + C[0] * a11;
            b1 = C[1] * a11 - C[0] * a02;
            b2 = d[0] + e[2];
            b3 = d[1] - e[3];
            d[0] = b2 + b0;
            d[1] = b3 + b1;
            e[2] = b2 - b0;
            e[3] = b1 - b3;
            a02 = d[2] - e[0];
            a11 = d[3] + e[1];
            b0 = C[3] * a02 + C[2] * a11;
            b1 = C[3] * a11 - C[2] * a02;
            b2 = d[2] + e[0];
            b3 = d[3] - e[1];
            d[2] = b2 + b0;
            d[3] = b3 + b1;
            e[0] = b2 - b0;
            e[1] = b1 - b3;
            C += 4;
            d += 4;
            e -= 4;
        }
    }
    {
        f32* d0;
        f32* d1;
        f32* d2;
        f32* d3;
        f32* B = f.B[blocktype] + n2 - 8;
        f32* e = buf2 + n2 - 8;
        d0 = &buffer[0];
        d1 = &buffer[n2 - 4];
        d2 = &buffer[n2];
        d3 = &buffer[n - 4];
        while e >= v {
            f32 p0;
            f32 p1;
            f32 p2;
            f32 p3;
            p3 = e[6] * B[7] - e[7] * B[6];
            p2 = -e[6] * B[6] - e[7] * B[7];
            d0[0] = p3;
            d1[3] = -p3;
            d2[0] = p2;
            d3[3] = p2;
            p1 = e[4] * B[5] - e[5] * B[4];
            p0 = -e[4] * B[4] - e[5] * B[5];
            d0[1] = p1;
            d1[2] = -p1;
            d2[1] = p0;
            d3[2] = p0;
            p3 = e[2] * B[3] - e[3] * B[2];
            p2 = -e[2] * B[2] - e[3] * B[3];
            d0[2] = p3;
            d1[1] = -p3;
            d2[2] = p2;
            d3[1] = p2;
            p1 = e[0] * B[1] - e[1] * B[0];
            p0 = -e[0] * B[0] - e[1] * B[1];
            d0[3] = p1;
            d1[0] = -p1;
            d2[3] = p0;
            d3[0] = p0;
            B -= 8;
            e -= 8;
            d0 += 4;
            d2 += 4;
            d1 -= 4;
            d3 -= 4;
        }
    }
    setup_temp_free(f, buf2, 0);
    f.temp_offset = save_point;
}

f32* get_window(vorb* f, i32 len) {
    len <<= 1;
    if len == f.blocksize_0 {
        return f.window[0];
    }
    if len == f.blocksize_1 {
        return f.window[1];
    }
    return null;
}
}
when !(defined(STB_VORBIS_NO_DEFER_FLOOR)) {
} else {
}

private {
i32 do_floor(vorb* f, Mapping* map, i32 i, i32 n, f32* target, YTYPE* finalY, uint8* step2_flag) {
    i32 n2 = n >> 1;
    var s = cast(i32, map.chan[i].mux);
    i32 floor;
    floor = cast(i32, map.submap_floor[s]);
    if f.floor_types[floor] == 0 {
        return error(f, VORBIS_invalid_stream);
    } else {
        Floor1* g = &f.floor_config[floor].floor1;
        i32 j;
        i32 q;
        i32 lx = 0;
        i32 ly = finalY[0] * g.floor1_multiplier;
        for q = 1; q < g.values; ++q {
            j = cast(i32, g.sorted_order[q]);
            i32 stbv__use_point;
            when !(defined(STB_VORBIS_NO_DEFER_FLOOR)) {
                ignore step2_flag;
                stbv__use_point = finalY[j] >= 0;
            } else {
                stbv__use_point = cast(i32, step2_flag[j]);
            }
            if stbv__use_point != 0 {
                i32 hy = finalY[j] * g.floor1_multiplier;
                var hx = cast(i32, g.Xlist[j]);
                if lx != hx {
                    draw_line(target, lx, ly, hx, hy, n2);
                }
                lx = hx;
                ly = hy;
            }
        }
        if lx < n2 {
            for j = lx; j < n2; ++j {
                target[j] *= inverse_db_table[ly];
            }
        }
    }
    return 1;
}

// The meaning of "left" and "right"
//
// For a given frame:
//     we compute samples from 0..n
//     window_center is n/2
//     we'll window and mix the samples from left_start to left_end with data from the previous frame
//     all of the samples from left_end to right_start can be output without mixing; however,
//        this interval is 0-length except when transitioning between short and long frames
//     all of the samples from right_start to right_end need to be mixed with the next frame,
//        which we don't have, so those get saved in a buffer
//     frame N's right_end-right_start, the number of samples to mix with the next frame,
//        has to be the same as frame N+1's left_end-left_start (which they are by
//        construction)
i32 vorbis_decode_initial(vorb* f, i32* p_left_start, i32* p_left_end, i32* p_right_start, i32* p_right_end, i32* mode) {
    Mode* m;
    i32 i;
    i32 n;
    i32 prev;
    i32 next;
    i32 window_center;
    f.channel_buffer_end = 0;
    f.channel_buffer_start = f.channel_buffer_end;
    while true {
        if f.eof != 0 {
            return 0;
        }
        if maybe_start_packet(f) == 0 {
            return 0;
        }
        if get_bits(f, 1) != 0 {
            if 0 != 0 {
                return error(f, VORBIS_bad_packet_type);
            }
            while -1 != get8_packet(f) {
            }
            continue;
        }
        if f.alloc.alloc_buffer != null {
            assert(f.alloc.alloc_buffer_length_in_bytes == f.temp_offset);
        }
        i = cast(i32, get_bits(f, ilog(f.mode_count - 1)));
        if i == -1 {
            return 0;
        }
        if i >= f.mode_count {
            return 0;
        }
        *mode = i;
        m = f.mode_config + i;
        if m.blockflag != 0 {
            n = f.blocksize_1;
            prev = cast(i32, get_bits(f, 1));
            next = cast(i32, get_bits(f, 1));
        } else {
            next = 0;
            prev = next;
            n = f.blocksize_0;
        }
        window_center = n >> 1;
        if m.blockflag && !prev {
            *p_left_start = n - f.blocksize_0 >> 2;
            *p_left_end = n + f.blocksize_0 >> 2;
        } else {
            *p_left_start = 0;
            *p_left_end = window_center;
        }
        if m.blockflag && !next {
            *p_right_start = n * 3 - f.blocksize_0 >> 2;
            *p_right_end = n * 3 + f.blocksize_0 >> 2;
        } else {
            *p_right_start = window_center;
            *p_right_end = n;
        }
        return 1;
    }
}

i32 vorbis_decode_packet_rest(vorb* f, i32* len, Mode* m, i32 left_start, i32 left_end, i32 right_start, i32 right_end, i32* p_left) {
    Mapping* map;
    i32 i;
    i32 j;
    i32 k;
    i32 n;
    i32 n2;
    noinit i32[256] zero_channel;
    noinit i32[256] really_zero_channel;
    ignore left_end;
    n = f.blocksize[m.blockflag];
    map = &f.mapping[m.mapping];
    n2 = n >> 1;
    for i = 0; i < f.channels; ++i {
        var s = cast(i32, map.chan[i].mux);
        i32 floor;
        zero_channel[i] = 0;
        floor = cast(i32, map.submap_floor[s]);
        if f.floor_types[floor] == 0 {
            return error(f, VORBIS_invalid_stream);
        } else {
            Floor1* g = &f.floor_config[floor].floor1;
            i32 floor_err = 0;
            if get_bits(f, 1) != 0 {
                i16* finalY;
                noinit uint8[256] step2_flag;
                i32 range = vorbis_decode_packet_rest__range_list[g.floor1_multiplier - 1];
                i32 offset = 2;
                finalY = f.finalY[i];
                finalY[0] = cast(i16, get_bits(f, ilog(range) - 1));
                finalY[1] = cast(i16, get_bits(f, ilog(range) - 1));
                for j = 0; j < cast(i32, g.partitions); ++j {
                    var pclass = cast(i32, g.partition_class_list[j]);
                    var cdim = cast(i32, g.class_dimensions[pclass]);
                    var cbits = cast(i32, g.class_subclasses[pclass]);
                    i32 csub = (1 << cbits) - 1;
                    i32 cval = 0;
                    if cbits != 0 {
                        Codebook* c = f.codebooks + g.class_masterbooks[pclass];
                        if f.valid_bits < 10 {
                            prep_huffman(f);
                        }
                        cval = cast(i32, f.acc & cast(u32, (1 << 10) - 1));
                        cval = c.fast_huffman[cval];
                        if cval >= 0 {
                            var n = cast(i32, c.codeword_lengths[cval]);
                            f.acc >>= cast(uint32, n);
                            f.valid_bits -= n;
                            if f.valid_bits < 0 {
                                f.valid_bits = 0;
                                cval = -1;
                            }
                        } else {
                            cval = codebook_decode_scalar_raw(f, c);
                        }
                        if c.sparse != 0 {
                            cval = c.sorted_values[cval];
                        }
                    }
                    for k = 0; k < cdim; ++k {
                        i32 book = g.subclass_books[pclass][cval & csub];
                        cval = cval >> cbits;
                        if book >= 0 {
                            i32 temp;
                            Codebook* c = f.codebooks + book;
                            if f.valid_bits < 10 {
                                prep_huffman(f);
                            }
                            temp = cast(i32, f.acc & cast(u32, (1 << 10) - 1));
                            temp = c.fast_huffman[temp];
                            if temp >= 0 {
                                var n = cast(i32, c.codeword_lengths[temp]);
                                f.acc >>= cast(uint32, n);
                                f.valid_bits -= n;
                                if f.valid_bits < 0 {
                                    f.valid_bits = 0;
                                    temp = -1;
                                }
                            } else {
                                temp = codebook_decode_scalar_raw(f, c);
                            }
                            if c.sparse != 0 {
                                temp = c.sorted_values[temp];
                            }
                            finalY[offset++] = cast(i16, temp);
                        } else {
                            finalY[offset++] = 0;
                        }
                    }
                }
                if f.valid_bits == -1 {
                    floor_err = 1;
                }
                if floor_err == 0 {
                    step2_flag[1] = 1;
                    step2_flag[0] = step2_flag[1];
                    for j = 2; j < g.values; ++j {
                        i32 low;
                        i32 high;
                        i32 pred;
                        i32 highroom;
                        i32 lowroom;
                        i32 room;
                        i32 val;
                        low = cast(i32, g.neighbors[j][0]);
                        high = cast(i32, g.neighbors[j][1]);
                        pred = predict_point(cast(i32, g.Xlist[j]), cast(i32, g.Xlist[low]), cast(i32, g.Xlist[high]), finalY[low], finalY[high]);
                        val = finalY[j];
                        highroom = range - pred;
                        lowroom = pred;
                        if highroom < lowroom {
                            room = highroom * 2;
                        } else {
                            room = lowroom * 2;
                        }
                        if val != 0 {
                            step2_flag[high] = 1;
                            step2_flag[low] = step2_flag[high];
                            step2_flag[j] = 1;
                            if val >= room {
                                if highroom > lowroom {
                                    finalY[j] = cast(i16, val - lowroom + pred);
                                } else {
                                    finalY[j] = cast(i16, pred - val + highroom - 1);
                                }
                            } else if (val & 1) != 0 {
                                finalY[j] = cast(i16, pred - (val + 1 >> 1));
                            } else {
                                finalY[j] = cast(i16, pred + (val >> 1));
                            }
                        } else {
                            step2_flag[j] = 0;
                            finalY[j] = cast(i16, pred);
                        }
                    }
                    when defined(STB_VORBIS_NO_DEFER_FLOOR) {
                        do_floor(f, map, i, n, f.floor_buffers[i], finalY, step2_flag);
                    } else {
                        for j = 0; j < g.values; ++j {
                            if step2_flag[j] == 0 {
                                finalY[j] = -1;
                            }
                        }
                    }
                }
            } else {
                floor_err = 1;
            }
            if floor_err != 0 {
                zero_channel[i] = 1;
            }
        }
    }
    if f.alloc.alloc_buffer != null {
        assert(f.alloc.alloc_buffer_length_in_bytes == f.temp_offset);
    }
    memcpy(really_zero_channel, zero_channel, cast(u64, sizeof(really_zero_channel[0]) * f.channels));
    for i = 0; i < cast(i32, map.coupling_steps); ++i {
        if !zero_channel[map.chan[i].magnitude] || !zero_channel[map.chan[i].angle] {
            zero_channel[map.chan[i].angle] = 0;
            zero_channel[map.chan[i].magnitude] = zero_channel[map.chan[i].angle];
        }
    }
    for i = 0; i < cast(i32, map.submaps); ++i {
        noinit f32*[16] residue_buffers;
        i32 r;
        noinit uint8[256] do_not_decode;
        i32 ch = 0;
        for j = 0; j < f.channels; ++j {
            if cast(i32, map.chan[j].mux) == i {
                if zero_channel[j] != 0 {
                    do_not_decode[ch] = 1;
                    residue_buffers[ch] = null;
                } else {
                    do_not_decode[ch] = 0;
                    residue_buffers[ch] = f.channel_buffers[j];
                }
                ++ch;
            }
        }
        r = cast(i32, map.submap_residue[i]);
        decode_residue(f, residue_buffers, ch, n2, r, do_not_decode);
    }
    if f.alloc.alloc_buffer != null {
        assert(f.alloc.alloc_buffer_length_in_bytes == f.temp_offset);
    }
    for i = cast(i32, map.coupling_steps - 1); i >= 0; --i {
        i32 n2 = n >> 1;
        f32* m = f.channel_buffers[map.chan[i].magnitude];
        f32* a = f.channel_buffers[map.chan[i].angle];
        for j = 0; j < n2; ++j {
            f32 a2;
            f32 m2;
            if m[j] > 0.0f {
                if a[j] > 0.0f {
                    m2 = m[j];
                    a2 = m[j] - a[j];
                } else {
                    a2 = m[j];
                    m2 = m[j] + a[j];
                }
            } else if a[j] > 0.0f {
                m2 = m[j];
                a2 = m[j] + a[j];
            } else {
                a2 = m[j];
                m2 = m[j] - a[j];
            }
            m[j] = m2;
            a[j] = a2;
        }
    }
    when !(defined(STB_VORBIS_NO_DEFER_FLOOR)) {
        for i = 0; i < f.channels; ++i {
            if really_zero_channel[i] != 0 {
                memset(f.channel_buffers[i], 0, cast(u64, sizeof(*f.channel_buffers[i]) * n2));
            } else {
                do_floor(f, map, i, n, f.channel_buffers[i], f.finalY[i], null);
            }
        }
    } else {
        for i = 0; i < f.channels; ++i {
            if really_zero_channel[i] != 0 {
                memset(f.channel_buffers[i], 0, cast(u64, sizeof(*f.channel_buffers[i]) * n2));
            } else {
                for j = 0; j < n2; ++j {
                    f.channel_buffers[i][j] *= f.floor_buffers[i][j];
                }
            }
        }
    }
    for i = 0; i < f.channels; ++i {
        inverse_mdct(f.channel_buffers[i], n, f, cast(i32, m.blockflag));
    }
    flush_packet(f);
    if f.first_decode != 0 {
        f.current_loc = cast(uint32, 0 - n2);
        f.discard_samples_deferred = n - right_end;
        f.current_loc_valid = 1;
        f.first_decode = 0;
    } else if f.discard_samples_deferred != 0 {
        if f.discard_samples_deferred >= right_start - left_start {
            f.discard_samples_deferred -= right_start - left_start;
            left_start = right_start;
            *p_left = left_start;
        } else {
            left_start += f.discard_samples_deferred;
            *p_left = left_start;
            f.discard_samples_deferred = 0;
        }
    } else if f.previous_length == 0 && f.current_loc_valid {
    }
    if f.last_seg_which == f.end_seg_with_known_loc {
        if f.current_loc_valid && f.page_flag & 4 {
            uint32 current_end = f.known_loc_for_packet;
            if current_end < f.current_loc + cast(u32, right_end - left_start) {
                if current_end < f.current_loc {
                    *len = 0;
                } else {
                    *len = cast(i32, current_end - f.current_loc);
                }
                *len += left_start;
                if *len > right_end {
                    *len = right_end;
                }
                f.current_loc += cast(uint32, *len);
                return 1;
            }
        }
        f.current_loc = f.known_loc_for_packet - cast(u32, n2 - left_start);
        f.current_loc_valid = 1;
    }
    if f.current_loc_valid != 0 {
        f.current_loc += cast(uint32, right_start - left_start);
    }
    if f.alloc.alloc_buffer != null {
        assert(f.alloc.alloc_buffer_length_in_bytes == f.temp_offset);
    }
    *len = right_end;
    return 1;
}

i32 vorbis_decode_packet(vorb* f, i32* len, i32* p_left, i32* p_right) {
    i32 mode;
    i32 left_end;
    i32 right_end;
    if vorbis_decode_initial(f, p_left, &left_end, p_right, &right_end, &mode) == 0 {
        return 0;
    }
    return vorbis_decode_packet_rest(f, len, f.mode_config + mode, *p_left, left_end, *p_right, right_end, p_left);
}

i32 vorbis_finish_frame(stb_vorbis* f, i32 len, i32 left, i32 right) {
    i32 prev;
    i32 i;
    i32 j;
    if f.previous_length != 0 {
        i32 i;
        i32 j;
        i32 n = f.previous_length;
        f32* w = get_window(f, n);
        if w == null {
            return 0;
        }
        for i = 0; i < f.channels; ++i {
            for j = 0; j < n; ++j {
                f.channel_buffers[i][left + j] = f.channel_buffers[i][left + j] * w[j] + f.previous_window[i][j] * w[n - 1 - j];
            }
        }
    }
    prev = f.previous_length;
    f.previous_length = len - right;
    for i = 0; i < f.channels; ++i {
        for j = 0; right + j < len; ++j {
            f.previous_window[i][j] = f.channel_buffers[i][right + j];
        }
    }
    if prev == 0 {
        return 0;
    }
    if len < right {
        right = len;
    }
    f.samples_output += cast(uint32, right - left);
    return right - left;
}

i32 vorbis_pump_first_frame(stb_vorbis* f) {
    i32 len;
    i32 right;
    i32 left;
    i32 res;
    res = vorbis_decode_packet(f, &len, &left, &right);
    if res != 0 {
        vorbis_finish_frame(f, len, left, right);
    }
    return res;
}

i32 start_decoder(vorb* f) {
    noinit uint8[6] header;
    uint8 x;
    uint8 y;
    i32 len;
    i32 i;
    i32 j;
    i32 k;
    i32 max_submaps = 0;
    i32 longest_floorlist = 0;
    f.first_decode = 1;
    if start_page(f) == 0 {
        return 0;
    }
    if (f.page_flag & 2) == 0 {
        return error(f, VORBIS_invalid_first_page);
    }
    if (f.page_flag & 4) != 0 {
        return error(f, VORBIS_invalid_first_page);
    }
    if (f.page_flag & 1) != 0 {
        return error(f, VORBIS_invalid_first_page);
    }
    if f.segment_count != 1 {
        return error(f, VORBIS_invalid_first_page);
    }
    if f.segments[0] != 30 {
        if f.segments[0] == 64 && getn(f, header, 6) && header[0] == 102 && header[1] == 105 && header[2] == 115 && header[3] == 104 && header[4] == 101 && header[5] == 97 && get8(f) == 100 && get8(f) == 0 {
            return error(f, VORBIS_ogg_skeleton_not_supported);
        } else {
            return error(f, VORBIS_invalid_first_page);
        }
    }
    if cast(i32, get8(f)) != VORBIS_packet_id {
        return error(f, VORBIS_invalid_first_page);
    }
    if getn(f, header, 6) == 0 {
        return error(f, VORBIS_unexpected_eof);
    }
    if vorbis_validate(header) == 0 {
        return error(f, VORBIS_invalid_first_page);
    }
    if get32(f) != 0 {
        return error(f, VORBIS_invalid_first_page);
    }
    f.channels = cast(i32, get8(f));
    if f.channels == 0 {
        return error(f, VORBIS_invalid_first_page);
    }
    if f.channels > 16 {
        return error(f, VORBIS_too_many_channels);
    }
    f.sample_rate = get32(f);
    if f.sample_rate == 0 {
        return error(f, VORBIS_invalid_first_page);
    }
    get32(f);
    get32(f);
    get32(f);
    x = get8(f);
    {
        i32 log0;
        i32 log1;
        log0 = cast(i32, x & 15);
        log1 = cast(i32, x) >> 4;
        f.blocksize_0 = 1 << log0;
        f.blocksize_1 = 1 << log1;
        if log0 < 6 || log0 > 13 {
            return error(f, VORBIS_invalid_setup);
        }
        if log1 < 6 || log1 > 13 {
            return error(f, VORBIS_invalid_setup);
        }
        if log0 > log1 {
            return error(f, VORBIS_invalid_setup);
        }
    }
    x = get8(f);
    if (x & 1) == 0 {
        return error(f, VORBIS_invalid_first_page);
    }
    if start_page(f) == 0 {
        return 0;
    }
    if start_packet(f) == 0 {
        return 0;
    }
    if next_segment(f) == 0 {
        return 0;
    }
    if get8_packet(f) != VORBIS_packet_comment {
        return error(f, VORBIS_invalid_setup);
    }
    for i = 0; i < 6; ++i {
        header[i] = cast(uint8, get8_packet(f));
    }
    if vorbis_validate(header) == 0 {
        return error(f, VORBIS_invalid_setup);
    }
    len = get32_packet(f);
    f.vendor = cast(u8*, setup_malloc(f, cast(i32, sizeof(u8) * (len + 1))));
    if f.vendor == null {
        return error(f, VORBIS_outofmem);
    }
    for i = 0; i < len; ++i {
        f.vendor[i] = cast(u8, get8_packet(f));
    }
    f.vendor[len] = 0;
    f.comment_list_length = get32_packet(f);
    f.comment_list = null;
    if f.comment_list_length > 0 {
        f.comment_list = cast(u8**, setup_malloc(f, cast(i32, sizeof(u8*) * f.comment_list_length)));
        if f.comment_list == null {
            return error(f, VORBIS_outofmem);
        }
    }
    for i = 0; i < f.comment_list_length; ++i {
        len = get32_packet(f);
        f.comment_list[i] = cast(u8*, setup_malloc(f, cast(i32, sizeof(u8) * (len + 1))));
        if f.comment_list[i] == null {
            return error(f, VORBIS_outofmem);
        }
        for j = 0; j < len; ++j {
            f.comment_list[i][j] = cast(u8, get8_packet(f));
        }
        f.comment_list[i][len] = 0;
    }
    x = cast(u8, get8_packet(f));
    if (x & 1) == 0 {
        return error(f, VORBIS_invalid_setup);
    }
    skip(f, cast(i32, f.bytes_in_seg));
    f.bytes_in_seg = 0;
    while true {
        len = next_segment(f);
        skip(f, len);
        f.bytes_in_seg = 0;
        if !(len != 0) { break; }
    }
    if start_packet(f) == 0 {
        return 0;
    }
    crc32_init();
    if get8_packet(f) != VORBIS_packet_setup {
        return error(f, VORBIS_invalid_setup);
    }
    for i = 0; i < 6; ++i {
        header[i] = cast(uint8, get8_packet(f));
    }
    if vorbis_validate(header) == 0 {
        return error(f, VORBIS_invalid_setup);
    }
    f.codebook_count = cast(i32, get_bits(f, 8) + 1);
    f.codebooks = cast(Codebook*, setup_malloc(f, cast(i32, sizeof(*f.codebooks) * f.codebook_count)));
    if f.codebooks == null {
        return error(f, VORBIS_outofmem);
    }
    memset(f.codebooks, 0, cast(u64, sizeof(*f.codebooks) * f.codebook_count));
    for i = 0; i < f.codebook_count; ++i {
        uint32* values;
        i32 ordered;
        i32 sorted_count;
        i32 total = 0;
        uint8* lengths;
        Codebook* c = f.codebooks + i;
        x = cast(u8, get_bits(f, 8));
        if x != 0x42 {
            return error(f, VORBIS_invalid_setup);
        }
        x = cast(u8, get_bits(f, 8));
        if x != 0x43 {
            return error(f, VORBIS_invalid_setup);
        }
        x = cast(u8, get_bits(f, 8));
        if x != 0x56 {
            return error(f, VORBIS_invalid_setup);
        }
        x = cast(u8, get_bits(f, 8));
        c.dimensions = cast(i32, (get_bits(f, 8) << 8) + x);
        x = cast(u8, get_bits(f, 8));
        y = cast(u8, get_bits(f, 8));
        c.entries = cast(i32, (get_bits(f, 8) << 16) + cast(u32, cast(i32, y) << 8) + x);
        ordered = cast(i32, get_bits(f, 1));
        c.sparse = cast(uint8, ordered != 0 ? 0 : get_bits(f, 1));
        if c.dimensions == 0 && c.entries != 0 {
            return error(f, VORBIS_invalid_setup);
        }
        if c.sparse != 0 {
            lengths = cast(uint8*, setup_temp_malloc(f, c.entries));
        } else {
            c.codeword_lengths = cast(uint8*, setup_malloc(f, c.entries));
            lengths = c.codeword_lengths;
        }
        if lengths == null {
            return error(f, VORBIS_outofmem);
        }
        if ordered != 0 {
            i32 current_entry = 0;
            var current_length = cast(i32, get_bits(f, 5) + 1);
            while current_entry < c.entries {
                i32 limit = c.entries - current_entry;
                var n = cast(i32, get_bits(f, ilog(limit)));
                if current_length >= 32 {
                    return error(f, VORBIS_invalid_setup);
                }
                if current_entry + n > c.entries {
                    return error(f, VORBIS_invalid_setup);
                }
                memset(lengths + current_entry, current_length, cast(u64, n));
                current_entry += n;
                ++current_length;
            }
        } else {
            for j = 0; j < c.entries; ++j {
                var present = cast(i32, c.sparse != 0 ? get_bits(f, 1) : 1);
                if present != 0 {
                    lengths[j] = cast(uint8, get_bits(f, 5) + 1);
                    ++total;
                    if lengths[j] == 32 {
                        return error(f, VORBIS_invalid_setup);
                    }
                } else {
                    lengths[j] = 255;
                }
            }
        }
        if c.sparse && total >= c.entries >> 2 {
            if c.entries > cast(i32, f.setup_temp_memory_required) {
                f.setup_temp_memory_required = cast(u32, c.entries);
            }
            c.codeword_lengths = cast(uint8*, setup_malloc(f, c.entries));
            if c.codeword_lengths == null {
                return error(f, VORBIS_outofmem);
            }
            memcpy(c.codeword_lengths, lengths, cast(u64, c.entries));
            setup_temp_free(f, lengths, c.entries);
            lengths = c.codeword_lengths;
            c.sparse = 0;
        }
        if c.sparse != 0 {
            sorted_count = total;
        } else {
            sorted_count = 0;
            when !(defined(STB_VORBIS_NO_HUFFMAN_BINARY_SEARCH)) {
                for j = 0; j < c.entries; ++j {
                    if lengths[j] > 10 && lengths[j] != 255 {
                        ++sorted_count;
                    }
                }
            }
        }
        c.sorted_entries = sorted_count;
        values = null;
        if c.sparse == 0 {
            c.codewords = cast(uint32*, setup_malloc(f, cast(i32, sizeof(c.codewords[0]) * c.entries)));
            if c.codewords == null {
                return error(f, VORBIS_outofmem);
            }
        } else {
            u32 size;
            if c.sorted_entries != 0 {
                c.codeword_lengths = cast(uint8*, setup_malloc(f, c.sorted_entries));
                if c.codeword_lengths == null {
                    return error(f, VORBIS_outofmem);
                }
                c.codewords = cast(uint32*, setup_temp_malloc(f, cast(i32, sizeof(*c.codewords) * c.sorted_entries)));
                if c.codewords == null {
                    return error(f, VORBIS_outofmem);
                }
                values = cast(uint32*, setup_temp_malloc(f, cast(i32, sizeof(*values) * c.sorted_entries)));
                if values == null {
                    return error(f, VORBIS_outofmem);
                }
            }
            size = cast(u32, c.entries + (sizeof(*c.codewords) + sizeof(*values)) * c.sorted_entries);
            if size > f.setup_temp_memory_required {
                f.setup_temp_memory_required = size;
            }
        }
        if compute_codewords(c, lengths, c.entries, values) == 0 {
            if c.sparse != 0 {
                setup_temp_free(f, values, 0);
            }
            return error(f, VORBIS_invalid_setup);
        }
        if c.sorted_entries != 0 {
            c.sorted_codewords = cast(uint32*, setup_malloc(f, cast(i32, sizeof(*c.sorted_codewords) * (c.sorted_entries + 1))));
            if c.sorted_codewords == null {
                return error(f, VORBIS_outofmem);
            }
            c.sorted_values = cast(i32*, setup_malloc(f, cast(i32, sizeof(*c.sorted_values) * (c.sorted_entries + 1))));
            if c.sorted_values == null {
                return error(f, VORBIS_outofmem);
            }
            ++c.sorted_values;
            c.sorted_values[-1] = -1;
            compute_sorted_huffman(c, lengths, values);
        }
        if c.sparse != 0 {
            setup_temp_free(f, values, cast(i32, sizeof(*values) * c.sorted_entries));
            setup_temp_free(f, c.codewords, cast(i32, sizeof(*c.codewords) * c.sorted_entries));
            setup_temp_free(f, lengths, c.entries);
            c.codewords = null;
        }
        compute_accelerated_huffman(c);
        c.lookup_type = cast(uint8, get_bits(f, 4));
        if c.lookup_type > 2 {
            return error(f, VORBIS_invalid_setup);
        }
        if c.lookup_type > 0 {
            uint16* mults;
            c.minimum_value = float32_unpack(get_bits(f, 32));
            c.delta_value = float32_unpack(get_bits(f, 32));
            c.value_bits = cast(uint8, get_bits(f, 4) + 1);
            c.sequence_p = cast(uint8, get_bits(f, 1));
            if c.lookup_type == 1 {
                i32 values = lookup1_values(c.entries, c.dimensions);
                if values < 0 {
                    return error(f, VORBIS_invalid_setup);
                }
                c.lookup_values = cast(uint32, values);
            } else {
                c.lookup_values = cast(uint32, c.entries * c.dimensions);
            }
            if c.lookup_values == 0 {
                return error(f, VORBIS_invalid_setup);
            }
            mults = cast(uint16*, setup_temp_malloc(f, cast(i32, sizeof(mults[0]) * c.lookup_values)));
            if mults == null {
                return error(f, VORBIS_outofmem);
            }
            for j = 0; j < cast(i32, c.lookup_values); ++j {
                var q = cast(i32, get_bits(f, cast(i32, c.value_bits)));
                if q == -1 {
                    setup_temp_free(f, mults, cast(i32, sizeof(mults[0]) * c.lookup_values));
                    return error(f, VORBIS_invalid_setup);
                }
                mults[j] = cast(uint16, q);
            }
            if c.lookup_type == 1 {
                i32 len;
                var sparse = cast(i32, c.sparse);
                f32 last = 0.0f;
                if !sparse || c.sorted_entries != 0 {
                    if sparse != 0 {
                        c.multiplicands = cast(codetype*, setup_malloc(f, cast(i32, sizeof(c.multiplicands[0]) * c.sorted_entries * c.dimensions)));
                    } else {
                        c.multiplicands = cast(codetype*, setup_malloc(f, cast(i32, sizeof(c.multiplicands[0]) * c.entries * c.dimensions)));
                    }
                    if c.multiplicands == null {
                        setup_temp_free(f, mults, cast(i32, sizeof(mults[0]) * c.lookup_values));
                        return error(f, VORBIS_outofmem);
                    }
                    len = sparse != 0 ? c.sorted_entries : c.entries;
                    for j = 0; j < len; ++j {
                        var z = cast(u32, sparse != 0 ? c.sorted_values[j] : j);
                        u32 div = 1;
                        for k = 0; k < c.dimensions; ++k {
                            var off = cast(i32, z / div % c.lookup_values);
                            f32 val = cast(f32, mults[off]) * c.delta_value + c.minimum_value + last;
                            c.multiplicands[j * c.dimensions + k] = val;
                            if c.sequence_p != 0 {
                                last = val;
                            }
                            if k + 1 < c.dimensions {
                                if div > UINT_MAX / cast(u32, c.lookup_values) {
                                    setup_temp_free(f, mults, cast(i32, sizeof(mults[0]) * c.lookup_values));
                                    return error(f, VORBIS_invalid_setup);
                                }
                                div *= c.lookup_values;
                            }
                        }
                    }
                    c.lookup_type = 2;
                }
            } else {
                f32 last = 0.0f;
                c.multiplicands = cast(codetype*, setup_malloc(f, cast(i32, sizeof(c.multiplicands[0]) * c.lookup_values)));
                if c.multiplicands == null {
                    setup_temp_free(f, mults, cast(i32, sizeof(mults[0]) * c.lookup_values));
                    return error(f, VORBIS_outofmem);
                }
                for j = 0; j < cast(i32, c.lookup_values); ++j {
                    f32 val = cast(f32, mults[j]) * c.delta_value + c.minimum_value + last;
                    c.multiplicands[j] = val;
                    if c.sequence_p != 0 {
                        last = val;
                    }
                }
            }
            setup_temp_free(f, mults, cast(i32, sizeof(mults[0]) * c.lookup_values));
        }
    }
    x = cast(u8, get_bits(f, 6) + 1);
    for i = 0; i < cast(i32, x); ++i {
        uint32 z = get_bits(f, 16);
        if z != 0 {
            return error(f, VORBIS_invalid_setup);
        }
    }
    f.floor_count = cast(i32, get_bits(f, 6) + 1);
    f.floor_config = cast(Floor*, setup_malloc(f, cast(i32, f.floor_count * sizeof(*f.floor_config))));
    if f.floor_config == null {
        return error(f, VORBIS_outofmem);
    }
    for i = 0; i < f.floor_count; ++i {
        f.floor_types[i] = cast(uint16, get_bits(f, 16));
        if f.floor_types[i] > 1 {
            return error(f, VORBIS_invalid_setup);
        }
        if f.floor_types[i] == 0 {
            Floor0* g = &f.floor_config[i].floor0;
            g.order = cast(uint8, get_bits(f, 8));
            g.rate = cast(uint16, get_bits(f, 16));
            g.bark_map_size = cast(uint16, get_bits(f, 16));
            g.amplitude_bits = cast(uint8, get_bits(f, 6));
            g.amplitude_offset = cast(uint8, get_bits(f, 8));
            g.number_of_books = cast(uint8, get_bits(f, 4) + 1);
            for j = 0; j < cast(i32, g.number_of_books); ++j {
                g.book_list[j] = cast(uint8, get_bits(f, 8));
            }
            return error(f, VORBIS_feature_not_supported);
        } else {
            noinit stbv__floor_ordering[31 * 8 + 2] p;
            Floor1* g = &f.floor_config[i].floor1;
            i32 max_class = -1;
            g.partitions = cast(uint8, get_bits(f, 5));
            for j = 0; j < cast(i32, g.partitions); ++j {
                g.partition_class_list[j] = cast(uint8, get_bits(f, 4));
                if cast(i32, g.partition_class_list[j]) > max_class {
                    max_class = cast(i32, g.partition_class_list[j]);
                }
            }
            for j = 0; j <= max_class; ++j {
                g.class_dimensions[j] = cast(uint8, get_bits(f, 3) + 1);
                g.class_subclasses[j] = cast(uint8, get_bits(f, 2));
                if g.class_subclasses[j] != 0 {
                    g.class_masterbooks[j] = cast(uint8, get_bits(f, 8));
                    if cast(i32, g.class_masterbooks[j]) >= f.codebook_count {
                        return error(f, VORBIS_invalid_setup);
                    }
                }
                for k = 0; k < 1 << cast(i32, g.class_subclasses[j]); ++k {
                    g.subclass_books[j][k] = cast(int16, cast(int16, get_bits(f, 8)) - 1);
                    if g.subclass_books[j][k] >= f.codebook_count {
                        return error(f, VORBIS_invalid_setup);
                    }
                }
            }
            g.floor1_multiplier = cast(uint8, get_bits(f, 2) + 1);
            g.rangebits = cast(uint8, get_bits(f, 4));
            g.Xlist[0] = 0;
            g.Xlist[1] = cast(uint16, 1 << cast(i32, g.rangebits));
            g.values = 2;
            for j = 0; j < cast(i32, g.partitions); ++j {
                var c = cast(i32, g.partition_class_list[j]);
                for k = 0; k < cast(i32, g.class_dimensions[c]); ++k {
                    g.Xlist[g.values] = cast(uint16, get_bits(f, cast(i32, g.rangebits)));
                    ++g.values;
                }
            }
            for j = 0; j < g.values; ++j {
                p[j].x = g.Xlist[j];
                p[j].id = cast(uint16, j);
            }
            qsort(p, g.values, sizeof(p[0]), point_compare);
            for j = 0; j < g.values - 1; ++j {
                if p[j].x == p[j + 1].x {
                    return error(f, VORBIS_invalid_setup);
                }
            }
            for j = 0; j < g.values; ++j {
                g.sorted_order[j] = cast(uint8, p[j].id);
            }
            for j = 2; j < g.values; ++j {
                i32 low = 0;
                i32 hi = 0;
                neighbors(g.Xlist, j, &low, &hi);
                g.neighbors[j][0] = cast(uint8, low);
                g.neighbors[j][1] = cast(uint8, hi);
            }
            if g.values > longest_floorlist {
                longest_floorlist = g.values;
            }
        }
    }
    f.residue_count = cast(i32, get_bits(f, 6) + 1);
    f.residue_config = cast(Residue*, setup_malloc(f, cast(i32, f.residue_count * sizeof(f.residue_config[0]))));
    if f.residue_config == null {
        return error(f, VORBIS_outofmem);
    }
    memset(f.residue_config, 0, cast(u64, f.residue_count * sizeof(f.residue_config[0])));
    for i = 0; i < f.residue_count; ++i {
        noinit uint8[64] residue_cascade;
        Residue* r = f.residue_config + i;
        f.residue_types[i] = cast(uint16, get_bits(f, 16));
        if f.residue_types[i] > 2 {
            return error(f, VORBIS_invalid_setup);
        }
        r.begin = get_bits(f, 24);
        r.end = get_bits(f, 24);
        if r.end < r.begin {
            return error(f, VORBIS_invalid_setup);
        }
        r.part_size = get_bits(f, 24) + 1;
        r.classifications = cast(uint8, get_bits(f, 6) + 1);
        r.classbook = cast(uint8, get_bits(f, 8));
        if cast(i32, r.classbook) >= f.codebook_count {
            return error(f, VORBIS_invalid_setup);
        }
        for j = 0; j < cast(i32, r.classifications); ++j {
            uint8 high_bits = 0;
            var low_bits = cast(uint8, get_bits(f, 3));
            if get_bits(f, 1) != 0 {
                high_bits = cast(u8, get_bits(f, 5));
            }
            residue_cascade[j] = cast(uint8, high_bits * 8 + low_bits);
        }
        r.residue_books = setup_malloc(f, cast(i32, sizeof(int16) * 8 * r.classifications));
        if r.residue_books == null {
            return error(f, VORBIS_outofmem);
        }
        for j = 0; j < cast(i32, r.classifications); ++j {
            for k = 0; k < 8; ++k {
                if (residue_cascade[j] & 1 << k) != 0 {
                    r.residue_books[j * 8 + k] = cast(int16, get_bits(f, 8));
                    if r.residue_books[j * 8 + k] >= f.codebook_count {
                        return error(f, VORBIS_invalid_setup);
                    }
                } else {
                    r.residue_books[j * 8 + k] = cast(int16, -1);
                }
            }
        }
        r.classdata = cast(uint8**, setup_malloc(f, cast(i32, sizeof(*r.classdata) * f.codebooks[r.classbook].entries)));
        if r.classdata == null {
            return error(f, VORBIS_outofmem);
        }
        memset(r.classdata, 0, cast(u64, sizeof(*r.classdata) * f.codebooks[r.classbook].entries));
        for j = 0; j < f.codebooks[r.classbook].entries; ++j {
            i32 classwords = f.codebooks[r.classbook].dimensions;
            i32 temp = j;
            r.classdata[j] = cast(uint8*, setup_malloc(f, cast(i32, sizeof(r.classdata[j][0]) * classwords)));
            if r.classdata[j] == null {
                return error(f, VORBIS_outofmem);
            }
            for k = classwords - 1; k >= 0; --k {
                r.classdata[j][k] = cast(uint8, temp % r.classifications);
                temp /= cast(i32, r.classifications);
            }
        }
    }
    f.mapping_count = cast(i32, get_bits(f, 6) + 1);
    f.mapping = cast(Mapping*, setup_malloc(f, cast(i32, f.mapping_count * sizeof(*f.mapping))));
    if f.mapping == null {
        return error(f, VORBIS_outofmem);
    }
    memset(f.mapping, 0, cast(u64, f.mapping_count * sizeof(*f.mapping)));
    for i = 0; i < f.mapping_count; ++i {
        Mapping* m = f.mapping + i;
        var mapping_type = cast(i32, get_bits(f, 16));
        if mapping_type != 0 {
            return error(f, VORBIS_invalid_setup);
        }
        m.chan = cast(MappingChannel*, setup_malloc(f, cast(i32, f.channels * sizeof(*m.chan))));
        if m.chan == null {
            return error(f, VORBIS_outofmem);
        }
        if get_bits(f, 1) != 0 {
            m.submaps = cast(uint8, get_bits(f, 4) + 1);
        } else {
            m.submaps = 1;
        }
        if cast(i32, m.submaps) > max_submaps {
            max_submaps = cast(i32, m.submaps);
        }
        if get_bits(f, 1) != 0 {
            m.coupling_steps = cast(uint16, get_bits(f, 8) + 1);
            if cast(i32, m.coupling_steps) > f.channels {
                return error(f, VORBIS_invalid_setup);
            }
            for k = 0; k < cast(i32, m.coupling_steps); ++k {
                m.chan[k].magnitude = cast(uint8, get_bits(f, ilog(f.channels - 1)));
                m.chan[k].angle = cast(uint8, get_bits(f, ilog(f.channels - 1)));
                if cast(i32, m.chan[k].magnitude) >= f.channels {
                    return error(f, VORBIS_invalid_setup);
                }
                if cast(i32, m.chan[k].angle) >= f.channels {
                    return error(f, VORBIS_invalid_setup);
                }
                if m.chan[k].magnitude == m.chan[k].angle {
                    return error(f, VORBIS_invalid_setup);
                }
            }
        } else {
            m.coupling_steps = 0;
        }
        if get_bits(f, 2) != 0 {
            return error(f, VORBIS_invalid_setup);
        }
        if m.submaps > 1 {
            for j = 0; j < f.channels; ++j {
                m.chan[j].mux = cast(uint8, get_bits(f, 4));
                if m.chan[j].mux >= m.submaps {
                    return error(f, VORBIS_invalid_setup);
                }
            }
        } else {
            for j = 0; j < f.channels; ++j {
                m.chan[j].mux = 0;
            }
        }
        for j = 0; j < cast(i32, m.submaps); ++j {
            get_bits(f, 8);
            m.submap_floor[j] = cast(uint8, get_bits(f, 8));
            m.submap_residue[j] = cast(uint8, get_bits(f, 8));
            if cast(i32, m.submap_floor[j]) >= f.floor_count {
                return error(f, VORBIS_invalid_setup);
            }
            if cast(i32, m.submap_residue[j]) >= f.residue_count {
                return error(f, VORBIS_invalid_setup);
            }
        }
    }
    f.mode_count = cast(i32, get_bits(f, 6) + 1);
    for i = 0; i < f.mode_count; ++i {
        Mode* m = f.mode_config + i;
        m.blockflag = cast(uint8, get_bits(f, 1));
        m.windowtype = cast(uint16, get_bits(f, 16));
        m.transformtype = cast(uint16, get_bits(f, 16));
        m.mapping = cast(uint8, get_bits(f, 8));
        if m.windowtype != 0 {
            return error(f, VORBIS_invalid_setup);
        }
        if m.transformtype != 0 {
            return error(f, VORBIS_invalid_setup);
        }
        if cast(i32, m.mapping) >= f.mapping_count {
            return error(f, VORBIS_invalid_setup);
        }
    }
    flush_packet(f);
    f.previous_length = 0;
    for i = 0; i < f.channels; ++i {
        f.channel_buffers[i] = cast(f32*, setup_malloc(f, cast(i32, sizeof(f32) * f.blocksize_1)));
        f.previous_window[i] = cast(f32*, setup_malloc(f, cast(i32, sizeof(f32) * f.blocksize_1 / 2)));
        f.finalY[i] = cast(int16*, setup_malloc(f, cast(i32, sizeof(int16) * longest_floorlist)));
        if f.channel_buffers[i] == null || f.previous_window[i] == null || f.finalY[i] == null {
            return error(f, VORBIS_outofmem);
        }
        memset(f.channel_buffers[i], 0, cast(u64, sizeof(f32) * f.blocksize_1));
        when defined(STB_VORBIS_NO_DEFER_FLOOR) {
            f.floor_buffers[i] = cast(f32*, setup_malloc(f, cast(i32, sizeof(f32) * f.blocksize_1 / 2)));
            if f.floor_buffers[i] == null {
                return error(f, VORBIS_outofmem);
            }
        }
    }
    if init_blocksize(f, 0, f.blocksize_0) == 0 {
        return 0;
    }
    if init_blocksize(f, 1, f.blocksize_1) == 0 {
        return 0;
    }
    f.blocksize[0] = f.blocksize_0;
    f.blocksize[1] = f.blocksize_1;
    when defined(STB_VORBIS_DIVIDE_TABLE) {
        if integer_divide_table[1][1] == 0 {
            for i = 0; i < 32; ++i {
                for j = 1; j < 64; ++j {
                    integer_divide_table[i][j] = cast(int8, i / j);
                }
            }
        }
    }
    {
        var imdct_mem = cast(uint32, f.blocksize_1 * sizeof(f32) >> 1);
        uint32 classify_mem;
        i32 i;
        i32 max_part_read = 0;
        for i = 0; i < f.residue_count; ++i {
            Residue* r = f.residue_config + i;
            var actual_size = cast(u32, f.blocksize_1 / 2);
            u32 limit_r_begin = r.begin < actual_size ? r.begin : actual_size;
            u32 limit_r_end = r.end < actual_size ? r.end : actual_size;
            var n_read = cast(i32, limit_r_end - limit_r_begin);
            var part_read = cast(i32, cast(u32, n_read) / r.part_size);
            if part_read > max_part_read {
                max_part_read = part_read;
            }
        }
        when !(defined(STB_VORBIS_DIVIDES_IN_RESIDUE)) {
            classify_mem = cast(u32, f.channels * (sizeof(void*) + max_part_read * sizeof(uint8*)));
        } else {
            classify_mem = cast(u32, f.channels * (sizeof(void*) + max_part_read * sizeof(i32*)));
        }
        f.temp_memory_required = classify_mem;
        if imdct_mem > f.temp_memory_required {
            f.temp_memory_required = imdct_mem;
        }
    }
    if f.alloc.alloc_buffer != null {
        assert(f.temp_offset == f.alloc.alloc_buffer_length_in_bytes);
        if f.setup_offset + sizeof(*f) + f.temp_memory_required > cast(i64, cast(u32, f.temp_offset)) {
            return error(f, VORBIS_outofmem);
        }
    }
    if f.next_seg == -1 {
        f.first_audio_page_offset = stb_vorbis_get_file_offset(f);
    } else {
        f.first_audio_page_offset = 0;
    }
    return 1;
}

void vorbis_deinit(stb_vorbis* p) {
    i32 i;
    i32 j;
    setup_free(p, p.vendor);
    for i = 0; i < p.comment_list_length; ++i {
        setup_free(p, p.comment_list[i]);
    }
    setup_free(p, p.comment_list);
    if p.residue_config != null {
        for i = 0; i < p.residue_count; ++i {
            Residue* r = p.residue_config + i;
            if r.classdata != null {
                for j = 0; j < p.codebooks[r.classbook].entries; ++j {
                    setup_free(p, r.classdata[j]);
                }
                setup_free(p, r.classdata);
            }
            setup_free(p, r.residue_books);
        }
    }
    if p.codebooks != null {
        for i = 0; i < p.codebook_count; ++i {
            Codebook* c = p.codebooks + i;
            setup_free(p, c.codeword_lengths);
            setup_free(p, c.multiplicands);
            setup_free(p, c.codewords);
            setup_free(p, c.sorted_codewords);
            setup_free(p, c.sorted_values != null ? c.sorted_values - 1 : null);
        }
        setup_free(p, p.codebooks);
    }
    setup_free(p, p.floor_config);
    setup_free(p, p.residue_config);
    if p.mapping != null {
        for i = 0; i < p.mapping_count; ++i {
            setup_free(p, p.mapping[i].chan);
        }
        setup_free(p, p.mapping);
    }
    for i = 0; i < p.channels && i < 16; ++i {
        setup_free(p, p.channel_buffers[i]);
        setup_free(p, p.previous_window[i]);
        when defined(STB_VORBIS_NO_DEFER_FLOOR) {
            setup_free(p, p.floor_buffers[i]);
        }
        setup_free(p, p.finalY[i]);
    }
    for i = 0; i < 2; ++i {
        setup_free(p, p.A[i]);
        setup_free(p, p.B[i]);
        setup_free(p, p.C[i]);
        setup_free(p, p.window[i]);
        setup_free(p, p.bit_reverse[i]);
    }
}
}

void stb_vorbis_close(stb_vorbis* p) {
    if p == null {
        return;
    }
    vorbis_deinit(p);
    setup_free(p, p);
}

private {
void vorbis_init(stb_vorbis* p, stb_vorbis_alloc* z) {
    memset(p, 0, cast(u64, sizeof(*p)));
    if z != null {
        p.alloc = *z;
        p.alloc.alloc_buffer_length_in_bytes &= ~7;
        p.temp_offset = p.alloc.alloc_buffer_length_in_bytes;
    }
    p.eof = 0;
    p.error = VORBIS__no_error;
    p.stream = null;
    p.codebooks = null;
    p.page_crc_tests = -1;
}
}

i32 stb_vorbis_get_sample_offset(stb_vorbis* f) {
    if f.current_loc_valid != 0 {
        return cast(i32, f.current_loc);
    } else {
        return -1;
    }
}

stb_vorbis_info stb_vorbis_get_info(stb_vorbis* f) {
    noinit stb_vorbis_info d;
    d.channels = f.channels;
    d.sample_rate = f.sample_rate;
    d.setup_memory_required = f.setup_memory_required;
    d.setup_temp_memory_required = f.setup_temp_memory_required;
    d.temp_memory_required = f.temp_memory_required;
    d.max_frame_size = f.blocksize_1 >> 1;
    return d;
}

stb_vorbis_comment stb_vorbis_get_comment(stb_vorbis* f) {
    noinit stb_vorbis_comment d;
    d.vendor = f.vendor;
    d.comment_list_length = f.comment_list_length;
    d.comment_list = f.comment_list;
    return d;
}

i32 stb_vorbis_get_error(stb_vorbis* f) {
    i32 e = f.error;
    f.error = VORBIS__no_error;
    return e;
}

private {
stb_vorbis* vorbis_alloc(stb_vorbis* f) {
    var p = cast(stb_vorbis*, setup_malloc(f, cast(i32, sizeof(stb_vorbis))));
    return p;
}
}

u32 stb_vorbis_get_file_offset(stb_vorbis* f) {
    if 1 != 0 {
        return cast(u32, cast(i64, f.stream - f.stream_start));
    }
    return 0;
}
when !(defined(STB_VORBIS_NO_PULLDATA_API)) {

//
// DATA-PULLING API
//
private {
uint32 vorbis_find_page(stb_vorbis* f, uint32* end, uint32* last) {
    while true {
        i32 n;
        if f.eof != 0 {
            return 0;
        }
        n = cast(i32, get8(f));
        if n == 0x4f {
            u32 retry_loc = stb_vorbis_get_file_offset(f);
            i32 i;
            if retry_loc - 25 > f.stream_len {
                return 0;
            }
            for i = 1; i < 4; ++i {
                if get8(f) != ogg_page_header[i] {
                    break;
                }
            }
            if f.eof != 0 {
                return 0;
            }
            if i == 4 {
                noinit uint8[27] header;
                uint32 i;
                uint32 crc;
                uint32 goal;
                uint32 len;
                for i = 0; i < 4; ++i {
                    header[i] = ogg_page_header[i];
                }
                for ; i < 27; ++i {
                    header[i] = get8(f);
                }
                if f.eof != 0 {
                    return 0;
                }
                if header[4] == 0 {
                    goal = cast(u32, header[22] + (cast(i32, header[23]) << 8) + (cast(i32, header[24]) << 16)) + (cast(uint32, header[25]) << 24);
                    for i = 22; i < 26; ++i {
                        header[i] = 0;
                    }
                    crc = 0;
                    for i = 0; i < 27; ++i {
                        crc = crc32_update(crc, header[i]);
                    }
                    len = 0;
                    for i = 0; i < header[26]; ++i {
                        var s = cast(i32, get8(f));
                        crc = crc32_update(crc, cast(uint8, s));
                        len += cast(u32, s);
                    }
                    if len && f.eof {
                        return 0;
                    }
                    for i = 0; i < len; ++i {
                        crc = crc32_update(crc, get8(f));
                    }
                    if crc == goal {
                        if end != null {
                            *end = stb_vorbis_get_file_offset(f);
                        }
                        if last != null {
                            if (header[5] & 0x04) != 0 {
                                *last = 1;
                            } else {
                                *last = 0;
                            }
                        }
                        set_file_offset(f, retry_loc - 1);
                        return 1;
                    }
                }
            }
            set_file_offset(f, retry_loc);
        }
    }
}

// seeking is implemented with a binary search, which narrows down the range to
// 64K, before using a linear search (because finding the synchronization
// pattern can be expensive, and the chance we'd find the end page again is
// relatively high for small ranges)
//
// two initial interpolation-style probes are used at the start of the search
// to try to bound either side of the binary search sensibly, while still
// working in O(log n) time if they fail.
i32 get_seek_page_info(stb_vorbis* f, ProbedPage* z) {
    noinit uint8[27] header;
    noinit uint8[255] lacing;
    i32 i;
    i32 len;
    z.page_start = stb_vorbis_get_file_offset(f);
    getn(f, header, 27);
    if header[0] != 79 || header[1] != 103 || header[2] != 103 || header[3] != 83 {
        return 0;
    }
    getn(f, lacing, cast(i32, header[26]));
    len = 0;
    for i = 0; i < cast(i32, header[26]); ++i {
        len += cast(i32, lacing[i]);
    }
    z.page_end = z.page_start + 27 + header[26] + cast(u32, len);
    z.last_decoded_sample = cast(uint32, header[6] + (cast(i32, header[7]) << 8) + (cast(i32, header[8]) << 16) + (cast(i32, header[9]) << 24));
    set_file_offset(f, z.page_start);
    return 1;
}

// rarely used function to seek back to the preceding page while finding the
// start of a packet
i32 go_to_page_before(stb_vorbis* f, u32 limit_offset) {
    u32 previous_safe;
    u32 end;
    if limit_offset >= 65536 && limit_offset - 65536 >= f.first_audio_page_offset {
        previous_safe = limit_offset - 65536;
    } else {
        previous_safe = f.first_audio_page_offset;
    }
    set_file_offset(f, previous_safe);
    while vorbis_find_page(f, &end, null) != 0 {
        if end >= limit_offset && stb_vorbis_get_file_offset(f) < limit_offset {
            return 1;
        }
        set_file_offset(f, end);
    }
    return 0;
}

// implements the search logic for finding a page and starting decoding. if
// the function succeeds, current_loc_valid will be true and current_loc will
// be less than or equal to the provided sample number (the closer the
// better).
i32 seek_to_sample_coarse(stb_vorbis* f, uint32 sample_number) {
    noinit ProbedPage left;
    noinit ProbedPage right;
    noinit ProbedPage mid;
    i32 i;
    i32 start_seg_with_known_loc;
    i32 end_pos;
    i32 page_start;
    uint32 delta;
    uint32 stream_length;
    uint32 padding;
    uint32 last_sample_limit;
    f64 offset = 0.0;
    f64 bytes_per_sample = 0.0;
    i32 probe = 0;
    stream_length = stb_vorbis_stream_length_in_samples(f);
    if stream_length == 0 {
        return error(f, VORBIS_seek_without_length);
    }
    if sample_number > stream_length {
        return error(f, VORBIS_seek_invalid);
    }
    padding = cast(u32, f.blocksize_1 - f.blocksize_0 >> 2);
    if sample_number < padding {
        last_sample_limit = 0;
    } else {
        last_sample_limit = sample_number - padding;
    }
    left = f.p_first;
    while left.last_decoded_sample == cast(u32, ~0) {
        set_file_offset(f, left.page_end);
        if get_seek_page_info(f, &left) == 0 {
            stb_vorbis_seek_start(f);
            return error(f, VORBIS_seek_failed);
        }
    }
    right = f.p_last;
    assert(right.last_decoded_sample != cast(u32, ~0));
    if last_sample_limit <= left.last_decoded_sample {
        if stb_vorbis_seek_start(f) != 0 {
            if f.current_loc > sample_number {
                return error(f, VORBIS_seek_failed);
            }
            return 1;
        }
        return 0;
    }
    while left.page_end != right.page_start {
        assert(left.page_end < right.page_start);
        delta = right.page_start - left.page_end;
        if delta <= 65536 {
            set_file_offset(f, left.page_end);
        } else {
            if probe < 2 {
                if probe == 0 {
                    var data_bytes = cast(f64, right.page_end - left.page_start);
                    bytes_per_sample = data_bytes / cast(f64, right.last_decoded_sample);
                    offset = cast(f64, left.page_start) + bytes_per_sample * cast(f64, last_sample_limit - left.last_decoded_sample);
                } else {
                    f64 error = (cast(f64, last_sample_limit) - cast(f64, mid.last_decoded_sample)) * bytes_per_sample;
                    if error >= 0.0 && error < 8000.0 {
                        error = 8000.0;
                    }
                    if error < 0.0 && error > -8000.0 {
                        error = cast(f64, -8000);
                    }
                    offset += error * 2.0;
                }
                if offset < cast(f64, left.page_end) {
                    offset = cast(f64, left.page_end);
                }
                if offset > cast(f64, right.page_start - 65536) {
                    offset = cast(f64, right.page_start - 65536);
                }
                set_file_offset(f, cast(u32, offset));
            } else {
                set_file_offset(f, left.page_end + delta / 2 - 32768);
            }
            if vorbis_find_page(f, null, null) == 0 {
                stb_vorbis_seek_start(f);
                return error(f, VORBIS_seek_failed);
            }
        }
        while true {
            if get_seek_page_info(f, &mid) == 0 {
                stb_vorbis_seek_start(f);
                return error(f, VORBIS_seek_failed);
            }
            if mid.last_decoded_sample != cast(u32, ~0) {
                break;
            }
            set_file_offset(f, mid.page_end);
            assert(mid.page_start < right.page_start);
        }
        if mid.page_start == right.page_start {
            if probe >= 2 || delta <= 65536 {
                break;
            }
        } else {
            if last_sample_limit < mid.last_decoded_sample {
                right = mid;
            } else {
                left = mid;
            }
        }
        ++probe;
    }
    page_start = cast(i32, left.page_start);
    set_file_offset(f, cast(u32, page_start));
    if start_page(f) == 0 {
        return error(f, VORBIS_seek_failed);
    }
    end_pos = f.end_seg_with_known_loc;
    assert(end_pos >= 0);
    while true {
        for i = end_pos; i > 0; --i {
            if f.segments[i - 1] != 255 {
                break;
            }
        }
        start_seg_with_known_loc = i;
        if start_seg_with_known_loc > 0 || !(f.page_flag & 1) {
            break;
        }
        if go_to_page_before(f, cast(u32, page_start)) == 0 {
            stb_vorbis_seek_start(f);
            return error(f, VORBIS_seek_failed);
        }
        page_start = cast(i32, stb_vorbis_get_file_offset(f));
        if start_page(f) == 0 {
            stb_vorbis_seek_start(f);
            return error(f, VORBIS_seek_failed);
        }
        end_pos = f.segment_count - 1;
    }
    f.current_loc_valid = 0;
    f.last_seg = 0;
    f.valid_bits = 0;
    f.packet_bytes = 0;
    f.bytes_in_seg = 0;
    f.previous_length = 0;
    f.next_seg = start_seg_with_known_loc;
    for i = 0; i < start_seg_with_known_loc; i++ {
        skip(f, cast(i32, f.segments[i]));
    }
    if vorbis_pump_first_frame(f) == 0 {
        return 0;
    }
    if f.current_loc > sample_number {
        return error(f, VORBIS_seek_failed);
    }
    return 1;
}

// the same as vorbis_decode_initial, but without advancing
i32 peek_decode_initial(vorb* f, i32* p_left_start, i32* p_left_end, i32* p_right_start, i32* p_right_end, i32* mode) {
    i32 bits_read;
    i32 bytes_read;
    if vorbis_decode_initial(f, p_left_start, p_left_end, p_right_start, p_right_end, mode) == 0 {
        return 0;
    }
    bits_read = 1 + ilog(f.mode_count - 1);
    if f.mode_config[*mode].blockflag != 0 {
        bits_read += 2;
    }
    bytes_read = (bits_read + 7) / 8;
    f.bytes_in_seg += cast(uint8, bytes_read);
    f.packet_bytes -= bytes_read;
    skip(f, -bytes_read);
    if f.next_seg == -1 {
        f.next_seg = f.segment_count - 1;
    } else {
        f.next_seg--;
    }
    f.valid_bits = 0;
    return 1;
}
}

i32 stb_vorbis_seek_frame(stb_vorbis* f, u32 sample_number) {
    uint32 max_frame_samples;
    if 0 != 0 {
        return error(f, VORBIS_invalid_api_mixing);
    }
    if seek_to_sample_coarse(f, sample_number) == 0 {
        return 0;
    }
    assert(cast(i64, f.current_loc_valid));
    assert(f.current_loc <= sample_number);
    max_frame_samples = cast(u32, f.blocksize_1 * 3 - f.blocksize_0 >> 2);
    while f.current_loc < sample_number {
        i32 left_start;
        i32 left_end;
        i32 right_start;
        i32 right_end;
        i32 mode;
        i32 frame_samples;
        if peek_decode_initial(f, &left_start, &left_end, &right_start, &right_end, &mode) == 0 {
            return error(f, VORBIS_seek_failed);
        }
        frame_samples = right_start - left_start;
        if f.current_loc + cast(u32, frame_samples) > sample_number {
            return 1;
        } else if f.current_loc + cast(u32, frame_samples) + max_frame_samples > sample_number {
            vorbis_pump_first_frame(f);
        } else {
            f.current_loc += cast(uint32, frame_samples);
            f.previous_length = 0;
            maybe_start_packet(f);
            flush_packet(f);
        }
    }
    if f.current_loc != sample_number {
        return error(f, VORBIS_seek_failed);
    }
    return 1;
}

i32 stb_vorbis_seek(stb_vorbis* f, u32 sample_number) {
    if stb_vorbis_seek_frame(f, sample_number) == 0 {
        return 0;
    }
    if sample_number != f.current_loc {
        i32 n;
        uint32 frame_start = f.current_loc;
        stb_vorbis_get_frame_float(f, &n, null);
        assert(sample_number > frame_start);
        assert(f.channel_buffer_start + cast(i32, sample_number - frame_start) <= f.channel_buffer_end);
        f.channel_buffer_start += cast(i32, sample_number - frame_start);
    }
    return 1;
}

i32 stb_vorbis_seek_start(stb_vorbis* f) {
    if 0 != 0 {
        return error(f, VORBIS_invalid_api_mixing);
    }
    set_file_offset(f, f.first_audio_page_offset);
    f.previous_length = 0;
    f.first_decode = 1;
    f.next_seg = -1;
    return vorbis_pump_first_frame(f);
}

u32 stb_vorbis_stream_length_in_samples(stb_vorbis* f) {
    u32 restore_offset;
    u32 previous_safe;
    u32 end;
    u32 last_page_loc;
    if 0 != 0 {
        return cast(u32, error(f, VORBIS_invalid_api_mixing));
    }
    if f.total_samples == 0 {
        u32 last;
        uint32 lo;
        uint32 hi;
        noinit u8[6] header;
        restore_offset = stb_vorbis_get_file_offset(f);
        if f.stream_len >= 65536 && f.stream_len - 65536 >= f.first_audio_page_offset {
            previous_safe = f.stream_len - 65536;
        } else {
            previous_safe = f.first_audio_page_offset;
        }
        set_file_offset(f, previous_safe);
        if vorbis_find_page(f, &end, &last) == 0 {
            f.error = VORBIS_cant_find_last_page;
            f.total_samples = 0xffffffff;
        } else {
            last_page_loc = stb_vorbis_get_file_offset(f);
            while last == 0 {
                set_file_offset(f, end);
                if vorbis_find_page(f, &end, &last) == 0 {
                    break;
                }
                last_page_loc = stb_vorbis_get_file_offset(f);
            }
            set_file_offset(f, last_page_loc);
            getn(f, header, 6);
            lo = get32(f);
            hi = get32(f);
            if lo == 0xffffffff && hi == 0xffffffff {
                f.error = VORBIS_cant_find_last_page;
                f.total_samples = 0xffffffff;
            } else {
                if hi != 0 {
                    lo = 0xfffffffe;
                }
                f.total_samples = lo;
                f.p_last.page_start = last_page_loc;
                f.p_last.page_end = end;
                f.p_last.last_decoded_sample = lo;
            }
        }
        set_file_offset(f, restore_offset);
    }
    return cast(u32, f.total_samples == 0xffffffff ? 0 : f.total_samples);
}

f32 stb_vorbis_stream_length_in_seconds(stb_vorbis* f) {
    return cast(f32, stb_vorbis_stream_length_in_samples(f)) / cast(f32, f.sample_rate);
}

i32 stb_vorbis_get_frame_float(stb_vorbis* f, i32* channels, f32*** output) {
    i32 len;
    i32 right;
    i32 left;
    i32 i;
    if 0 != 0 {
        return error(f, VORBIS_invalid_api_mixing);
    }
    if vorbis_decode_packet(f, &len, &left, &right) == 0 {
        f.channel_buffer_end = 0;
        f.channel_buffer_start = f.channel_buffer_end;
        return 0;
    }
    len = vorbis_finish_frame(f, len, left, right);
    for i = 0; i < f.channels; ++i {
        f.outputs[i] = f.channel_buffers[i] + left;
    }
    f.channel_buffer_start = left;
    f.channel_buffer_end = left + len;
    if channels != null {
        *channels = f.channels;
    }
    if output != null {
        *output = f.outputs;
    }
    return len;
}

stb_vorbis* stb_vorbis_open_memory(u8* data, i32 len, i32* error, stb_vorbis_alloc* alloc_var) {
    stb_vorbis* f;
    noinit stb_vorbis p;
    if data == null {
        if error != null {
            *error = VORBIS_unexpected_eof;
        }
        return null;
    }
    vorbis_init(&p, alloc_var);
    p.stream = cast(uint8*, data);
    p.stream_end = cast(uint8*, data) + len;
    p.stream_start = p.stream;
    p.stream_len = cast(uint32, len);
    p.push_mode = 0;
    if start_decoder(&p) != 0 {
        f = vorbis_alloc(&p);
        if f != null {
            *f = p;
            vorbis_pump_first_frame(f);
            if error != null {
                *error = VORBIS__no_error;
            }
            return f;
        }
    }
    if error != null {
        *error = p.error;
    }
    vorbis_deinit(&p);
    return null;
}
when !(defined(STB_VORBIS_NO_INTEGER_CONVERSION)) {
private {
int8:[7][6] channel_position = {
    {0},
    {2 | 4 | 1},
    {2 | 1, 4 | 1},
    {2 | 1, 2 | 4 | 1, 4 | 1},
    {2 | 1, 4 | 1, 2 | 1, 4 | 1},
    {2 | 1, 2 | 4 | 1, 4 | 1, 2 | 1, 4 | 1},
    {2 | 1, 2 | 4 | 1, 4 | 1, 2 | 1, 4 | 1, 2 | 4 | 1},
};

// add (1<<23) to convert to int, then divide by 2^SHIFT, then add 0.5/2^SHIFT to round
void copy_samples(i16* dest, f32* src, i32 len) {
    i32 i;
    for i = 0; i < len; ++i {
        float_conv temp;
        temp.f = src[i] + (1.5f * cast(f32, 1 << 23 - 15) + 0.5f / cast(f32, 1 << 15));
        i32 v = temp.i - ((150 - 15 << 23) + (1 << 22));
        if cast(u32, v + 32768) > 65535 {
            v = v < 0 ? -32768 : 32767;
        }
        dest[i] = cast(i16, v);
    }
}

void compute_samples(i32 mask, i16* output, i32 num_c, f32** data, i32 d_offset, i32 len) {
    noinit f32[32] buffer;
    i32 i;
    i32 j;
    i32 o;
    i32 n = 32;
    for o = 0; o < len; o += 32 {
        memset(buffer, 0, cast(u64, sizeof(buffer)));
        if o + n > len {
            n = len - o;
        }
        for j = 0; j < num_c; ++j {
            if (channel_position[num_c][j] & mask) != 0 {
                for i = 0; i < n; ++i {
                    buffer[i] += data[j][d_offset + o + i];
                }
            }
        }
        for i = 0; i < n; ++i {
            float_conv temp;
            temp.f = buffer[i] + (1.5f * cast(f32, 1 << 23 - 15) + 0.5f / cast(f32, 1 << 15));
            i32 v = temp.i - ((150 - 15 << 23) + (1 << 22));
            if cast(u32, v + 32768) > 65535 {
                v = v < 0 ? -32768 : 32767;
            }
            output[o + i] = cast(i16, v);
        }
    }
}

void compute_stereo_samples(i16* output, i32 num_c, f32** data, i32 d_offset, i32 len) {
    noinit f32[32] buffer;
    i32 i;
    i32 j;
    i32 o;
    i32 n = 32 >> 1;
    for o = 0; o < len; o += 32 >> 1 {
        i32 o2 = o << 1;
        memset(buffer, 0, cast(u64, sizeof(buffer)));
        if o + n > len {
            n = len - o;
        }
        for j = 0; j < num_c; ++j {
            i32 m = channel_position[num_c][j] & (2 | 4);
            if m == (2 | 4) {
                for i = 0; i < n; ++i {
                    buffer[i * 2 + 0] += data[j][d_offset + o + i];
                    buffer[i * 2 + 1] += data[j][d_offset + o + i];
                }
            } else if m == 2 {
                for i = 0; i < n; ++i {
                    buffer[i * 2 + 0] += data[j][d_offset + o + i];
                }
            } else if m == 4 {
                for i = 0; i < n; ++i {
                    buffer[i * 2 + 1] += data[j][d_offset + o + i];
                }
            }
        }
        for i = 0; i < n << 1; ++i {
            float_conv temp;
            temp.f = buffer[i] + (1.5f * cast(f32, 1 << 23 - 15) + 0.5f / cast(f32, 1 << 15));
            i32 v = temp.i - ((150 - 15 << 23) + (1 << 22));
            if cast(u32, v + 32768) > 65535 {
                v = v < 0 ? -32768 : 32767;
            }
            output[o2 + i] = cast(i16, v);
        }
    }
}

void convert_samples_short(i32 buf_c, i16** buffer, i32 b_offset, i32 data_c, f32** data, i32 d_offset, i32 samples) {
    i32 i;
    if buf_c != data_c && buf_c <= 2 && data_c <= 6 {
        for i = 0; i < buf_c; ++i {
            compute_samples(convert_samples_short__channel_selector[buf_c][i], buffer[i] + b_offset, data_c, data, d_offset, samples);
        }
    } else {
        i32 limit = buf_c < data_c ? buf_c : data_c;
        for i = 0; i < limit; ++i {
            copy_samples(buffer[i] + b_offset, data[i] + d_offset, samples);
        }
        for ; i < buf_c; ++i {
            memset(buffer[i] + b_offset, 0, cast(u64, sizeof(i16) * samples));
        }
    }
}
}

i32 stb_vorbis_get_frame_short(stb_vorbis* f, i32 num_c, i16** buffer, i32 num_samples) {
    f32** output = null;
    i32 len = stb_vorbis_get_frame_float(f, null, &output);
    if len > num_samples {
        len = num_samples;
    }
    if len != 0 {
        convert_samples_short(num_c, buffer, 0, f.channels, output, 0, len);
    }
    return len;
}

private {
void convert_channels_short_interleaved(i32 buf_c, i16* buffer, i32 data_c, f32** data, i32 d_offset, i32 len) {
    i32 i;
    if buf_c != data_c && buf_c <= 2 && data_c <= 6 {
        assert(buf_c == 2);
        for i = 0; i < buf_c; ++i {
            compute_stereo_samples(buffer, data_c, data, d_offset, len);
        }
    } else {
        i32 limit = buf_c < data_c ? buf_c : data_c;
        i32 j;
        for j = 0; j < len; ++j {
            for i = 0; i < limit; ++i {
                float_conv temp;
                f32 f = data[i][d_offset + j];
                temp.f = f + (1.5f * cast(f32, 1 << 23 - 15) + 0.5f / cast(f32, 1 << 15));
                i32 v = temp.i - ((150 - 15 << 23) + (1 << 22));
                if cast(u32, v + 32768) > 65535 {
                    v = v < 0 ? -32768 : 32767;
                }
                *buffer++ = cast(i16, v);
            }
            for ; i < buf_c; ++i {
                *buffer++ = 0;
            }
        }
    }
}
}

i32 stb_vorbis_get_frame_short_interleaved(stb_vorbis* f, i32 num_c, i16* buffer, i32 num_shorts) {
    f32** output;
    i32 len;
    if num_c == 1 {
        return stb_vorbis_get_frame_short(f, num_c, &buffer, num_shorts);
    }
    len = stb_vorbis_get_frame_float(f, null, &output);
    if len != 0 {
        if len * num_c > num_shorts {
            len = num_shorts / num_c;
        }
        convert_channels_short_interleaved(num_c, buffer, f.channels, output, 0, len);
    }
    return len;
}

i32 stb_vorbis_get_samples_short_interleaved(stb_vorbis* f, i32 channels, i16* buffer, i32 num_shorts) {
    f32** outputs;
    i32 len = num_shorts / channels;
    i32 n = 0;
    while n < len {
        i32 k = f.channel_buffer_end - f.channel_buffer_start;
        if n + k >= len {
            k = len - n;
        }
        if k != 0 {
            convert_channels_short_interleaved(channels, buffer, f.channels, f.channel_buffers, f.channel_buffer_start, k);
        }
        buffer += k * channels;
        n += k;
        f.channel_buffer_start += k;
        if n == len {
            break;
        }
        if stb_vorbis_get_frame_float(f, null, &outputs) == 0 {
            break;
        }
    }
    return n;
}

i32 stb_vorbis_get_samples_short(stb_vorbis* f, i32 channels, i16** buffer, i32 len) {
    f32** outputs;
    i32 n = 0;
    while n < len {
        i32 k = f.channel_buffer_end - f.channel_buffer_start;
        if n + k >= len {
            k = len - n;
        }
        if k != 0 {
            convert_samples_short(channels, buffer, n, f.channels, f.channel_buffers, f.channel_buffer_start, k);
        }
        n += k;
        f.channel_buffer_start += k;
        if n == len {
            break;
        }
        if stb_vorbis_get_frame_float(f, null, &outputs) == 0 {
            break;
        }
    }
    return n;
}

i32 stb_vorbis_decode_memory(uint8* mem, i32 len, i32* channels, i32* sample_rate, i16** output) {
    i32 data_len;
    i32 offset;
    i32 total;
    i32 limit;
    i32 error;
    i16* data;
    stb_vorbis* v = stb_vorbis_open_memory(mem, len, &error, null);
    if v == null {
        return -1;
    }
    limit = v.channels * 4096;
    *channels = v.channels;
    if sample_rate != null {
        *sample_rate = cast(i32, v.sample_rate);
    }
    data_len = 0;
    offset = data_len;
    total = limit;
    data = cast(i16*, alloc(total * sizeof(*data)));
    if data == null {
        stb_vorbis_close(v);
        return -2;
    }
    while true {
        i32 n = stb_vorbis_get_frame_short_interleaved(v, v.channels, data + offset, total - offset);
        if n == 0 {
            break;
        }
        data_len += n;
        offset += n * v.channels;
        if offset + limit > total {
            i16* data2;
            total *= 2;
            data2 = cast(i16*, realloc(data, cast(u64, total * sizeof(*data))));
            if data2 == null {
                free(data);
                stb_vorbis_close(v);
                return -2;
            }
            data = data2;
        }
    }
    *output = data;
    stb_vorbis_close(v);
    return data_len;
}
}

i32 stb_vorbis_get_samples_float_interleaved(stb_vorbis* f, i32 channels, f32* buffer, i32 num_floats) {
    f32** outputs;
    i32 len = num_floats / channels;
    i32 n = 0;
    i32 z = f.channels;
    if z > channels {
        z = channels;
    }
    while n < len {
        i32 i;
        i32 j;
        i32 k = f.channel_buffer_end - f.channel_buffer_start;
        if n + k >= len {
            k = len - n;
        }
        for j = 0; j < k; ++j {
            for i = 0; i < z; ++i {
                *buffer++ = f.channel_buffers[i][f.channel_buffer_start + j];
            }
            for ; i < channels; ++i {
                *buffer++ = 0.0f;
            }
        }
        n += k;
        f.channel_buffer_start += k;
        if n == len {
            break;
        }
        if stb_vorbis_get_frame_float(f, null, &outputs) == 0 {
            break;
        }
    }
    return n;
}

i32 stb_vorbis_get_samples_float(stb_vorbis* f, i32 channels, f32** buffer, i32 num_samples) {
    f32** outputs;
    i32 n = 0;
    i32 z = f.channels;
    if z > channels {
        z = channels;
    }
    while n < num_samples {
        i32 i;
        i32 k = f.channel_buffer_end - f.channel_buffer_start;
        if n + k >= num_samples {
            k = num_samples - n;
        }
        if k != 0 {
            for i = 0; i < z; ++i {
                memcpy(buffer[i] + n, f.channel_buffers[i] + f.channel_buffer_start, cast(u64, sizeof(f32) * k));
            }
            for ; i < channels; ++i {
                memset(buffer[i] + n, 0, cast(u64, sizeof(f32) * k));
            }
        }
        n += k;
        f.channel_buffer_start += k;
        if n == num_samples {
            break;
        }
        if stb_vorbis_get_frame_float(f, null, &outputs) == 0 {
            break;
        }
    }
    return n;
}
}
private {
i8[16] ilog__log2_4 = {0, 1, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4};
uint8[6] vorbis_validate__vorbis = {118, 111, 114, 98, 105, 115};
i32[4] vorbis_decode_packet_rest__range_list = {256, 128, 86, 64};
i32:[3][2] convert_samples_short__channel_selector = {{0}, {1}, {2, 4}};
}
