# Perf · What steered a match guard's fight, and what fixed it (#203)

Side file of `domain-testing`. State and the A/B tool: `perf-nondeterminism.md`; the fingerprint every cause below was found with: `perf-fingerprint.md`.

A match plays the same fight whatever ran before it in the process, with or without padding. What steered it, found with the fingerprint (first differing frame and field of two plays):

- **The AI's cadences read the process-global physics frame** (`Engine.get_physics_frames()`), so a match's phase followed how many frames the process had run.
  The sight cadence and the house look phase count `WorldRng.frame_of(node)` now: frames since the world's first character took its place.
- **`GameClock.seconds() - start >= 0.8` was false at 45 of 100 start frames** (floats rounded where they fall: `(f + 48) / 60 - f / 60 < 0.8`), so every such timer
  (a still leader's 0.8 s, a follower's re-aim) ended a frame late on some start frames: the first split was a follower's goal one frame late at frame 391, run
  after another match. `seconds()` reads 1e-9 above exact (`SECONDS_BIAS`): a timer ends on its frame.
- **`GameClock.msec()` reads 16 or 17 ms a frame by the frame a span starts on** (16 2/3 ms a frame): a walker's speed from two sightings (`PerceptionSight._track`)
  differed by a px/s, which flipped a give-way at frame 21 of the grenade guard. A world calls `GameClock.align()` at its start (`WorldRng`): the ms grid starts there,
  no jump in `msec()`.
- No split followed physics body or area order: plays with 777 and 333, 1013 and 7 padding and after other matches (their RIDs and instance ids shifted) played the
  same fight once the two above were fixed. The split #192 saw at frame 64 was most likely these two.

**Tests:** `perf/match_5v5_replay`, `grenade_match_replay`, `match_10v10_replay`, `match_npc_vision_replay` play the guard three times in one process (`tests/_perf/guard_replay.gd`: the guard
unchanged, in a world of its own, its fingerprint read back): plain, plain again 7 frames later, and with padding on 13 frames later, and the three must match line for line, through the
warm-up and the whole window, and have a shot in them. `general/game_clock_suite`, `general/world_rng_two_worlds`, `ai/perception/sight_checks_spread` pin the pieces.

**The guards' seed is 13 (was 7).** Played the same on every run, seed 7's fight became the slow one: the invaders clear the living room (stack, bang, cross, corner, clear, cover, rear: 18 s) while the
defenders hold an ambush at the garage doorway, so contact came at 31.3 s in the 5v5 and never in 36 s in the grenade guard, where the base's luck had it at 6 to 15 s. With main-thread map syncs it missed 9 of 10 runs
over avoid counts 10 to 16; with async syncs 6 of 8 were quick, so the sync puts this seed in the slow branch. Seeds 1 to 16 (not 7), contact: 13 and 2 at 8.1 to 8.6 s in the 5v5 and the grenade guard
(10v10s 6.0 s), 1, 5, 9, 12, 16 at once (6.0 s, the sides in sight at the end of the warm-up), 4 no contact, 6, 8, 10, 11 the viewed invader died. 13 is the first with a gap before contact and every premise held. `MATCH_PLAN` stays the
largest plan. No budget and not `MATCH_CONTACT_WITHIN` changed.

