# Stack tests (tag `stack`)

`tests/ai/stack/stack_*_test.gd` pin the human's place in an AI stack (E16, `docs/tactical-entry.md`) on the Terrace house and
the back door, like the entry tests (`tests-entry.md`).

- A **puppet with the invader faction** stands in for the human. Give it the stack radio the way Main does: declare
  `s.squads({ "human": id })` and read `t.world.player_stack`, with `Stack.require_human_leads(t, squad, me)` requiring
  that premise; else in `run`, `Stack.attach(t, id)` (`tests/_ai/stack_probe.gd`, `const Stack`, which loads `PlayerStack`
  by path).
- Read the stack through `view()` (`Stack.mine`, `Stack.slot_point`) and the human's radio through `Entry.calls(t, step,
  &"me")`; `Stack.walk` takes the puppet through points, `Stack.crossing(door)` in through a door.
- Hold a late AI joiner back as `entry_ally_joins_stack` does (`tuning:entry:enabled` false, `movement:speed` 0) until the
  human has its slot.
- `stack_player_slot_von` runs the whole thing with real Von. `stack_ai_goes_round_player_in_slot` declares Main's match
  (`s.declared_match`, `test-setup.md`) with the player's own character and controller, given its stack through
  `MatchBuilder.bind_player`.
- The UI half is `tests/ui/stack_markers_draw_test.gd` (a fake stack with `view()`), the wiring
  `tests/general/stack_player_wiring_test.gd`.
