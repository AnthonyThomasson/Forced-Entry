# AI · Perception · The stack (`scenes/ai/perception/stack/`)

A doorway's stack as the radio describes it, held once for every reader: the NPC's entry and its snapshot, the human's `PlayerStack` and the side's `Squad` (`team.md`). Behaviour, the orchestrator and the team preload these files themselves; this folder is the **stack seam**. Specs: `docs/tactical-entry.md` E2, E6, E16 to E22; `docs/leadership.md` LD13, LD18, D38.

| File | Role |
|---|---|
| `stack_claim.gd` (`StackClaim`, static) | The entry claim's wire format on the `&"callout"` radio (interface 10): `DEFAULTS` (what a claim that does not say a field has), `encode` / `decode`, `is_claim`, `keeps_claim`, `is_join` (the one test of a join, LD24), `order_terms` (the one builder of a claim's `order_*` fields), `MODES` / `throws_first`, the step lists (`STACKING`, `IN_SLOT`, `THROUGH`, ...) and their tests, `in_funnel`, `by_slot` (the one comparator claims sort by). |
| `claim_ledger.gd` (`ClaimLedger`) | The claims one listener has heard: one per listener (the perception's `entry.ledger`, `PlayerStack`'s, the `Squad`'s). Keeps each speaker's latest claim, its side only, within range; lapses on `GameClock` (LD1); a dead speaker's goes at once. `stack(opening, g)` builds a `DoorStack`, at most once a physics frame per doorway and room. |
| `door_stack.gd` (`DoorStack`) | Every slot rule over one doorway's geometry and claims, settled one way for whoever asks. Read-only: it never changes the claims it was built from. |
| `stack_layout.gd` (`StackLayout`, static) | The one place a slot becomes a point (slots, sides, files, tail, dead ends, crossing order). |
| `stack_member.gd` (`StackMember`) | One member's own claim, which it never hears on the radio, and the one way it claims, keeps and settles its slot against a `DoorStack`. The NPC's entry owns one (`state.member`), `PlayerStack` one (`reservation.member`); the snapshot's slot guess (`snapshot_options.gd` `_entry_pick`) and `PlayerStack._look_for_team` build transient ones; `orders.held_room()` asks the `DoorStack` with a plain `StackClaim.order_terms` dict. |

How callers reach it: behaviour reads `AgentPerception.entry.stack(opening, into := "") -> DoorStack` (`into` "" has no geometry and answers only what claims alone do) and preloads `StackClaim` / `DoorStack` / `StackLayout` / `StackMember`; the orchestrator preloads `StackClaim` for the radio's `post_entry_call`; the team preloads all five plus `AgentEntry` (`perception-entry.md`), `AgentVision.wall_hit` and `HouseRooms`.

## Gotchas

- **Stale claim.** The ledger keeps each speaker's latest claim whichever entry it was for, so a claim from the team's last entry through a doorway still stands while the next one forms there. A rule that reads a claim names what makes it the current entry's: its `order_id`, its `into`, or a frame since (`order_frame` / `crossed_frame`, as `released` scopes the human's crossing by the order's frame). Test any new rule against a claim left from an earlier entry through the same doorway.
- `keeps_claim`: a live-grenade call (G16) or an order step with no entry step leaves the speaker's last claim standing; any other callout drops it; `abort` / `done` replace it.
- A member asking about itself passes `me` (`StackMember.me()`, in the radio's field names), never hears its own claim.
- `slot_for` (E2): the lowest free slot. Two claims on one slot made on the same frame and side settle by distance to the slot's point, then the one spawned first (`WorldRng`); a slot claimed on that frame by someone farther is taken from them, so the settling runs down the stack. A move-up holds against a plain claim and its holder takes the freed slot (`_moved_up` rewrites a claim still on a slot a member moved up from).
- `released` (LD13) scopes the human's crossing by `since` (the order's frame) because the human's claim carries no order; a `-1` frame on either side releases nothing. `order_id` "" is the human leader's rally (`hold`, `_releases_rally`, D38).
- `held(me)`: the stack holds for a go that has not come; nobody in it slices the pie, listens, calls a bang or crosses. `mode(me)` resolves `quiet` / `stun` / `frag` (an order's mode, a rally's, else the first claimer's).
- `thrower(kind, me)` (E17, LD14): slot 2 if it carries one, else the lowest slot that does; never the human.
- `claim(me)` is the chain every member claims by: `slot_for`, `held` (`StackLayout.holds_slot`, E20), then `settle` on the side `me.want` asks for, which the member weighs and hands in as a value. A member whose slot changes is no longer moving up. `StackMember.claim` returns `changed` when the slot or side differs from before; the entry's `keep_slot` and `PlayerStack._keeps_slot` radio that as a new claim.
- `split_side` (D6, E19) balances a split stack; `order_place` (E20, LD9) gives an ordered member its slot after the order's living recipients, so a dead end's extras are known before anyone claims; `move_up_vacancies` is the rule half of the move-up (the walk and the latecomer are the entry's).
- `SLOT_REACH` (an NPC walks all the way into its slot, since a stride short of it stands on the next one) and `HUMAN_SLOT_REACH` (how near a hand-driven body counts as in its slot) are named apart.

## Tests

`tests/ai/stack_claim_suite.gd` (codec, `order_terms`, ledger), `tests/ai/door_stack_suite.gd` (slot rules, `hold` / `held` / `mode`), `tests/ai/stack_member_suite.gd` (a member's claim): `UnitSuite` over plain claim dicts, beneath the simulation tests (ADR-0002). Game tests for the human's side: `tests/ai/stack/`.
