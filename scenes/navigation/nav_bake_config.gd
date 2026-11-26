class_name NavBakeConfig
## Navigation domain: when a re-bake lands. A `class_name` holder of `static var`s, read as
## `NavBakeConfig.<name>`; there is no instance and no autoload. A count is game frames
## (`GameClock`, which a pause stops) from a bake's start to the one its result is assigned on
## (`NavBake`): fixed, so a match plays the same fight whatever a thread's wall-clock is, and the
## game waits for the thread (blocking the frame) only when the thread is later than the count. A
## count is two costs: too low and the thread is late, which holds a frame for the rest of its run;
## too high and everything that waits for the
## map (the AI's first decision, an entry's slots) waits for it too, which moves the fight.

## A district's planning re-bake (the 3D baker's, D16). The thread is the server's bake (98 to 105
## ms) plus the polygon merge (`NavMerge`, 16 to 30 ms) and the plan's prep (3 to 6 ms): 120 to 140
## ms, and the pool runs it beside the tile bursts and the avoid bakes. 36 frames is about 600 ms
## in play at 60 fps, well above the thread, and what the fight tolerates: at 43 or more the
## fight itself moves heavier (`perf/match_npc_vision` fails its p95), at 36 it is lighter than
## before the 3D baker. A count is frames, so a guard whose frames are short sees the thread late:
## `perf/ambush_order_stress`' headless frames are about 3 ms, so 36 of them are about 110 ms,
## under the thread's 120 to 140, and it sets 50 for itself (its thread was done on frame 46 or
## 47 in 4 of 7 runs). Bringing the thread down (a faster planning bake) is open work, after which
## that override goes.
static var district_frames := 36
## A district's avoid map (`NavBuilder.avoid_map`): the same source and a few holes, so the same
## thread as the planning bake, and the AI asks for one at the start of every decision's walk and
## of an entry's slot, and a new set of bodies is a new bake, so what it waits for is a chain of
## them: each link costs the count, not the thread's own time. The count sits just above the
## thread's longest (24 avoid bakes of the runs `district_frames` was measured on: 105 to 176 ms,
## 2 to 16 frames, none late at 20; the polygon merge adds 2 frames: 22), since a later thread holds
## the frame for the rest of its run, and the count does not decide the fight: with the map synced
## on the main thread (`navigation/map_syncs_without_a_thread`) the 5v5 guard's contact came the
## same every run of a count. Measured again 2026-11-23 (73 avoid bakes of the guards above): done
## on frame 3 to 20, p95 19; 22 holds.
static var avoid_frames := 22
## The most background bakes (every one but the urgent ring's) between their start and their
## landing (`NavBake`): one asked past that waits its turn, the oldest first, and its count runs
## from its start. 3 is what the worker pool runs at once for normal-priority tasks on a machine of
## 10 to 13 threads (its share is 0.3 of them, rounded down; measured on a 12-thread Mac: sleepers
## start three at a time), so a bake that has started has a thread, except just after a world
## starts: the sound pre-warm (`Sound.warm`) and the pixel-art pre-warm (`PixelArt.warm`) are
## normal-priority tasks too and share those 3, so a bake may queue behind them. A fixed number, not
## the machine's: the frame a bake lands on is the same on every machine. On one with fewer than 10
## threads the pool runs 1 or 2 at once, a started bake may still queue behind the others, and a
## frame that waits for it waits as it did before this rule (`rebake.md`).
static var at_once := 3
## A held bake whose asker asks every beat while it wants the map (`NavBuilder.avoid_map`'s
## `repeats`) is dropped, when its turn comes, if nobody has asked for it in this many frames: two
## of the NPC's beats (`AgentBeat`: every second frame).
static var held_ask_frames := 4
## The planning ring (`NavRing`): a small map of the match building, read by every snap and route
## in the building, so it lands as soon as it safely can. It is a high-priority task
## (`NavBake.start`, `urgent`: queued with the others it waited 46 ms behind three district bakes
## and the frame that landed it was 67 ms), a 14 ms thread. Measured on the guards above (36 rings):
## done 0 to 2 frames after its start for 30, 6 for 6 of them (the thread taken late behind a
## tile burst's group): the p95 is 6, and 7 holds it.
static var ring_frames := 7
## A lone house (a test world's, the sandboxes'): its bake takes a few ms, so a count of 36 would
## make the AI wait 0.6 s for an avoid map it used to have in a frame or two (its first decision
## waits for it). Measured 2026-11-09 with the 2D baker over 517 bakes of the ai and navigation
## tests' houses (the frame 1 to 3 ms): 1 to 2 frames, p50 1, p95 2; 3, a little above the p95. Not
## measured again with the 3D baker, whose thread is longer (open work).
static var house_frames := 3
## A district's steering tiles (`NavTileBurst`): each tile of a tick's burst is baked on a worker
## thread (`NavTiles.prepare`) and the burst lands, all its tiles at once, this many frames after
## the last tile was started. A tile's bake is a few ms of thread (the server's voxel bake), so the
## tiles started a frame apart are all done by then unless the pool is busy with a planning bake
## (`NavTiles.late_total` counts the ones that were not; the perf frame report prints it).
static var tile_frames := 3
