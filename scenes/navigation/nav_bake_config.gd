class_name NavBakeConfig
## Navigation domain: when a re-bake lands. A `class_name` holder of `static var`s, read as
## `NavBakeConfig.<name>`; there is no instance and no autoload. A count is game frames
## (`GameClock`, which a pause stops) from a bake's start to the one its result is assigned on
## (`NavBake`): fixed, so a match plays the same fight whatever a thread's wall-clock is, and the
## game waits for the thread (blocking the frame) only when the thread is later than the count. A
## count is two costs: too low and the thread is late, which holds a frame for the rest of its run;
## too high and everything that waits for the
## map (the AI's first decision, an entry's slots) waits for it too, which moves the fight.

## A district's planning re-bake (the 3D baker's, D16). Measured 2026-11-22 over the match guards
## (`ambush_order_stress`, `grenade_match_stress`, `match_5v5_stress`; 15 planning bakes), the
## thread takes 104 to 113 ms (the 2D baker's was 53), which is 6 to 17 frames of the 5v5's and the
## grenade match's frame (9 ms) but 23 of the ambush guard's (4.7 ms a frame): a count is frames,
## so the guard with the shortest frames sets it. At 24 that guard's second planning bake was still
## on its thread at its landing frame (it started with the pool busy with a tile burst) and the
## frame waited 38 ms (max 41.6 against a budget of 33.4); 32 is the 23 frames and the wait the
## pool's other work adds (a landing still waits 20 ms at most there). The merge of the baker's
## polygons (`NavMerge`, 13 ms of the district's thread) takes it to 36 (ambush guard: the landing
## at 32 waited 34 to 42 ms on a quiet machine, 25 to 28 at 36).
static var district_frames := 36
## A district's avoid map (`NavBuilder.avoid_map`): the same source and a few holes, so the same
## thread as the planning bake, and the AI asks for one at the start of every decision's walk and
## of an entry's slot, and a new set of bodies is a new bake, so what it waits for is a chain of
## them: each link costs the count, not the thread's own time. The count sits just above the
## thread's longest (24 avoid bakes of the runs `district_frames` was measured on: 105 to 176 ms,
## 2 to 16 frames, none late at 20; the polygon merge adds 2 frames: 22), since a later thread holds
## the frame for the rest of its run, and the count does not decide the fight: with the map synced
## on the main thread (`navigation/map_syncs_without_a_thread`) the 5v5 guard's contact came the
## same every run of a count.
static var avoid_frames := 22
## The planning ring (`NavRing`): a small map of the match building, read by every snap and route
## in the building, so it lands as soon as it safely can. The 3D baker's thread takes 14 ms and is
## done in 0 to 2 frames, but 4 of the 15 rings that landed on 3 found it still queued behind a
## tile burst (3 to 6 ms waited): 4.
static var ring_frames := 4
## A lone house (a test world's, the sandboxes'): its bake takes a few ms, so a count of 36 would
## make the AI wait 0.6 s for an avoid map it used to have in a frame or two (its first decision
## waits for it). Measured 2026-11-09 with the 2D baker over 517 bakes of the ai and navigation
## tests' houses (the frame 1 to 3 ms): 1 to 2 frames, p50 1, p95 2; 3, a little above the p95. Not
## measured again with the 3D baker, whose thread is longer (perf3d owns that).
static var house_frames := 3
## A district's steering tiles (`NavTileBurst`): each tile of a tick's burst is baked on a worker
## thread (`NavTiles.prepare`) and the burst lands, all its tiles at once, this many frames after
## the last tile was started. A tile's bake is a few ms of thread (the server's voxel bake), so the
## tiles started a frame apart are all done by then unless the pool is busy with a planning bake
## (`NavTiles.late_total` counts the ones that were not; the perf frame report prints it).
static var tile_frames := 3
