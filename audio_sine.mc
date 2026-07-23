// audio_sine.mc — 440 Hz sine wave on the default output device.
// Runs for ~3 seconds and exits.

import sokol_audio;
import math;
import thread;

f32 g_phase = 0.0f;
f32 g_step = 0.0f;
const f32 G_FREQ = 440.0f;
const f32 G_TWO_PI = 6.2831853f;

// callback
void stream_cb(f32* buf, i32 num_frames, i32 num_channels) {
    f32 step = g_step;
    for i32 i = 0; i < num_frames; i++ {
        f32 s = sinf(g_phase) * 0.2f;
        g_phase = g_phase + step;
        if g_phase > G_TWO_PI { g_phase = g_phase - G_TWO_PI; }
        for i32 c = 0; c < num_channels; c++ {
            buf[i * num_channels + c] = s;
        }
    }
}

// Logger callback — receives diagnostic from sokol_audio.
void audio_log(u8* tag, u32 level, u32 item_id, u8* msg, u32 line_nr, u8* filename, void* user_data) {
    eprint("[{}] level={} item={} line={} msg={}\n",
           tag, level, item_id, line_nr, msg);
}

i32 main() {
    saudio_desc desc;
    desc.sample_rate = 44100;
    desc.num_channels = 1;
    desc.buffer_frames = 2048;
    desc.stream_cb = stream_cb;
    desc.stream_userdata_cb = null;
    desc.user_data = null;
    desc.logger.func = audio_log;
    saudio_setup(&desc);
    if !saudio_isvalid() {
        print("audio_sine: saudio_setup failed (audio backend unavailable)\n");
        return 1;
    }
    g_step = G_TWO_PI * G_FREQ / cast(f32, saudio_sample_rate());
    print("audio_sine: playing 440 Hz at {} Hz / {} ch / {} frames for 3 s\n",
          saudio_sample_rate(), saudio_channels(), saudio_buffer_frames());
    when os(wasm) {
        // On wasm the host JS owns the AudioContext. main() has to
        // return promptly so the browser can run the audio worklet —
        // thread_sleep is a no-op there and an explicit shutdown would
        // tear down the context before a single buffer plays. The
        // worklet keeps pulling samples until the page closes.
    } else {
        thread_sleep(3000);
        saudio_shutdown();
    }
    when os(ios) {
        // iOS treats main() returning as a watchdog crash and respawns
        // the process once before giving up — that's why a plain
        // `return 0;` would play the test tone twice. Block the main
        // thread so the system sees a live app; the user closes it
        // via the home gesture.
        while true { thread_sleep(60000); }
    }
    return 0;
}
