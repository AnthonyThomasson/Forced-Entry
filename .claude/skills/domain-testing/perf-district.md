# Performance guards on the district (#182)

Side file of `domain-testing` (`perf.md`). The match guards moved from a lone house to a downtown district (`Perf.configure_match`),
and the standard of `perf.md` stands (`SMOOTH_*` is untouched; no guard is skipped or tagged). The exceptions are the five gates below, which moved on the district premise with the user's sign-off (recorded in the brief of the review-fix task), and each test header says why it is heavier than the house.

## Gates moved on the district premise

A district match is a different load from a house (nine towers and their streets, a nav map of about 800 polygons against 130, the
invaders starting in the street), so five gates moved. Each was signed off by the user.

- `Perf.MATCH_CONTACT_WITHIN` 20 → 30 s: the sides are in contact 6 to 30 s into a district match (the invaders walk in from the street).
- `perf/match_5v5_stress` timeout 40 → 50 s, for the same wait.
- `perf/bake_and_path_stress` `REBAKE_BUDGET_MS` 12 → 150 and `QUERY_BUDGET_MS` 10 → 60: it measures the planning re-bake of a district whole
  (~57 ms, a house ~2.5) and 300 queries on a map of ten times the polygons. The synchronous re-bake is now a test seam; what a frame
  pays is held by the new `ASYNC_BUDGET_MS` (60, starting an async re-bake) and `STEERING_BUDGET_MS` (15, a steering re-bake of the one to
  four tiles a character stops in).
- `perf/bake_and_path_stress` `STEERING_BUDGET_MS` 15 → 10 (#192, 2026-11-07): the steering re-bake of a tick read about 5.5 ms and now reads
  2.52 and 2.58 ms (a tick cuts only the pieces that moved), so the budget is set again at about 4x.
- `SMOOTH_AVG_MS`, `SMOOTH_P95_MS`, `SMOOTH_MAX_MS`, every vision budget and the house budgets of `perf/generate_houses_stress` did not move.

## After #192 and its Extension 1 (2026-11-07): AC30 is NOT met on this commit

**Not `--quiet` runs.** The quiet gate waited over ten minutes with no Godot of ours running (it counts the `godot-mcp` servers of other sessions
and a Godot app left open). The two runs are `tools/run_tests.sh --domain=perf --summary --verbose`, begun at a 1-minute load under 6 with none of
the worktree's own Godot left; their `PERF` lines read load 3.2 to 6.7 and `6 other Godot` (none a test's). None is marked `loaded` and none is claimed `--quiet`.

| Guard (ms) | run 1 avg / p95 / max | run 2 avg / p95 / max | budget |
|---|---|---|---|
| `match_5v5_stress` | 7.07 / 15.88 / 26.01 | 6.44 / 13.09 / 17.98 | 16.7 / 20 / 33.4: **green** |
| `grenade_match_stress` | 13.14 / **24.32** / **37.70** | 11.34 / 18.54 / **35.51** | red |
| `match_10v10_stress` | 12.93 / **27.07** / **56.08** | 14.03 / **25.90** / **37.93** | red |
| `match_npc_vision` | **22.53** / **35.97** / **46.69** | **20.13** / **31.25** / **42.67** | red (the moving view's cone: a follow-up) |
| `match_npc_vision_relative`, parked | **5.64** (rounds 1.0 to 11.7) | **4.77** (1.1 to 9.4) | 3.2, red (4.9 and 5.2 on 2026-11-02) |
| the same, moving | 11.89 | 10.90 | 20: green (cone ratio 0.23, moving 0.43) |

The other eleven guards pass (nav re-bake 55.8 and 53.6 ms, steering 2.52 and 2.58, 300 queries 23.3 and 22.9, a district 157 and 155,
12 houses 1849 and 1882). The budgets of the red four are not loosened; no test is skipped or tagged.

**Profile** (`Time.get_ticks_usec` accumulators on a scratch checkout, two runs each; 10v10 p95 24.9 and 30.0, max 63.6 and 57.3). The tail is the
escape search a grenade's landing sets off: `react_to_grenades` -> `evade_plan` -> `AgentThrow.escape`, 5.7 and 6.4 ms a call (grenade match
4.4), for several NPCs in one frame: 40 and 32 calls in the 10v10's 300 frames, in the 15 that set its p95; 53 and 49 in 29 and 28 of the grenade
match's 560. Four of the 10v10's five worst frames (50 to 64 ms) spend 39 to 46 ms in that reflex, one 20; the grenade match's worst, 31.7, spends
22.4. Tail frames average 33.4 and 36.7 ms against 9.8 and 11.8 in the lower half; escape is +11.3 and +7.2 of the 23 to 25 excess, decisions
+4.5 and +10.7, whose snapshots build in 4.0 and 4.3 ms and never over 8.4. The burst also swamps the relative guard's few-ms difference. A cap on
escape plans per frame is out of #192's scope.

**A flake of its own:** `vision/cone_same_after_savings` misses one corner in one cone of 5564 in about 2 to 8 runs in 100 under `--jobs=6` (9 of 10
at `--jobs=4`), on main too (1 of 48 on `f55dc462`'s scenes); a fresh cone misses it too. A follow-up.

## Known red on the district before #192: "AI decision cost in open combat" (#190)

Four match guards miss their budgets on the district (quiet machine, load 3 to 4, no other Godot, 2026-11-02; budgets avg 16.7, p95 20, max 33.4 ms):

| Guard | avg | p95 | max |
|---|---|---|---|
| `perf/match_5v5_stress` | 8.0 | 21.3 | 65.4 |
| `perf/grenade_match_stress` | 13.9 | 24.7 | 73.8 |
| `perf/match_10v10_stress` | 19.4 | 36.2 | 59.6 |
| `perf/match_npc_vision` | 25.0 | 48.7 | 70.1 |

Read again at the end of the review fixes (`--domain=perf --quiet`, load 3.9, none marked loaded, 2026-11-03): 5v5 avg 7.5, max 35.5 (p95 passes); grenade avg 15.0, p95 28.3, max 49.9; 10v10 avg 17.6, p95 44.0, max 92.7; vision avg 25.4, p95 46.5, max 74.2. The other 13 perf guards pass.

On main (1ae01f50, the same machine) the 5v5 passes, the grenade guard sits on its edge (p95 15 to 21, max 35) and the 10v10 and the vision guard were already red (#98). The cost is the AI's decisions in open fights. 10v10 over
600 frames, district against main: 288 to 344 decisions against 66 to 150, each 11 to 16 ms against 4 to 6; decisions with a hostile known
47 % against 13 % (long open sight lines keep hostiles known: 128 decision starts on a changed belief against 45); about 1.1 targets analysed
a decision against 0.27 (capped at 4). Per analysed target the district costs 1.5x (8.5 ms against 5.7): 810 tactics rays a decision against 302
(3.1 us each, a broadphase over the neighbours' walls and furniture), and 54 000 snaps and 25 000 routes in 600 frames (1.2 s of 4.7 s deciding).
A per-decision memo of identical rays hits 14 to 16 % and its lookup costs what it saves; a candidate cap would not bind (4 to 7 candidates a target).
Options for the follow-up, which change AI choices: re-decision hysteresis on belief changes (about 3 to 4 ms a frame), at most two targets fully
analysed a decision (about 1.5 ms), ray sharing between targets. Each guard's header says so; the guards stay as they are and go green with that ticket.

## The view's cost on the district (`perf/match_npc_vision_relative`), 2026-11-02

- The view's rise came with `5204e489` (the five district-cost fixes): the bisect read 3.9 ms at `d95ae639`, 10.4 at `5204e489` and 13.7 at `5df7f6db`.
  The Vision change (the cone casts its even fan once, queries the hull of its sector, `ViewWatch` rebuilds for a blocker where a ray can pass) brought it back
  to 4.9 ms and 5.2 ms in the next runs. The mechanism of the rise was **not isolated**: with `environment_object_visuals.gd` and `blood_smear.gd` put back to
  their older form it read 4.25; with only one of the two, 9 to 16; `reask_frames` 1 did not change it.
- On the district today: 0.88 ms (median of 12 rounds, rounds from -9.0 to +7.1), the cone at 0.11 of the reference's, against the 3.2 ms and 0.75 budgets.
  The budget 3.2 was set from eight quiet runs **on a house** and was not set again for the district; it is kept, not loosened.
- `perf/match_npc_vision`, the absolute guard on the same match, is red with the other three above.
