# Performance tests (domain `perf`, `tests/perf/`)

Regression guards for speed and runaway object counts, one folder, one browser section, one selector. They are ordinary
tests that load other domains, so they live apart from them. Read `tests/perf/*_stress_test.gd` for the loads: a
whole-match guard built as Main builds one (5v5, 10v10), a grenade fight (P1) and burst (P2) (`docs/grenades.md`,
"Performance"), an NPC crowd, automatic fire, hit overload, a crowd's deaths, a furniture pile, and one-shot work (nav
re-bake, world-gen, the sound library's cold render).

- **Run:** `tools/run_tests.sh --domain=perf --quiet --summary` (add `--verbose` for the `PERF` lines). The pre-commit hook
  leaves the domain out (`--skip-domain=perf`): its frame-time budgets fail on a busy machine, so run it on its own before
  a push that touches a per-frame path. The default run holds it back from the shards and runs it alone last;
  `--changed` adds it when a scene they exercise changes (`affected()` in `tools/run_tests.sh`) or `tests/_perf/` changes.
- **Judge only a result not marked `loaded`:** `--quiet` waits for a quiet machine and marks a result `loaded` when it
  gave up (`runner-flags.md`); a `loaded` red or green says nothing about the code. Every `PERF` line ends with
  `(load <x>, <n> other Godot)`, so a number read from a log carries the state of its machine.
- `perf/match_10v10_stress` is red on a quiet machine until #98 (an invader's decision that weighs its grenades spikes in
  one frame), by the user's decision: the standard is untouched.

## The standard

A match runs without frame loss, so every frame-based test holds `Perf.SMOOTH_AVG_MS` (16.7, one 60 fps frame),
`SMOOTH_P95_MS` (20) and `SMOOTH_MAX_MS` (33.4, two frames) through `Perf.within_frames(t, label, stats)`, at the scale of
the largest match (twenty characters), with no looser tail. One-shot work (`Perf.time_ms`) keeps a `const` budget at the
top of its test, about 4x the baseline stated in the comment above it. `Perf.within` prints `PERF <label> <value>
(budget <limit>)`, traces it and fails the check with the value. Counts (nodes, dents, pools) are asserted tightly.

**The standard is never loosened to fit a slower game:** make the game faster, or state in the test why one load is
heavier than a match. Update the "before" numbers in a test's comment only when its load changes.

## The helper (`tests/_perf/perf_probe.gd`, `const Perf := preload(...)`)

- **Measured:** wall-clock ms per frame (`Perf.frame_stats` → avg / p95 / max): the main-loop iteration a frame ran in.
  Headless `--fixed-fps` steps one physics frame an iteration, so this is the CPU cost; rendering is not covered. Also
  `Perf.time_ms` and exact counts (`Perf.nodes()`, `Despawner.count()`, dent and blood-pool caps).
- **The three match guards share one match and warm-up:** `configure_match(s, per_side)` declares it (the house
  `MATCH_SEED` on `MATCH_PLAN`, pinned to the largest plan so a catalogue change never shrinks it; `s.declared_match`;
  scripted Von; callouts, vision and pursuit on), `warm_until_contact(t, label, characters)` runs `MATCH_WARMUP_S` then
  `await_contact` (at most `MATCH_CONTACT_WITHIN`) and `require`s contact as the premise (a shot fired and some NPC
  knowing a hostile, `knows_hostile`), and `MATCH_LOGS` is their `allowed_logs` (the re-bake's nav lines).
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
library's pre-warm renders on a worker thread (`domain-audio`). A windowed run does not yet meet the standard everywhere
(`docs/grenades.md`, "Performance"); that is the honest state, not a reason to loosen it.

## Finding what costs, and gotchas

- **Attribute by timing:** a frame's wall time is script time. A throwaway `Time.get_ticks_usec` accumulator around the
  suspect functions (never committed), dumped at the end of the measured window, ranks them in minutes; switching a
  feature off with `set_static` / `switch` shows what it is worth. Measure before reading: a per-frame cost is rarely
  where the code suggests.
- A lambda captures ints by value (count into an Array).
- `nav.rebake` is off in tests that shove or shoot furniture into overlaps (re-baking overlapping holes logs a nav sync
  error); the match guards keep it on and allow that log (`MATCH_LOGS`).
- World-gen's first run in a process is slower (cold caches), so its budget covers the cold case.
- Headless runs skip the sound pre-warm: a test that plays sound calls `Perf.warm_sounds()` first or turns `audio.sound`
  off, or the first play of each variant (9 to 35 ms) lands in its worst frame.
- A speed-up must not change what the game does: where a fast path replaces a plain algorithm, a test pins its output to
  the plain one (`navigation/furniture_union_fast_path`, `physics/blood_splat_merge_fast_path`,
  `physics/convex_pieces_match_plain_scan`, `physics/shape_polygon_cache`).
