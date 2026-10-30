## Flanking tests (tag `flank`)

`tests/ai/flank/` pin down how the AI weighs and takes the sides of a target: frame geometry, route
safety, ally and radio claims, shot and cover wording, territory, and the walk itself. They are
scripted-Von tests (no server); `tools/run_tests.sh flank` runs them. What they assert is written in
`docs/flanking-behavior.md` (behaviours F, B1 to B9, C); each test header names the behaviour. A test that
asserts a behaviour the AI does not show yet is written first, left red and tagged `gap`
(`tools/run_tests.sh gap`); none are open now.

- **Realistic maps** (`tests/_ai/flank_maps.gd`, `const Maps := preload(...)`): `Maps.house(s)`,
  `Maps.spine(s)` and `Maps.warehouse(s)` lay out rooms, doorways, corridors and cover with
  `TestSetup.layout`, and expose landmark consts (doors, wall and room points). Call the map first, then
  `Flank.rules(s)`. Flank points sit 220 px from the target and snap to the navmesh, so a room-sized map
  gives some sides behind walls; choose positions from a `Flank.dump(brain)` of the situation.
- **Shared helper** `tests/_ai/flank_probe.gd` (`const Flank := preload(...)`; not a test): `rules`,
  `target`, `npc`, `ally`, `radio`, `settle`, and the reads below.
- **Observe through the controller's public reads.** `debug_zones()` lists every flank side the snapshot
  weighed *including those the planner then dropped*, with its `desc` and `tags` (`held`, `held_by`,
  `crosses`, `crosses_name`, `no_shot`, `heading`, `lane`, `clear_shot`, `cover`, `inside`,
  `route_exposed`, `ally_lane`);
  `debug_state()["decision"]["levels"]` holds what each level offered. So "dropped because X" is `zones`
  says X and `offered` lacks the id. `Flank.zones/offered/offered_sides/dump/level/side_of_act` wrap these;
  `Flank.side_of` is the test's own copy of the target-frame maths (left is the target's own left, so a
  west-facing target's left is south). With several hostiles known, `debug_zones()` mixes their sides:
  give `Flank.zones(brain, target_pos)` the target and make the NPC fight it with `Flank.prefer_target`
  (the nearest hostile is otherwise the first option and gets picked).
- **Hold the NPC and settle** (`Flank.npc` + `Flank.settle`): `movement:speed` 0 and a 0.4 s commit and tactic
  cadence, so it re-decides from a fixed spot and `settle` waits for a finished walk. A walking test holds
  the NPC until `settle`, then sets `brain.tuning.decision.max_commit_time` back to 6 and `npc.movement.speed` to 150.
- **Set the target's frame before the first frame** (`Flank.target`): its `facing` and `movement:aim_point` are
  props, because a puppet's `movement.aim_point` defaults to the origin and turns it that way until `aim_at` runs.
  Give targets and allies a huge `max_health`; the NPCs shoot while they wait.
- **Radio claims** are real `callout` events posted with `Flank.radio` from an ally puppet the NPC cannot
  see (behind a wall, or far off). An ally it can see holds the side it stands on by name, without
  "(radio)". Two or more live invaders get different `tuning.decision` `max_commit_time` / `tactic_interval` /
  `decide_interval`, otherwise they decide on the same frame and claim the same side.
- **Route-safety rules decide which sides exist.** A route within `tuning.tactics.route_clearance` of a hostile is dropped,
  and in open ground the straight route to a rear point passes the target. Tests about other rules set
  `route_clearance` low (0 for the group tests, 40 for the ally lane) so only the rule under test acts, and
  say so in a comment.
- **An ally only counts if the NPC sees it.** The NPC weighs allies by sight (a 110° view cone toward its
  target, plus a 48 px bubble) or by radio, so a test about an ally's line of fire or side must put the ally
  within 55° of the NPC's line to the target, with no wall or pillar between. An ally outside it leaves
  `allies` empty and no rule fires. The lane rule also tests the NPC's *route*: a route that passes between an
  ally and the target is dropped, so place a held-side ally off the routes the test expects to be offered.
- **TTL lapse is in sim time.** Memory ages on the game clock (`GameClock.msec()`, physics frames, `docs/leadership.md` LD1),
  so a callout or contact lapses after its ttl of test time (`t.seconds`) as in the game, and not while the tree is paused
  (`ai/perception/clock_pauses`).
- **Flank point sampling** prefers any sampled point with a clear shot, so a "line blocked" scenario needs
  a barrier across the whole arc (a row of shelves), not one piece.
