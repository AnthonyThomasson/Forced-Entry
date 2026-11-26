# The district perf guards' measurement history (#182, #192, #195)

Recorded for #194 (docs sweep, job 20). The `domain-testing` perf skills state what holds now: the guards, their premises and the rules to keep. Their dated
measurement runs, profiles, spikes and the budgets that were red when each was taken lived there too; they are here, unedited but for the heading levels.
Every number below was measured on the 2D build (before #194), but for the dated 3D-build (#194) entries of the player's view near the end: the 2D `character_visuals` `_draw` rows, `draw_cache_pixel_identical` and the draw caches, the
nav polygon counts and the baker are gone or changed (ADR 0016), so none is a baseline for the 3D build; the perf guards' own `PERF` lines are.

**Decision.** A skill is current state only; a measurement with a date and a commit is history and goes in an ADR. The standing rules stay in `perf.md`,
`perf-district.md` (the gates the district moved), `perf-opening.md` (the opening guard and the worst-frames report), `perf-npc-cost.md`,
`perf-nondeterminism.md` and `perf-gotchas.md`.

## From `perf-district.md`

### After #192's Extension 3 (2026-11-07): AC40 is NOT met

5v5 green; the grenade match's p95 reads 18.9 to 22.3 (red in three of six reads); `match_10v10_stress` and `match_npc_vision` recorded red; the parked and moving view guards green with a tightened `MOVING_BUDGET_MS` 8.5. Runs, loads and both spikes' findings: `perf-district-ext3.md`.

### After #192's Extension 2 (2026-11-07): AC34 is NOT met

The escape search is capped and pruned; its tail is gone, but `match_10v10_stress`, `grenade_match_stress` (p95, once) and `match_npc_vision` still miss. Two ungated runs, the frame profile and the three levers: `perf-district-ext2.md`.

### After #192 and its Extension 1 (2026-11-07): AC30 is NOT met on this commit

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

### Known red on the district before #192: "AI decision cost in open combat" (#190)

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

### The view's cost on the district (`perf/match_npc_vision_relative`), 2026-11-02

- The view's rise came with `5204e489` (the five district-cost fixes): the bisect read 3.9 ms at `d95ae639`, 10.4 at `5204e489` and 13.7 at `5df7f6db`.
  The Vision change (the cone casts its even fan once, queries the hull of its sector, `ViewWatch` rebuilds for a blocker where a ray can pass) brought it back
  to 4.9 ms and 5.2 ms in the next runs. The mechanism of the rise was **not isolated**: with `environment_object_visuals.gd` and `blood_smear.gd` put back to
  their older form it read 4.25; with only one of the two, 9 to 16; `reask_frames` 1 did not change it.
- On the district today: 0.88 ms (median of 12 rounds, rounds from -9.0 to +7.1), the cone at 0.11 of the reference's, against the 3.2 ms and 0.75 budgets.
  The budget 3.2 was set from eight quiet runs **on a house** and was not set again for the district; it is kept, not loosened.
- `perf/match_npc_vision`, the absolute guard on the same match, is red with the other three above.

## From `perf-opening.md`

**Measured (2026-11-12, tip 98e9b9b2 plus these changes, window 300 frames, `--quiet`, none `loaded`):** (load 2.94, 0 busy
Godot) avg 11.92, p95 22.04, max 32.95 ms; (load 6.95, 0 busy Godot) 12.00 / 22.72 / 33.85; (load 3.86, 5 busy Godot, not a quiet
run) 12.58 / 24.45 / 35.63. Red on p95 every run, on max in two. The first 240 frames, three runs at load 3.7 to 4.3: avg 11.88 to
12.41, p95 21.19 to 22.23, max 32.25 to 35.01. Its worst frames, stable across runs: #285 (33 to 36 ms, a decision claimed, two
asked, a callout), #195 (31 to 35 ms, nothing counted), #15 (27 to 29 ms, a claim and a callout), #84 (a claim and a nav bake), #60
(nothing counted) and #43 (a claim, an ask, three callouts). Spikes with nothing counted are not decisions and not yet attributed.
Sliced decisions (job dec-price) are expected to change this.

## Extension 2 (from `perf-district-ext2.md`)

Side file of `perf-district.md` (`perf.md`, `domain-testing`).

### After #192's Extension 2 (2026-11-07): AC34 is NOT met, the escape tail is gone

The escape search is pruned (nearest route first, stop past the best) and capped at `AgentGrenades.ESCAPE_CAP` 3 a physics frame (a count, not a cost: #194 job 20 perf-escape replaced it with `EscapePool`, 80 units a frame, `perception-grenades.md`) (fresh plans first, a
replan keeps one slot; `docs/grenades.md` G16: an NPC may start its run up to 3 frames late, which matches the code). A call now costs 3.4 ms (5.7 and 6.4 before), at most 3
run in a frame, 59 and 50 calls in the grenade match's 560 frames (53 and 49 before, in 29 and 28 frames over 20 ms).

**Not `--quiet` runs, on purpose.** The quiet gate counts every Godot process, and 13 are on this machine (other sessions' editors and `godot-mcp` servers, none a
test's of this worktree), so it would wait for ever. The two runs are `tools/run_tests.sh --domain=perf --summary --verbose` with none of this worktree's Godot left
over; `uptime` 1-minute load 4.93 before and 3.24 after run 1, 3.24 before and 4.77 after run 2; the `PERF` lines read load 3.2 to 5.7 and 10 to 13 other
Godot. None is marked `loaded`, none is claimed `--quiet`.

| Guard (ms) | run 1 avg / p95 / max | run 2 avg / p95 / max | budget |
|---|---|---|---|
| `match_5v5_stress` | 7.09 / 13.69 / 22.06 | 7.59 / 15.22 / 23.81 | 16.7 / 20 / 33.4: **green** |
| `grenade_match_stress` | 11.61 / 19.05 / 29.59 (green) | 12.60 / **20.80** / 31.51 | p95 red in run 2 |
| `match_10v10_stress` | 13.58 / **21.74** / 30.13 | 13.46 / **23.22** / **50.03** | red |
| `match_npc_vision` | **20.45** / **33.06** / **48.67** | **19.11** / **32.60** / **40.16** | red |
| `match_npc_vision_relative`, parked | **5.48** (rounds 1.2 to 8.5) | 1.21 (rounds -1.6 to 6.5) | 3.2: red once, green once |
| the same, moving | 13.00 (cone ratio parked 0.27, moving 0.42) | 12.97 (0.13, 0.45) | 20: green |

The other twelve guards pass (nav re-bake 56.1 and 54.6 ms, steering 2.65 and 2.60, 300 queries 23.9 and 22.9, a district 157.5 and 158.8, 12 houses 1883 and 1859).
Against Extension 1: the grenade match's p95 fell from 24.3 and 18.5 to 19.05 and 20.8 and its max from 37.7 and 35.5 to 29.6 and 31.5; the 10v10's p95 and max
are unchanged within the run-to-run spread (p95 27.1 and 25.9 then, 21.7 and 23.2 now; max 56.1 and 37.9 then, 30.1 and 50.0 now), and it never threw a grenade (zero escape
calls). AC34 (all four match guards within budget) is not met. No budget is loosened, no test skipped or tagged.

#### Profile of the frames that set p95 and max (2026-11-07, HEAD 05f0b476)

`Time.get_ticks_usec` accumulators on a throwaway checkout of HEAD (never committed, deleted): `fe-prof-patch-ext2.py` (profile-2's `patch_prof.py` in `deep` mode, output
to `/tmp/fe-ext2/out`), two runs each of `match_10v10_stress` (300 frames) and `grenade_match_stress` (560), ungated, load 3.8 to 5.6. Instrumented frames cost
more than stock (10v10 avg 17.6 and 18.0 against 13.5; p95 31.0 and 30.2; grenade avg 13.1, p95 21.4 and 20.8), so **read the shares and the deltas**.
Frame sets per run: the lower half (the 150 or 280 fastest frames), the top 5 % (15 or 28 frames: these set p95 and max), the single worst frame. Means of the two runs, ms:

| | 10v10 lower half | 10v10 top 5 % | grenade lower half | grenade top 5 % |
|---|---|---|---|---|
| frame | 13.9 | **33.0** | 10.4 | **23.8** |
| decisions (the decision start, now the job; `snap.build` inside) | 0.1 (0.1) | **11.2 (7.3)** | 0.0 (0.0) | **3.3 (1.1)** |
| per-NPC fixed: `observe` (`sight.see` inside) | 3.0 (2.3) | 3.4 (2.6) | 0.9 (0.5) | 1.0 (0.6) |
| per-NPC fixed: `behavior.apply` | 3.3 | 4.8 | 1.1 | 2.3 |
| other AI (`control` less decision, observe, apply, react) | 1.9 | 2.4 | 0.7 | 1.0 |
| `anatomy.step` (Character) | 2.0 | 2.0 | 1.2 | 1.5 |
| react / escape (`AgentThrow.escape` inside) | 0.2 (0) | 0.2 (0) | 0.4 (0) | 1.8 (1.6) |
| nav tick | 0 | 1.0 | 0 | 1.5 |
| `character_visuals` `_draw` | 0.1 | 0.2 | **3.2** | 4.0 |
| other `_draw` (blood pools, debris, shots) | 0.8 | 0.8 | 0.1 | 0.3 |
| physics engine and the rest of the physics step | 1.0 | **5.1** | 0.8 | 4.1 |
| rest (non-AI character, `_process`, render, idle, GC) | 1.6 | 2.3 | 2.3 | 3.2 |

- **10v10: the tail is the decision build.** Every frame of the top 5 % holds a decision (0.93 and 1.00 a frame; 0.03 and 0.05 in the lower half): 11.1 of the 19.1 ms the
  top frames add over the lower half, 7.2 of it `snap.build`; physics adds 4.1 (colliding pairs do not rise, 363 and 461 against 370 and 445: spikes, not contact count).
  A decision costs 5.2 and 4.7 ms on average, 18.1 and 10.8 at most. The two worst frames: 38.3 ms (decision 16.1, `snap.build` 9.5, physics 7.6) and 39.5 ms (a nav tick 12.6,
  decision 10.8). No escape call anywhere in the 10v10. The calm frame is already 13.9 ms: 20 NPCs at 0.5 ms (`observe` 3.0, `apply` 3.3, other AI 1.9, `anatomy.step` 2.0 = 10 ms),
  so a frame with no decision sits near 14 and a frame with one lands at 25 to 35.
- **Grenade match: a high floor more than a tail.** The lower half is 10.4 ms and 3.2 of it is `character_visuals` `_draw` (5761 and 5630 draws in 560 frames, about 10 a frame, the
  match framed whole by the test camera as a player's screen would show it): it is in every frame, so it moves p95 and max alike. The top 5 % add 13.4 ms over the lower half: decisions 3.3
  (a decision in 0.5 to 0.6 of those frames), physics 3.3, escape 1.4 (the cap held: at most 3 calls of 3.4 ms a frame), nav tick 1.5, `apply` 1.2. Its worst frames are
  30.3 ms (physics 13.8, decision 6.9) and 30.8 ms (a nav tick 7.7, `apply` 5.3).
- The nav tick (a steering tick, then a planning gather, one tick in about 45 frames) is in 5 to 9 of the 15 to 28 top frames of a run and is the single worst frame of 10v10 run 2 (12.6 ms).

**The three levers** (estimates by re-playing the measured frames of both runs, deltas of p95 / max on instrumented frames; not implemented):

| # | Lever | Domain | 10v10 p95 / max | grenade p95 / max |
|---|---|---|---|---|
| 1 | Make a decision build cheaper or sliced: build option groups on demand (profile-2: a build skips 2.1 to 3.2 ms; 81 % of decisions read only the `grenade_ready` existence check), or hold a build to about 6 ms a frame | AI (`agent_snapshot`, `decision`) | on demand -2.5 / -2.5; capped at 6 ms -4.4 / -4.8 | on demand -0.7 / -1.6; capped -0.6 / -0.4 |
| 2 | Redraw a character's visuals only when they change (`character_visuals` `_draw`: 3.2 ms in the lower half of the grenade match, 0.1 in the headless 10v10) | Character (visuals) | about 0 (barely drawn there) | -2.4 / -1.9 (at -60 %) |
| 3 | Cut the per-NPC fixed cost, 10 ms of the 10v10's calm frame: `sight.see` 2.3 (-40 %), `anatomy.step` 2.0 (-50 %), `apply` 3.3 | AI (perception, behaviour); Character (`anatomy`) | -1.1 / -1.0 (sight), -1.0 / -0.9 (anatomy) | -0.2 / -0.2 (sight), -0.7 / -0.8 (anatomy) |

A fourth, in Navigation: spread the nav tick over about 8 frames (-0.7 / -2.0 in the 10v10, -0.5 / -0.9 in the grenade match; profile-2 read -2.1 and -2.6 on p95 for the
quiet guards). The engine's physics step adds 4 to 5 ms to the top frames of both guards, with no lever of ours (colliding pairs do not rise). Taken together, levers 1 and 3 could bring the
10v10's p95 from about 22.5 stock to 17 to 19, and lever 2 alone the grenade match's p95 from 19 to 21 down to 17 to 18; the 10v10's max (30 to 50) and the viewed-NPC guard still need
the structural change profile-2 named. Tools: `/tmp/fe-perf-findings/fe-prof-patch-ext2.py` and `fe-prof-analyze-ext2.py` (not in the repo).

## Extension 3 (from `perf-district-ext3.md`)

Side file of `perf-district.md` (`perf.md`, `domain-testing`). Extension 3 (rules 33 to 38) merged the view's fan table and pose lag, the
character draw caches and the decision micro bundle. Runs were made 2026-11-07 on the merge of the three slices
(`b947d6e8`, story branch `AnthonyThomasson/Investigate-strategies-to-improve-performce`).

### After #192's Extension 3 (2026-11-07): AC40 is NOT met

**Not `--quiet` runs, on purpose.** The quiet gate counts every process with `godot` in its name (the `godot-mcp` servers of other sessions, an editor)
and would wait for ever, so the runs are `tools/run_tests.sh --domain=perf --summary --verbose`, ungated, with none of this worktree's own Godot left over.
`uptime` 1-minute load: run 1 3.20 before and 4.89 after, run 2 4.89 before and 5.85 after. The `PERF` lines read load 4.1 to 7.8 and 9 other Godot
(none a test's). None is marked `loaded`, none is claimed `--quiet`.

| Guard (ms) | run 1 avg / p95 / max | run 2 avg / p95 / max | budget |
|---|---|---|---|
| `match_5v5_stress` | 6.84 / 13.60 / 19.44 | 8.72 / 18.86 / 26.91 | 16.7 / 20 / 33.4: **green** |
| `grenade_match_stress` | 12.45 / **21.12** / 32.60 | 11.61 / 18.95 / 32.80 | p95 red in run 1 |
| `match_10v10_stress` | 13.67 / **24.18** / 31.30 | 15.58 / **26.20** / **40.33** | red |
| `match_npc_vision` | **27.13** / **45.20** / **69.05** | **23.84** / **43.59** / **59.90** | red |
| `match_npc_vision_relative`, parked | -1.70 (rounds -7.2 to 1.9) | -1.58 (rounds -3.6 to 0.0) | 3.2: green (red on 3 of the 4 reads of Extensions 1 and 2) |
| the same, moving | 4.60 (rounds 2.5 to 6.5) | 5.61 (rounds 3.3 to 7.2) | 8.5: green (11.9 and 10.9 before; the loop turns 6 degrees a frame, past the pose lag's bounds, so the gain is the fan table alone) |

Live cone / reference cone: parked 0.08 and 0.07 (budget 0.75), moving 0.59 and 0.58. The other 12 guards pass (run 1: 14 passed, 3 failed; run 2: 15 passed, 2 failed).
The full suite's own perf shard (load 3.3) read `grenade_match_stress` 11.73 / 19.95 / **37.70** (max red) and 10v10 14.13 / 23.68 / 32.94, `match_npc_vision` 18.47 / 33.99 / 52.89.

**`grenade_match_stress` run 3 more times alone** (`--id=perf/grenade_match_stress`, ungated, load before and after: 5.25 to 4.97, 4.97 to 4.43, 4.43 to 4.94):
11.66 / 18.88 / 31.47 (green), 13.27 / **21.27** / 31.62 (p95 red), 13.62 / **22.33** / **38.94** (p95 and max red); `PERF` loads 4.9, 5.0, 4.4, 9 other Godot. Of six reads
of the guard in this extension (two perf runs, three solo, the suite's shard) three are over p95 20 and two over max 33.4. The spread (p95 18.9 to 22.3 at load 4.4 to 5.0) is
the machine's and the match's: the guard sits on its edge. AC40 (the four match guards within budget) is therefore **not met**; its blockers are the grenade match's p95 (and one max),
`match_10v10_stress` and `match_npc_vision`. No budget is loosened, no test skipped or tagged. Rule 38 records the last two red; a follow-up ticket holds what would close them.

**What the three slices did** (their own A/B, not this run's): the view's moving cost fell from 10.9 to 11.9 ms to 5.0 to 6.8 (the fan table; the moving loop turns 6 degrees a frame, past the
pose lag's bounds, so it is the table alone) and the parked viewer, now out of the fight's reach, costs about 0; `MOVING_BUDGET_MS` 20 to 8.5. The draw caches (`character/draw_cache_pixel_identical`)
cut a redrawn body from 6.65 to 6.33 ms in a scratch A/B of 10 bodies, far under the spike's 1 to 1.3 ms estimate for a 10-body frame. The decision micro bundle
(`ai/decision/micro_bundle_matches_plain`) showed no measurable ms a decision. Neither moved the grenade match's floor, so its p95 still reads 18.9 to 22.3.

Why 10v10 and `match_npc_vision` stay red, with both spikes' findings copied (`/tmp` is not durable): `perf-district-ext3-spikes.md`.

### After the stagger fix, before the review fixes: base against the branch, interleaved (2026-11-07)

The branch is Extension 3 as it stood after the look-phase fix (`d2f20dea`), before the twelve review-fix commits that followed; the base is the story's own revision before Extension 3 (`1afec1d2`), not `main`. The review fixes touch the measured path and are unmeasured (#195). Run alternately (A, B, A, B), without the quiet gate, at load 10 to 19 with 29 to 40 other Godot processes (none a test's). The branch's average frame was
higher in **8 of 8 pairs**:

| Guard | branch minus base, average frame |
|---|---|
| `grenade_match_stress` | +0.4 to +1.8 ms |
| `match_10v10_stress` | +2.0 to +3.9 ms |

**Not isolated.** The two revisions play different matches (`perf-nondeterminism.md`: a revision plays its own fight), so the gap is either a real cost of the branch or
a different match, and this run cannot say which; each slice measured on its own work was neutral or faster (about 0 ms a decision, 0.3 ms less for 10 redrawn
bodies, about 5 ms less for the moving view). The user chose to record it and move on. Only the ranges were recorded. Follow-up #195 holds the question
(time each slice's own work on one recorded workload, base against branch, on a quiet machine; revert any slice that is net slower) and the repeatable match guard.

## Extension 3's two spikes (from `perf-district-ext3-spikes.md`)

Side file of `perf-district-ext3.md` (`perf-district.md`, `perf.md`, `domain-testing`).

Copied from the spike reports; `/tmp` is not durable.

#### `spike-ext3` (HEAD 1afec1d2, 2026-11-07; scratch worktrees, ungated, load 3.3 to 6.5; M = measured, E = estimated)

- **10v10 is dominated by the fixed per-NPC cost.** With every decision free the instrumented p95 is still 23.2 and the no-decision frames' p95 is 21.0. Stock 10v10: p95 25 to 29, max 33 to 59.
  A calm frame is about 14.7 ms: `observe` 2.8 (`sight.see` 2.2), `behavior.apply` 3.0, `anatomy.step` 2.0, other controller about 2.3. 24.5 % of the frames hold a decision (a decision frame
  averages 27 ms), 9.1 ms a decision (build 5.6 plus walk 3.1; the perf Von stub answers synchronously).
- **The decision build has no single hot spot** (per decision, 10v10: `snap.build` 5.73 ms with 420 rays, 21 routes, 58 snaps; `_per_target` 4.06; `tac.fire_positions` 2.47; `_safe_spot` 1.10;
  `retreat_group` 1.26). Rays are about 23 % of a build, routes 14 %, snaps 9 %, the other 54 % GDScript overhead. The heavy decile of decisions (17 to 19 ms) is the lazy `grenade_ready` fact
  (`tac.throw_points` 7.4 ms in the 10v10, `thr.shots_possible` 10.6 in the grenade match); it is read in about 97 % of decisions with a hostile known.
- **Identical savings are small:** the micro bundle (`_route_exposed` early exit, snap memos, `_safe_spot` ordering; the 1.0 ms was measured with a `coverage`-property read in `is_cover` that is no longer in it) is about 1.0 ms a decision at 10v10 (E), 0.3 at the grenade match,
  10v10 p95 about -1.5 (E; stock still about 26.5). Rays repeat 11 % inside a decision, snaps in the walk 43 to 50 %, routes about 0 %; consecutive decisions of one NPC differ, so a cross-decision cache has little to hit.
- **Slicing a decision** (E, replayed): pieces packed to at most 4 ms take the 10v10's stock p95 from about 25.9 to 23.3 and leave max about 46; at most 3 ms, 22.4. It costs 1 to 3 frames of latency
  (small against Von's about 100 ms) and breaks tests that pin the state at the decision's start tick (a delayed walk by one frame fails `ai/decision/order_transport` and
  `ai/decision/unordered_state_unchanged`; by two also `ai/entry/entry_ajar_door_hostile_in_gap`). `DecisionBudget.per_frame` 1 means no two decisions share a frame.
  **Correction (#194 perf-decide2 review, 2026-11-24, measured):** "1 to 3 frames, small against Von's about 100 ms" no longer holds. With the pieces split and priced a decision with a hostile lands in 4 frames alone, 7 with two, and in a 10v10 (seed 23) the pool of 4 units is full: the median claim to land is 4 frames in the opening but the p95 52 and the max 68 (1.1 s), in the stress window 9 / 81 / 97; eight at once land on frames 4 to 31 (`decision-prices.md`). A decision is not hidden behind Von's wait; whether to widen the pool is a decision of the ticket's. *(#194 pool6, the user's call: `per_frame` 6, three frames with a hostile, four with two, six with an ambush ranking, eight at once on frames 3 to 20; the table is in `decision-latency.md`.)*
- **Max stays above 33.4 in every 10v10 replay** (E 39 to 44 stock): single events set it (an escape search about 9 ms, a nav tick 7.8, engine spikes). Nav tick spreading gains about 0.
- **The grenade match's floor is the character draw:** 5.1 ms of about 12 ms average (M: drawing disabled reads avg 7.25, p95 13.9 against 12.4 and 19.8), 9.5 draws a frame at about 0.47 ms
  (`_draw` 4.46 plus shadow 1.16). A walking body's redraw key changes in about 95 % of in-view character-frames, so a "cache what is unchanged" scheme has little static part to keep (the draw caches' small gain).
  Half-rate redraw was about -2 ms (M) but is not identical and conflicts with `standing_body_repaints_on_change`. Its max outliers (24 to 51 ms) are engine or blast frames.
- **Ranked:** identical draw caches; slice decisions into 3 to 4 ms deterministic pieces (10v10 p95 -5 to -6, max little); cut the per-NPC fixed cost about 40 % (the only lever on the 10v10's no-decision p95 of 21);
  the micro bundle; LOD draw; nav tick spread. The 10v10 needs the slicing and the fixed-cost cut together and still lands near 19 to 20 stock p95 with max red.

#### `spike-vision` (HEAD 1afec1d2, 2026-11-07; timed ms x 0.69 is about the real ms)

- **The player's view cost is the cone rebuild** and nothing else: on a moving viewer 13 of 14 ms of the view's frame (timed; 9.6 to 10.7 ms uninstrumented); memory, mask and composite on the CPU 0.08 + 0.05 ms,
  `ViewWatch` 0.005 ms; windowed the render side adds about 1.7 ms. About 6.4 ms of the 10.7 ms is the engine (743 rays at 5.8 us, the region shape query 6.2 us a shape, 2.1 ms for 340 shapes); the
  GDScript side identical work can touch is about 4.3 ms.
- **In a real fight the view rebuilds on 36 to 54 % of the frames** (viewed invader), 100 % while the viewer moves or turns; a "parked" viewer in the match rebuilds on 28 to 100 % (shoved by hits,
  dents, doors, which is why the guard now parks it out of reach). 67 to 83 % of the rebuilds are forced by the viewer's own eye or facing, 15 to 19 % by a world signal. Every one of the top 5 % frames (15 of 15,
  14 of 15) holds a rebuild: wall 42 to 61 ms, of which the view is 13.7 to 16.2 ms (timed).
- **Identical savings are capped** at about -2.5 ms of 10 (-25 %), most of it a high-risk shape-set cache; measured: the fan-hide table -0.9 ms (-8 to -10 %), inlining the visibility cast +0.4 (slower), a coarser sweep 0
  (the saving moves to the corner rays). A native port would be about -7 ms but is a native build in a pure GDScript project.
- **p95 20 and max 33.4 cannot be met by the view alone:** the same 10v10 with the view switched off (the relative guard's "off" blocks) reads p95 21.5 to 25.6 and max 33 to 37 (avg 10.8 to 15.1, load 4 to 7),
  so `match_npc_vision` is red on p95 and max whatever the view does. Closing them takes the decisions work and either a time-sliced rebuild (p95 / max -8 to -10 ms on rebuild frames, E, L effort) or the native port.
- **The cone flake** (`vision/cone_same_after_savings`, 2 to 8 %): `ViewCone._fan_hides` trusted two engine hit positions (about 0.02 px off a shape) to prove a corner hidden; a corner within about 3e-5 rad of a fan
  ray on a dented face of collinear vertices was falsely hidden and 3 vertices were missing. Fixed by an angular margin of `0.25 / distance` (rule 33); 514 000 comparisons with it, 0 mismatches.
- **The pose lag (rule 34)** is a spec change: every polygon drawn is the exact cone of an earlier real eye (never a quantised or invented eye, which the never-cleared memory would keep), so no phantom area is remembered.
  Its measured effect on the guards is small because the moving loop turns 6 degrees a frame and the fight forces world rebuilds; it helps a player walking with a still mouse (the eye-only phase).

#### What a follow-up holds (rule 38, AC41)

Sliced decisions (deterministic work-unit pieces, tests that wait for the decision to land), a per-NPC fixed-cost cut (`sight.see`, `behavior.apply`, `anatomy.step`), and a sliced cone rebuild.
Tools used by the spikes: `/tmp/fe-perf-findings/ext3-tools/`, `/tmp/fe-vision-out/` (not in the repo).

## From `docs/grenades.md`, "Performance"

The P1 windowed p95 of 21.98 in the last entries was read against 20, the budget of that day.

**Before** (origin/main `7428c4a`, before issue #56's fixes; one run each at a 1-minute load of about 2.9, ms a frame):

| Test | Mode | avg | p95 | max |
|---|---|---|---|---|
| P1 | headless | 10.78 | 17.51 | **34.30** |
| P2 | headless | 5.73 | 10.08 | 32.27 |
| P1 | windowed | **23.37** | **32.44** | **50.19** |
| P2 | windowed | 12.69 | **20.13** | **41.59** |

**After** (16 October 2026, issue #56 on origin/main `f0e4f8e`; each run started at a 1-minute load of 3.0 or less, one Godot at a time, the
load before → after each run; bold misses its budget). The headless runs are of the whole of issue #56, the audit's fixes included. The
windowed runs were made just before those fixes and not repeated: the fixes change nothing that is drawn (comments, and a worker's cut making
its own circle ring), and the headless runs after them stayed within the noise of the runs before them (P1 avg 9.08-10.49, p95 15.03-16.31, max
22.73-31.60; P2 avg 5.80-6.56, p95 8.20-8.86, max 23.08-23.88):

| Test | Mode | Run | Load | avg | p95 | max |
|---|---|---|---|---|---|---|
| P1 | headless | 1 | 2.94 → 2.86 | 9.97 | 14.64 | 23.26 |
| P1 | headless | 2 | 2.86 → 2.96 | 9.80 | 15.28 | 21.57 |
| P1 | headless | 3 | 2.96 → 2.88 | 9.35 | 13.85 | 22.12 |
| P2 | headless | 1 | 2.88 → 2.90 | 5.84 | 7.96 | 23.45 |
| P2 | headless | 2 | 2.90 → 3.79 | 7.02 | 9.56 | 27.38 |
| P2 | headless | 3 | 3.00 → 2.77 | 6.57 | 9.03 | 22.74 |
| P1 | windowed | 1 | 2.78 → 2.79 | 16.15 | **22.76** | **39.64** |
| P1 | windowed | 2 | 2.79 → 2.81 | **17.65** | **22.98** | 28.71 |
| P1 | windowed | 3 | 2.81 → 2.99 | 14.51 | 19.64 | 27.18 |
| P2 | windowed | 1 | 2.99 → 3.88 | 10.64 | 14.61 | **38.33** |
| P2 | windowed | 2 | 2.73 → 3.18 | 12.00 | 14.62 | **36.55** |
| P2 | windowed | 3 | 2.49 → 2.87 | 10.24 | 13.25 | **35.99** |

Headless, both pass in every run, and `tools/run_tests.sh --domain=perf` (one run, load 2.78 → 2.94) passed all eleven perf tests (P1 8.59 /
13.21 / 24.53, P2 5.58 / 7.47 / 22.66). Windowed, P1 came down from 23.4 / 32.4 / 50.2 to 14.5-17.7 / 19.6-23.0 / 27.2-39.6 and passes now
and then; P2 from 12.7 / 20.1 / 41.6 to 10.2-12.0 / 13.3-14.6 / 36.0-38.3, its average and p95 well within, its worst frame still over.

**Where the time went** (the profile of issue #56, its fixes pinned each by a test that holds the new code to the plain one, all without a change
to what is drawn, when or how anything behaves): the bodies' drawing was about 70 % of a rendered frame, each plain-coloured polygon a vertex
buffer of its own, so they go out as General's `FillBatch` (one triangle array) and the limbs are built once a frame for body and shadow; furniture
moves its drop shadow instead of repainting on a turn and walls repaint the struck segment alone; spreading pools blur separably; dented colliders
are cut and a spray's splats merged side by side on worker threads; navigation re-bakes measure and parse once a tick; the escape search judges each
spot once (and, since issue #65, shares what depends on the burst alone among the NPCs planning on one physics frame: `docs/leadership.md`,
Performance); and weapon art is painted ahead of time.

**Issue #78** (19 to 21 October 2026) kept the same budgets windowed, no exemption, and fixed the window's costs at their cause, each fix
pinned to the old pixels or bytes: the sound library's pre-warm renders on a worker thread instead of about 10 ms a frame on the main
thread (`domain-audio`); a debris chip lands as a record in its layer; and a hit's spray no longer waits for its splats' merges, which finish later in the
frame (`domain-physics` (`blood.md`)). The limb outlines as kept meshes were measured and dropped (exact, but no faster). Three windowed
`tools/run_tests.sh --windowed --domain=perf` runs on 21 October 2026, each alone (no other Godot during it); this machine's quiet
baseline that day was a 1-minute load of about 5 (ordinary apps), load before → after (peak) 4.46 → 4.64 (5.87), 4.83 → 3.89 (4.83),
2.79 → 4.70 (5.26) (avg / p95 / max ms; bold misses):

| Test | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| P1 | 16.54 / **22.84** / 32.42 | 16.31 / **23.74** / **33.97** | 15.60 / **21.81** / **33.46** |
| P2 | 9.41 / 12.10 / 30.09 | 9.77 / 13.40 / 26.86 | 11.01 / 13.99 / **39.85** |

P1 does not meet the standard windowed: its average is under the budget and its p95 2-4 ms over. P2 holds its average and p95 and missed
once on one frame (39.85; 26.9-31.4 in the other five windowed runs since 19 October). Headless the same build passes (P1 10.61 / 15.80 /
25.29, P2 6.44 / 8.40 / 22.50, load 4.00 → 3.61). The other perf tests' windowed numbers are in the `domain-testing` skill (Performance
tests, "Rendered too"), with the latest windowed runs of all twelve, from before issue #95.

**The GdUnit panel.** One **Run overall** from the editor's GdUnit panel on 21 October 2026 (every suite, an hour; no other Godot but the
editor and its runner; the perf suite at a 1-minute load of 3.9-5.1) gives the windowed verdicts: P1 15.59 / **21.98** / 31.88, its p95
over as in every windowed run; P2 10.49 / 13.08 / **40.50**, its worst frame over as in two of the three latest windowed runs in
`domain-testing`. Of the twelve perf tests nine pass and three fail (P1, P2 and `match_10v10`'s p95 at 20.87), each on a measure the
windowed CLI runs miss too; the panel's numbers for all twelve are beside the windowed table in `domain-testing`.

**What is left.** Of P1's windowed frame (15.6-16.5 ms on average) about 10.6 ms is paid headless too: the characters' physics frame
with the AI it drives (6.4 ms, 0.41 ms a body in both modes, measured with a timer on every `_process`, `_physics_process` and `_draw`),
the ragdolls, and the fallen bodies, which repaint every frame until they settle (about 2 ms a repaint, mostly the trunk's outline built
twice, body and shadow; only 3-5 % of those repaints change nothing). The window adds the rest: the standing bodies' drawing on the
script side (5.3 ms against 3.5 headless) and the engine's render of the frame. Closing it needs work on the AI and the fallen bodies,
outside #78. P2's worst frame is the frag's own frame, about 23 ms of CPU and about 12 ms more of rendering what the burst adds in it
(not a first use, not the flash lights: both ruled out by measurement in the profile). An atlas for the limb art was built and measured
and gained nothing in P1, so it was not kept. What would surely close the rest is only what the user ruled out: visible or timing
changes (fewer splats per blast, the blast's work spread over frames, simpler art).

**Issue #95** builds P1's match through `MatchBuilder`, so its invaders carry their plates and grenades, are styled and ranked and follow
their squad's leader, from beside the front door. Re-baselined headless only (`tools/run_tests.sh --domain=perf --verbose --summary
--no-lint`, three valid runs a side, each started at a 1-minute load under 3.5 with no other headless Godot, a run whose load went over 4
discarded; before 4af0b43, after 91400e6's guard code, measured before the branch was rebased onto #81), P1's medians went from 10.16 /
15.09 / 24.20 to 10.58 / 17.29 / 33.18, and P2's from 6.41 / 8.47 / 22.10 to 6.89 / 8.90 / 22.50. P1's median passes; its max missed in one run of three (34.52). Not yet re-measured windowed; the other
guards' numbers are in the `domain-testing` skill.

**The prepaint's cost.** A gun or grenade paints its art ahead of time once per weapon style per process (`ItemRegistry.inventory_for`, every
raise step, both lying sides, every lighting step: the very draws it will make), about **230 ms** once, when the first inventory in that style
is made at a match's spawns; later inventories cost about 0.05 ms. It moves 0.3-0.5 ms first paints out of a fight's busiest frames.

## From `docs/player-vision.md`, "Measured cost" and "Played in a window"

The entries dated 2026-11-19 and later were measured on the 3D build (#194). A "V1", "V3" or "below" in them is the spec's of that day.

### Measured cost


**2026-11-24, perf-view2: the settling job, and the corners' list reused (tried, not kept) (#194 perf3d, same window, seed 23, load 8 to 55 so the ms are noisy and the counters exact; three alternating pairs against the ticket's tip).** The fight and the counters are the same in both arms. **Kept: the settling job** (V1): at the restart cap a change that is slow moves only goes on as a job instead of a whole build: whole builds (`cap`) **8 -> 3-4 in 301 frames**, units 279 -> 269 a frame, the cone's p99 **9.6 to 11.1 -> 7.4 ms**, avg 2.91, 2.98, 3.26 (tip) against 2.89, 3.02 (settling only), p95 6.2 to 6.9 against 6.3 to 6.6; the worst frame stays about 11.6 to 12 ms (a cap that is not slow moves, and a start tick that costs a full slice, 4.5 to 5 ms loaded). The lags at the restarts were all under 1 px (0.0 to 0.95: a settling shelf), which is why `settle_px` is 1. **Not kept: the corners list reused across jobs** (the lever the last pass named, about -1 ms). Built exact (a list read once for the eye +-24 px and the facing +-0.3 rad, used while the next jobs stay inside, nothing it holds moved or changed, under `rebuild_every` frames old; the whole vision suite and `vision/cone_skip_exact`'s checker held every cone to the reference), it reused the list in 42 of 124 jobs (the others read one: a wall dented by the fight 21 times, a blocker that moved in reach 30, the age cap 13, a facing turn 7) and the extra the wider region costs (about +40 % corners to read and to walk for every job, 1.3 ms more on a read) took what it saved: avg 3.07 against 2.95, p95 7.2 against 6.4, with margins of 10 px and 0.1 rad (28 of 121 jobs reused) no better (2.97, 2.99 against 2.91, 3.26 tip; p95 6.6, 6.8 against 6.2, 6.9). The corners' 2.2 ms per job is 0.8 ms of the shape query and **1.4 ms of the loop over its hits** (227 hits, 1,337 points, a polygon check and a dedupe cell each), so a lever that pays is a cheaper loop (a polygon the watch knows is unmoved needs no check; a keyed dedupe) or the polygons of a hit kept across jobs, not the query. `ViewWatch` keeps no list today.

**2026-11-24, where the view's frame goes in the guard (#194 perf3d, seed 23, the `perf/match_npc_vision` window, a probe of its own, a physics-tick bracket round the view, loaded machine).** The cone cost **3.73 ms a frame** (p95 8.4, max 10.5). Its parts: a start tick or restart is a slice (450 units, 4.1 to 4.8 ms); the corners are 2.2 ms of a job's 735 units (262 jobs, about 880 corners each: the dedupe loop and the polygons, so `cost_shape` 225 is the right price); a check with no job in flight costs 0.45 ms (a walk of 482 blockers, 267 us, and 311 colliders with no twin asked again, 146 us). **The tail is restarts, not slices:** 76 of the run's 164 restarts ended in a whole build (`cap`, 8 to 10 ms, 956 units), every fourth frame for stretches of 30 frames, because a shoved bookshelf that was settling moved 0.0005 to 0.003 px a frame and each move restarted the job (`moved_then`, 212 of 240 restarts; the world watch names no move too small). The twin-space word above takes the 146 us; the blocker walk is 150 us now (no call in a frame nothing moved). **Landed, on the user's word (2026-11-24): the creep rule of V1** (a blocker that moved under 0.05 px is where it was): the same window read 3.07 ms, p95 6.4, 18 whole builds for 76, the fight unchanged. Next lever: the corners' list reused by the next job while the eye and facing stay within a margin and no blocker moved (about -1 ms, the 2.2 ms off every second tick).

**2026-11-24, the cone's one-off frames (#194 perf-view3, `perf/match_npc_vision`, seed 23, a probe round each cone tick, loaded machine: three alternating plays each of the tip and the change).** The window's worst frames were the cone's: a frame of 26 to 33 ms (cone 24 to 28 ms) that followed four to nine frames of no cone work. **Cause:** the viewer, idle in a fight, changed posture (ducked or rose to fire), the eye height changed, and `ViewWatch` sorted every collider of the tree again from scratch (`_read_new` cleared and classified all of them: a twin read, a top, a measure, signals, 16 ms of the 26 in a 1,300-body district) before the 450-unit start slice. **Now** a collider's top is kept (`_known`, id to top; it does not change in play, as `ViewWatch` already assumed) and a new eye height moves bodies between the blockers and the looked-over by it, measuring only those that start to block (`vision/view_watch_posture_suite`, which the old sort fails). The cone's max over three plays fell from 26 to 33 ms to 15 to 20; what is left is the whole builds past the restart cap (2 in 300 frames, 1,500 to 1,800 units, 9 to 14 ms: the cap's rule stands, one exact cone in one frame; a cone built across frames from a moving world is not exact, and is a decision for the spec).

**2026-11-19, the corners re-priced for the twin space (#194 del2d; the user chose A, to price them at what they cost: `cost_shape` 225, not a slice).** `perf/cone_corner_cost` (the 10v10 district, 168 reads, load 5.35, 2 busy Godot, so the times are inflated and the ratio is what is read): the corners took **1,428 µs** against **7.02 µs** a unit of the rest of the job, so **198 units** (p25 104, p75 304; 203 on an earlier run at load 13; the 2D query had been 372 to 374), `cost_shape` 450 would have been 2.3 times that, outside the test's 2x, and 225 is within it. A job at the default slice is a median **2 ticks (max 5; 10 % over 3)** (3, 6 and 26 % before, below), so a cone shown is up to 2 times (ticks - 1) frames old: usually up to 2, at most 8 in the grid. The tick figures were measured loaded and not on a quiet machine: perf3d re-measures them (`--quiet`). `perf_ab.sh` of the twin-space cone, 29e423bc against 0fa52306 (before this re-pricing), 4 rounds: `perf/match_npc_vision` avg -0.5 %, the 10v10 guard -2.1 %, 5v5 -0.2 %, grenade -1.1 %; not re-run for the price (it moves when a rebuild's rays are cast, not how many).

**2026-11-12, the corners priced at a slice (#195, cone-start; superseded by the re-pricing above; `--quiet` runs, none marked loaded, load 4.7 to 7.5, 0 busy Godot).**
`perf/cone_corner_cost` (the 10v10 district, 168 reads: a grid of eyes and facings, each the median of 5): the corners (`begin` and the first
step: the region shape query, its polygons, the dedupe) took **1,982 and 1,937 µs** against **5.51 and 5.35 µs** a unit of the rest of the job
(rays, far-face probes, visibility casts), so **372 to 374 units** (p25 168, p75 627 by eye), where `cost_shape` had been 1. It is 450 now, a
slice, so the tick that starts a job holds the corners (about 2 ms) and no rays, not the corners plus 449 units (about 6 to 7 ms). The
cost is a tick more a job: at the default slice a district job was a median 2 ticks (max 5; 11 % over 3) and is a median **3 (max 6; 26 % over
3)**; the cone shown is 2 times (ticks - 1) frames old at most (V1 has the figures). `perf_ab.sh` same-fight, base `5343aa38`,
tip `dc3fa0dc`, 4 rounds, the fight unchanged (the cone steers no NPC): `perf/match_npc_vision` avg 16.94 to 16.29 ms (-0.65), p95 28.83 to
28.52, max 43.52 to 39.19 (-4.33); the three guards with no view moved by noise (avg +0.03, +0.06, +0.34). `perf/match_npc_vision_relative`, one run:
parked -0.13 ms, ratio 0.08; moving 1.34 ms (2.0 to 2.1 before), ratio 0.19 (0.25 to 0.26 before).
Tests: `perf/cone_corner_cost`, `vision/cone_corners_priced`, `perf/match_npc_vision`, `perf/match_npc_vision_relative`.

**2026-11-12, the cone as a sliced job (#195; `--quiet` runs, none marked loaded, load 3.9 to 5.9, 0 to 2 busy Godot).** The same fight
at the commit before the pipeline (`d3f40a8f`) and at it. `perf/match_npc_vision_relative`, three runs before and six after: the moving view's cost over
the unviewed match **4.49, 4.67 and 4.36 ms before, 2.05, 2.00, 2.00, 1.94, 2.04 and 2.14 after (six runs)** (the job is one slice, about 3.5 ms, a frame, where the
whole rebuild fell in every moving frame), its cone 0.44 to 0.45 of the reference cone's before and 0.25 to 0.26 after; the parked view
-0.14, -0.14 and -0.08 ms before, -0.17, -0.32, -0.23, -0.07, -0.32 and -0.09 after (no change: it rebuilds for its backstop only). `MOVING_BUDGET_MS` is
3.5 ms, 1.7 times the median of six runs of the sliced cone (2.05, 2.00, 2.00, 1.94, 2.04, 2.14 ms) and below the 4.36 to 4.67 of the cone before. `perf_ab.sh` in same-fight mode (`--ids=perf/match_npc_vision`, 3 rounds, the fight is unchanged since
the view steers no NPC): the absolute guard's median avg frame 19.12 ms before and 17.75 after (-1.37 ms, -7.2 %), p95 31.70 and 29.17,
max 47.44 and 42.37. (That guard's gain is smaller than the relative guard's: what share of its frame the view's cone is was not separated.) The age of the cone shown is V1's.
Tests: `perf/match_npc_vision_relative`, `perf/match_npc_vision`.

**2026-11-07, the pose lag and the fan table (not `--quiet`: load 10 to 12, 29 other Godot).** `perf/match_npc_vision_relative` with the parked
viewer moved to the district's outer corner facing away from the fight (a viewer in the centre house's largest room rebuilt on 28 to 100 %
of the frames, shoved and dented by the fight): the parked view read -0.82 and -0.64 ms against 3.2, rebuilding only for its backstop; the
moving rounds, whose turning aim (6 degrees a frame) is past the lag's bounds and so still rebuild every frame, read 6.74 and 5.02 ms
(11.9 and 10.9 on 2026-11-07 before). `MOVING_BUDGET_MS` is 8.5, about 1.4x of their mean.
Test: `perf/match_npc_vision_relative`.

The perf tests run headless and see only the CPU side, so the GPU side was measured by hand, windowed, as `docs/lighting.md`
"Measured cost" does. **Each figure below says where it comes from.** *Recorded* means a commit's test header or message holds it
(the commit is named). *Not reproduced* means it comes from the ticket's own measurements and its slices' notes, was first
written down in this document (commit 6ecb4659) and has been re-run by no one since: take it as the order of magnitude it
gave, not as a number to hold the code to.

**When the perf figures were measured.** Every perf figure below but the last two bullets (the district, 2026-11-02) was taken before commit 6bd7cc63 (a blood pool's repaint
decided on the frame's view, by its box), and **no perf test was run after it or after the later fixes of the review, until the district run of 2026-11-02 (the bullet below)**. 6bd7cc63
does not touch the cone, the change check or the ratio the second guard reads, so the cone figures and the ratio stand. It does
touch the frame the first guard reads: a pool then asked `SeenArea.reaches_rect` (a box, since removed, a little cheaper to refuse than the
circle) and draws in `_process`, not `_physics_process`; that moves the view's cost by about the pool skip's own size (0.13 to
0.5 ms, below) or less, which is inside the spread between runs, but it was not measured. Two later changes to the change check
are unmeasured too: `ViewWatch` no longer rebuilds for a blocker that is moving outside the eye's reach (the cone test
`vision/cone_skip_exact` counts it) and no longer measures a moving blocker's shapes anew each frame (it keeps each blocker's
extent, and compares the key field by field without building an Array), which can only cost less; and after a rebuild made while
a blocker within reach moved it rebuilds once more the next frame (a query in the frame a body moved can read it where it was),
which costs one rebuild a move that ends within reach.

- **Before the savings, the view on an NPC in a 10v10 (not reproduced).** The ticket measured about +7.4 ms a frame windowed,
  "4 to 5 ms of it the cone's CPU, about 3 ms the second world render (the capture) and about 2 ms GPU". Those three parts
  sum to 9 to 10 ms, not 7.4: they are separate estimates from separate measurements, so read them as the shape of the cost
  (the cone, then the capture, then the GPU) and not as a breakdown of the 7.4.
- **A measurement of the same match before slices 13 and 14 (not reproduced)** on a shared, loaded machine (load average 1.2 to 4.0;
  Vulkan, 1152×648, `--fixed-fps 60`, vsync off): the median frame was 18.78 ms headless and 29.95 ms windowed, the cone's rebuild
  4.86 ms headless and 3.81 ms windowed, the characters' visual update 3.78 and 7.00 ms, blood 1.69 and 1.51 ms (0.73 and 0.50 ms
  of it pools wholly outside the cone). The cone's cost depends on where the viewer stands (2.6 to 6.0 ms between runs).
- **Slice 11, the cone's own caches (not reproduced):** the ticket put the view's cost at 5.68 ms before and 3.65 ms after, and the
  cone's headless bench down 45 %. Both sit inside the 2.92 to 5.46 ms the ten quiet runs below spread over, so the pair is not
  evidence of a saving by itself; the saving the code makes is held by `vision/cone_same_after_savings` (the same polygon) and
  the ratio below.
- **Ten quiet runs before the savings (recorded, commit 46b929e4, and the header of
  `perf/match_npc_vision_relative`):** the view's cost over the unviewed match was 2.92 to 5.46 ms, median 4.36.
- **After slices 13 and 14** (unseen characters not repainted; the cone rebuilt only when its inputs changed), **eight quiet runs of
  `perf/match_npc_vision_relative` (recorded, commit a7f3b67c, and that test's header)** (the `--quiet` gate passed, none marked
  loaded) gave the view's cost over the unviewed match as 0.33, 0.36, 0.63, 1.18, 1.58, 1.70, 2.50 and 2.51 ms, median 1.38.
  **The budget is 3.2 ms**: the highest quiet run plus 25 %, rounded, by the user's choice. Median plus 25 % (1.73 ms) was not
  chosen, because the spread is between runs (each plays a different fight) and it would fail two of these eight correct runs;
  3.2 ms still fails the cost before the savings, every one of whose runs was over it. The second check is a ratio: the live cone's
  per-frame cost (the change check, and the rebuild when there was one) over the reference cone's, built from the same eye in
  blocks of its own, at most **0.75**. The same eight runs gave 0.27, 0.31, 0.39, 0.39, 0.40, 0.42, 0.49 and 0.59, median 0.40;
  with the savings off it reads 1.00 to 1.02 and with only the skip off about 0.65 (all recorded, a7f3b67c).
- **Windowed, after the savings (not reproduced):** Vulkan, `--fixed-fps 60`, vsync off, 1152×648, the same 10v10 with the view on
  an NPC, interleaved on and off, three runs: the view on minus off was −4.74, −1.54 and −2.18 ms a frame, with the cone ratio 0.47,
  0.22 and 0.35. The ticket read this as a net gain windowed because unseen characters are not repainted while the off blocks
  repaint everyone; the GPU was not separated from the CPU in these runs, and three runs are too few to say a sign, so the claim is
  only that the view was not seen to cost windowed.
- **The pool skip (not reproduced)** alone measured 0.13 to 0.5 ms a frame (12 to 25 % of the pools' draw time), the whole frame's
  change within noise. It is kept for what it saves in the pools' own draw, not for a frame it was seen to speed up.
- **Dropped, not measured to hold:** the single world draw (V3). An earlier probe that drew only what moves in the main viewport
  read +2.6 to +6.2 ms windowed and about 3 to 4 ms of GPU saved; it is unverified, since by the ancestor rule above it probably drew
  none of the characters' children.
- **On the district, 2026-11-02 (recorded, `perf/match_npc_vision_relative` and `perf/match_npc_vision`).** Both guards now play the
  10v10 in a downtown district whose centre house is the largest plan (`Perf.configure_match`), not in a house. A quiet run (load 3.6, no other
  Godot) of the relative guard read **0.88 ms** (median of 12 rounds, rounds from -9.0 to +7.1) and the cone at 0.11 of the reference
  cone's, against the 3.2 ms and 0.75 budgets. **The budget was set on a house** (the eight runs above) and has not been set again for the
  district; it is kept, not loosened. The view's cost rose with `5204e489`, the district-cost commit (the bisect read 3.9 ms before it,
  10.4 at it and 13.7 after the planning ring), and the Vision change that followed brought it back to 4.9 and 5.2 ms: the even fan is cast
  once, the shape query takes the cone's sector, `ViewWatch` rebuilds only for a blocker where a ray can pass, and a corner beyond the
  view distance adds no ray (`vision/cone_hidden_corners_not_cast`, `cone_reads_only_its_sector`, `cone_beyond_reach_exact`). **What in
  `5204e489` raised it was not isolated**: with `environment_object_visuals.gd` and `blood_smear.gd` put back to their older form it read
  4.25 ms, with only one of the two 9 to 16, and `reask_frames` 1 changed nothing. The district had 3208 corners a rebuild against 480 on
  main, which is what the Vision change removed.
- **The cone rewrite is beyond the district brief (#182).** The even fan cast once, the shape query on the cone's sector and the
  watcher's blocker check (`view_cone.gd`, `view_sector.gd`, `view_shapes.gd`, `view_watch.gd`, the reference cone and four
  equivalence tests) were made to cut the view's cost on a district. The ticket's brief had no vision line. The cone is vertex for
  vertex the reference cone's (V-tests above), and it changes the lone house's view cost too.
- **The moving viewer, #192 (recorded, `perf/match_npc_vision_relative`, `vision/cone_same_after_savings`).** The relative guard parks
  its viewer, so it never measured the cone that rebuilds about every frame while its viewer walks (6 to 9 ms a frame in
  `perf/match_npc_vision`). #192 made that rebuild cheaper without changing a vertex: static blockers' corner polygons are kept
  across rebuilds until the collider moves, is dented or is re-cut, and each is checked against its body once a rebuild (a memo
  in front of the lookup, dropped at each rebuild, when polygons are cleared and when a collider leaves the tree: a rebuild asks for
  a polygon about 1,300 times and uses few); the angles are built without lambda sort or map. A first form also reused the previous
  ray's blocker shapes for the far face; a profile found it fired on 0.2 % of the far-face reads (298 of 146,583) and cost more than
  it saved (its isolation query, point test and settled check ran on the other 99.8 %), so it was removed. `vision/cone_same_after_savings`
  holds a walking, turning eye past moved, dented and re-cut blockers, and past a body that moves every frame, to
  `tests/_vision/reference_view_cone.gd`, frame by frame, counts the cross-rebuild reuses and the memo's hits, and checks no polygon
  is checked twice in a rebuild. The guard also plays rounds where the viewer walks a scripted loop (eye and facing change every timed
  frame, a premise it checks) and holds the moving view's median cost to `MOVING_BUDGET_MS`, **20 ms**: about 1.4x the quiet moving
  median of about 13 ms (11.89 and 10.90 ms in the two runs of 2026-11-07, so about 1.7x). It departs from `perf.md`'s 4x rule because the
  cost is a cone rebuilt every frame, and 4x of a per-frame cost would never trip. (Before the memo the quiet median was 13.9 ms, against 12.2 at the base of the story; the profile put the
  difference on the polygon re-checks and the far-face reuse.)
- **The perf matches run with `worldgen.doors` off** until #178 and #159 make the entry door-aware, which the shared perf probe
  (`tests/_perf/perf_probe.gd`) says. `perf/match_npc_vision`, the absolute guard on the same match, is still red on the district after
  #192 (2026-11-07, two runs that were not `--quiet`: avg 22.53 and 20.13, p95 35.97 and 31.25, max 46.69 and 42.67 ms). Its excess over
  the 10v10 is the moving view's cone, rebuilt almost every frame (about 11 ms a frame in the moving rounds), and a follow-up; the 10v10's
  own tail is the grenades' escape search. The relative guard's parked view read 5.64 and 4.77 ms against its 3.2 ms (rounds 1.0 to 11.7),
  red as it was on 2026-11-02 (4.9 and 5.2). Numbers and loads: `domain-testing` (`perf-district.md`).
  Tests: `vision/cone_same_after_savings`, `perf/match_npc_vision_relative`, `perf/match_npc_vision`.

### Played in a window

The headless tests never open a window, so the change was played in one (2026-11-01, Metal, Apple M2 Max, a shared machine with
load averages of 4 to 7). Each run had its own `--log-file`, and its whole log was read with
`python3 tools/scan_godot_log.py <log> --from=0`. The matches ran on `a9bb08d7`, the tests on `cd92abf4`; the two commits hold the
same `scenes/` and `addons/`, `cd92abf4` changing one test only. Perf was not re-run at either (see "When the perf figures were
measured").

- **Five played matches of Main** (Start pressed by a scratch driver once the setup menu was up, 40 s of play, the game then quit by
  `get_tree().quit()`): all five exited 0 and every scan came back empty (no error, no warning). The view, in the group
  `player_view`, was there 8 s into each match and at its end.
- **Five windowed runs of the change's game tests** (the 20 `*_test.gd` added or changed since `origin/main`, except `perf/*`, which
  these runs do not play, and `_harness/log_gate_probe`, which logs an error on purpose), each played whole in the test runner's
  window with the log gate on (`--log-file <out>/godot.log`, the file the runner follows). On `cd92abf4`: 19 passed and 1 failed in
  each of the five, the one failure `ui/leader_overlay_draw`, and no engine error or warning in any log up to its `Queue done:`
  line. `ui/leader_overlay_draw` is not this change's: the same test fails the same way (its first checks read `[]` where a crown
  should be) played in a window from an `origin/main` checkout, and passes headless; its cause was not looked into.
- **What they found.** An earlier set of five, on `a9bb08d7`, passed 19 of 20 four times and failed `vision/at_rest_remembered` once
  ("a gun was seen both moving (0 frames) and at rest (694)", 3 frames not on `WORLD`) besides `ui/leader_overlay_draw`. The shooter's
  frag grenade sends fragments ricocheting round the arena, and one killed the victim (50 hp) at 5.9 s, before the test killed it on
  the run: a body that dies standing lets its gun go with no skid, which no change of place shows moving, so the test judged the gun at
  rest after 90 still frames while it still spun on `MOVING`. Alone the test passed ten of ten windowed runs, so it was not
  reproduced by waiting; a 60 hp hit standing in for the fragments made the old test fail the same way, in a headless run. The victim
  has 100 000 hp now and the test kills it with its own health: green with the stand-in, ten of ten headless runs, five of five in the
  windowed queue above. Nothing in the player's view was wrong: the gun was on `MOVING` while it spun and on `WORLD` after.
- **The shutdown noise.** Every log shows `BUG: Unreferenced static string to 0: ...` (33 or 34 lines) and three
  `Pages in use exist at exit in PagedAllocator` lines, all after the `Queue done:` line: the engine's shutdown noise when it is
  ended by a signal, not this change's. The test runner scene has no command server to quit through, so these runs ended by `SIGTERM`
  to the pid they started, and the same lines come out of an `origin/main` checkout ended the same way, in a count that varies from
  run to run on both, because the signal lands at a different point of the teardown. One of the five logs also holds about thirty-five
  `Can't emit non-existing signal ""` / `Attempt to connect nonexistent signal ''` lines, again after `Queue done:`, in the same
  teardown; it was not compared with `origin/main` (it came once in five and did not come again). The five matches of Main, which
  quit through the game, print none of this.

**2026-11-24, the corners' parts priced at what they measure (#194 fixes3).** `perf/cone_corner_cost` (207 reads, load 5 to 6, so the ratio is what is read) measured the query at **57 to 61 units** against `cost_shape` 120 (2.05 to 2.1x: outside the test's 2x) and the chunks at **198 to 208 units** against 105 priced; the whole (225) passed because the two errors cancelled. The user's rule: the guard and the 225 stay, the code gets cheaper. The test's job begins on a fresh `ViewShapes`, so the chunks are the cold fold: each shape's entry is built (the polygon, its cells, the signal hooks). Cuts, all exact (the polygon is the same vertex for vertex): `TwinShapes.footprint_of` moves a shape's extreme points in one product and builds the box and the rings without allocations (bit-identical, `general/twin_footprint_matches_frozen` against a frozen copy over every twin of the district, 5.2 to 3 us a shape), the polygon's cells are a dictionary merged into the job's in one step (a fold that was 0.25 us a corner is one engine call a shape), `_watch_polygon_shape` hooks a collider's signals once, not once a shape, and a hit's `looks_through` is read off its meta. A cold fold of the district's median read went from **1,144 to 910 us**, the chunks to **151 to 152 units** (a chunk about 50), the query still **59 to 61**, the whole **211 to 213** (225 priced before: the test's band holds it). **The split is the open choice.** At the honest split (`cost_shape` 60, `cost_hits` 50 to 55) `vision/view_on_npc` shows a cone **6 frames old** against its bound of 4 (60 / 45: 6; 60 / 40: 5; 60 / 35 and 105 / 35 and 120 / 35: within 4), because a crowded region folds about 7 chunks, not the median 3: at 60 + 3 x 55 = 225 a chunk costs 1.7 units a hit where 120 + 3 x 35 had 1.1. So the prices are `cost_shape` 105 (1.8 to 1.9x the query: inside the test's 2x) and `cost_hits` 35: 210 summed, within the 15 % band of 225 and 1 to 3 % under what the read measures, the chunks priced at 70 % of theirs, the cone's age as it was. The honest split, or the whole honest sum with an older cone in crowded regions, is the user's to choose (cone age against per-frame cost). Test: `perf/cone_corner_cost`, `vision/cone_corners_priced`, `vision/view_on_npc`.

## From `docs/leadership.md`, "Baseline" and "Performance"

### Baseline

AI against AI, with squads following their leaders and before them (main, e6cdbf7: every member decides on its own, nobody
follows), scored by `tools/match.py` (`--seed 101 --rounds 10 --timeout 180`: seeds 101 to 110, one round each) on
2026-10-19 from 11:55 to 12:19, the two trees alternated (squads 3v3, main 3v3, squads 5v5, main 5v5). Each tree was a scratch
`git worktree` of its commit; for each run a headless game ran on its own command port from an uncommitted scene inheriting
`main.tscn` with its `run`'s `defender_count` and `invader_count` set, spectator mode, the default loadouts, and the real Von server (one shared
server). A round ends when one side is wiped out (the `match` verdict, `scenes/general/command_server.gd` `verdict_of`, deciding by
General's `MatchVerdict`, the rule the MatchHUD decides by too). Main's own `match` verdict calls a match larger than 1v1 a draw at
its first death, so main's tree was run with the squads tree's `scenes/general/match_verdict.gd` and the calls to it in
`command_server.gd` and `match_hud.gd` copied onto it, and nothing else. The round length is the `match` line's `elapsed`, over the rounds a side won. The load is the 1-min average
from `uptime` before and after the run, on 12 cores; the machine was shared, and other work raised it during the runs.

| Size | Tree | Invader wins | Defender wins | Draws | Timeouts | Round length, mean (min to max) | Load |
|---|---|---|---|---|---|---|---|
| 3v3 | squads | 10 | 0 | 0 | 0 | 29.6 s (4.0 to 66.9) | 3.95 → 11.67 |
| 3v3 | main (e6cdbf7) | 9 | 1 (seed 105) | 0 | 0 | 31.8 s (14.2 to 47.7) | 12.26 → 8.15 |
| 5v5 | squads | 10 | 0 | 0 | 0 | 35.0 s (13.1 to 50.5) | 7.57 → 7.81 |
| 5v5 | main (e6cdbf7) | 7 | 2 (seeds 104, 105) | 0 | 1 (seed 107) | 32.4 s (16.2 to 82.0), 9 rounds | 7.34 → 11.30 |

Main's 5v5 timeout on seed 107 was still undecided at 180 s, one defender and three invaders standing. A run of the squads tree
before its audit fixes, the same morning (06:52 to 07:03, load 3.07 to 7.28), gave the same tallies: 10 invader wins in 10 at both sizes.

**With the defenders' ambush (LD29, issue #128).** The same `tools/match.py` run (`--seed 101 --rounds 10 --timeout 180`) on
2026-10-29 at f2d89ae5, set up as above: a headless game per run on its own command port, from an uncommitted scene inheriting
`main.tscn` with its `run`'s `defender_count` and `invader_count` set, spectator mode, the default loadouts and the real Von server
(shared with other sessions). 3v3 from 16:36 to 16:41, 5v5 from 16:41 to 16:49, and 5v5 again from 18:11 to 18:19, the machine still
loaded. Survivors are the members standing when the round ended, over the ten rounds. An ambush order is one doorway an AI defender
leader ordered its crew to ambush, counted from the log by the `ORDER - ambush the doorway from the <room>` decisions of the members
that took it (one round can hold two). The early rounds are those whose first such decision came before any defender's first `COMBAT`
decision. No reply is the share of the decisions' log lines that are `no reply ... (HTTPRequest result 13) — holding steady` (a Von
timeout) instead of a decision; an NPC logs the same failure again only after a reply came between (`decision_client.gd` `_fail`), so
the share is a floor.

| Size | Invader wins | Defender wins | Timeouts | Survivors (invaders / defenders) | Round length, mean (min to max) | Ambush orders (rounds; early) | Members taking one | No reply | Load |
|---|---|---|---|---|---|---|---|---|---|
| 3v3 | 9 | 1 (seed 102) | 0 | 22 / 2 | 28.4 s (10.1 to 50.7) | 5 (5 rounds; 3) | 25 | 0.4% (2 of 521) | 3.19 → 6.97 |
| 5v5 | 9 | 1 (seed 108) | 0 | 31 / 3 | 50.5 s (11.2 to 117.1) | 11 (9 rounds; 4) | 43 | 5.7% (63 of 1100) | 6.97 → 15.83 |
| 5v5, again | 8 | 2 (seeds 104, 106) | 0 | 25 / 3 | 51.6 s (11.1 to 160.7) | 11 (9 rounds; 4) | 51 | 4.3% (42 of 967) | 4.18 → 17.60 |

Against the squads rows above (10 invader wins in 10 at both sizes), the defenders win 1 or 2 rounds in 10. Ten seeds cannot show
that as a change: two runs of one tree differ by a round or two (the two 5v5 runs here won on different seeds), and from 3 wins in 10
an arm needs 9 in 10 to differ at p < 0.05 (Fisher's exact test, two-sided); from the squads' 0 in 10 it needs 5. Neither is an A/B
of issue #128 alone: main has moved since e6cdbf7. The 3v3 seed the defenders won (102) holds no ambush order. The 5v5 rounds last
longer, with a tail past 100 s in each run, and both 5v5 runs were made on a loaded machine with Von timing out on at least 4 to 6%
of the decisions.

### Performance

**With the defenders' ambush (LD29, issue #128).** `tools/run_tests.sh --domain=perf --verbose --summary --no-lint` on f2d89ae5 and
on main (af3e0f48, a scratch `git worktree`), alternated, on 2026-10-29 from 16:08 to 16:15, each run started at a 1-min load under 4
with no other headless Godot test running (`uptime` before and after). The machine was shared and seldom quiet: of main's runs, the
first (3.82 → 4.47) and a rerun at 18:23 (3.89 → 4.28) ended over 4 and are left out, so main has two runs (3.87 → 2.75, 2.52 → 2.78)
and the change three (3.88 → 3.62, 3.99 → 3.87, 2.75 → 2.52). Every counted run of either tree passed 10 of 12: the 10v10 missed its
max in every run and its p95 in all but one, as before (#98), and the grenade match its max in every run and its p95 in two of the
change's and one of main's. In ms per frame, avg / p95 / max (bold misses):

| Guard | Change (median of 3) | Main (2 runs) |
|---|---|---|
| 10v10 match (`match_10v10_stress`) | 13.47 / **24.92** / **34.59** | 14.83 / **32.54** / **68.06**, 10.88 / 18.50 / **37.26** |
| 5v5 match (`match_5v5_stress`) | 5.90 / 11.09 / 24.83 | 5.75 / 11.56 / 31.77, 5.82 / 12.08 / 25.62 |
| grenades in a 5v5 match (`grenade_match_stress`) | 13.30 / **21.83** / **48.01** | 12.71 / **20.48** / **40.01**, 10.26 / 15.71 / **37.94** |

The grenade match's p95 was higher on the change in each of the three pairs, so that guard alone was run 8 times a tree, alternated
(16:25 to 16:32, each started at a load under 4 with no other headless Godot): the change missed a budget in 5 runs of 8 and main in
6, and the means were 11.10 / 18.15 / 33.2 on the change against 11.49 / 18.74 / 40.8 on main (without the change's two runs that
ended over 4, 10.86 / 17.89 / 32.2 and 4 misses in 6). No cost of the change shows in the guards. What the ambush adds is the
ranking of a doorway's ambush posts (`entry_posts.gd` `_ambush_ranking`): 80 candidates (5 depths by 8 offsets either side of the
axis), each with its sight lines from the stack's slots and pie steps, plus an entry's grenade landings (up to 9 frags and 9 stuns)
for the posts that can still be picked. In the A/B run whose worst frame was 69 ms, the defender leader ordered a new doorway's
ambush inside the window.

**The cost of an ambush order (issue #128's review).** The ranking is worked out once a map, not once a member: every NPC on the
navigation map shares it, keyed by the geometry's and the sight's tunables and the crouched height, until the house changes. The first
recipient's decision snapshot works it out, and the others read it. The grenade landings are counted only for the posts tied on the
least `seen` and side among those still open (`_best_post`). Every rank below `seen` adds up to less than one `RANK_SEEN`, so no other
post can be picked, and the picks are those of the full ranking: `ai/combat/ambush_posts_capture_terrace` and `_house` pin every
member's post at every doorway of two houses to a capture of it, read off a geometry with no NPC, which keeps a ranking of its own
worked out as the shared one. The shared ranking itself runs in `ai/combat/ambush_post_cover_through_body`, `perf/ambush_order_stress`
and the crew scenarios.

`perf/ambush_order_stress` guards it: a crew of three AI defenders in the match guards' house, ordered inside the window to ambush a
doorway not yet ranked. It was measured headless on 2026-10-30 against 9d078064 (the ranking once a member, every landing of all 80
counted), in a scratch worktree with the guard copied in. Three alternated pairs were run with the ranking timed in place, each run
started and ended at a 1-minute load of 3.2 to 3.7, with two other headless Godots running. In ms, the guard's max frame, then the ranking per
order:

| | max frame | ranking per order |
|---|---|---|
| per member, all landings (9d078064) | 21.05 / 21.65 / 25.15 | 9.7 / 10.4 / 11.6 ms on each of 3 frames (29.1 / 29.9 / 33.7 ms) |
| once a map, landings where they decide | 18.35 / 18.09 / 19.14 | 7.0 / 7.0 / 7.1 ms on 1 frame, + 0.35 ms of landings for 4 posts |

The guard's avg was 1.49 to 1.66 ms before and 1.29 to 1.31 after. Its budgets held both ways (an order to a crew never broke the max
on a quiet machine), but an order costs one frame of about 7 ms, against three frames of about 10 ms.

**Since the match builder (issue #95).** The three match guards (`match_5v5_stress`, `match_10v10_stress`, `grenade_match_stress`) build
their match through `MatchBuilder` as Main builds one (`s.declared_match`): the invader team beside the front door with its plates and grenades,
styled and ranked, one squad a side, every member but the leader following it. `perf/match_10v10_team_stress` is folded into
`match_10v10_stress`, which keeps its premises (one squad a side, the rank rule's leader, every member but the leader following, contact
within `Perf.MATCH_CONTACT_WITHIN`) and its logs; the 5v5 and the grenade match now require contact too (`Perf.warm_until_contact`). So `tools/run_tests.sh
--domain=perf` runs eleven guards. Re-baselined headless (`--domain=perf --verbose --summary --no-lint`, three valid runs a side, each
started at a 1-min load under 3.5 with no other headless Godot and discarded if the load went over 4; before 4af0b43, after 91400e6's
guard code, measured before the branch was rebased onto #81), medians in ms per frame, avg / p95 / max against 16.7 / 20 / 33.4 (bold
misses):

| Guard | Before (4af0b43) | After (91400e6) |
|---|---|---|
| 10v10 match (`match_10v10_stress`) | 10.88 / 14.69 / 22.42 | 11.74 / **22.04** / **65.34** |
| 10v10 team match (`match_10v10_team_stress`) | 8.91 / 11.94 / 14.41 | (folded into the 10v10) |
| 5v5 match (`match_5v5_stress`) | 5.93 / 9.10 / 12.47 | 5.55 / 11.31 / 22.89 |
| grenades in a 5v5 match (`grenade_match_stress`) | 10.16 / 15.09 / 24.20 | 10.58 / 17.29 / 33.18 |

The averages barely move; the tails do, because the guards now measure a real match. The 10v10's window holds 10 to 16 NPCs knowing a
hostile and 21 to 48 shots (the team guard's held 2 and 0), and its p95 and max miss in every run: one invader's decision that weighs its
grenades (the throw spots and the escape from the burst, in its decision snapshot) takes 20 to 47 ms in one frame. With the invaders' stuns
and frags set to 0 its max fell to 29.02. By the user's decision the guard stays red on a quiet machine and the standard is untouched; the
fix is #98. The 5v5 and the grenade match medians pass, each grazing or missing its max in one run of three. The other guards' numbers are
in the `domain-testing` skill.

**Re-measured after the review fixes** (7d067bf: the give-way's look-ahead cut to the walk left and the follower's catch-up run, both
on a per-frame path, and the three guards on one `Perf` helper). `tools/run_tests.sh --domain=perf --verbose`, three runs back to back on
2026-10-24 from 12:35 to 12:38, each started at a 1-min load under 4 (3.60-3.96, 3.62-4.22 and 3.15-3.32 through the runs, sampled
every 10 s; none discarded), medians avg / p95 / max: 10v10 12.11 / **25.91** / **51.13** (p95 23.19 to 34.42, max 50.72 to 51.77), 5v5
5.28 / 9.22 / 23.40, grenades in a 5v5 match 10.80 / 17.14 / **35.51** (max 25.30, 35.51, 50.28). Within the runs' spread of the
medians above: the 10v10 misses its p95 and max in every run (#98), the grenade match its max in two runs of three, and the 5v5 missed its
max in one run of three (38.26), as before. Every other guard held its budget in all three runs. The runs below are from before issue
#95.

**With squads following their leaders (LD19 to LD28).** `tools/run_tests.sh --domain=perf` (twelve guards, the eleven below and
`perf/match_10v10_team_stress`: the 10v10 guard's match, the same house, placement and scripted Von, with one squad a side bound as Main
binds it, so its members follow their leaders), `--verbose` for the `PERF` lines, with the squads, 3 runs back to back on
2026-10-19 from 12:36 to 12:39, the 1-min load 3.19 → 3.08, 3.08 → 3.29 and 3.29 → 4.06 (`uptime` before and after each, on 12 cores;
none discarded). Each passed 12 of 12. In ms per frame, avg / p95 / max, against the smooth-match budgets 16.7 / 20 / 33.4:

| Guard | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| 10v10 match (`match_10v10_stress`) | 10.80 / 14.79 / 20.18 | 10.45 / 13.72 / 18.40 | 10.37 / 13.87 / 19.87 |
| 10v10 team match (`match_10v10_team_stress`) | 7.59 / 9.16 / 13.11 | 8.25 / 10.76 / 13.42 | 11.06 / 15.07 / 19.34 |
| 5v5 match (`match_5v5_stress`) | 5.83 / 8.65 / 12.38 | 5.06 / 8.90 / 12.99 | 5.82 / 8.90 / 12.73 |
| grenades in a 5v5 match (`grenade_match_stress`) | 8.65 / 13.97 / 22.06 | 8.86 / 14.29 / 24.14 | 10.88 / 15.70 / 24.06 |

The team guard opens its window only once the sides are in contact (a shot fired; the warm-up runs on past its 6 s for at most
`Perf.MATCH_CONTACT_WITHIN`, 20 s, and the guard fails without it), so what it measures is the teams' fight; in all three runs the first shot came
within the warm-up (`PERF 10v10 team match contact at 6.0 s`), and the window ended with 13, 18 and 9 members following. The guard
also requires that some NPC knows a hostile as the window opens (`known_contacts_for_display()`): in 8 runs on 2026-10-19 (14:10 to
14:12, load 3.97 to 5.54) two NPCs did each time, while shots fired inside the window came in 1 of those 8 (12 shots) and 1 of 5 runs
just before them (11 shots), none in the rest, so the shots are logged, not required. Every frame
guard of all three runs was within its budget: the worst frame of these four guards, 24.14 ms (the grenade match), is under the 33.4 ms
max, so the budgets stand. Then those four guards ran `--repeat=10` in one process (12:41 to 12:46, load 3.59 → 4.53): 40 of 40 passed.
Over the ten runs of each, avg / p95 / max ranged 4.30 to 6.60 / 7.31 to 10.34 / 11.04 to 30.80 (5v5), 9.88 to 11.15 / 12.85 to 14.72 /
15.30 to 24.78 (10v10), 6.55 to 9.46 / 8.16 to 11.87 / 11.49 to 17.05 (10v10 team, contact at 6.0 s in all ten) and 8.51 to 11.98 /
12.75 to 19.18 / 19.85 to 30.73 (grenades in a 5v5).

**Before the audit fixes.** The same three `--domain=perf` runs on the squads tree before its audit fixes, the same morning (07:42 to
07:44, load 2.06 to 2.70, the team guard not yet waiting for contact), gave the 10v10 9.81 to 10.59 ms avg (max at most 18.95), the team
match 7.04 to 9.74 (max at most 20.07) and the 5v5 4.36 to 5.85 (max at most 14.62). Runs 1 and 3 passed 12 of 12. Run 2 passed 11: the log gate failed
`perf/crowd_deaths_stress` (ten puppets killed at once; no AI, no squad) on one engine error, "Invalid polygon data, triangulation
failed" (`canvas_item_add_polygon`), on the frame the deaths were dealt. That guard then passed 40 of 40 on its own (four at a time), and 300 more runs
(six at a time, so their frame times do not count) logged no such error, with every polygon draw on its path that has no triangulation check (`FillBatch.fill` and `fill_convex`, a limb's
strip, the trunk, the shoulders' shadow, `Deformation.draw_shape` and `draw_wall`) checked for an outline the engine cannot cut. The
error is not reproduced and its source is not known.

**Before following.** The perf guards (`tools/run_tests.sh --domain=perf`, eleven tests then) with LD13 to LD18 and the stack geometry of `docs/tactical-entry.md`
E20 to E22, against the base commit (c8821b0, a clean checkout). Measured on 2026-10-17 from 13:57 to 14:07, 8 full runs of each,
alternated base then change. The machine was shared with other sessions: the 1-min load average was 3.6 to 5.9 on 12 cores, read with
`uptime` before and after every run, and no run was discarded. Means in ms per frame, avg / p95 / max:

| Guard | Base (c8821b0) | Change |
|---|---|---|
| 10v10 match | 10.77 / 14.50 / 19.81 | 10.71 / 14.43 / 19.96 |
| 5v5 match | 6.01 / 9.70 / 13.43 | 5.60 / 9.19 / 13.98 |
| NPC crowd | 4.49 / 9.72 / 16.38 | 4.63 / 10.64 / 16.09 |
| grenades in a 5v5 match | 10.15 / 15.72 / 30.13 | 10.33 / 15.76 / 33.32 |
| hit overload | 10.45 / 12.60 / 16.19 | 10.30 / 12.64 / 14.34 |
| crowd fall | 7.64 / 11.80 / 16.56 | 7.66 / 11.85 / 16.31 |
| frag and stun burst | 6.61 / 8.41 / 24.20 | 6.75 / 8.68 / 24.20 |
| gunfire | 5.50 / 8.49 / 10.91 | 5.76 / 9.47 / 14.80 |
| furniture pile moving | 0.70 / 2.02 / 2.80 | 0.71 / 2.04 / 2.64 |

The other two guards, `bake_and_path_stress` and `generate_houses_stress`, time one-shot work (a nav re-bake with its path queries, house
generation) against a budget of their own (`Perf.time_ms`), not frames: they have no avg / p95 / max to compare, so they are not in the
table. Both stayed within their budgets in every run of both trees.

**The mean frame.** It is the same in both trees, within the run-to-run spread. The 8 runs' avg, mean ± sd:

| Guard | Base | Change |
|---|---|---|
| 10v10 | 10.77 ± 0.25 | 10.71 ± 0.70 |
| grenades | 10.15 ± 0.73 | 10.33 ± 0.99 |

**The worst frame.** The grenade match's worst frame per run, in the 8 runs above:
- Change: 22.75, 44.26, 28.10, 25.92, 23.58, 63.13, 25.70, 33.12.
- Base: 57.60, 23.42, 26.25, 23.86, 25.16, 24.15, 34.34, 26.24.

Each tree went over a 33.4 ms max budget in 3 of its 8 runs:
- Base: grenades 57.60 and 34.34, and hit overload (no AI) 34.07.
- Change: grenades 44.26 and 63.13, and gunfire (no AI) 40.29.

A per-frame log of navigation bakes found none of those frames on a frame where an avoid or planning bake started, landed or was in flight.

**Against the base the change is rebased on (0e19010), the grenade match's worst frame was over budget more often before the shared escape work below.** On 2026-10-17
the change was measured again: 3 runs of `--domain=perf`, each with a 1-min load under 4 before and after. Every guard is within the
run-to-run spread of the Change column above. The grenade match's worst frame went over 33.4 ms in 2 of the 3 runs (36.85, 35.66).
Then `--id=perf/grenade_match_stress --repeat=10` was run in 5 pairs, base then change, one Godot at a time, from 23:06 to 23:23, with
the 1-min load 4.0 to 6.7 before and after each run. Per pair, the worst frame's median / its worst / the runs over 33.4 ms:

| Pair | Base (0e19010) | Change |
|---|---|---|
| 1 | 24.27 / 28.70 / 0 | 23.01 / 43.90 / 1 |
| 2 | 24.74 / 33.15 / 0 | 26.49 / 33.72 / 1 |
| 3 | 24.72 / 32.99 / 0 | 24.14 / 43.13 / 2 |
| 4 | 23.79 / 26.99 / 0 | 26.27 / 37.79 / 2 |
| 5 | 25.88 / 33.30 / 0 | 26.23 / 55.24 / 2 |

The medians of the 50 runs are the same in both trees:

| Tree | avg | p95 | max |
|---|---|---|---|
| Base | 10.13 | 15.58 | 24.48 |
| Change | 10.23 | 15.36 | 24.80 |

The tail is not the same:
- **Base:** 0 of 50 runs go over 33.4 ms (worst 33.30).
- **Change:** 8 of 50 go over (33.72 to 55.24), at least one in every pair.

**Where that frame's time goes.** A throwaway per-function timer (since removed) ran in 2 alternated pairs of 10 runs at a load of 4.6
to 6.3. Under the timer, 5 change frames and 4 base frames went over 33.4 ms.
- **Change:** 4 of its 5 are frames on which 4 to 8 NPCs are evading a grenade.
- **Base:** 2 of its 4 are such frames (6 NPCs each). One more mixes an evade plan with a decision, and one has no evade in it.

Most of such a frame is `AgentGrenades.plan`: the escape plan, `AgentThrow.escape`, with its `NavBuilder.route` calls. The timer also
read each run's three slowest frames where the plan took over 5 ms: 21 a tree, with 2 to 9 NPCs evading. On those frames:

| | Change | Base |
|---|---|---|
| `AgentGrenades.plan`, average | 16.87 ms | 13.63 ms |
| `AgentGrenades.plan`, worst | 37.81 ms | 30.26 ms |
| `NavBuilder.route` calls | 371 | 301 |
| Cost per route call | about 11.5 µs | about 11.5 µs |
| The rest of the AI tick | 3.08 ms | 3.01 ms |

`AgentThrow.escape` and the plan's search were the same code in both profiled trees, before the fix below. On the change they routed
about a quarter more spots on those frames. Which of the change's behaviours puts the NPCs where more of the candidates survive is not
traced: the fix below takes the repeated work out of every such frame, whatever the count.

**What a plan costs, and the fix (2026-10-18).** A throwaway timer inside `AgentThrow.escape` (since removed) split the plan, on the
grenade match's slowest frames:
- **Per escape** (one NPC's plan, made alone): about 2.5 ms of work that depends only on the burst (the candidates round it, about
  50 rays, 0.4 to 0.5 ms; snapping them onto the navmesh, 0.45 to 0.55 ms; judging each spot by the blast's lines, `Explosion.shields`,
  1.5 to 2.2 ms) and about 1.2 ms of routing (about 90 `NavBuilder.route` calls). The routes are a third of it, the rest the burst's.
- **Per frame:** an evade wave is 3 to 8 escapes on one frame, mostly for one grenade. On the slowest wave measured (7 NPCs, 37.7 ms
  of planning) the candidates cost 3.6 ms, the snaps 3.6 ms (1176 snaps of 412 different points), the verdicts 17.2 ms (991 of 362
  different spots) and the routes 7.7 ms (625).

So most of a wave's cost was the same burst work done once per NPC. `AgentThrow` now keeps it for the physics frame (`_shared_burst`,
`_shared_snaps`: the candidates round the burst, each candidate's navmesh spot, each spot's verdict, keyed by the burst, its kind, the
zone, the NPC's heights and the bodies the lines pass through); each NPC keeps its own ring of candidates and its own routes. Inside a
physics frame the walls, furniture and navigation map hold still for these queries, so every NPC picks the spot its own search would
(test `ai/grenade/evade_wave_spots_match_own_plan`: five defenders plan together, every plan's spot equals the plain search's for that
NPC on that frame). The same timer, 10 runs of each tree in alternated rounds of 5 (load 5.2 to 7.1), then 30 more of the change
(load 4.9 to 5.9): the worst evade wave, 8 NPCs planning on one frame, took 35.9 ms of planning before the fix and 17.4 ms after (a
26.1 ms frame); a plan made alone costs what it did. In those 30 timed runs no frame went over 33.4 ms (worst 33.25 ms, a frame with no
evade plan in it), and of each run's worst frame, 3 are evade waves (26.75, 26.11 and 23.20 ms, with 3, 8 and 5 NPCs planning), the
others burst frames with no plan in them.

**The A/B after the fix** (2026-10-18, 02:28 to 02:45 and 03:14 to 03:30): `--id=perf/grenade_match_stress --repeat=10` in 10 pairs,
base (a `git archive` of 0e19010) then change, one Godot at a time, the 1-min load 4.3 to 7.2 before and after each run but for pair 7's
change run and pair 8's base run, between which it rose to 11.4 (another worktree's work; both runs kept). No run was replaced or dropped.
Per pair, the worst frame's median / its worst / the runs over 33.4 ms:

| Pair | Base (0e19010) | Change |
|---|---|---|
| 1 | 25.86 / 32.24 / 0 | 23.66 / 30.02 / 0 |
| 2 | 27.89 / 35.57 / 2 | 24.76 / 27.97 / 0 |
| 3 | 25.85 / 32.37 / 0 | 24.89 / 30.14 / 0 |
| 4 | 23.71 / 31.56 / 0 | 24.27 / 43.84 / 1 |
| 5 | 25.70 / 28.64 / 0 | 26.82 / 59.34 / 2 |
| 6 | 24.19 / 47.76 / 1 | 25.12 / 30.19 / 0 |
| 7 | 25.01 / 39.52 / 1 | 24.18 / 32.00 / 0 |
| 8 | 23.82 / 34.14 / 1 | 24.09 / 31.18 / 0 |
| 9 | 24.79 / 33.51 / 1 | 22.87 / 25.19 / 0 |
| 10 | 26.08 / 31.04 / 0 | 24.81 / 38.41 / 1 |

The 100 runs of each tree, pooled (medians, ms):

| Tree | avg | p95 | max | Runs over 33.4 ms |
|---|---|---|---|---|
| Base | 10.04 | 15.35 | 25.33 | 6 of 100 (33.41, 33.51, 34.14, 35.57, 39.52, 47.76) |
| Change | 10.46 | 15.80 | 24.31 | 4 of 100 (33.56, 38.41, 43.84, 59.34) |

The change's worst frame is now lower than the base's in the median and goes over the budget no more often. Pairs 1 to 5 alone gave the
base 2 of 50 and the change 3, pairs 6 to 10 the base 4 and the change 1: at this load the tail is a few runs in 50 in both trees. The timed runs
put no evade wave near the budget; what the change's 43.84 and 59.34 ms frames were is not known (no timer ran in those runs).

**The perf guards after the fix** (2026-10-18, 03:13, `--domain=perf`, 1-min load 3.84 before and 3.55 after): 11 of 11 pass. The
grenade match 10.06 / 14.31 / 21.60 ms (avg / p95 / max), the frag and stun burst 6.12 / 8.12 / 24.77, the 10v10 10.83 / 14.08 / 19.44,
the 5v5 6.02 / 9.37 / 14.30. An earlier run at 03:06 also passed 11 of 11 and is not counted: the load rose from 3.87 to 6.45 during it.

**What the profile found** (2026-10-17, profiled pairs of both trees, load 3.4 to 4.7):
- **The slowest frames in the measured window are grenade evade planning, in both trees.** `AgentGrenades.plan` / `AgentThrow.escape`
  cost 3 to 10 ms per NPC per plan, and 2 to 5 NPCs plan on one frame. Measured against c8821b0, the same in both trees: 23.0 ms of evade
  planning in one frame across 5 defenders on the change, 22.9 ms (34.3 ms wall) on the base. The code was shared and unchanged when
  profiled (against 0e19010 the plan routed more spots on the change, above).
- **The stack geometry is laid before the window opens.** Each way in costs 7 to 52 ms to lay (its bands 2 to 15, the overflow 10 to 28),
  one a physics frame among every NPC (`AgentEntry.warm_geometry`). All of Garage Home's are laid by 0.22 s, well before the guards' 6 s
  warm-up ends. Once a pass finds every way in laid, `warm_geometry` stops looking until the house, a tunable or the map's shared geometry
  changes (`AgentEntry`'s `layouts.warm_done_in` / `warm_done_for`). That brought its per-tick cost from 0.10 to 0.21 ms a frame down to the profiler's floor,
  0.04 ms.
- **The room an approach enters is carved only when the way round would go into it (D4).**
  - `AgentDoorViews.walk_route` routes an approach on the uncarved views map, the one every walk shares, and asks for a map with the
    entered room's floor carved too only when that route goes into the room (test
    `ai/entry/entry_ordered_approach_keeps_out_of_entered_room`). Each avoid map is re-baked after every planning bake while approaches
    walk (furniture shoved by a blast, say), so a carved map per approach is a cost: priced on the base commit, 4 of them take the
    grenade match's avg from 9.55 to 10.19 ms and bring 40 ms worst frames, and leave the 10v10's avg as it is (10.96 and 10.85; 7
    alternated runs, load 3.3 to 6.5).
  - In the AI match guards no room-carved map is built. A match bakes 2 to 9 avoid maps against the base's 1 to 3: the extra ones are
    the single-doorway sets of `_entering_set`.
- **The AI tick's own extra cost on the 10v10 is +0.2 to 0.3 ms a frame, profiled** over 3 + 3 pairs with every approach's room
  carved (the costlier routing above). It is mostly the entry choreography and the rest of `observe`. It does not show in the unprofiled
  mean above, where the gap is within the spread.

The dated sections of `docs/grenades.md`, `docs/player-vision.md` and `docs/leadership.md` above were moved here the same way (#194,
the last docs pass): the specs keep the current rules.
