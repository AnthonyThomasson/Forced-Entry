# AI · The decision job's prices and how to observe a landing (`decision_prices.gd`, `decision_budget.gd`)

Side file of `decision-job.md` (split out to keep it under the 8192-byte cap). How the prices were measured, and the measured effects: `docs/adr/0017-district-perf-measurement-history.md`.

**The pool and the unit.** `DecisionBudget.per_frame` 6 units, about 3 ms of decision work a frame (a unit is about half a millisecond; START, 1 unit, is about 0.3 ms alone). A piece costs what it measured, rounded up so its p90 fits the pool less the start's unit: no piece is dearer than 3 (`decision_pool_suite` pins that), and a piece dearer than what is left waits for a fresh frame. Prices live in `DecisionPrices` (piece kinds, `of_piece`) and `DecisionBudget` (throw steps, group units, refusal, level, `work_unit`).

**Prices** (mean / p90 as multiples of START's median in `perf/match_10v10_opening` at seed 23, 1.0 = about 0.3 ms alone):

| Piece | Static | Units | Mean / p90 (x START) |
|---|---|---|---|
| START (the claim: reads, freezes the knowledge) | `cost_start` | 1 | 1.1 / 1.8 |
| HOSTILE (a hostile's line and fire rings) | `cost_hostile` | 2 | 2.6 / 3.2 |
| SPOTS (its fire spots and ambush spots) | `cost_spots` | 3 | 3.3 / 4.6 |
| FLANKS (one side's flank test, one piece a side, two sides tried) | `cost_flanks` | 1 | 0.9 / 1.8 |
| REST (its analyses, targets, sections) | `cost_rest` | 2 | 2.1 / 2.7 |
| RETREAT (the retreat group's spots: the heaviest of the finish's) | `cost_retreat` | 3 | 3.0 / 6 |
| AMBUSH chunk (4 of 80 offsets of the post ranking) | `cost_ambush` | 1 | 0.4 / 4.8 (mostly kept) |
| FINISH (facts, the other groups, the demand, the sections) | `cost_finish` | 1 | 0.8 |
| REFUSAL, each planner LEVEL | `cost_refusal`, `cost_level` | 0 | well under START |
| THROW block of the throw-spot scan (`ThrowSpots.block_size` 48 raw, ended at `block_work` 80 of `work()`) | `cost_throw_block`, then charged by work | 2 | 3.0 / 4.7 |
| THROW rank pass, one route | `cost_throw_rank`, `cost_throw_route` | 2, 2 | 1.8 (a route) / 3 |
| GROUP / GRENADE unit (a lead's route, a doorway's pick, one kind's throw: the throw spot is stepped, rank then a route a step) | `cost_group_unit` | 2 | 1.6 / 3.1 |

**Work charge.** A priced throw step that did more than its price is charged the rest once it has run (`DecisionBudget.charge`, `work_unit` 40): the work is `ThrowSpots.work()`, a count in quarter-units (four for each count of `GrenadeArc.work` (it counts every sweep or level cast, a remembered one again) and one for each raw candidate tested, through the cheap tests: whole numbers, so a block's cut and a charge never follow what the process counted before), never a time. 4 raw candidates cost about one `GrenadeArc.work`. An 80-work block is 2 units, a 160-work lob 4, a frame to itself.

**The pieces.** The hostile is HOSTILE, SPOTS, FLANKS a side, REST (`AgentSnapshot._analyse_step`, `FireSpots.begin` / `spots_step`, `AgentTactics.flank_side`), the retreat spots are RETREAT ahead of the finish, and the throw spot is stepped (`ThrowSpots.ranked_spots`, `walk_one`, `SnapshotThrows._wayed`), so no piece is a long frame. The price is latency, pinned by `decision_pool_suite`: with a hostile the build lands in 3 frames (the RETREAT, 3 units, does not fit what the second frame leaves, so it and the finish take the third), with two in 4, with an ambush ranking in 6 (the fake build runs the RETREAT piece as a real one does; a live trace of the real build, `sliced_matches_whole`, gives the same pieces); the shipped pool never lets one frame hold a whole decision.

**How long a decision takes, who is served first, what keeps decisions cheap:** `decision-latency.md`.

**Observing a decision's landing.** A decision claims at once (`decisions` grows at the claim) and lands frames later, so a test that reads its result waits for `debug_state()["decisions"]` past the count it saw and `debug_state()["decision"]["pending"]` (also `debug_brain()["pending"]`) false: `pending` is the job's (claimed, building, searching for a throw or walking), not only the planner's walk. Tests that carry the prices as a premise name them: `tests/_ai/job_fakes.gd` has `whole_prices()` (a pool of one, every piece but the claim free: the decision runs whole in one frame) and `prices()` / `set_prices()` to put the game's own back; a test that watches pieces over frames sets every piece to 1 and the pool to 1 (`pool_release_probe.gd`). `sliced_matches_whole` and `sliced_flank_sides_differ` are the scenario guards; a scenario test never pins the whole prices to dodge the latency.

A bang's plan (`EntryGrenade._plan_bang`, one planner call a grid aim x spot) tries `BANG_PLANS_A_FRAME` 12 aims a frame and the thrower waits meanwhile.
