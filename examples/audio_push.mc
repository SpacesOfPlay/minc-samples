// audio_push.mc — push-model 440 Hz sine. Same audible result as
// audio_sine.mc but the main thread feeds the FIFO instead of the
// audio thread pulling via callback.

import sokol_audio;
import math;
import thread;

const f32 G_FREQ = 440.0f;
const f32 G_TWO_PI = 6.2831853f;

i32 main() {
    saudio_desc desc;
    desc.sample_rate = 44100;
    desc.num_channels = 1;
    desc.buffer_frames = 2048;
    desc.packet_frames = 0;       // default
    desc.num_packets = 0;         // default
    desc.stream_cb = null;        // push mode
    desc.stream_userdata_cb = null;
    desc.user_data = null;
    saudio_setup(&desc);
    if !saudio_isvalid() {
        print("audio_push: saudio_setup failed\n");
        return 1;
    }
    print("audio_push: pushing 440 Hz at {} Hz / {} ch for 3 s\n",
          saudio_sample_rate(), saudio_channels());

    f32 phase = 0.0f;
    f32 step = G_TWO_PI * G_FREQ / cast(f32, saudio_sample_rate());

    // Push for ~3 s. Each loop pushes whatever the FIFO can absorb,
    // then sleeps a few ms — enough for the audio thread to drain a
    // bit but not so much that the FIFO underruns.
    f32[1024] buf;
    i32 total_frames = 0;
    while total_frames < saudio_sample_rate() * 3 {
        i32 want = saudio_expect();
        if want > 1024 { want = 1024; }
        if want > 0 {
            for i32 i = 0; i < want; i++ {
                buf[i] = sinf(phase) * 0.2f;
                phase = phase + step;
                if phase > G_TWO_PI { phase = phase - G_TWO_PI; }
            }
            i32 got = saudio_push(&buf[0], want);
            total_frames = total_frames + got;
        } else {
            thread_sleep(5);
        }
    }
    // Let the audio thread drain the tail of the FIFO before shutdown.
    thread_sleep(200);
    saudio_shutdown();
    when os(ios) {
        // iOS treats main() returning as a watchdog crash and respawns
        // the process once before giving up — that's why a plain
        // `return 0;` here would play the test tone twice. Block the
        // main thread so the system sees a live app; the user closes
        // it via the home gesture.
        while true { thread_sleep(60000); }
    }
    return 0;
}
