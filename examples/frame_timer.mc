// frame_timer.mc — per-frame delta time.
//
// This header is a work-around for v-sync not working correctly on
// some linux installations.
//
// Used by example apps that require correct time deltas.
//

when os(linux) {
    struct timespec { i64 tv_sec; i64 tv_nsec; }
    extern "libc.so.6" i32 clock_gettime(i32 clk_id, timespec* tp);
    extern "libc.so.6" i32 nanosleep(timespec* req, timespec* rem);

    const i64 _FT_TARGET_NS = 16_666_667;   // 60 fps
    timespec _ft_prev;
    bool     _ft_have_prev = false;
}

f32 frame_dt() {
    when !os(linux) {
        return cast(f32, sapp_frame_duration());
    }
    else {
        timespec now;
        clock_gettime(1, &now);              // CLOCK_MONOTONIC

        if _ft_have_prev == false {
            _ft_have_prev = true;
            _ft_prev = now;
            return cast(f32, _FT_TARGET_NS) / 1_000_000_000.0f;
        }

        i64 elapsed = (now.tv_sec - _ft_prev.tv_sec) * 1_000_000_000
                    + (now.tv_nsec - _ft_prev.tv_nsec);
        while elapsed < _FT_TARGET_NS {
            i64 remain = _FT_TARGET_NS - elapsed;
            if remain > 1_000_000 {
                // Sleep most of the remaining time, leave 1 ms to spin.
                timespec req;
                req.tv_sec  = 0;
                req.tv_nsec = remain - 1_000_000;
                nanosleep(&req, null);
            }
            clock_gettime(1, &now);
            elapsed = (now.tv_sec - _ft_prev.tv_sec) * 1_000_000_000
                    + (now.tv_nsec - _ft_prev.tv_nsec);
        }

        _ft_prev = now;
        f32 dt = cast(f32, elapsed) / 1_000_000_000.0f;
        if dt > 0.05f { dt = 0.05f; }        // clamp a stalled frame
        return dt;
    }
}
