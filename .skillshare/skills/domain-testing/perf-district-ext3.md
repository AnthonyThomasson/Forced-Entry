# Performance guards on the district: #192's Extension 3 runs and the two spikes' findings

Side file of `perf-district.md` (`perf.md`, `domain-testing`). Extension 3 (rules 33 to 38) merged the view's fan table and pose lag, the
character draw caches and the decision micro bundle. Runs were made 2026-11-07 on the merge of the three slices
(`b947d6e8`, story branch `AnthonyThomasson/Investigate-strategies-to-improve-performce`).

## After #192's Extension 3 (2026-11-07): AC40 is NOT met

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

## After the stagger fix, before the review fixes: base against the branch, interleaved (2026-11-07)

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
