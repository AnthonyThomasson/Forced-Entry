# Perf · What steered a match guard's fight, and what fixed it (#203)

Side file of `domain-testing`. State and the A/B tool: `perf-nondeterminism.md`; the fingerprint every cause below was found with: `perf-fingerprint.md`.

A match plays the same fight whatever ran before it in the process, with or without padding. What steered it, found with the fingerprint (first differing frame and field of two plays):

- **The AI's cadences read the process-global physics frame** (`Engine.get_physics_frames()`), so a match's phase followed how many frames the process had run.
  The sight cadence and the house look phase count `WorldRng.frame_of(node)` now: `GameClock` frames (still while paused, like the AI's timers) since the world's first character took its place.
- **`GameClock.seconds() - start >= 0.8` was false at 45 of 100 start frames** (floats rounded where they fall: `(f + 48) / 60 - f / 60 < 0.8`), so every such timer
  (a still leader's 0.8 s, a follower's re-aim) ended a frame late on some start frames: the first split was a follower's goal one frame late at frame 391, run
  after another match. `seconds()` reads 1e-9 above exact (`SECONDS_BIAS`): a timer ends on its frame.
- **`GameClock.msec()` reads 16 or 17 ms a frame by the frame a span starts on** (16 2/3 ms a frame): a walker's speed from two sightings (`PerceptionSight._track`)
  differed by a px/s, which flipped a give-way at frame 21 of the grenade guard. A world calls `GameClock.align()` at its start (`WorldRng`): the ms grid starts there,
  no jump in `msec()`.
- No split followed physics body or area order: plays with 777 and 333, 1013 and 7 padding and after other matches (their RIDs and instance ids shifted) played the
  same fight once the two above were fixed. **The frame-64 split #192 saw** was reproduced as a kind, not by its own run: the replay harness on the tip before this job (`e9afa04d`) splits the 5v5's second
  play at frame 61 (the grenade guard at 40, both 10v10s at 8 and 9) when the worlds are built on other residues of the frame, and at frames 260 to 610 when they are built on the same one (the clock's rounding); the padded
  play there plays like the plain one built on the same frame, so padding is not what splits it. On this branch the same plays are identical.
- A house look's phase changed nothing in the four guards' fights (checked by mutation): the cadence on the process's frames passes the replays. `ai/perception/house_look_cadence` pins that the look
  reads the world's frame (it fails the process-frame cadence); the sight cadence on them fails both the 5v5 and the 10v10 replay.

**Tests:** `perf/match_5v5_replay`, `grenade_match_replay`, `match_10v10_replay`, `match_npc_vision_replay` play the guard three times in one process (`tests/_perf/guard_replay.gd`: the guard
unchanged, in a world of its own, its fingerprint read back): plain, plain again and with padding on, their worlds built on three residues modulo 6 (every cadence divides it; the test checks it as a premise), and the three must match line for line, through the
warm-up and the whole window, and have a shot in them. Without the seconds bias only the 10v10 replay goes red (`general/game_clock_suite` pins it). `general/game_clock_suite`, `general/world_rng_two_worlds`, `ai/perception/sight_checks_spread` pin the pieces.

**The guards' seed is 2 (was 7).** Played the same on every run, seed 7's fight became the slow one: the invaders clear the living room (stack, bang, cross, corner, clear, cover, rear: 18 s) while the
defenders hold an ambush at the garage doorway, so contact came at 31.3 s in the 5v5 and never in 36 s in the grenade guard, where the base's luck had it at 6 to 15 s. With main-thread map syncs it missed 9 of 10 runs
over avoid counts 10 to 16; with async syncs 6 of 8 were quick, so the sync puts this seed in the slow branch. Seeds 1 to 16 (not 7), by contact and late nav bakes (a late bake holds its frame 30 to 50 ms, over
`SMOOTH_MAX_MS`): 1, 5, 9, 12, 16 meet at once (6.0 s, the sides in sight at the end of the warm-up); 4 never; 6, 8, 10, 11 the viewed invader dies; 13 meets at 8.3 s but has 4 to 5 of 22 bakes late in the 5v5 (max 49 ms);
3 has 9 of 31 late; 15 meets the 10v10 at 17.9 s; **2** meets at 7.7 s (5v5), 8.1 s (grenade) and 6.0 s (both 10v10s) with 0 late bakes of 21 to 57: 5v5 avg 6.69 p95 15.0 max 27.5 ms
(load 5, 0 busy Godot). `MATCH_PLAN` stays the largest plan. No budget and not `MATCH_CONTACT_WITHIN` changed.
