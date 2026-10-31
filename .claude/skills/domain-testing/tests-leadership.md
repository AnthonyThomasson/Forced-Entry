# Leadership tests (tag `leadership`): orders, the squad, the menu, the ambush

The rules are `docs/leadership.md` (LD1 to LD29, each with its tests named under it); `tools/run_tests.sh leadership` runs
them, its real-Von ones (`requires_von`) with `--include-von --require-von`. Following, the leash, the rally, held stacks
and slots: `tests-leadership-follow.md`.

**Where the tests live** (spread by domain): the clock in `tests/ai/perception/clock_pauses`; the order transport, the
ORDER node, the progress radio, a refused order and what an order stops in `tests/ai/decision/` (`order_*`;
`unordered_state_unchanged` compares an unordered NPC's first walk and state text with the capture beside it); defending a
room in `tests/ai/combat/defend_room_*`; the ambush (LD15) in `tests/ai/combat/ambush_*`; the ordered stack in
`tests/ai/entry/order_stack_*` (scripted, the Terrace house's back door); the frag entry (LD14) in
`tests/ai/grenade/order_frag_*`; the squad and Main's wiring in `tests/general/` (`squad_*`, `lead_rank`,
`command_menu_wiring`); the UI in `tests/ui/` (`command_menu_*`, `order_markers_draw`, `leader_overlay_draw`,
`setup_menu_config`'s "Lead the team"). LD17's tests are `entry/order_stack_waits_for_leader` and
`order_stack_joiner_grace`; LD18's `ui/stack_markers_draw`; a dead end's refusal (D21) `entry/stack_dead_end_refused`.

A test with one squad per side declares it (`s.squads`, the human leader a puppet named by `human`; read with
`t.world.squad(faction)` and `t.world.player_stack`).

**Probes** (`tests/_ai/`, not tests; each file's header says what it holds):

- `order_probe.gd` (`const Order`): a squad built by the match's own rule (`squad`, for the two-squad cases that no setup
  declares), orders and their views (`issue`, `post`, `stack_order`, `go`, `orders`, `ambushes`), the progress radio
  (`progress`, `steps`, `ordered_claims`), `gunfire_near` (forces a decision without touching the brain), `pause_for` (holds
  the tree paused for wall time: the test clock stops with it), the back door's click points (`BACK_*`) and the spec's
  numbers as consts (`ORDER_READY_CAP`).
- `order_brain_probe.gd` (`const OrderBrain`): the brain's reads (`brain`, `ordered`, `decisions`, `primitive`, `params`,
  `levels`, `stack_point`, `stacked`).
- `order_menu_probe.gd` (`const OrderMenu`): the command menu and the order markers (`command_menu`, `items`, `choose`,
  `click`, `view_still`). `player_screen` sizes a headless root viewport to the project's window, as a real screen is (the
  grenade perf guards use it too, so the bodies a player would see are drawn); `check_dock` is the dock-side tests' run (the
  panel's rect covers neither the click nor a selected teammate), `check_clear_of_bar` the overlay-bar ones.
- Ambush (LD15, LD29): `ambush_maps.gd` (`AmbushMap`: one room over a hall, as `flank_maps.gd` lays maps), `ambush_rule_probe.gd`
  (`AmbushRule.combat_call`: a COMBAT callout placing a hostile, returning the ambush order it gave rise to, read with
  `Order.ambushes`), `ambush_posts_probe.gd` (`AmbushPosts`: where every member of an ambush order waits at every doorway
  of a house, read through the published entry geometry with no NPC; `ai/combat/ambush_posts_capture_terrace` / `_house`
  pin it to a capture of the full ranking).

The squad, menu and markers are loaded by path and read duck-typed, so a missing piece fails an assertion that names it.
