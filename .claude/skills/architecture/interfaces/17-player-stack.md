17. **Main / Testing (through `MatchBuilder`) → AI team: the human's place in a stack** (`scenes/ai/team/player_stack.gd`; a human invader is one
    of the stack; implementation in `domain-ai` (side file team))
    - `PlayerStack.attach(character, rooms, openings) -> Node` adds a `PlayerStack` child to the human and returns it. Its one caller is
      `MatchBuilder.bind_player` (23, beside `bind_npc`): a match's human (`populate`) and a test world's human leader (`TestSetup.squads`'
      `human`) alike.
    - `PlayerStack.view() -> Dictionary`: `{}` with no reservation, else `{ opening, door, slots: [{ n, point, mine, held }], mine, step }`
      (`n` the slot in claim order; `point` where it stands, on its holder's side of the door: both sides on a split stack, E19). The UI's
      `StackMarkers` (`ui/hud/stack_markers.gd`, `watch(stack)`, built by Main under `World` on the handle's `player_stack`) draws it and
      reads nothing else.
    - **Radio:** the human claims by entry `&"callout"`s (10), a full claim encoded by `StackClaim.encode`, and hears the allies' off the bus
      through a `ClaimLedger` of its own (`ai/perception/stack/claim_ledger.gd`: its side only, within its `callout_range`, lapsing after
      its `callout_ttl` on `GameClock`). Slot, side, point, crossing order and marker slots come from the reserved doorway's `DoorStack`
      (`ai/perception/stack/door_stack.gd`), asked with the human's own claim, a `StackMember` (`stack_member.gd`), through
      `StackMember.claim` over `DoorStack.claim`, the chain an NPC's claims take too: `view()` lays the stack as the AI stands it. The AI's
      entry code treats the human as any teammate (E16, `docs/tactical-entry.md`) except `human` (no AI moves up into its slot; it never
      moves up itself nor throws the stack's grenade) and, when it leads, `leader`.
    - `PlayerStack.squad: Node`: the human's side's squad, handed in by `MatchBuilder.bind_squad(player, squad, stack, own_claims)` with the
      stack `bind_player` returned (21, 23). Its claims say `leader: true` while `squad.leader()` is the human (`docs/leadership.md` LD17).
    - `PlayerStack.own_claims: bool` (false unless set; `MatchBuilder.build_squads` sets it through `bind_squad` on the invaders' side only,
      D29): while set, with the human leading a squad that has another living member and no allied stack forming in its reach, the human
      claims of its own (LD24). Stepping up to a doorway nobody stacks at (on its stack side against the wall beside the opening, within
      `PlayerStack.STEP_UP_REACH` of the wall plane and the jamb, for `STEP_UP_TIME`) claims slot 1, marked `own: true`, which the squad
      hears as its leader's own claim and rallies the team to (21); the claim stands while nobody else stacks there. A slot reserved in an
      allied stack (E16) is never `own` and never rallies.
    - `StackMarkers.watch_squad(view: Callable)`: Main (`_watch_side_stacks`, every played match) hands the markers the human's side's
      `Squad.view`, whose `stacks` they draw too (LD18): every stack of that side, a ring per slot, a slot both views give drawn once.
      `StackMarkers.drawn() -> Array` (test read): `[{ n, point, mine, held, there, side, row, opening }]`.
