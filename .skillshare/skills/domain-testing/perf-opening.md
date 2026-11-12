# Perf · A match's opening, and the worst-frames report (#195)

**The opening guard, `perf/match_10v10_opening`.** The match guards open their window late: `warm_until_contact` waits `MATCH_WARMUP_S`
and then for a shot AND some NPC knowing a hostile, so `match_10v10_stress` opens at 8.8 s of test time while the first sighting is at
4.2 s (seed 2). The first sightings, the first decisions, throws and escape searches were in no window, and a player feels those as
the stutter when a fight starts. This guard is the same match (`configure_match`, 10 a side) with its window opened by
`Perf.await_first_contact`: the first shot or the first NPC knowing a hostile, whichever comes first (`"shot"` or `"sighting"`).
It runs `Perf.OPENING_FRAMES` (240, four seconds) from there and is held to `Perf.within_frames` (16.7 / 20 / 33.4), no looser tail.
Premises: at most `MOST_SHOTS_BEFORE` shots before the window; a shot and decisions asked in it. It calls `Perf.record_fight`;
`perf/match_10v10_opening_replay` plays it three times and diffs the fingerprints (green: the opening is one fixed fight, the
window 4.2 to 8.2 s). It is not in `perf_ab.py`'s default ids (the four match guards are): `--ids=perf/match_10v10_opening`.

**Measured (2026-11-12, tip 98e9b9b2, `--quiet`, load 3.7 to 4.3, no busy Godot, none `loaded`; three runs):** avg 12.22 / 11.88 /
12.41, p95 21.83 / 21.19 / 22.23, max 32.74 / 32.25 / 35.01 ms. Red on p95 every run, on max once. Its worst frames (stable across
runs): #195 (32 to 35 ms, nothing counted), #15 (28 ms, a claimed decision and a callout), #60 (27 to 28 ms, nothing counted), #84
(26 to 28 ms, a decision claimed and a nav bake) and #43 (26 ms, a claim, an ask and three callouts). Spikes with nothing
counted are not decisions: they are the escape searches and engine frames. Sliced decisions (job dec-price) are expected to change this.

**The worst-frames report.** `Perf.frame_stats` returns, beside `avg_ms` / `p95_ms` / `max_ms`, `samples` (each frame's ms) and
`ran` (what ran in each frame, `{}` unless the game's log is on). `Perf.within_frames` (so every frame-based guard) prints, under
`--verbose`, `PERF <label> worst frames:` and the `Perf.WORST_FRAMES` (5) slowest, `#<frame in the window> <ms> ms: <what ran>`.
What ran is the rise of counters between a frame's start and the next (`tests/_perf/frame_report.gd`): decisions claimed (the roster's
`_seq`, read as a Script's static: a decision's build runs in its claim frame), decisions asked (`DecisionStub.requests`, one a
level), cone starts and publishes (`PlayerView.starts` / `rebuilds`, when a view is on), grenades thrown, explosions, callouts,
deaths and shots (the event log) and nav bakes started and late. Nothing is counted without `--verbose` and no game code gained a
line; the counters' reads (a few ints) are in the verbose run's frames. The pure part is `tests/perf/frame_report_suite.gd`.
A frame with nothing counted is an escape search, a nav tick or the engine: attribute it by timing (`perf-gotchas.md`).
