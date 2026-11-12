# Perf · A match's opening, and the worst-frames report (#195)

**The opening guard, `perf/match_10v10_opening`.** The match guards open their window late: `warm_until_contact` waits `MATCH_WARMUP_S`
and then for a shot AND some NPC knowing a hostile, so `match_10v10_stress` opens at 8.8 s of test time while the first sighting is at
4.2 s (seed 2). The first sightings, the first decisions, throws and escape searches were in no window, and a player feels those as
the stutter when a fight starts. This guard is the same match (`configure_match`, 10 a side) with its window opened by
`Perf.await_first_contact`: the first shot or the first NPC knowing a hostile, whichever comes first (`"shot"` or `"sighting"`).
It runs `Perf.OPENING_FRAMES` (300, five seconds) from there, so it overlaps the start of the stress window and is held to `Perf.within_frames` (16.7 / 20 / 33.4), no looser tail.
Premises: at most `MOST_SHOTS_BEFORE` shots before the window; a shot and decisions asked in it. It calls `Perf.record_fight`;
`perf/match_10v10_opening_replay` plays it three times and diffs the fingerprints (green: the opening is one fixed fight, the
window 4.2 to 9.2 s, the stress guard's opening at 8.8 s). It is not in `perf_ab.py`'s default ids (the four match guards are): `--ids=perf/match_10v10_opening`.

**Measured (2026-11-12, tip 98e9b9b2 plus these changes, window 300 frames, `--quiet`, none `loaded`):** (load 2.94, 0 busy
Godot) avg 11.92, p95 22.04, max 32.95 ms; (load 6.95, 0 busy Godot) 12.00 / 22.72 / 33.85; (load 3.86, 5 busy Godot, not a quiet
run) 12.58 / 24.45 / 35.63. Red on p95 every run, on max in two. The first 240 frames, three runs at load 3.7 to 4.3: avg 11.88 to
12.41, p95 21.19 to 22.23, max 32.25 to 35.01. Its worst frames, stable across runs: #285 (33 to 36 ms, a decision claimed, two
asked, a callout), #195 (31 to 35 ms, nothing counted), #15 (27 to 29 ms, a claim and a callout), #84 (a claim and a nav bake), #60
(nothing counted) and #43 (a claim, an ask, three callouts). Spikes with nothing counted are not decisions and not yet attributed.
Sliced decisions (job dec-price) are expected to change this.

**The worst-frames report.** `Perf.frame_stats` returns, beside `avg_ms` / `p95_ms` / `max_ms`, `samples` (each frame's ms) and
`ran` (what ran in each frame, an empty Array unless the game's log is on). `Perf.within_frames` (so every frame-based guard) prints, under
`--verbose`, `PERF <label> worst frames:` and the `Perf.WORST_FRAMES` (5) slowest, `#<frame in the window> <ms> ms: <what ran>`.
What ran is the rise of counters between a frame's start and the next (`tests/_perf/frame_report.gd`): decisions claimed (`DecisionRoster.claims()`, a forgotten job that
runs again not counted: a decision's build runs in its claim frame), decisions asked (`DecisionStub.requests`, one a
level), cone starts and publishes (`PlayerView.starts` / `rebuilds`, when a view is on), grenades thrown, explosions, callouts,
deaths and shots (the event log) and nav bakes started and late. Nothing is counted without `--verbose` and no game code gained a
line; the counters' reads (a few ints) are in the verbose run's frames. The pure part is `tests/perf/frame_report_suite.gd`.
A frame with nothing counted is not a decision and not yet attributed (an escape search, a nav tick or the engine?): attribute it by timing (`perf-gotchas.md`).
`perf/frame_report_counters` checks the counters on a live world (every count an int, a shot in its frame; nothing counted with the log off).
