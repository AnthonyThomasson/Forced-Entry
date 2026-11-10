# Perf · A match guard plays the same fight on every revision (#192 Extension 3, #203)

Until #203 a revision played its own match: the order and timing of events followed memory allocation or the wall clock, so
`perf/grenade_match_stress` read a sim length of 21.3 to 21.5 s merged against 20.4 s at base, and "the branch is slower in 8 of 8 pairs"
(`perf-district-ext3.md`) could not be told from a different fight. The sim length is `warm_until_contact` plus the window, so it is the
contact time. Never judge a match guard by its sim length or by one run.

## What is deterministic now (#203, always on in the game, no switch)

Every order or timing that came from an allocation is keyed on spawn order, an id only ever being a lookup key; each one has a test of its own
in `tests/ai/`, `tests/navigation/` or `tests/perf/`:

- the look phase (`look_phases.gd`, #192) and the sight cadence (`perception_sight.gd`), handed out in turn;
- the give-way order (`loco_give_way.gd`) and any other AI order or timing that read an instance id;
- the planning re-bake (`NavRebake._bake_async`): its result lands on a fixed frame count after it starts and waits for the thread only
  when it is late (a late thread is the one wall-clock effect left: a quiet machine never shows it);
- randomness: each world has an RNG seeded from the match seed, used by projectiles, casings, explosions, debris, ragdolls and stun; two
  worlds in one process share none, and different match seeds still play different fights;
- the physics order #192 saw split at frame 64.

How it is proved: the fight fingerprint (`perf-fingerprint.md`: every NPC's position, goal, act and health, the shots and the deaths, a
line per physics frame through the warm-up and the whole window) of two plays of one revision is identical, with and without the
allocation padding (`testing.allocation_padding`: 777 nodes and 333 bodies, areas and shapes before the world, so any dependence on
allocation shows).

**TODO (#203, the acceptance run):** the result of `tools/perf_ab.sh HEAD~0 HEAD` on this ticket's own tip is written here when it has
run (identical fingerprints, the delta against the bar), with the four guards' two-run fingerprints and the padding on / off check.

## Reading rule: `tools/perf_ab.sh BASE TIP`

Compare two revisions only through it (`tools/perf_ab.py`'s header holds the flags, the scratch trees and the exit codes):

- **Rounds interleave** (BASE, TIP, BASE, TIP, ...), each round one `run_tests.sh --quiet --verbose` of that revision's own scratch
  worktree (`${TMPDIR}/forced-entry-perf-ab/<sha>`, built once and reused) with `GAME_TEST_FINGERPRINT_DIR` set per round. This replaces
  interleaving by hand: a drifting machine hits both revisions alike.
- **A round marked `loaded`** (the quiet gate gave up, `runner-flags.md`) is dropped and run again, at most `--retries` times (3), then the
  run ends: a loaded result says nothing about the code.
- **The fights must be the same.** Every round's fingerprint is checked against the first one of BASE, test by test; the first
  difference ends the run with `fights differ from frame N` (the test, the two revisions or rounds, the files kept) and no delta. Not
  the tool's fault: the revisions play different matches, or one revision does not replay its own. A revision from before the fingerprint
  has none and the run says so.
- **Only then** it prints per test the medians of avg / p95 / max ms per frame for both and the delta of each, in percent of BASE's
  median avg, and fails (exit 1) when the avg delta is over `--bar` (5). The medians resist a round the machine spoiled; p95 and max are
  read, not held.
- The pass is a statement about the revisions' cost on *one* fight; a budget (`Perf.within_frames`) is still the standard
  (`perf.md`), and the bar never replaces it.

A reading is only as quiet as its machine: quote the load of each `PERF` line (`perf.md`), and say when a run was not `--quiet`.

## History: what was shown before #203 (2026-11-07, scratch traces, `Perf.configure_match` 5v5)

- Base 1afec1d2 alone was not deterministic (contact at 11.1, 13.0, 11.2 s; the traces first split at frame 78): the planning re-bake landed on a
  worker thread, on a wall-clock frame. With it off each revision was stable run to run but played its own match, and 40 ms a frame
  changed none of it; any change to what the process allocates moved it.
- `perception_house.gd` phased each NPC's look by `perception.get_instance_id() % LEARN_EVERY_FRAMES`; ids step in fixed strides, so
  the phases clustered and moved with allocations (merged: nine NPCs on one frame). Handed out in turn since (`look_phases.gd`; `ai/perception/
  sight_learning_staggered`, `look_phases_two_worlds`, `house_look_cadence`). The sight cadence, the give-way order and the unseeded
  global `randf` were left, and are #203's.

## The fingerprint's first reading (2026-11-10, #203, before the determinism jobs)

Each guard twice with the fingerprint, padding off and on, at load 14 to 18 with 20+ other Godot. No pair matched; the first differing
frame, run 1 against 2, was 77 / 10 (5v5), 72 / 74 (grenade), 32 / 48 (10v10) and 57 / 31 (vision), off / on: a position a pixel or
three off, a goal, or an NPC's health with no shot logged, all long before contact (6 s, frame 360, or later). Padding off against on
differed too (frames 10, 120, 32, 49). Those are the jobs' starting point, not a state of the code.
