// audio_vorbis.mc — decode an Ogg Vorbis file with lib/stb_vorbis.mc and
// play it through sokol_audio. The file is decoded up front; the stream
// callback copies frames from the PCM buffer. The same code runs on
// native and wasm.

import sokol_audio;
import stb_vorbis;
import file;
import thread;

i16* g_pcm = null;
i32 g_frames = 0;
i32 g_channels = 0;
i32 g_pos = 0;

// Device and file channel counts may differ: extra device channels
// repeat the file's last channel, extra file channels are dropped.
void stream_cb(f32* buf, i32 num_frames, i32 num_channels) {
    for i32 i = 0; i < num_frames; i++ {
        i64 s = cast(i64, g_pos) * g_channels;
        for i32 c = 0; c < num_channels; c++ {
            i32 sc = c;
            if sc >= g_channels { sc = g_channels - 1; }
            buf[i * num_channels + c] = cast(f32, g_pcm[s + sc]) / 32768.0f;
        }
        g_pos++;
        if g_pos >= g_frames { g_pos = 0; }   // loop the tune
    }
}

i32 main() {
    FileData fd = file_read("test/tune.ogg");
    if fd.data == null || fd.len <= 0 {
        print("audio_vorbis: cannot read test/tune.ogg (run from the samples root)\n");
        return 1;
    }
    i32 rate = 0;
    g_frames = stb_vorbis_decode_memory(fd.data, cast(i32, fd.len), &g_channels, &rate, &g_pcm);
    free(fd.data);
    if g_frames <= 0 {
        print("audio_vorbis: decode failed ({})\n", g_frames);
        return 1;
    }

    saudio_desc desc;
    desc.sample_rate = rate;
    desc.num_channels = g_channels;
    desc.buffer_frames = 2048;
    desc.stream_cb = stream_cb;
    desc.stream_userdata_cb = null;
    desc.user_data = null;
    saudio_setup(&desc);
    if !saudio_isvalid() {
        print("audio_vorbis: saudio_setup failed (audio backend unavailable)\n");
        return 1;
    }
    print("audio_vorbis: {} frames, {} ch, {} Hz\n",
          g_frames, g_channels, saudio_sample_rate());

    when os(wasm) {
        // On wasm main() must return so the browser can run the audio
        // worklet; it keeps pulling until the page closes.
    } else {
        // Play once, then exit. The PCM buffer is never freed; the audio
        // thread reads it until shutdown.
        i32 ms = cast(i32, cast(i64, g_frames) * 1000 / rate);
        thread_sleep(ms + 200);
        saudio_shutdown();
    }
    when os(ios) {
        // iOS treats a returning main() as a crash and respawns the
        // process. Block instead; the user closes the app from the home
        // screen.
        while true { thread_sleep(60000); }
    }
    return 0;
}
