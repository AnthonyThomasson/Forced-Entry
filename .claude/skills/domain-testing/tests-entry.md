# Tactical entry tests (tag `entry`)

`tests/ai/entry/` pins `docs/tactical-entry.md` (E1 to E15 here, E16 to E22 in `tests-stack.md` and
`tests-leadership.md`; each test header names its behaviour). `tools/run_tests.sh entry` runs them; the real-Von ones
need `--include-von --require-von`.

- **Scripted-Von tests** run on the Terrace house (`Maps.house(s, false)` in `tests/_ai/flank_maps.gd`, bare rooms so the
  geometry is clean) through `tests/_ai/entry_probe.gd` (`const Entry`): the rules that send an invader to a doorway
  (`rules`, `guard_rules` for the entry guard's E9 tests with `asked(prefix)` proving the scripted order was the one asked),
  `npc`, `target`, the test's own doorway frames (`BACK`, `FRONT`, …), and the radio reads (`calls`, `first_call_time`,
  `radio_claim`, a puppet teammate's claim). The entry at a house door (`entry_*_door_*`, E3): `tests/_ai/entry_door_probe.gd` (`const DoorPie`: the Terrace house's back doorway with a 60 px hollow door, its hinges, `slicing`). A per-frame sampler and "it went in by entry" are
  `tests/_ai/entry_watch_probe.gd` (`const EntryWatch`: `watch`, `path_of`, `check_entered`, …). The brain is read through
  `debug_entry()` and `debug_room_zones()` on the controller.
- **Real-Von tests** (`requires_von`, paced in real time, so timeouts are wall-clock) run the whole pipeline: plain
  `invader`s with match defaults (no switch, no timer override, only a premise such as a part-spent magazine), the world
  placed so the doorway under test is the natural pick. Each test first `require`s that the AI claimed that doorway, so a
  different Von choice reads in the bundle as a set-up finding, not a doctrine gap. Their maps: the box room
  (`Maps.box_room`, `Entry.BOX`) and the corridor spine (`Entry.SPINE_A/B/C`). A behaviour not built yet is a red test
  tagged `gap` with the spec in `docs/`; drop the tag when it turns green.
- E15's mechanism has scripted tests of its own (`entry_guard_*`, one mechanism each).

Gotchas:

- Two invaders that claim a doorway on the same frame settle their slots by instance id: the first actor declared gets
  slot 1 on a tie.
- From beside a door you see the opposite door-wall corner through the gap, so what the pie leaves hidden is geometry:
  assert the hidden corners are on the door's wall, not that both are.
- A defender meant to be unseen from outside must be behind the jamb from every spot the entrant visits (stack, arc, the
  walk there).

**Doorway views (E18, tag `door_view`).** `tests/_ai/door_view_probe.gd` (`const View`) keeps the test's own copy of a
doorway's view and the spec's numbers (`DEPTH`, `AVOID_RATIO`, `AVOID_SLACK`, `PASS_CLEAR_TIME`), so a test checks the
plan and not the code, plus reads on a `watch` sample set and `wait_wall` (waits a span on the wall clock and in sim time:
the memory ages on `GameClock`, so the sim half is the one that ages it). `navigation/avoid_map_carves_the_views` tests the
map. A late joiner that starts south of the back door outside its view and joins a stack on the north splits it (E19); a
test wanting a one-sided stack starts its joiner on the stack's side.

## Bodies in the way

`tests/_ai/bump_probe.gd` (`const Bump`) measures "walks into" off public state only: `watch` records every frame a
character steers within 60° of another it touches (centres under 31 px) as a bump; `pressed_watch` is a clock of the
walker standing pressed against the other (`PRESSED_GAP` 45 px, `PRESSED_MAX` 0.5 s: what `keep_off` leaves of a walk into
a body). The mechanism tests are `tests/ai/movement/npc_*` (scripted Von, a puppet teammate standing still), the scenario
is `ai/entry/entry_team_no_bumping` (real Von, four invaders placed as a match places its team through
`tests/_ai/house_probe.gd`). A test that a held walk re-plans reads `debug_state()["decisions"]` /
`["decision_reason"]` ("way blocked"): an auto-picked level asks Von nothing (`entry_held_walk_replans`).

## A match built as Main builds one

Every test world is staged as Main's match is (`MatchBuilder.stage`, `wait_nav` on: `general/match_nav_ready_before_spawn`).
A test that wants Main's whole match declares it (`s.declared_match`, read with `t.world.match_handle`); its human may be a
test actor. A test of Main itself runs Main whole through its public members with `tests/_main/main_probe.gd`
(`const MainProbe`: `open`, `viewport`, `setup_menu`, `house`, `close`), then starts a match with `Main.start_match(spec)`
or reads `SetupMenu.current_config()`. No test reads or writes a private member of `main.gd`.
