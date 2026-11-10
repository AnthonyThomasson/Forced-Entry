# Perf · A match guard plays the same fight on every revision (#192 Extension 3, #203)

Until #203 a revision played its own match: the order and timing of events followed memory allocation or the wall clock, so
`perf/grenade_match_stress` read a sim length of 21.3 to 21.5 s merged against 20.4 s at base, and "the branch is slower in 8 of 8 pairs"
(`perf-district-ext3.md`) could not be told from a different fight. The sim length is `warm_until_contact` plus the window, so it is the
contact time. Never judge a match guard by its sim length or by one run.

## State of #203 (what exists, what is landing)

Built and pinned by tests: the fight fingerprint (`perf-fingerprint.md`: every NPC's position, goal, act and health, the shots and the
deaths, a line per physics frame through the warm-up and the whole window), the allocation-padding switch
(`testing.allocation_padding`: 777 nodes and 333 bodies, areas and shapes before the world is built, so a dependence on allocation
shows), the quiet gate that counts only busy engines (`perf.md`) and `tools/perf_ab.sh` (below). The look phase has been handed out in
turn since #192 (`look_phases.gd`).

**Landing in #203 (not on every branch yet; the final job writes the list as it merged):** the sight cadence, the give-way order and any
other AI order or timing keyed on an instance id moved to spawn order; a per-world RNG seeded from the match seed in place of the global
`randf`; the physics-order split #192 saw at frame 64. Until they merge, two plays of one revision do not match (the first reading below),
and `perf_ab.sh` refuses.

**Landed with the navigation job (#203):** a re-bake and an avoid map land on a fixed physics frame count after they start, the thread
waited for only when late (`NavBake`, `NavBakeConfig`; `domain-navigation`, its re-bake side file), and a navigation map syncs on the main
thread (`project.godot`, `navigation/world/map_use_async_iterations` off; `navigation/map_syncs_without_a_thread`). Both were needed: the
server's async sync showed a landed bake on a frame that followed the machine's load, so the 5v5 guard's contact came at 12 s, at 30 s or not
in 30 s at any landing count; with it off, four runs of one build had contact at 12.3 s each, and 14, 12 and 8 frames for the avoid maps gave
11.8, 11.5 and 10.5 s. Idle avoid maps are freed by physics frames, not wall-clock ms (`NavBuilder.avoid_idle_frames`). Each guard logs
`PERF <label> nav bakes late N of M` (`Perf.log_late_bakes`): a creeping share of late bakes means a count has fallen behind its thread.

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
  difference ends the run with `fights differ from frame N` (the test, the two revisions or rounds, the files kept), no delta and exit 3
  (a regression over the bar is exit 1, an unreadable run 2). Not the tool's fault: the revisions play different matches, or one revision does not replay its own. A revision from before the fingerprint
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
