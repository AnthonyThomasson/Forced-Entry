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
- `SMOOTH_AVG_MS`, `SMOOTH_P95_MS`, `SMOOTH_MAX_MS`, every vision budget and the house budgets of `perf/generate_houses_stress` did not move.

## Known red on the district: "AI decision cost in open combat" (follow-up to #182)

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
