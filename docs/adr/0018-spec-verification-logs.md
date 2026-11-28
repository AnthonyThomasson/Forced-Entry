# Verification logs the behaviour specs used to carry (#51, #54, #56, outfits)

Recorded for #194 (a docs sweep). `docs/grenades.md`, `docs/outfits.md` and `docs/vehicles.md` opened with a dated **Verification** paragraph each: what a
feature's wrap-up ran (lint, the suite, repeats, loads) and read in October 2026. They are history, not behaviour, so they left the specs; they are kept here
unedited. Every count, test id and number was true of that commit and none is a claim about the code now: `general/fill_batch_matches_draw_calls` and `general/use_vehicle_key`
no longer exist (the second was renamed `general/space_vehicle_key`), and the perf figures are of the 2D build.

**Decision.** A behaviour spec says what the code does and which tests assert it; the log of one run of the checks belongs to the commit or the pull request, and where
it is kept for the record it goes in an ADR, not in the spec.

## From `docs/grenades.md`

**Verification (15 October 2026, issue #51 final wrap-up, R1 to R17 and the audit's fixes on main `a03e23f`).** `tools/lint.sh` and
`tools/load_check.sh`: clean. The 50 tests issue #51 adds, `--repeat=10 --include-von --require-von --jobs=auto`: 500 passed, 0 failed (load average 5.5
before, 3.6 after); the 11 existing tests it changes, the same way: 110 passed, 0 failed. The whole suite, `tools/run_tests.sh --summary --jobs=auto
--include-von --require-von`: 407 passed, 0 failed, 0 timed out, 0 skipped, 0 `gap` (load average 5.3 before, 4.7 after). Perf, `tools/run_tests.sh
--domain=perf`, six runs each started at load average 3.5 to 4.4: 9 of 9 each time; 5v5 match 3.71 to 4.20 ms a frame on average (p95 5.31 to 6.47),
10v10 7.81 to 9.73 (p95 9.63 to 14.40), NPC crowd 4.32 to 4.92 (p95 6.43 to 13.30). Main `a03e23f` run in turn with two of them on the same machine:
5v5 3.63 to 3.80, 10v10 8.13 to 8.42, NPC crowd 4.08 to 4.49, so the branch costs 5 to 12 % more a frame in those pairs (0.3, 1.0 and 0.2 ms on the
mean), all within the 16.7 ms standard. `tools/von_probe.py tools/von_scenarios/grenade_*.json tools/von_scenarios/stun_entry_*.json --ablate -v`:
16 of 16.

**Verification (16 October 2026, issue #56 wrap-up after the audit's fixes, on origin/main `f0e4f8e`).** `tools/lint.sh` and
`tools/load_check.sh`: clean. Every test issue #56 adds or changes passes alone (the 19 headless ones one process each, the two perf ones in the
gated runs below, the two Von ones with `--include-von --require-von`); the timing-dependent ones 10 of 10 with `--repeat=10`,
`ai/grenade/stunned_defender_blind` and `stunned_defender_holds_fire` 3 of 3 on the real Von server. The whole suite, `tools/run_tests.sh --summary
--jobs=auto` (load 3.5 before, 5.4 after): 441 passed, 0 failed, 0 timed out, 44 skipped (the Von ones), 0 `gap`; all of `tests/ai/grenade/` on the
real Von server: 53 passed, 0 failed. `general/fill_batch_matches_draw_calls` and `items/prepaint_covers_the_draws` pass with `--windowed`. The
wrap-up before the audit's fixes saw one 94 ms frame of `perf/hit_overload_stress` in the whole suite (load 4.5 to 5.2, its average 12.1 and p95
14.0 within); it did not come back in 16 runs alternated with origin/main under a parallel load of 4.0 to 7.6, 3 more each alone at a load of 3 or
less (the branch at or below origin/main: avg 10.4-10.6 against 11.3-12.2), nor in this suite or the `--domain=perf` run below. The perf numbers
are under Performance below. *(Added 2026-11: that section of the spec is now in `docs/adr/0017-district-perf-measurement-history.md`,
"From `docs/grenades.md`".)*

## From `docs/outfits.md`

**Verification (14 October 2026, on the finished branch).** `tools/lint.sh` and the headless load check: clean. The 14 outfit tests (the 13
tagged `outfit` and `ai/entry/entry_guard_fires_from_outside`, whose bullet height is pinned to the torso) with `--repeat=10 --jobs=auto`:
140 runs, 140 passed (load average 4.4 before, 5.5 after). The whole suite with `--summary --jobs=auto`: 298 passed, 0 failed, 24 skipped
(the Von tests), 0 `gap`. `--domain=perf` alone: 9 of 9 passed (load average 4.4 before and after); `perf/hit_overload_stress`
with `--repeat=5`: 12.28 to 12.68 ms average a frame, against 12.14 to 12.70 ms on `main` measured the same way (load average 4.1).

## From `docs/vehicles.md`

**Verification (14 October 2026, on the finished branch).** `tools/lint.sh` and the headless load check: clean. The 34 tests the
feature adds (the 30 in `tests/vehicle/`, `audio/vehicle_sounds`, `audio/vehicle_door_tone`, `general/camera_zooms_out_driving`,
`general/use_vehicle_key`, since renamed `general/space_vehicle_key`): 34 passed. `tools/run_tests.sh --changed --summary --jobs=auto` (which runs everything): 332 passed,
0 failed, 24 skipped (they need the Von server), 0 `gap`; `--self-test`: 7 passed, 1 failed, `_harness/catalog_selection` ("an ai
test's category is the folder between its domain and its file"), which fails the same way on the clean base commit. Measured
(`vehicle/top_speed`, `vehicle/launch_and_brake`): tops 1280 / 880; 0 → 640 in 0.75 s, van 0 → 440 in 0.97 s; stop from the top
1.42 / 1.70 s.
