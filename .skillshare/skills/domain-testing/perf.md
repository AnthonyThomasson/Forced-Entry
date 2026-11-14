# Performance tests (domain `perf`, `tests/perf/`)

Regression guards for speed and runaway object counts, one folder, one browser section, one selector. They are ordinary
tests that load other domains, so they live apart from them. Read `tests/perf/*_test.gd` for the loads: a
whole-match guard built as Main builds one (5v5, 10v10, and a 10v10 with the player's view on an NPC), a re-bake landing in a 5v5 match, a grenade fight (P1) and burst (P2) (`docs/grenades.md`,
"Performance"), an NPC crowd, automatic fire, hit overload, a crowd's deaths, a furniture pile, and one-shot work (nav
re-bake, world-gen of houses and of a district, the sound library's cold render). The re-bake and world-gen guards run on a district; the re-bake
guard measures the planning bake whole, what a frame pays to start one and a steering re-bake (the tile a character stops in).

- **Run:** `tools/run_tests.sh --domain=perf --quiet --summary` (add `--verbose` for the `PERF` lines). The pre-commit hook
  leaves the domain out (`--skip-domain=perf`): its frame-time budgets fail on a busy machine, so run it on its own before
  a push that touches a per-frame path. The default run holds it back from the shards and runs it alone last;
  `--changed` adds it when a scene they exercise changes (`affected()` in `tools/run_tests.sh`) or `tests/_perf/` changes.
- **A run that was not `--quiet` says so.** The gate waits only for a *busy* other Godot: an engine process (editor, test run,
  game) over `busy_cpu` percent of a core across `busy_sample_s` (`tools/perf_quiet.conf`); `godot-mcp` servers and idle
  editors do not hold it. If you run ungated (`uptime` under 6, none of your Godot busy), quote the
  `(load <x>, <n> busy Godot)` tails and never call it a `--quiet` run (`perf-district.md`).
- **Judge only a result not marked `loaded`:** `--quiet` waits for a quiet machine and marks a result `loaded` when it
  gave up (`runner-flags.md`); a `loaded` red or green says nothing about the code. Every `PERF` line ends with
  `(load <x>, <n> busy Godot)`, so a number read from a log carries the state of its machine.

## The standard

A match runs without frame loss, so every frame-based test holds `Perf.SMOOTH_AVG_MS` (16.7, one 60 fps frame),
`SMOOTH_P95_MS` (20) and `SMOOTH_MAX_MS` (33.4, two frames) through `Perf.within_frames(t, label, stats)`, at the scale of
the largest match (twenty characters), with no looser tail (the one decided exception: `grenade_match_stress`'s p95 is 25, its own `P95_MS` passed as `p95_limit`). One-shot work (`Perf.time_ms`) keeps a `const` budget at the
top of its test, about 4x the baseline stated in the comment above it. `Perf.within` prints `PERF <label> <value>
(budget <limit>)`, traces it and fails the check with the value. Counts (nodes, dents, pools) are asserted tightly.

**The standard is never loosened to fit a slower game:** make the game faster, or state in the test why one load is
heavier than a match. Update the "before" numbers in a test's comment only when its load changes.

## The helper (`tests/_perf/perf_probe.gd`, `const Perf := preload(...)`)

- **Measured:** wall-clock ms per frame (`Perf.frame_stats` → avg / p95 / max): the main-loop iteration a frame ran in.
  Headless `--fixed-fps` steps one physics frame an iteration, so this is the CPU cost; rendering is not covered. Also
  `Perf.time_ms` and exact counts (`Perf.nodes()`, `Despawner.count()`, dent and blood-pool caps).
- **The match guards share one match and warm-up:** `configure_match(s, per_side)` declares it (the downtown district
  `MATCH_SEED` with `MATCH_PLAN` as its centre house, pinned to the largest plan so a catalogue change never shrinks it; `s.declared_match`;
  scripted Von; callouts, vision and pursuit on; `worldgen.doors` off until #178 and #159 make the entry door-aware, the way the older AI
  tests on a generated house are), `warm_until_contact(t, label, characters)` runs `MATCH_WARMUP_S` then
  `await_contact` (at most `MATCH_CONTACT_WITHIN`, 30 s: the invaders start in the street) and `require`s contact as the premise (a shot fired and some NPC
  knowing a hostile, `knows_hostile`), and `MATCH_LOGS` is their `allowed_logs` (the re-bake's nav lines).
- **What the player's view costs is held as a difference** (`perf/match_npc_vision_relative`: one 10v10 in one process, blocks of frames
  with the view on and off, interleaved, since two plays of a match differ by far more than the view costs): `perf-vision-cost.md` (split out to keep this file under the 8192-byte cap).
  `perf/match_5v5_stress` is green on the district since #192; after Extensions 2 and 3 (2026-11-07) `perf/match_10v10_stress`,
  `perf/grenade_match_stress` and `perf/match_npc_vision` still miss and AC40 is not met; none is loosened, skipped or tagged:
  `perf-district-ext2.md`, `perf-district-ext3.md`, the gates the district moved: `perf-district.md`.
  What one NPC costs a frame (measured, #195): `perf-npc-cost.md`. A match's opening (`perf/match_10v10_opening`, from the first
  sighting or shot) and the worst-frames report `--verbose` prints for every frame guard: `perf-opening.md`.
- **A wall-clock budget belongs here and nowhere else:** the lint rule `timing_in_perf` fails a `Time.get_ticks_usec()`
  under `tests/` outside `tests/perf/` and `tests/_perf/`.

## Rendered too

`tools/run_tests.sh --windowed --domain=perf` (or `--id=`) measures the same tests with the render in each frame. The two
grenade guards frame the whole fight with the test camera, locked, as a player's screen would show it, so every body is
drawn; headless (a 64 px viewport) they size the root viewport to the project's window first. Windowed, `FillBatch` batches
the plain-coloured shapes.

**Windowed keeps the same budgets:** no windowed exemption and no looser number; what a window costs is fixed at its
cause, each fix pinned to the old pixels or bytes by a windowed-only test (`tests/character/body_mesh_matches_polygons_test.gd`,
`tests/physics/debris_pages_match_one_batch_test.gd`, `tests/general/fill_batch_matches_draw_calls_test.gd`). The sound
library's pre-warm renders on a worker thread (`domain-audio`); a sound was the only first use that hitched a fight in the frame logging of #195 (`domain-audio`).

## Comparing revisions, finding what costs

- **Compare two revisions with `tools/perf_ab.sh BASE TIP`, never by one run or a sim length:** it plays both in interleaved rounds on
  scratch worktrees, drops a `loaded` round, refuses ("fights differ from frame N") unless every round played the same fight, and
  prints the medians and the delta against `--bar`. A change that must not change the fight (a speed-up) uses that default; one
  that changes it on purpose (a later decision, a late cone) uses `--different-fights` (10 rounds, 2 at least; each side must replay its own
  fight, BASE and TIP need not; avg held to `--bar`; the report says "different fights"). How it reads: `perf-nondeterminism.md`;
  the fingerprint: `perf-fingerprint.md`.
- **Finding what costs, and gotchas** (attribute by timing, a lambda's ints, `nav.rebake`, cold world-gen, headless sound, per-piece callbacks, a speed-up pinned to the plain algorithm): `perf-gotchas.md`.
