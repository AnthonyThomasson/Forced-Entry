# Leadership tests: following, the leash, the rally, held stacks, slots

`docs/leadership.md` LD13, LD19 to LD28, D38; `E20` to `E22` in `docs/tactical-entry.md`. Orders and the menu:
`tests-leadership.md`.

**Following and the leash (LD19 to LD28).**
- `tests/_ai/follow_probe.gd` (`const Follow`): the spec's numbers as its own consts (`FOLLOW_GAP`, `FOLLOW_RING`, `LEASH`, …),
  so a test checks the spec and not the code; the band a follower keeps (`band_p50(i)`: the `i`-th follower's place in the
  file plus `BAND_LAG`, 45 px of walking lag, at the median); a member's reads (`brain_of`, `act`, `following`,
  `walk_target`, `entry`); the radio (`raw_joins`, `raw_orders`, `calls_of`, `own_claims`, `first_call`, `clears`); and
  `chase_hall`, the leash chase's world (`ai/combat/leash_no_chase` and its contrast `leash_free_chase`, which binds no
  squad).
- The squad is the test's declared one (`s.squads` or `s.declared_match`), built and bound as a match's. A squad read that
  only answers the code's own value (`follows`, `SquadFollowConfig.leash`) is a `require` premise; the behaviour the spec
  describes is the check.
- `tests/_ai/follow_watch_probe.gd` (`const FollowWatch`): a watch of the team (`new_watch`, `tick`, `asked`: the Von
  questions of a member's walks, `gaps`, `went_through`, `percentile`, `step_up`: the human walked up beside the back door,
  the rally tests' claim).

**The rally and held stacks (LD13, D38).**
- `tests/_ai/rally_probe.gd` (`const Rally`): the human leader's held rally (`tests/ai/stack/rally_*`): `world` (the bare
  Terrace house, the human puppet and two invader NPCs, bound as Main binds them with "Lead the team" on), `rallied`,
  `menu_go(t, mode)`, `both_in`, `check_went_without_human`.
- `tests/_ai/held_fight_probe.gd` (`const HeldFight`): a stack held for its go under fire
  (`ai/entry/order_stack_hold_fights_stack_side`, `ai/stack/rally_held_fights_stack_side`): `fight` walks the defender back
  to `HIDDEN` and then takes it `OFFSTAGE`, beyond sight, since every spot of the bare house is seen through some doorway
  from where a member's fight can take it; `check_stack_side`: fired from the stack's side, never into the room nor
  `going_in`, and each member back in its slot within `SLOT_NEAR` once the fight lapsed.
- Held-walk cases: `ai/entry/order_stack_hold_walk_round_body`, `order_stack_hold_from_doorway` (the order at once, its own
  `DOORWAY` depth), `order_stack_hold_retreat_stays_stack_side` (no RETREAT spot beyond the held room, #154; the members
  familiar with the house as a premise prop), `order_stack_hold_round_teammate_from_doorway_mouth` (left standing still just
  outside the doorway, its own carve leaving a way round its teammate only through the held room: `movement.speed` held at 0
  as a premise until the steering map shows that, over a few pinned spots, checked through `NavBuilder.route`).

**Where a stack stands (E20 to E22) and every member reaching its slot.**
- `tests/_ai/slots_probe.gd` (`const Slots`) judges slots from the house's own data and the test's own geometry (rooms, wall
  plane, navmesh, carved furniture, its own copies of the other doorways' views and funnels): `frames`, `entry_geometry`
  (`AgentEntry`, loaded by path), `layout` (the slots, read only through the published rule `StackLayout.slots`), the
  spec's numbers. Beside it: `slot_rules_probe.gd` (one rule per point: `in_stack_room`, `on_navmesh`, `reachable`, …),
  `slot_faults_probe.gd` (the faults a slot, a stack or a short wall's chain breaks), `slot_capacity_probe.gd` (rule 6: what
  each way in holds). `ai/entry/stack_slots_sweep` runs them over every generated floorplan.
- `tests/_ai/reach_probe.gd` (`const Reach`) runs an ordered stack, held for the go, from given starting places and checks
  each member by its own measure: in its last-claimed slot within `SLOT_REACH`, in time (its keep-out route's walk plus slack),
  never the back of the stack nor an `abort`, never the doorway's view nor its front when a way round exists, no bump; the
  `tests/ai/entry/stack_reach_*` tests use it. `Reach.run_with_move_up` is `run` with a premise first: it fails when no member moved up, so
  `ai/entry/stack_move_up_lets_follower_in` and `stack_move_up_keeps_slot_reachable` never pass with their move-up not happening. Their kitchen,
  and `ai/entry/entry_last_leg_sealed_goes_round`'s, is `tests/_ai/pocket_kitchen_probe.gd` (`const Pocket`: `layout(s, sealed)`, a hand-laid
  kitchen at a 60 px doorway into a garage, furnished so the stack forms in the west file with a pocket behind its first three slots, and the
  places the members start from): the generated doorways, at their own width, hold no stack in a pocket like that.
- Native suites feed plain claim dicts to the stack module over `tests/_ai/stack_radio_probe.gd` (`const StackRadio`:
  `speaker`, `callout`, `claim`, `door`, `slot_at`): `tests/ai/stack_claim_suite.gd` (`StackClaim`),
  `tests/ai/door_stack_suite.gd` (`DoorStack`: same-frame ties, move-up, held and released stacks),
  `tests/ai/stack_member_suite.gd` (`StackMember`).
- Where an NPC may act: `tests/ai/perception/confinement_suite.gd` (each rule alone and combined), beside the simulation
  tests `ai/grenade/territorial_throw_from_inside` and `ai/combat/ambush_contact_leashes_follower`, and two game tests
  driving one module through the confinement's answers with no world of its own:
  `ai/decision/combat_options_within_confinement` and `ai/combat/combat_spot_within_confinement`.
