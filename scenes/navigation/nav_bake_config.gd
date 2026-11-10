class_name NavBakeConfig
## Navigation domain: when a re-bake lands. A `class_name` holder of `static var`s, read as
## `NavBakeConfig.<name>`; there is no instance and no autoload.

## Physics frames from the start of a district's planning re-bake (or of one of its avoid maps) to
## the one its result is assigned in (`NavBake`): fixed, so a match plays the same fight whatever a
## thread's wall-clock is, and the game waits for the thread (blocking the frame) only when the
## thread is later than this. Measured 2026-11-09 over 41 district planning bakes of the match
## guards (`perf/match_5v5_stress`, 17 of them, the frame about 7 ms: the thread took 7 to 16
## frames, p95 12; `perf/match_10v10_stress`, 24 of them, the frame about 15 ms: 3 to 7 frames), the
## thread itself 65 to 94 ms (the planning ring's bake, 4 to 7 ms, is always on time): 14, a little
## above the p95 of the slower frame. The district's avoid maps (the same source and a few holes,
## 196 bakes over two runs of each guard) took 55 to 85 ms, 1 to 14 frames, p95 13: no different.
static var district_frames := 14
## The same for a lone house (a test world's, the sandboxes'): its bake takes a few ms, so a fixed
## count of 14 would make the AI wait 0.23 s for an avoid map it used to have in a frame or two
## (its first decision waits for it). Measured 2026-11-09 over 517 bakes of the ai and navigation
## tests' houses (the frame 1 to 3 ms): 1 to 2 frames, p50 1, p95 2; 3, a little above the p95.
static var house_frames := 3
