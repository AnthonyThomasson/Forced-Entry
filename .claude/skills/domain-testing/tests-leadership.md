## Leadership tests (tag `leadership`)

The rules are `docs/leadership.md` (LD1 to LD18, each with its tests named under it); `tools/run_tests.sh leadership` runs them, its
real-Von ones (`requires_von`) with `--include-von --require-von`. They are spread by domain: the clock in `tests/ai/perception/clock_pauses` (LD1 also names
`memory_matches_reference`, which is not tagged `leadership`), the order transport, ORDER node, progress radio, a refused order and what an order stops (a walk, not a fight: `order_stops_walk`, `order_fight_goes_on`, `order_retreat_goes_on`) in `tests/ai/decision/` (`order_*`, and
`unordered_state_unchanged`, which compares an unordered NPC's first walk and state text with the capture `unordered_state_unchanged.json`
beside it), defending a room in `tests/ai/combat/defend_room_*`, the ambush (LD15) in `tests/ai/combat/ambush_*` (`ambush_door_post`,
`ambush_ends_on_shot_at`, `ambush_post_cover_through_body`, and `ambush_vs_stack` with real Von), the ordered stack in `tests/ai/entry/order_stack_*` (scripted, the Terrace
house's back door; the held stack of LD13 in `order_stack_hold_for_go`, `order_stack_go_latched`, `order_stack_hold_human_go`,
`order_stack_hold_leader_dies`), the frag entry (LD14) in `tests/ai/grenade/order_frag_*` (`order_frag_entry`, `order_frag_held_then_go`,
`order_frag_no_frag_goes_quiet`), the squad and Main's wiring in `tests/general/` (`squad_leader_rule`, `squad_succession`,
`squad_done_order_not_cancellable`, `squad_go_and_ambush`, `lead_rank`, `command_menu_wiring`: also the held stack and the menu's Go) and the UI in `tests/ui/` (`command_menu_items`, `command_menu_docks_right`, `command_menu_docks_left`, `command_menu_clear_of_overlay_bar` / `_centre` / `_crowded`, `command_menu_label_matches_order`, `order_markers_draw`, `leader_overlay_draw`,
and `setup_menu_config`'s "Lead the team").
A test with one squad per side declares it (`s.squads`, the human leader a puppet named by `human`; read with `t.world.squad(faction)` and
`t.world.player_stack`). The shared helper is `tests/_ai/order_probe.gd` (`const Order := preload(...)`; not a test): `squad(t, faction,
members, leader)`, a squad built and bound by the match's own rule (`MatchBuilder.build_squads`) in `run`, for the squads no setup declares
(two squads of one side, in `general/squad_leader_rule` and `ai/decision/order_progress_radio`, each saying why in its header), `issue` / `post` / `view` /
`stack_order` (a stack the way the menu asks for it, `mode` and `wait_go`) / `go` (the leader's go, LD13) /
`member_view` / `orders` / `ambushes` (the ambush orders posted) / `names` (an order's `to`, sorted names), the radio
(`progress`, `steps` (a member's progress steps on one order), `ordered_claims`, `raw_calls`, `first_time`, `all_called`, `by_slot`), `gunfire_near` (forces a decision without touching the brain),
`pause_for(t, wall_s)` (holds the tree paused for that much wall time: the test clock stops with it) and the back door's click points (`BACK_NORTH`, `BACK_SOUTH`,
`BACK_ON`, `BACK_INSIDE_NORTH`, `back_side`), with the spec's numbers as consts (`ORDER_READY_CAP`). The brain's reads are
`tests/_ai/order_brain_probe.gd` (`const OrderBrain := preload(...)`: `brain`, `ordered`, `decisions`, `primitive`, `params`, `on_order`,
`levels`, and where its entry has it stand at the back door, `stack_point` and `stacked`). The ambush tests on one room (LD15, D17, D18:
`ambush_post_shielded_from_bang`, `ambush_primed_fires_on_line_open`, `ambush_survives_stun_entry`) lay it with
`tests/_ai/ambush_maps.gd` (`const AmbushMap := preload(...)`: `room(s)`, a room over a hall, their doorway, the front door and a wardrobe,
and its landmarks as consts, as `flank_maps.gd` does). The defenders' ambush rule's tests (`general/squad_ambush_rule`, `squad_ambush_rule_off`, LD29) post their radio calls through
`tests/_ai/ambush_rule_probe.gd` (`const AmbushRule := preload(...)`: `combat_call(t, speaker, faction, target)`, a COMBAT callout placing a
hostile, returning the ambush order it gave rise to, read with `Order.ambushes`). Where every member of an ambush order waits, at every doorway of a house, is read
by `tests/_ai/ambush_posts_probe.gd` (`const AmbushPosts := preload(...)`: `posts_of(t)`, `check_capture(t, path)`) through the published
entry geometry with no NPC (a ranking of its own, worked out as the one the NPCs on a map share), and
`ai/combat/ambush_posts_capture_terrace` / `_house` pin it to a capture of the full ranking beside each; the shared ranking itself runs in
`ai/combat/ambush_post_cover_through_body` (its own room: a bystander between a post and the low cover on its line leaves the post its
cover rank), `perf/ambush_order_stress` and the crew scenarios. The command menu and the order markers are
`tests/_ai/order_menu_probe.gd` (`const OrderMenu := preload(...)`: `command_menu`, `items`, `item`, `labels`, `choose`, `tick`, `click`,
`view_still`; `player_screen` sizes a headless root
viewport to the project's window, as a real screen is (a real window keeps its own size unless `exact`, for a premise built on the
project's size: that size is then stretched over the window, and `click` maps through the stretch; the grenade perf guards
read it too, so the bodies a player would see are drawn headless), and `check_dock` is the dock-side tests' run: the panel's rect covers neither
the click nor a selected teammate; `check_clear_of_bar` the overlay-bar ones, Debug on: with a real `OverlayToggles`, the panel
clears the bar too). The squad,
menu and markers are loaded by path and read duck-typed, so a missing piece fails an assertion that names it.
LD17's tests are `tests/ai/entry/order_stack_waits_for_leader` (the human puppet's `PlayerStack` claim says `leader`) and
`order_stack_joiner_grace`; LD18's is `tests/ui/stack_markers_draw` (a fake squad view's `stacks`); a dead end's refusal (D21) is
`tests/ai/entry/stack_dead_end_refused`.

**Following, the leash and the rally (LD19 to LD28).** The shared helper is `tests/_ai/follow_probe.gd` (`const Follow :=
preload(...)`; not a test): the spec's numbers as its own consts (`FOLLOW_GAP`, `FOLLOW_STEP`, `FOLLOW_CAUGHT_UP`, `FOLLOW_RING`, `FOLLOW_RINGS`,
`FOLLOW_STILL_TIME`, `FOLLOW_RETARGET`, `FOLLOW_ARRIVE`, `LEASH`, `LEASH_BREAK`), so a test checks the spec and not the code, and the band a follower keeps
(`band_p50(i)`: the `i`-th follower's place in the file plus `BAND_LAG`, 45 px of walking lag, at the median; `BAND_P90`); the squad
is the test's declared one (`s.squads` or `s.declared_match`, read with `t.world.squad`), built and bound as a match's; a member's reads (`brain_of`, `act`, `following`, `walk_target`, `entry`); the radio
(`raw_joins`, `raw_orders`, `calls_of`, `own_claims`, `first_call`, `clears`); and the leash
chase's world (`chase_hall`, shared by `ai/combat/leash_no_chase` and its contrast `leash_free_chase`, which binds no squad). The tests
call the squad itself (`follows`, `follow_spot`, `leader()`, `view()`) and its tunables on `SquadFollowConfig` (`leash`); a squad read
that only answers the code's own value (`follows`, `SquadFollowConfig.leash`) is a `require` premise, and the behaviour the spec describes is the check.
A watch of the team is `tests/_ai/follow_watch_probe.gd` (`const FollowWatch := preload(...)`): `new_watch`, `tick`, `watch`, `asked` (the Von
questions of a member's walks), `gaps`, `took`, `acts_of`, `went_through`, `percentile`, `off_spot_tick` and `step_up` (the
human walked up to `STEP_UP` beside the back door, the rally tests' claim).

**Where a stack stands (E20 to E22) and every member reaching its slot.** `tests/_ai/slots_probe.gd` (`const Slots := preload(...)`; not a
test) judges slots from the house's own data and the test's own geometry (rooms, wall plane, navmesh, carved furniture, its own copies of
the other doorways' views and funnels): `frames` / `frame` (a way in's door frame), `world_of`, `entry_geometry` (the AI's `AgentEntry`, loaded
by path), `layout(g, count, side)` (the slots, read only through the published rule `StackLayout.slots`, perception's
`stack/stack_layout.gd` loaded by path) and the spec's numbers (`MAX_STACK`, `ROOM_INSET`, `STACK_SPACING`, ...). The checks are three
probes beside it: one per rule for a point in `tests/_ai/slot_rules_probe.gd` (`const SlotRules := preload(...)`: `in_stack_room`,
`on_navmesh`, `reachable`, `clear_of_other_doors`, `in_other_funnel`, `in_other_view`, `clear_of_furniture`, `side_has_room`, `room_for_one`,
`in_wall_band`, `view_count`, `tail_fault`, and `ray_to_edge`, how far from a point along an axis to a rect's edge); the faults a slot, a stack or a short wall's chain breaks in `tests/_ai/slot_faults_probe.gd`
(`const SlotFaults`: `point_faults`, `stack_faults`, `short_wall_faults`, `is_short_wall`, `capacity_text`); and rule 6's ways in, the rule
a way in's slots answer to and what each holds, in `tests/_ai/slot_capacity_probe.gd` (`const SlotCapacity`: `way_kind`, `dead_end_capacity`,
`wall_capacity`, `views_capacity`, `open_floor_capacity`, `wall_spots`, `fewest_views_bar`). `tests/ai/entry/stack_slots_sweep` runs them over
every generated floorplan. Beneath them two native suites
feed plain claim dicts to the stack module, over the shared speakers and callouts of `tests/_ai/stack_radio_probe.gd` (`const StackRadio :=
preload(...)`: `speaker(suite, dead)`, freed with the suite's case, and `callout`): `tests/ai/stack_claim_suite.gd` (`StackClaim`'s codec, its
not-a-claim, step and join rules, a `ClaimLedger`) and `tests/ai/door_stack_suite.gd` (`DoorStack`'s slot rules: same-frame ties, move-up, the
human's slot, a split stack's crossing order, `released`, layout rows). Where an NPC may act has its native suite too,
`tests/ai/perception/confinement_suite.gd` (perception's `confinement` part, `domain-ai-perception`: each rule alone and combined, an option
judged at `from` else `point`, the snapshot's frozen copy), beside its simulation tests `ai/grenade/territorial_throw_from_inside` and
`ai/combat/ambush_contact_leashes_follower` and two game tests driving one module through the confinement's answers with no world of its own:
`ai/decision/combat_options_within_confinement` (the planner's COMBAT filter on hand-made snapshots, a node under the world walked over frames
with `DecisionStub`) and `ai/combat/combat_spot_within_confinement` (Combat's spot choice, with stand-ins as `ai/combat/combat_waits_for_facing`
drives it). `tests/_ai/reach_probe.gd`
(`const Reach := preload(...)`) runs an ordered stack, held for the go, from given starting places (`frame`, `click`, `run(t, f, lead, side,
starts)`, the members the keys of `starts`) and checks each member by its own measure: in the slot it last claimed within `SLOT_REACH`, in time (its keep-out route's
walk, `keep_out_route`, plus slack, timed from its last D4 detour), never the back of the stack nor an `abort` (a rise only as the other half of
a real move-up, `move_ups` / `_check_move_up`), never the doorway's view nor its front close in when a way round exists (`way_round`,
`front_crossings`), no bump; the nine `tests/ai/entry/stack_reach_*` use it.
