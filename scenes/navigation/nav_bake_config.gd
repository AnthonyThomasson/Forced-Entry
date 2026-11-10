class_name NavBakeConfig
## Navigation domain: when a re-bake lands. A `class_name` holder of `static var`s, read as
## `NavBakeConfig.<name>`; there is no instance and no autoload. A count is physics frames from a
## bake's start to the one its result is assigned on (`NavBake`): fixed, so a match plays the same
## fight whatever a thread's wall-clock is, and the game waits for the thread (blocking the frame)
## only when the thread is later than the count. A count is two costs: too low and the thread is
## late, which holds a frame for the rest of its run; too high and everything that waits for the
## map (the AI's first decision, an entry's slots) waits for it too, which moves the fight.

## A district's planning re-bake. Measured 2026-11-10 over 175 planning bakes of the match guards'
## match (`Perf.configure_match`; the 5v5 frame about 7 ms, the 10v10's 15 ms): the thread took 4 to
## 18 frames of the 5v5 frame (p50 10, p75 11, p95 14), 3 to 7 of the 10v10's; it is rare (the
## updater's tick) and nothing waits on it, so the count is the p95: 14.
static var district_frames := 14
## A district's avoid map (`NavBuilder.avoid_map`): the same source and a few holes, so the same
## thread (568 bakes in those runs: 1 to 14 frames of the 5v5 frame, p50 9, p75 11, p95 13), but
## the AI asks for one at the start of every decision's walk and of an entry's slot, and a new set
## of bodies is a new bake, so what it waits for is a chain of them: each link costs the count, not
## the thread's own time (14 adds 2 frames to a link over 12, 4 over the median). 12, the p90: a
## tenth of them are later and hold the frame for the rest of their thread. Four 5v5 guard runs each
## on a loaded machine (2026-11-10): 12 had 0 late bakes of 52; 14 had 2 of 89; 10 had 24 of 86
## (more than a quarter, and the frame max no better), so a count near the median costs more than
## the 2 frames it saves; the 10v10's thread (3 to 7 frames of its 15 ms frame) is never late. The
## count does not decide the fight: with the map synced on the main thread
## (`navigation/map_syncs_without_a_thread`) the 5v5 guard's contact came at 10.5 to 12.3 s, the
## same every run of a count, at 14, 12, 10 and 8 alike. (With the server's async map sync it came
## at 12 s, 30 s or not at all from run to run at any count, and was taken for the count.)
static var avoid_frames := 12
## The planning ring (`NavRing`): a small map of the match building, a bake of 4 to 7 ms that is
## done in a frame (211 bakes: 1 frame, at most 4); read by every snap and route in the building,
## so it lands as soon as it safely can: 3.
static var ring_frames := 3
## A lone house (a test world's, the sandboxes'): its bake takes a few ms, so a count of 14 would
## make the AI wait 0.23 s for an avoid map it used to have in a frame or two (its first decision
## waits for it). Measured 2026-11-09 over 517 bakes of the ai and navigation tests' houses (the
## frame 1 to 3 ms): 1 to 2 frames, p50 1, p95 2; 3, a little above the p95.
static var house_frames := 3
