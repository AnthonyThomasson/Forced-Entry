class_name NavBakeConfig
## Navigation domain: when a re-bake lands. A `class_name` holder of `static var`s, read as
## `NavBakeConfig.<name>`; there is no instance and no autoload.

## Physics frames from the start of a planning re-bake to the one its result is assigned in
## (`NavBake`): fixed, so a match plays the same fight whatever a thread's wall-clock is, and the
## game waits for the thread (blocking the frame) only when the thread is later than this. Measured
## 2026-11-09 over 41 district bakes of the match guards (`perf/match_5v5_stress`, 17 of them, the
## frame about 7 ms: the thread took 7 to 16 frames, p95 12; `perf/match_10v10_stress`, 24 of
## them, the frame about 15 ms: 3 to 7 frames), the thread itself 65 to 94 ms (the planning ring's
## bake, 4 to 7 ms, is always on time): 14, a little above the p95 of the slower frame.
static var land_frames := 14
