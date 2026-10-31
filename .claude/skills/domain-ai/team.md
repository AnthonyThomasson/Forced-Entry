# AI team module

`scenes/ai/team/`: the human's side of the entry radio (`PlayerStack`, interface 17) and each side's squad (`Squad`, interface 21, `docs/leadership.md`). Not a fifth AI sub-domain: two small modules beside the four. Only `MatchBuilder` builds them (for Main's match and the Testing world alike: `bind_player`, `build_squads`, `bind_squad`); the AI controllers hear them over the EventBus; the UI reads them through `view()` and the command menu's `resolve()`. Interface signatures: `architecture` interfaces 17 and 21. How NPCs carry an order out is `behavior-policy.md` and `entry-orders.md`.

Files: `player_stack.gd` (+ `player_stack_reservation.gd` leaf, `player_stack_step_up.gd` part), `squad.gd` (+ `squad_stacks.gd`, `squad_ambush.gd`, `squad_follow.gd`, `squad_roster.gd`, `attack_door.gd`), the static holders `squad_follow_config.gd` (`SquadFollowConfig`) and `squad_ambush_config.gd` (`SquadAmbushConfig`). The squad is `team-squad.md`.

All of it reuses perception's stack module (`StackClaim`, `ClaimLedger`, `DoorStack`, `StackLayout`, `StackMember`; stale-claim rule in `perception.md`) and three more perception parts, preloaded: `AgentEntry` (the doorway geometry, built with no NPC), `AgentVision.wall_hit` and `HouseRooms`.

## PlayerStack (E16, LD17, LD24)

A child of the human's character, attached by `MatchBuilder.bind_player`. It never moves the character; it only radios and draws.

- It listens to `&"callout"` through a `ClaimLedger` of its own (its side only, within `callout_range`, lapsing after `callout_ttl` on `GameClock`; the setters reach the ledger at once). When an allied team is stacking at a doorway within `reserve_range` of walking, it radios the human's claim for the first free slot (none in a dead end with no room, E20), on the team's side or, when its way would cross the doorway's view, on its own (E19), standing where the doorway's `DoorStack` settles it (E21).
- **It claims through the same chain an NPC's entry does** (`StackMember.claim` over `DoorStack.claim`; `_ask_side` weighs the side from where the human stands; `_keeps_slot` re-radios when slot or side `changed`), so `view()` lays the stack the AI stands. The claim is a full `StackClaim.encode`, with the human's fixed terms: `human: true` (no AI moves up into its slot, E2), `bang: true` / `bang_off: false` (it never holds a stack back or turns it), `stuns: 0` / `frags: 0` (it throws nothing), `leader` (true while its `squad.leader()` is the human, LD17), `own`.
- **`crossed_frame`** is restamped to `GameClock.frame()` each time the step goes from `claim` / `ready` to `going_in` / `in`, and cleared on a new reservation and on withdrawal. A human that brushed the funnel steps back out, unlike an NPC, so a held stack's go (D14) counts only a crossing begun since the order was issued. Test `ai/stack/stack_player_go_after_funnel_brush`.
- **The step is read from where the human stands** (`_step_at`: `HUMAN_SLOT_REACH`, `FUNNEL_DEPTH`, `THROUGH_DEPTH` in `StackClaim`). It withdraws on leaving, dying, nobody left stacking (no claim at a `StackClaim.STACKING` step, so an AI on its `bang` keeps the slot reserved), `go_timeout` after the AI ahead is through, or `abort` when the stack outgrows a dead end. `_withdraw` clears the `reservation` leaf.
- **A grenade call or an order's progress callout is no stack claim** (`StackClaim.keeps_claim`, LD7).
- **Its own claim (LD24).** With `own_claims` set (`MatchBuilder.build_squads` sets it through `bind_squad` on the invaders' side only, D29: a human defender leader claims nothing and rallies nobody), no allied stack forming in reach and the human leading a squad with another living member (`_leads_team`), `_look_for_team` calls `_claim_own`. Once the human has stood stepped up to a doorway for `STEP_UP_TIME` (`step_up.stepped`: on the stack side, out from the wall plane and past the jamb, within `STEP_UP_REACH`, at a doorway nobody stacks at, not `_barred`) it claims slot 1 there on the side it stands on, flagged `own` and radioed `own: true`. The squad hears that as the leader's own claim and rallies (`team-squad.md`). A reservation in an allied stack (E16), the leader's or not, is `own: false` and never rallies. An own claim is kept while nobody else stacks there, and with nobody ahead the `go_timeout` withdrawal does not fire.
- `entry.gd` has no case for a human: the barrier, the lone entrant's pie and the follow rule see one more teammate.
- `view()` feeds `StackMarkers` (`domain-ui`); its slots are `DoorStack.layout(_me())`.

## Interfaces

1 (the house's `rooms` and `openings`), 7 (what a squad reads of a character: `wardrobe.rank`, `is_dead`, `died`, the leader's `global_position` and `facing`), 9 (map queries by the follow spots and stack slots), 10 (EventBus: `&"callout"` claims, aborts and order steps in; `&"order"` and `&"leader"` out), 11 (`GameClock`), 17 (`PlayerStack`, `StackMarkers`), 21 (`Squad`, command menu, order markers, leader overlay).

## Tests

`tests/ai/stack/` (the human's claim and the rally), `tests/ai/stack_member_suite.gd` (the member's claim chain), `tests/ai/attack_door_suite.gd`, `tests/general/` (`squad_*`, `lead_rank`, `stack_player_wiring`), `tests/ai/movement/` (`follow_*`, `independent_no_squad`), `tests/ai/combat/` (`leash_*`, `defend_room_stays_inside`, `ordered_melee_off_leash`, `crew_ambush_attack_door`), `tests/ai/entry/` (`order_*`, `join_*`), and the UI's `tests/ui/` (`stack_markers_draw`, `order_markers_draw`, `command_menu_*`, `leader_overlay_draw`).
