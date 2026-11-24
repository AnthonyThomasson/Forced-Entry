# AI · The decision job's prices and how to observe a landing (`decision_prices.gd`, `decision_budget.gd`)

Side file of `decision-job.md` (split out to keep it under the 8192-byte cap). History of the measured effects: `docs/adr/0017-district-perf-measurement-history.md`.

**The pool and the unit.** `DecisionBudget.per_frame` 4 units, about 2 ms of decision work a frame (a unit is about half a millisecond; START, 1 unit, is about 0.3 ms alone). A piece costs what it measured, rounded up so its p90 fits the pool less the start's unit: no piece is dearer than 3 (`decision_pool_suite` pins that), and a piece dearer than what is left waits for a fresh frame. Prices live in `DecisionPrices` (piece kinds, `of_piece`) and `DecisionBudget` (throw steps, group units, refusal, level, `work_unit`).

**Prices** (#194 perf-decide2, throwaway timers round each piece in `perf/match_10v10_opening` at seed 23, ratio to START's median in the same run because the machine was loaded 200 to 500; never committed; mean / p90 as multiples of START, 1.0 = about 0.3 ms alone):

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
| THROW block of the throw-spot scan (`ThrowSpots.block_size` 48 raw, ended at `block_work` 20 of `work()`) | `cost_throw_block`, then charged by work | 2 | 3.0 / 4.7 |
| THROW rank pass, one route | `cost_throw_rank`, `cost_throw_route` | 2, 2 | 1.8 (a route) / 3 |
| GROUP / GRENADE unit (a lead's route, a doorway's pick, one kind's throw: the throw spot is stepped, rank then a route a step) | `cost_group_unit` | 2 | 1.6 / 3.1 |

**Work charge.** A priced throw step that did more than its price is charged the rest once it has run (`DecisionBudget.charge`, `work_unit` 10): the work is `ThrowSpots.work()`, a count (the arc planner's questions, memo hits included, plus a quarter of the raw candidates through the cheap tests), never a time. Fit on 290 blocks: cost = 0.03 x raw + 0.11 x work in START-units, so 4 raw candidates cost one planner question. A 20-work block is 2 units, a 40-work lob 4, a frame to itself.

**What the cut changed (#194 perf-decide2).** Before: the hostile was one piece (3 units' worth of lump, up to 9 ms with a heavy `fire_positions`), the finish ran the retreat group (a quarter of a frame) and the throw spot's rank plus up to ten routes ran in one grenade unit (the one-off 41 ms frame, `job_advance` 13.7 ms). Now the hostile is HOSTILE, SPOTS, FLANKS a side, REST (`AgentSnapshot._analyse_step`, `FireSpots.begin` / `spots_step`, `AgentTactics.flank_side`), the retreat spots are RETREAT ahead of the finish, and the throw spot is stepped (`ThrowSpots.ranked_spots`, `walk_one`, `SnapshotThrows._wayed`). The price is latency, pinned by `decision_pool_suite`: with a hostile the build lands in 4 frames (RETREAT, 3 units, and the finish share the last), with two in 7, with an ambush ranking in 9 (the fake build runs the RETREAT piece as a real one does; a live trace of the real build, `sliced_matches_whole`, gives the same pieces); the shipped pool never lets one frame hold a whole decision.

**How long a decision takes in a 10v10** (#194 perf-decide2 review, a probe that is no test: seed 23, scripted Von, counts of frames, two runs byte-identical; opening = 300 frames from first contact at 0.52 s, stress = 6 to 11 s; "before" = the pool of 3 and the coarse pieces of 7ac9c9ee, which f6ad93ee matches exactly; frames count the claim as 1):

| | Opening before / now | Stress before / now |
|---|---|---|
| claims in the window, per NPC a second | 78 / 72, 0.84 / 0.75 | 51 / 37, 0.59 / 0.41 |
| claim to land, median / p95 / max | 2 / 16 / 25, then 4 / 52 / 68 | 3 / 20 / 23, then 9 / 81 / 97 |
| refused wait (wanted, no job, pool said no), median / p95 / max | 0 / 38 / 115, then 2 / 60 / 73 | 0 / 33 / 53, then 4 / 53 / 71 |
| forced of the landed decisions | 74 of 76, then 66 of 68 | 48 of 48, then 35 of 36 |
| jobs in flight, mean / max; units spent a frame | 0.9 / 3, 2.4 of 3, then 3.0 / 5, 3.9 of 4 | 0.8 / 2, 2.2 of 3, then 1.9 / 4, 3.7 of 4 |
| units per landed decision | 9.6, then 17 | 13, then 31 |

Cadence decisions are one or two a window: nearly every decision is forced (a new hostile, an order, under fire, a task resolved), so serving forced before cadence orders nothing. The pool is full (3.7 to 3.9 of 4 units, at its limit in 77 % of the frames) and claims queue 3 to 5 deep: a decision with a hostile or two and a grenade search costs 17 to 31 units against 4 a frame, the match asks for 10 to 15 a second. By reason (now): a new hostile lands in 30 frames median (68 max) in the opening, under fire in 3 (77 max in the stress), an order in 3 to 25. Eight decisions at once land on frames 4, 8, 12, 16, 20, 23, 27 and 31 (`decisions_spread_over_frames` pins each, it was 2 to 11).

**Cheaper and ranked (#194 perf-decide2, the user's decision "cheaper decisions"; probe above, stress / opening claim to land now median 3 / 3.5, p95 21 / 34, 0.46 / 0.79 decisions an NPC a second).** (1) An NPC that carries no grenade makes no throw search: `SnapshotDemand.throw_search` sets `grenade_ready` false at once (no throw is possible with none in the pack: `throw_search_skipped_without_grenade`). (2) The pool is served by reason rank, then oldest claim (`DecisionRoster.rank_of`): attacked and hostile belief changed, ordered, task resolved, follows its leader, way blocked, any other reason and cadence; a job is served after the better-ranked jobs in flight and the older ones of its rank, so under fire a decision is not queued behind routine ones. A routine job can wait behind a stream of urgent ones (the opening's worst landing is 122 frames). `decision_pool_suite` pins the ranks and the overtaking.

**Observing a decision's landing.** A decision claims at once (`decisions` grows at the claim) and lands frames later, so a test that reads its result waits for `debug_state()["decisions"]` past the count it saw and `debug_state()["decision"]["pending"]` (also `debug_brain()["pending"]`) false: `pending` is the job's (claimed, building, searching for a throw or walking), not only the planner's walk. Tests that carry the prices as a premise name them: `tests/_ai/job_fakes.gd` has `whole_prices()` (a pool of one, every piece but the claim free: the decision runs whole in one frame) and `prices()` / `set_prices()` to put the game's own back; a test that watches pieces over frames sets every piece to 1 and the pool to 1 (`pool_release_probe.gd`). `sliced_matches_whole` and `sliced_flank_sides_differ` are the scenario guards; a scenario test never pins the whole prices to dodge the latency.

A bang's plan (`EntryGrenade._plan_bang`, one planner call a grid aim x spot) tries `BANG_PLANS_A_FRAME` 12 aims a frame and the thrower waits meanwhile.
