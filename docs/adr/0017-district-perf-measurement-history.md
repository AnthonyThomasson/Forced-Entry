# The district perf guards' measurement history (#182, #192, #195)

Recorded for #194 (docs sweep, job 20). The `domain-testing` perf skills state what holds now: the guards, their premises and the rules to keep. Their dated
measurement runs, profiles, spikes and the budgets that were red when each was taken lived there too; they are here, unedited but for the heading levels.
Every number below was measured on the 2D build (before #194): the 2D `character_visuals` `_draw` rows, `draw_cache_pixel_identical` and the draw caches, the
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

The escape search is pruned (nearest route first, stop past the best) and capped at `AgentGrenades.ESCAPE_CAP` 3 a physics frame (fresh plans first, a
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
  **Correction (#194 perf-decide2 review, 2026-11-24, measured):** "1 to 3 frames, small against Von's about 100 ms" no longer holds. With the pieces split and priced a decision with a hostile lands in 4 frames alone, 7 with two, and in a 10v10 (seed 23) the pool of 4 units is full: the median claim to land is 4 frames in the opening but the p95 52 and the max 68 (1.1 s), in the stress window 9 / 81 / 97; eight at once land on frames 4 to 31 (`decision-prices.md`). A decision is not hidden behind Von's wait; whether to widen the pool is a decision of the ticket's.
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
