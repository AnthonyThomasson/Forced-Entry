# Flanking tests (tag `flank`)

`tests/ai/flank/` pins how the AI weighs and takes the sides of a target (`docs/flanking-behavior.md`: behaviours F, B1 to
B9, C). They are scripted-Von tests; `tools/run_tests.sh flank` runs them. A test of a behaviour the AI does not show yet
is written first, left red and tagged `gap`.

- **Maps** (`tests/_ai/flank_maps.gd`, `const Maps`): `Maps.house(s)`, `spine(s)`, `warehouse(s)` lay out rooms, doorways,
  corridors and cover with `TestSetup.layout` and expose landmark consts. Call the map first, then `Flank.rules(s)`. Flank
  points sit 220 px from the target and snap to the navmesh, so a room-sized map puts some sides behind walls: choose
  positions from a `Flank.dump(brain)`.
- **Helper** `tests/_ai/flank_probe.gd` (`const Flank`): `rules`, `target`, `npc`, `ally`, `radio`, `settle`, and the reads.
- **Observe through the controller's public reads.** `debug_zones()` lists every flank side the snapshot weighed,
  including those the planner then dropped, with `desc` and `tags`; `debug_state()["decision"]["levels"]` holds what each
  level offered. "Dropped because X" is: zones says X and `offered` lacks the id. With several hostiles known the zones mix
  their sides: give `Flank.zones(brain, target_pos)` the target and make the NPC fight it with `Flank.prefer_target`.
  `Flank.side_of` is the test's own copy of the target-frame maths (left is the target's own left).
- **Hold the NPC and settle** (`Flank.npc` + `Flank.settle`): `movement:speed` 0 and a 0.4 s commit and tactic cadence, so it
  re-decides from a fixed spot and `settle` waits for a finished walk. A walking test holds the NPC until `settle`, then sets
  `brain.tuning.decision.max_commit_time` back to 6 and `npc.movement.speed` to 150.
- **Set the target's frame before the first frame** (`Flank.target`): its `facing` and `movement:aim_point` are props,
  because a puppet's `aim_point` defaults to the origin and turns it that way until `aim_at` runs. Give targets and allies a
  huge `max_health`; the NPCs shoot while they wait.
- **Radio claims** are real `callout` events posted with `Flank.radio` from an ally puppet the NPC cannot see; an ally it
  can see holds the side it stands on by name, without "(radio)". Two or more live invaders get different
  `tuning.decision` `max_commit_time` / `tactic_interval` / `decide_interval`, else they decide on one frame and claim one
  side.
- **Route-safety rules decide which sides exist.** A route within `tuning.tactics.route_clearance` of a hostile is dropped,
  and in open ground the straight route to a rear point passes the target. Tests of other rules set `route_clearance` low
  (0 for the group tests, 40 for the ally lane) so only the rule under test acts, and say so in a comment.
- **An ally counts only if the NPC sees it** (a 110° view cone toward its target plus a 48 px bubble) or by radio: put the
  ally within 55° of the NPC's line to the target with nothing between. The lane rule also tests the NPC's route: a route
  passing between an ally and the target is dropped.
- **TTL lapse is sim time:** memory ages on `GameClock.msec()` (physics frames, `docs/leadership.md` LD1), so a callout or
  contact lapses after its ttl of test time, and not while the tree is paused (`ai/perception/clock_pauses`).
- **Flank point sampling** prefers any sampled point with a clear shot, so a "line blocked" scenario needs a barrier across
  the whole arc (a row of shelves).
