# Perf · A match guard plays the same fight on every revision (#192 Extension 3, #203)

Until #203 a revision played its own match: the order and timing of events followed memory allocation or the wall clock, so
`perf/grenade_match_stress` read a sim length of 21.3 to 21.5 s merged against 20.4 s at base, and "the branch is slower in 8 of 8 pairs"
(`perf-district-ext3.md`) could not be told from a different fight. The sim length is `warm_until_contact` plus the window, so it is the
contact time. Never judge a guard by its sim length or one run.

## State of #203 (all landed)

Everything #203 set out to build has landed on the tip and is pinned by tests: the fight fingerprint (`perf-fingerprint.md`: every NPC's position, goal, act and health, the shots and the
deaths, a line per physics frame through the warm-up and the whole window), the allocation-padding switch
(`testing.allocation_padding`: 777 nodes and 333 bodies, areas and shapes before the world is built, so a dependence on allocation
shows), the quiet gate that counts only busy engines (`perf.md`) and `tools/perf_ab.sh` (below). The look phase has been handed out in
turn since #192 (`look_phases.gd`); the sight cadence, the give-way order and the AI's other orders are keyed on spawn order (`WorldRng`).

**The cadences-and-clock job:** a match plays the same fight whatever ran before it in the process, with or without padding: the AI's cadences
count the world's own frames (`WorldRng.frame_of`), `GameClock.seconds()` and `msec()` no longer follow the frame a timer started on, the guards' seed is 2, and four replay tests
pin it. The split #192 saw at frame 64 reproduces, as a kind, on the tip before this job (the replays split at frames 8 to 61, 260 to 610 on one phase) and not after it; padding alone never split a fight. The causes, the tests and the seed: `perf-determinism-causes.md`.

**The navigation job:** a re-bake and an avoid map land on a fixed game-frame count after they start, the thread
waited for only when late (`NavBake`, `NavBakeConfig`; `domain-navigation`, its re-bake side file), and a navigation map syncs on the main
thread (`project.godot`, `navigation/world/map_use_async_iterations` off; `navigation/map_syncs_without_a_thread`). Both were needed: the
server's async sync showed a landed bake on a frame that followed the machine's load, so the 5v5 guard's contact came at 12 s, at 30 s or not
in 30 s at any landing count; with it off, four runs of one build had contact at 12.3 s each, and 14, 12 and 8 frames for the avoid maps gave
11.8, 11.5 and 10.5 s. Idle avoid maps are freed by game frames, not wall-clock ms (`NavBuilder.avoid_idle_frames`). Each guard logs
`PERF <label> nav bakes late N of M` (`Perf.log_late_bakes`): a creeping share of late bakes means a count has fallen behind its thread.

**What the main-thread sync costs (#203, seed 2, 5v5 and 10v10 guards, `--quiet` cleared: 0 busy Godot, load 5.0 to 6.7; sync vs async interleaved, four rounds):** sync 5v5 avg 6.82
p95 14.8 max 28.6 ms; 10v10 avg 12.58 p95 21.7 max 31.5. Async plays another fight (5v5 contact 22.9 s in three runs of four, 8.1 s in the fourth), so its numbers are of a lighter load, not the flag's; where the fight is the same (10v10 at 6.0 s: avg 12.94 p95 18.3 max 29.8; the 5v5's one 8.1 s run: avg 6.88 p95 15.15 max 22.7) the sync is within 0.4 ms of the average and its max
stays under `SMOOTH_MAX_MS`, so no frame is pushed over it. An earlier reading on seed 13 (5v5 p95 20.3 sync vs 15.0 async) compared different fights and carried late-bake spikes: it is not the flag's cost. The 10v10 p95 stays over 20 ms either way (known red, `match_10v10_stress_test.gd`).

**Acceptance run (#203, 2026-11-10, tip `3dae2431`, seed 2, machine load 7.1 at the start to 4.3 at the end, no round marked `loaded`, none dropped):** `tools/perf_ab.sh HEAD~0 HEAD`
(the default four guards, `--rounds=6`, `--bar=5`, BASE and TIP the one sha and so one scratch tree: a same-revision A/B, the tool's noise floor) reported identical fingerprints for all 12 plays of each guard (no `fights differ`)
and `perf_ab: PASS`, exit 0. Medians of six rounds, BASE / TIP avg ms per frame and the avg delta in percent of BASE's avg: 5v5 7.89 / 7.78 (-1.5%), grenade match 12.97 / 12.94 (-0.3%),
10v10 16.90 / 16.87 (-0.1%), NPC-vision match 19.98 / 19.88 (-0.6%); p95 and max moved by at most +1.3% and +6.8% (the vision guard's max, 48.44 / 49.79 ms; read, not held). Load was read with `uptime` before (7.1) and after (4.3) the run only, not per round, and the ms read heavier than the sync reading above (5v5 avg 6.7 there, 7.9 here): quote these ms for the delta, not as a level. The two-run and padding-on / off fingerprint
checks of each guard are the replay tests (`perf/match_5v5_replay`, `grenade_match_replay`, `match_10v10_replay`, `match_npc_vision_replay`), green on this tip.

## Reading rule: `tools/perf_ab.sh BASE TIP`

Compare two revisions only through it (`tools/perf_ab.py`'s header holds the flags, the scratch trees and the exit codes):

- **Rounds interleave** (BASE, TIP, BASE, TIP, ...), each round one `run_tests.sh --quiet --verbose` of that revision's own scratch
  worktree (`${TMPDIR}/forced-entry-perf-ab/<sha>`, built once and reused; BASE and TIP the one sha share one) with `GAME_TEST_FINGERPRINT_DIR` set per round. This replaces
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
