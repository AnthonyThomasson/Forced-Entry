# AI · How long a decision takes, who is served first (`decision_roster.gd`)

Side file of `decision-job.md` and `decision-prices.md` (split out to keep them under the 8192-byte cap): the probe tables of a decision's latency in the 10v10, the order the pool serves jobs in and what the "cheaper decisions" steps cut (#194 perf-decide2).

**Order and ageing.** The pool is served by reason rank (`DecisionRoster.rank_of`): attacked and hostile belief changed (also `sight returned`, `lost the engaged contact`: a change of the hostile belief), ordered (an order is rank 1, not a routine job), task resolved, follows its leader, way blocked, any other reason and cadence. A younger better-ranked claim is served before an older worse-ranked job: cross-rank overtaking is the rule. A rank **ages in frames** (never a clock): effective rank = rank less one for every 30 frames since the claim (`AGE_FRAMES`, never below 0), judged in `owed()`, so no job waits more than 5 x 30 frames behind a stream of better ones, then it ranks with them and, begun before them, is served first (`decision_pool_suite` pins 6 x 30). A job the roster forgot (not served for 3 frames) is registered again as a new claim and starts its age over.

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

**Cheaper and ranked (#194 perf-decide2, the user's decision "cheaper decisions"; probe above, stress / opening claim to land now median 3 / 3.5, p95 21 / 34, 0.46 / 0.79 decisions an NPC a second).** (1) An NPC that carries no grenade makes no throw search: `SnapshotDemand.throw_search` sets `grenade_ready` false at once (no throw is possible with none in the pack: `throw_search_skipped_without_grenade`). (2) The pool is served by reason rank, then oldest claim (`DecisionRoster.rank_of`): attacked and hostile belief changed, ordered, task resolved, follows its leader, way blocked, any other reason and cadence; a job is served after the better-ranked jobs in flight and the older ones of its rank, so under fire a decision is not queued behind routine ones. A job's rank ages (one step per 30 frames since its claim, `DecisionRoster.AGE_FRAMES`), so a routine job or an order waits at most 150 frames behind a stream of urgent ones (122 frames was the worst landing of an order, rank 1, in the opening before). `decision_pool_suite` pins the ranks and the overtaking.

**One analysed hostile unless engaged (step 1b, #194 perf-decide2).** An NPC with no engaged contact analyses the nearest hostile only (`AgentSnapshot._analysed_ids`: cap 1; with an engaged one in the contacts the cap stays `min(max_analysed_targets, max_options_per_level)`, the engaged one and the nearest other). The others are listed with their line only, as those past the cap already were. Pinned by `analyses_one_when_not_engaged`; the engaged-and-nearest tests set an engaged hostile.

**The measure that counts is wish to land** (the pool-refused wait before a claim plus claim to land; frames), seed 23 at the merged ticket tip a56fd2d2, one probe window each, counts, run twice the same (`decide_probe_test.gd`, never committed). "Before" is that tip (pool 3, coarse pieces), "now" this branch (pool 4, split pieces, no throw search without a grenade, reason ranks with ageing, one hostile unless engaged). A match diverges once decisions land on other frames, so the claim counts differ (the stress window's fight ended earlier).

| | Opening before / now | Stress before / now |
|---|---|---|
| claim to land, median / p95 / max | 3 / 16.5 / 49, then 3 / 36 / 62 | 2 / 4 / 16, then 3 / 26 / 28 |
| wish to land, median / p95 / max | 9 / 56 / 114, then 10.5 / 73 / 90 | 3 / 25 / 27, then 4.5 / 26 / 28 |
| decisions per NPC a second | 1.04, then 0.91 | 0.47, then 0.24 |
| dropped claims (claimed, then cancelled) | 4 of 95, then 9 of 85 | 2 of 39, then 2 of 20 |
| units per landed decision, pool use | 10.8 of 3, then 13.6 of 4 | 4.8, then 17.9 |

**Why claims drop.** Every drop is an interrupt by design, none a better-ranked wish re-claiming over its own job: an order taken since a build began restarts it (`overtaken_by_order`), or a forced decision starts at another node than the job in flight (`stale`: a walk that began at the root while the NPC came under fire, a new hostile in a build begun at the root). A job in flight longer is exposed to more of them, so the count follows the claim-to-land time, not a waste: the cure is a build that is shorter.

**Step 1c, measured and not made (round 4).** A hostile's analysis kept for the NPC's next decision (stamp: hostile, NPC and others within 6 px, front 0.05 rad, eye, side, nav iterations, doors; 12 frames) was built and probed: 0 of 43 analyses in the seed 23 opening reused. An NPC's decisions are 15 to 210 frames apart (the belief interval alone is 30), by then it has moved (0 to 99 px), the other hostiles known differ and the nav iterations turned. Ignoring all but the hostile, the NPC and the side, 4 of 43 hit, at ages 15 to 42: about 20 of 700 units, for stale spots. Dropped, nothing committed.

**Pool size, measured (round 4; probe on seeds 23, 5, 11, 17, 31 pooled, wish to land median / p95, decisions an NPC a second, units per decision; the fights diverge with the pool, so one seed alone says little).**

| pool | opening | stress |
|---|---|---|
| 4 (now) | 7 / 107, 0.58, 15 | 7 / 203, 0.36, 16 |
| 5 | 5 / 143, 0.56, 20 | 9.5 / 170, 0.35, 31 |
| 6 | 7 / 52, 0.63, 20 | 16 / 156, 0.43, 36 |

5 is no better than 4. 6 cuts the opening's tail (seed 23: 10.5 / 73 / 90 to 10 / 46 / 58) but the stress median doubles, a frame may spend 3 ms on decisions instead of 2, and 19 ai tests' Von recordings stop matching (re-record). Not shipped: `per_frame` stays 4.
