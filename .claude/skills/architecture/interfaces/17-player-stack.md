17. **Main / Testing (through `MatchBuilder`) → AI team: the human's place in a stack** (`scenes/ai/team/player_stack.gd`; a human invader
    is one of the stack)
    - `PlayerStack.attach(character, rooms, openings) -> Node` attaches a `PlayerStack` child to the human with the house's `rooms` and
      `openings` and returns it; the match builder's `bind_player` (interface 23, beside `bind_npc`) is its one caller, for a match's human
      (`populate`) and a test world's human leader (`TestSetup.squads`' `human`) alike.
    - `PlayerStack.view() -> Dictionary` — `{}` with no reservation, else `{ opening, door, slots: [{ n, point, mine, held }], mine, step }`
      (`n` the slot, numbered in claim order; `point` where it stands, on its holder's side of the door: both sides on a split stack, E19):
      the UI's `StackMarkers` (`ui/hud/stack_markers.gd`, `watch(stack)`, built by Main under `World` on the match handle's `player_stack`) draws it on the floor and reads
      nothing else. The stack radios the human's claim as entry `&"callout"`s (interface 10), a full claim encoded by `StackClaim.encode`,
      and hears the allies' off the same bus through a `ClaimLedger` of its own (`ai/perception/stack/claim_ledger.gd`: its side only,
      within its `callout_range`, lapsing after its `callout_ttl` on `GameClock`); its slot, side, point, the crossing order and the markers'
      slots come from the reserved doorway's `DoorStack` (`ai/perception/stack/door_stack.gd`), asked with the human's own claim, a
      `StackMember` (`ai/perception/stack/stack_member.gd`), through `StackMember.claim` over `DoorStack.claim`, the chain an NPC's entry claims by too, so
      `view()` lays the stack the AI stands. The AI's entry code treats it as any teammate (E16 in `docs/tactical-entry.md`), but for `human`
      (no AI moves up into its slot, and the human never moves up itself nor throws the stack's grenade) and, when the human leads, `leader`.
    - `PlayerStack.squad: Node` — the human's side's squad, handed in by `MatchBuilder.bind_squad(player, squad, stack, own_claims)` with the stack `bind_player` returned (interfaces 21, 23); its claims say
      `leader: true` while `squad.leader()` is the human (`docs/leadership.md` LD17). `PlayerStack.own_claims: bool` (false unless set;
      `MatchBuilder.build_squads` sets it through `bind_squad` on the invaders' side only, D29): while it is set and the human leads a squad with another living
      member and no allied stack forms in its reach, it also claims of its own (LD24): stepping up to a doorway nobody stacks at (on its stack
      side against the wall beside the opening, out from the wall plane and past the jamb each within `PlayerStack.STEP_UP_REACH`, 60 px,
      for `STEP_UP_TIME`, 0.5 s) it claims slot 1 there, marked `own: true`, which the squad hears as its leader's own claim and rallies the
      team to; that claim stands while nobody else stacks there. A slot it is reserved in an allied stack (E16) is never `own` and never
      rallies.
    - `StackMarkers.watch_squad(view: Callable)` — Main (`_watch_side_stacks`, every played match) hands the markers the human's side's
      `Squad.view`, whose `stacks` they draw too (LD18): every stack of that side, a ring per slot, a slot both views give drawn once.
      `StackMarkers.drawn() -> Array` (test read) is what is shown: `[{ n, point, mine, held, there, side, row, opening }]`.
