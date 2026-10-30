## Stack tests (tag `stack`)

`tests/ai/stack/stack_*_test.gd` pin down the human's place in an AI stack (E16 in `docs/tactical-entry.md`), on the Terrace house and the
back door like the entry tests. A **puppet with the invader faction** stands in for the human, and the test gives it the stack radio the way
Main does: declared with `s.squads({ "human": id })` and read with `t.world.player_stack` when the test needs a squad too (`Stack.require_human_leads(t, squad, me)`
requires that premise: the stack handed its squad, which the human leads), else in `run`:
`Stack.attach(t, id)` (`tests/_ai/stack_probe.gd`, `const Stack := preload(...)`, which loads `PlayerStack` by path and calls
`attach(character, rooms, t.world.openings)`; null before the feature exists). The stack is read through `view()` (`Stack.mine`,
`Stack.slot_point`) and the human's radio through the usual `Entry.calls(t, step, &"me")`; `Stack.walk` takes the puppet through points
(`Stack.crossing(door)` goes in through a door). A late AI joiner is held back like in `entry_ally_joins_stack` (`tuning:entry:enabled` false,
`movement:speed` 0) until the human has its slot. `stack_player_slot_von` runs the whole thing with the real Von server (`requires_von`).
`stack_ai_goes_round_player_in_slot` declares Main's match instead (`s.declared_match`, `test-setup.md`) and its human is the player's own character and
controller, given its stack through `MatchBuilder.bind_player`. The UI half is `tests/ui/stack_markers_draw_test.gd` (a fake stack with a
`view()`), the wiring `tests/general/stack_player_wiring_test.gd`.
