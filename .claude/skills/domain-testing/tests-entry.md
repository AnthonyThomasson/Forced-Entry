## Tactical entry tests (tag `entry`)

`tests/ai/entry/` pin down `docs/tactical-entry.md` (E1 to E15 here, E16 to E22 in `tests-stack.md`, the sections below and `tests-leadership.md`; each header names its behaviour): staging and
the approach, the stack's slots, the pie, the crossing, the corners, the ready barrier and the radio, the solo entry
and a joining ally, clearing, covering the doorways on and rear security. Scripted-Von tests on the Terrace house (`Maps.house(s, false)`, bare
rooms so the geometry is clean), through `tests/_ai/entry_probe.gd` (`const Entry := preload(...)`): `rules(s, door)`
(SEARCH > ENTER > that doorway, engage in a fight), `npc` (an invader that walks; a `tuning:decision:decide_interval` in its `gc` offsets its decide timer),
`target`, `guard_rules(s, picks)` (a plain order that is not ENTER: for the E9 tests, with `asked(prefix)` to check the
order was really the one scripted), the test's own
doorway frame (`BACK`, `FRONT`, `HALL_LIVING`, `KITCHEN_LIVING`, and the doorways on that a team covers once it holds the
kitchen or living room, `KITCHEN_HALL`, `LIVING_KITCHEN`, with `out`, `outward`, `lateral`, `in_funnel`, `in_room`,
`beside_door`, `corners`, `faces_through`) and the radio (`calls(t, step, id)`, `first_call_time`;
callouts carry `entry_step`; `radio_claim(c, opening, into, place, frame)`, a puppet teammate's claim, `place` its slot and side). The per-frame sampler and "it went in by entry" are `tests/_ai/entry_watch_probe.gd`
(`const EntryWatch := preload(...)`): `watch`, then `path_of`, `pos_at`, `first_stop_in_room`, `funnel_entries`,
`first_in_funnel`, `last_in_funnel`, `longest_pause_in_funnel`, `time_facing_through`, `share_facing`, and
`check_entered(t, samples, id, door)` for the E9 tests. The brain is read through `debug_entry()` and `debug_room_zones()`.

E10 to E15 are covered by `entry_clear_within_benchmark` (E10), `entry_reloads_before_crossing` (E11), `entry_stack_last_covers_rear`
(E12), `entry_short_room_two_go_in` (E13), `entry_hostile_in_view_holds_outside` (E14) and `entry_corridor_doors_not_passed` (E15), which
carry no `gap` tag (`tools/run_tests.sh --include-von --require-von entry` runs them with the others). A behaviour not built yet is
written the same way: a red test tagged `gap`, the spec in `docs/`. E15 has scripted tests of its mechanism too
(`entry_guard_secures_passed_doorway`, `entry_guard_enter_walk_secures_passed_doorway`,
`entry_guard_enter_walk_with_team_keeps_together`: one mechanism each, scripted Von). The six real-Von tests
run the whole pipeline with the **real Von server** (`requires_von`, paced in real time, so their timeouts are wall-clock):
the actors are plain `invader`s with match defaults (no switch, no timer override, only a premise such as a part-spent magazine), the world is placed so the doorway under test is the natural pick,
and each test first `require`s that the AI claimed that doorway, so a different Von choice reads in the bundle as a set-up
finding, not as the doctrine gap. Their maps: the box room (`Maps.box_room`, `Entry.BOX`) and the corridor spine
(`Entry.SPINE_A/B/C`). A `gap` test that turns green gets its tag dropped (a run fails a passing gap test until then).

- Two invaders that claim a doorway on the same frame settle their slots by instance id: the first actor declared
  gets slot 1 on a tie.
- From beside a door you can see the opposite door-wall corner through the gap, so what the pie leaves hidden is
  geometry, not a rule: assert that hidden corners are on the door's wall, not that both are.
- A defender meant to be unseen from outside has to be behind the jamb from every spot the entrant visits (stack,
  arc, the walk there), e.g. tucked against the door's wall well along from it.

**Doorway views (E18, tag `door_view`).** `tests/_ai/door_view_probe.gd` (`const View := preload(...)`) holds the test's own copy of a doorway's view (`polygon`, `in_view`: the
spec numbers `DEPTH` 450, `AVOID_RATIO` 2.0, `AVOID_SLACK` 300, `PASS_CLEAR_TIME` 60 are consts there, so a test checks the plan and not the code) and the reads on a `watch` sample
set (`first_in_view`, `time_in_view`, `longest_pause_in_view`, `axis_crossed_at`, `crossing_span`, `time_covering`), plus `wait_wall` (waits until a span has passed both on the wall clock and in sim time, pacing the sim
to real time meanwhile; the memory ages on `GameClock`, so the sim-time half is the one that ages it). The tests: `entry_route_round_door_view_outside` / `_inside`, `entry_secure_exterior_door_then_cross`, `entry_pass_far_out_secured` (real Von, gunfire heard as the premise),
`entry_cleared_room_pass_expires` (scripted, about 65 s of wall time) and `entry_route_band_as_walked` (scripted, the snapshot's wording); `navigation/avoid_map_carves_the_views` tests the map.
`entry_split_stack_criss_cross` (E19, real Von) uses the view to check a split stack: two invaders at the back door from north and south, neither walking across the view.
An invader that starts south of the back door outside its view (e.g. (990, 450)) and joins a stack on the north splits it (E19); a test that
wants a one-sided stack starts its late joiner on the stack's side (the E16 tests start `b` at (980, -70)).

## Bodies in the way (issue #53)

`tests/_ai/bump_probe.gd` (`const Bump := preload(...)`) measures "walks into" off public state only: `watch(t, who, duration, stop)` records
every frame a character steers (`movement.move_input`) within 60° of another it touches (centres under 31 px) as a bump, with whether the other was at
rest and how far it was shoved; `of_kind`, `collisions` (a head-on pair's two bumps as one collision), `describe`, `tally`, `totals`;
`pressed_watch(walker, other)` is a clock of the walker standing pressed against the other (still, centres under `PRESSED_GAP` 45 px: what `keep_off`
leaves of a walk into a body, short of a bump), called once a frame, against `PRESSED_MAX` (0.5 s). The
mechanism tests are `tests/ai/movement/npc_*` (scripted Von, a puppet teammate standing still), the scenario `tests/ai/entry/entry_team_no_bumping`
(real Von, four invaders placed as a match places its team: `s.declared_match` through `tests/_ai/house_probe.gd`). A test that a held walk re-plans reads `debug_state()["decisions"]` / `["decision_reason"]`
("way blocked"): an auto-picked level asks Von nothing (`tests/ai/entry/entry_held_walk_replans` for an entry's walk).

**A match built as Main builds one.** Every test world is staged as Main's match is (`MatchBuilder.stage`, `wait_nav` on: it waits until
the navigation maps answer with the world before an actor spawns, and Main's match waits the same way, `general/match_nav_ready_before_spawn`).
A test that wants Main's whole match declares it (`s.declared_match`, read with `t.world.match_handle`); its human may be a test actor: in
`tests/ai/stack/stack_ai_goes_round_player_in_slot` it is the player's own character and controller (no input), joined to the invaders
and handed its stack radio as a match's human is (`MatchBuilder.bind_player`). A test of Main itself runs Main whole through its public
members with `tests/_main/main_probe.gd` (`const MainProbe := preload(...)`; not a test): `open(parent, exports, player_at := ZERO)` (Main with
the children `main.tscn` gives it that `_ready` reads, `Player`, at `player_at`, and `SetupMenu`, without the Von launcher and the command
server; it opens the setup window, as a fresh launch does, or with the Engine `skip_setup` meta set while it enters the tree builds its
match at once, as a scripted restart does: `general/match_nav_ready_before_spawn`), `viewport(t)` (a `SubViewport` with a `World2D` of its own, so fresh physics and navigation maps, as each
match's), `setup_menu(main)`, `house(layout, parent)` (a `TestSetup` layout built as the match's `house`) and `close(t, node)` (puts back
what Main changed outside it); the test then starts a match with `Main.start_match(spec)` or reads `SetupMenu.current_config()`. No test
reads or writes a private member of `main.gd`.
