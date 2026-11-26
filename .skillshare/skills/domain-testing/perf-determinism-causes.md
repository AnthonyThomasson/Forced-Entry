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

**The guards' seed is 23** (`MATCH_SEED`, `tests/_perf/perf_probe.gd`, which holds the rule that picks it: over seeds 1 to 32, the first contact nearest the median, the viewed invader living through the `match_npc_vision` window and the contact inside the opening window; seed 23 meets at 0.5 s). It is picked by that rule, never by which seed passes; `MATCH_PLAN` is the largest plan. Why seed 7 was left for seed 2 before it: `docs/adr/0017-district-perf-measurement-history.md`.
