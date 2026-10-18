# Leadership

Each side has a squad and a leader, and the leader can order members to defend a room, to stack on a door (quietly, with a stun or with
a frag first, going in when ready or holding for the leader's go) or to ambush a door. A member with no order acts on its own, exactly
as it would without any of this. The human can choose to lead its side from the setup window; a right-click
then pauses the game and opens a menu to order the selected teammates. In a played match the human sees the slots of every stack its side
forms, ordered or its own (LD18). The tests named under each behaviour assert this document.

The pieces: `general/game_clock.gd` (the pausable clock every AI timer reads), `ai/team/squad.gd` (the squad: roster, leader, succession,
`issue` and `view`), `goal_controller.gd` (the order intake, the `ordered → order` entry rule, the progress radio), `agent_perception.gd`
(`process_order`, the live order, its end, the ambush's end on contact, `stack_room`), `agent_entry.gd` (`defend_spot`, `ambush_spot`,
`stack_slots`), the snapshot
(`snapshot_options.gd` `order_group` and `tag_rooms`, `snapshot_sections.gd` `order_text`), the decision tree's `order` node and the
planner's `confine_room`, the behaviour's `defend` and `ambush` primitives (`behavior.gd`, `combat.gd`) and its ordered stack (`entry.gd`:
the hold for go, the frag entry; the entry guard in `behavior.gd`, and the perception's `ordered_walk` and `seen_empty`), and the human's
`PlayerStack` (`ai/team/player_stack.gd`) in a held stack and as the leader a stack waits for (LD17). Main builds the squads (`main.gd` `_build_squads`, `match_spawner.gd` `bind_squad`) and, when the
human leads, the command menu and the order markers (`main.gd` `_build_command_menu`; `ui/hud/command_menu.gd`, `ui/hud/order_markers.gd`;
the setup window's "Lead the team", `ui/menus/setup_menu.gd`; `Keybinds.COMMAND`), and in every played match points the stack markers at
the human's side's squad (`main.gd` `_watch_side_stacks`, `ui/hud/stack_markers.gd`). See the `architecture` skill (interfaces 7, 10, 11,
17 and 21), the `domain-ai-*` skills, `domain-main`, `domain-general`, `domain-ui-menus` and `domain-ui-hud`.

## Behaviours

**LD1. Pausable AI clock.** Every AI ttl and timer runs on `GameClock` (General, interface 11), which counts physics frames and so stands
still while the tree is paused: the memory's ages (a contact's 4 s, a callout's 6 s, leads, under fire), the controller's stamps and force
age, the leaf age, the burst ages, the grenade replan and the debug overlays' ages and blink. A pause of any length expires nothing. Two
things stay on the wall clock because they measure real time: the Von launcher's boot timeout and the planner's per-level `ms` (Von's
latency).

On this clock a headless `--fixed-fps` run ages the memory in sim time, as a played game does in real time, so a contact lapses
after 4 s of play. Two consequences (D9): a GRENADE order keeps the hostile it was offered on while the throw runs, so the contact
lapsing on the way forces no new decision, while its death does (`docs/grenades.md` G17, tests `ai/grenade/grenade_throw_spot_round_wall`,
`ai/grenade/grenade_throw_target_killed_redecides`); and
`ai/decision/von_down_holds_steady` keeps its hostile alive through the check (its premise: a dead hostile leaves no threat, and the
quiet reload, which needs no Von, would be taken).

Tests: `ai/perception/clock_pauses` (the tree paused for 10 s of wall time: a known contact and a callout are still known on resume),
`ai/perception/memory_matches_reference` (the memory against a plain log, on the game clock), `ai/movement/npc_hold_clock_across_pause`
(a held walk's hold ends, the tree is paused longer than `HOLD_GAP` and the same hold begins again: its clock carries on).

**LD2. A Von request across a pause.** The `HTTPRequest` asking Von pauses with its NPC, and its timeout timer with it: an answer that
arrives during the pause is read on resume and adopted then, with no failure.

Tests: `ai/decision/von_request_across_pause` (real Von: paused mid-request for 10 s, the answer adopted after resume).

**LD3. Squad.** One squad per side. Its leader is the member of the highest `rank`, the first in spawn order among equals: for the invaders
that is the unit's lead (rank 2, then its sergeant, rank 1), and a defenders' crew, which carries no rank, is led by its first spawned. A
squad the human leads is led by the human. Main builds one per side under `World` after arming the characters, and hands each NPC its own
(`MatchSpawner.bind_squad`). An AI leader gives no orders: nothing in a match changes unless a leader orders.

Tests: `general/squad_leader_rule` (invaders by rank, then spawn order; defenders by the first spawned; the human when leading).

**LD4. Succession.** When the leader dies, the next in line by the same rule leads within the frame, and the squad says so on the bus:
`&"leader"` `{ faction, leader, previous }`. The orders already given stand; a later order, from the new leader, replaces them.

Tests: `general/squad_succession` (a Main-built match: the lead invader killed, the sergeant leads within a frame, one `leader` event, the
trooper keeps its order, a newer order from the sergeant replaces it).

**LD5. Order transport.** A squad posts each order its leader gives as `&"order"` `{ id, leader, faction, to, kind, ... }`, kinds
`defend_room` (`room`), `stack` (`opening`, `into`, `stack_at` or `split`, `mode`, `bang`, `wait_go`), `go` (`opening`; LD13), `ambush`
(`opening`, `room`, `beyond`; LD15) and `cancel`; a `defend_room`, `stack`, `go` or `ambush` order also carries its target point, `pos` (the
room's centre, the doorway's), for the order markers (LD12). `Squad.issue` turns a leader's request in plain terms (`{ kind, to, pos?,
room?, bang?, mode?, wait_go? }`) into one: a room key or the room under `pos`; for a stack the doorway nearest `pos` within its width, the
room on the far side of the wall plane from `pos` (an exterior door always goes into the house), and the side of the door `pos` lies on
along the wall (`stack_at`) or, for a click on the opening itself, both (`split`); its `mode` (`quiet` / `stun` / `frag`; with none, `bang`
true is a stun, else quiet) and `bang` (true for any mode but quiet), and `wait_go` (false unless asked). No `to` means every living
member but the leader; an order to a dead member is dropped (a `go` ignores `to`: D13). Range is unlimited. Only the recipients named in `to`, of the squad's side, take it: each
holds it as its live order (the memory topic `order`, permanent) until it is done, cancelled or replaced, and never on a timer. While it
holds one the snapshot fact `ordered` is true.

Tests: `ai/decision/order_transport` (`ordered` on the recipients only; still held after three times the callout ttl; a newer order
replaces it; a cancel clears it).

**LD6. The ORDER node.** An arriving order forces a decision at once, as a hit does (after a crossing or an evade, which hold every
decision). The entry rules run in the order `under_fire → combat`, `engaged → combat`, `ordered → order`, `hostile_known → combat`: an
ordered member that is shot at or fighting fights, and goes back to its order once the fight lapses; a hostile merely known does not hide
the order. The ORDER node offers one option, the order itself, built by the snapshot with the primitive it runs (`defend` for a room, an
`entry` for a stack, `ambush` for an ambush) and its params, each carrying the order's `order_id`; it is taken without asking Von. At Von's
other levels the state carries one sentence, after the goal, while the member holds an order: "Your leader ordered you to defend the
kitchen." or "Your leader ordered you to go into the kitchen by its doorway quietly." ("with a stun grenade first", "with a frag grenade
first", LD14; a held stack adds " when they give the go", LD13), or the ambush's (LD15). A member with no order reads exactly what it
read before: the same tree, the same rules, the same state text.

An order stops a walk, not a fight. From the frame it takes an order until the decision made knowing it lands (`Behavior.await_order`,
set by the controller with `_order_from`), a decision walk already in flight is restarted and its answer, when it comes, dropped, and a
walk the order replaces stops where it is, as an arrived move stands (`Behavior._walking`): a move not chosen under COMBAT (a search's
walk, an investigation's, an idle walk), an entry's approach to its slot, a defend or ambush walk to its post, a throw's walk to its throw
spot, an interaction's walk to its object. The member never walks on with what it chose before the order. A fight goes on until the new
decision lands: an engage (arrived or on its way, its peek-and-cover peeking, firing and ducking), a melee, a reload, and a move chosen
under COMBAT (an advance, a retreat, a locate: the leaf's path starts at `combat`); a member frozen there would stand in the open while
Von answers.
The rest of an entry goes on too (the pie, the crossing, the corner, the clear, the cover, the rear): one stopped there would stand in
the doorway's funnel. An evade and a committed step (a crossing, a bang's throw) are never touched. The watch stage looks and shoots
throughout.

The sentence was measured with `tools/von_probe.py` on the 38 `tools/von_scenarios` levels (all 38 pass as they stand), each with the
sentence inserted after the goal: at the combat levels, the only ones an ordered member is asked (bind, engage, flank, grenade, retreat,
tactic: 18 levels), the top pick is unchanged in 17 of 18 for the defend sentence (the one change is the flank near-tie of
`flank_free_sides`, 0.52 to 0.48, toward a side outside the house that a member defending the kitchen is never offered) and in 18 of 18 for
both stack sentences, the expected pick's probability moving by 0.02 on average (0.09 at most). At the levels an ordered member never
reaches (search, enter, investigate: the order takes the walk first) the sentence naming the kitchen pulls toward kitchen options, which
is why it is shown only while ordered. "defend" and "hold" read alike (17 of 18 either way); "defend" is the menu's word.

Tests: `ai/decision/order_node_no_von` (an order is adopted by a walk that starts at the ORDER node, every level auto, no question to
Von), `ai/decision/order_fight_then_resume` (real Von: shot at, an ordered defender fights, then goes back to its order),
`ai/decision/unordered_state_unchanged` (an unordered NPC's walk and state text match a capture taken before any of this),
`ai/entry/stack_dead_end_refused` (the members refused a slot never move more than 6 px from where the order found them),
`ai/decision/order_stops_walk` (a defender walking a search, ordered with shots landing by it, stands while the decision made with the
order waits on Von), `ai/decision/order_fight_goes_on` (a defender in a peek-and-cover fight, ordered to defend the room it fights in,
keeps moving between its spots and firing through that wait), `ai/decision/order_retreat_goes_on` (a defender falling back under fire,
ordered to defend the hall it is crossing, keeps falling back through that wait).

**LD7. Progress radio.** A member radios how its order goes as a callout with `order_id` and `order_step`: `moving` when it takes the order
up, `in_position` once it holds its defend spot or its ambush post, or is ready in its slot of a held stack (LD13), `done` when the order is
done (a stack's room cleared, by itself or by a teammate who radioed it; an ambush's first contact, LD15), `refused` when it cannot carry the order out: a room or doorway it does not know (the order is dropped as the decision walk starts, and
that walk is the member's own, not kept to the refused order's room), or a stack at a dead end with no slot left for it (LD9: the order
is kept and the member holds where it is); each step once until the next differs.
The entry steps of a stack go out as they always do. Allies leave a progress call out of what they weigh (it never replaces a member's
entry claim on their radio); the squad keeps each member's latest step for `view()` (`{ leader, members: [{ node, order, step, held }] }`,
`held` whether the order is a stack still waiting for the leader's go, LD13).
An order radioed `done` is no longer one the member holds: the view shows it with no order and the step `done`, so the order markers drop
it and the command menu offers no "Cancel order" for it. A `refused` order is still held, and drawn red.

Tests: `ai/decision/order_progress_radio` (a defender radios `in_position` in the living room, an invader `done` once it has cleared the
kitchen; each callout names its order; the squads' views show the steps), `general/squad_done_order_not_cancellable` (a member's order
radioed done is held no more and the menu offers no cancel for it; a refused one is still held), `ai/decision/order_refused_unconfined`
(a defender refuses a defend order for a room it does not know and still engages from its own room, no `confine_room` in the leaf).

**LD8. Defend a room.** Ordered to defend a room, the members share out its doorways (D2): member `n` of the order's recipients (in the
order `to` names them) takes doorway `n` (by id) of the room, the extras doubling up on the other side of the doorways in turn. Each walks
to a spot back in the room, off its doorway's axis and out of every doorway's fatal funnel, with a sight line to its doorway and low cover
on that line where there is some (`AgentEntry.defend_spot`): a guarded walk for an invader, as any of its walks, and a plain one for a
defender. There it holds, still, its gun on its doorway; a lone member of a room with several doorways takes the spot from which it sees
the most of them and turns among them. The watch stage turns it to a threat in sight and shoots, as in every primitive. A fight its own
shots begin (a hostile in its sector) is the decision's to weigh, as is one where it is shot at: in a fight Von still picks the tactic, but
only among the options inside that room (every option naming a place is tagged with its room, `tags.room`; the planner's `confine_room`
drops the engage, flank, advance, retreat and locate spots and the throw spots outside it), and `_hold_ground` and `Combat.peek_cover` keep
it inside against a contact outside the room. A live grenade (D8) sets off the evade reflex as it would anywhere, which may take the member
out of the room; once the grenade has burst it decides again, takes its order up and walks back in to its spot. "Never leaves the room" is
a rule on its fight options, not on the reflex. The order lasts until it is cancelled or replaced.

Tests: `ai/combat/defend_room_stays_inside` (real Von: an ordered defender shot at from the hall fights and never leaves the kitchen),
`ai/combat/defend_room_shares_doorways` (two members, two doorways, one each, off-axis and back from the wall, guns on them),
`ai/combat/defend_room_evade_returns` (a frag drives a defender out of the box room; after the burst it walks back in and holds).

**LD9. Stack on a door.** Ordered to stack on a doorway, the members go in by it as one stack (`docs/tactical-entry.md` E1 to E22), from
wherever in the house they are, invaders and defenders alike, whatever `entry_enabled` says (D4). The ORDER node's option is an `entry`
whose params carry the order: `opening`, `into`, `bang`, `mode`, `wait_go`, `go`, `stack_at` or `split`, `order_id`. Its claims carry it on
the radio (`order_id`, `order_bang` (a grenade first), `order_mode` (`quiet` / `stun` / `frag`), `order_hold` (held for the leader's go,
LD13), `order_go` (that go has come) and `order_side`, the side it names, 0 for a split stack; every claim also carries the `stuns` and
`frags` the member carries), and the order's rules hold for any stack that has a claim carrying an `order_id`; a stack nobody was ordered
to keeps its own (D10).
- **The side (D3, D6).** With `stack_at` (the leader's click beside the opening) every member stacks on the side of the door the click lies
  on along the wall, whichever side it comes from. On a split stack (a click on the opening) each member takes the side it begins on (it
  reaches it without crossing the doorway's view, E19), but when that side would hold two more of the stack than the other, the last to
  claim it takes the other side: the sides differ by one at most, and once they do nobody moves again.
- **The mode wins.** The stack goes in quietly, with a stun or with a frag (LD14) as ordered: no suspect-room bang (E17, `entry.gd` `begin`), no first claimer's
  mode, no late upgrade (`_maybe_upgrade`) nor the listen at the stack that waits for one, and no veto from anyone outside the order (a
  teammate's `bang_off`). An unordered member that joins an ordered stack follows the order's mode and side (D10). **D1:** ordered with a
  stun when, the stack in place, nobody in it carries one, it goes in quietly and radios `bang_off` (the order's members follow it), and
  the order is still done at `cleared_room`; the throw's own failures give the bang up as they always do.
- **Go when ready (D7).** Unless the order holds for the leader's go (LD13), the point crosses (or the thrower calls the bang) once every living recipient of the order (the order's `to`,
  `Squad.alive` through the controller's `squad`) has radioed past `claim` at the doorway, or `order_ready_cap` (60 s, Entry export) after
  the first ordered `ready` it heard or said, and for the human leader that gave the order when it holds a slot (LD17); a member the order
  does not name is waited for `entry_ready_timeout` from the moment every recipient is in its slot (LD17). A member does
  not go in alone (no second side of the pie) while another recipient is coming, and an ordered bang holds the point in its slot until
  the stack is in.
- **The way there is guarded (D4).** Before its claim goes out the ordered entry works out its slot, its side and its approach and holds
  the claim back (`Entry.held_back`), and the whole walk to the slot, leg by leg as the approach walks it (out of the room being entered and
  its doorway's view, E18), is read (`Behavior._detour_first`; at most `ROUTE_WAIT`, 2 s, waiting for the map round the views): a threshold
  into a room that is not cleared, other than the room being entered, is entered first, as a detour (E9), and with no other recipient of
  the order coming, a doorway view the walk would cross is secured first (E15; not one of the room being entered, nor one a stack already
  claims). The entry is dropped unheard, so no claim was made, and starts afresh after the detour, reading the way again. The ordered
  member's approach goes round every doorway view it can, uncapped (E18), and its walk to the slot is guarded as any walk. **The stack's
  room (D20):** once a member under the same order holds its slot (its claim radioed `ready` or `bang`), the room that stack stands in
  counts as cleared for passing (`AgentPerception.stack_room`): the members still coming walk through it to their slots and are not sent
  into it by entry. **D11:** on that walk an NPC that does not
  clear rooms by entry (`entry_enabled` off: a defender) counts a room it has stood in within `entry_pass_clear_time` (60 s) and seen no
  hostile in (`AgentPerception.seen_empty`) as clear for passing, for thresholds and views alike; any other room still gets an entry. A
  room only glimpsed through a doorway was not stood in. An invader's way is unchanged: it clears rooms by entry.
- **No room (D21).** A doorway whose stack room is a dead end holds only as many slots as its wall and open floor hold at the normal spacing (E20). A member whose place
  in the stack is past that claims no slot: the ORDER node offers it, instead of the entry, `hold_<opening>` ("hold where you are: no room
  at the doorway into the <room>"), a `hold` whose params carry `refused`, so it holds where it is and radios `refused`. The order is kept
  (still held in the squad's view, drawn red; a cancel or a new order replaces it), unlike LD7's refusal of a room it does not know, which
  drops it. A member pushed past what the room holds after it claimed (the stack grew in front of it) withdraws its claim (`abort`) and
  its next decision holds it the same way.
- **The end.** The order is done when its room is cleared (`cleared_room`, by the member or radioed by a teammate): the member radios
  `order_step` `done` and acts on its own from then (the rest of the entry, covering the doorways on, runs to its end first). The same
  order decided again (a decision forced meanwhile) leaves the running entry, or the detour in front of it, running.
- **The human.** A human leader near the ordered doorway is given a slot by its `PlayerStack` as for any stack (E16); it is a member the
  order does not name, but the stack it ordered waits for it (LD17).

Tests (all scripted, on the Terrace house's back door unless said; `tests/ai/entry/`): `order_stack_quiet_suspect_room` (ordered quiet
into a suspect kitchen: no bang mode, no bang, no stun thrown), `order_stack_stun_despite_bang_off` (a teammate radioing `bang_off`
throughout: the bang is called and a stun goes off before the crossing), `order_stack_no_stun_goes_quiet` (D1: the stuns gone, in quietly
with `bang_off`, done at the cleared kitchen), `order_stack_far_guards_thresholds` (from the living room to the kitchen's hall doorway: the
hall entered first, then the ordered entry), `order_stack_side_from_click` (D3: a click south, then north, of the opening stacks the member
there; the squad's resolution of the room, an exterior door and a split stack), `order_stack_split_even` (D6: three from the north and one
from the south stack two and two, the southerner south), `order_stack_waits_for_all` (D7: the point waits for the far recipient past the 6 s
timeout), `order_stack_defender` (D4, D11: a defender passes a corridor it has seen empty and enters a room it has not),
`order_stack_unordered_joiner_follows` (D10: a quiet claimer north follows a later stun order south), `order_stack_ends_at_cleared` (the
order done at the cleared kitchen, then Von asked again with no `ordered` fact), `stack_dead_end_refused` (D21: four ordered to stack from
a 100 x 100 dead-end closet: as many as its open floor holds claim and reach a slot; each of the others never claims, holds where it was
and shows the order refused, and still held, in the squad's view). The nine `stack_reach_*` (D4, D20: four or six invaders ordered to
stack, held for the go, on doorways of the Terrace house, the Bungalow and Garage Home and on a vestibule with no wall beside its door,
from every starting place: each ends in the slot it claimed within its walk's time, never takes the back of the stack, gives its claim
up, walks the doorway's view when a way round exists or bumps a teammate; `tests/_ai/reach_probe.gd`, `docs/tactical-entry.md` E2).

**LD10. Lead the team.** The setup window has a "Lead the team" checkbox, off by default, which applies to Start only (a played match;
Watch and Endless ignore it). It is reported as the window's `lead` and saved with the rest of its choices (`Settings.set_setup`), so the
window reopens with it as it was left. With it on, the human leads its side's squad (`Squad.setup`'s `human`), and a human invader is the
unit's lead (`rank` 2): the first NPC invader is its sergeant (1) and the rest troopers (0). The style draws are the same either way: each
character gets the style, look seed and weapon style it would get with it off. With it off, nothing changes: the human invader is ranked
last of the unit as before, the squads are led by their own rule, and neither the command menu nor the order markers are built.

Tests: `ui/setup_menu_config` (the checkbox: off by default, reported as `lead` by `current_config()` and Start, ticked again from a
remembered config), `general/lead_rank` (on: the human invader rank 2, the first NPC 1, the next 0, the same styles and look seeds; off:
the human last; `Settings.set_setup` keeps and saves `lead`).

**LD11. Command menu.** Built only when the human leads (`ui/hud/command_menu.gd`). `Keybinds.COMMAND` ("Command teammates", right
mouse by default; nothing reads the right button otherwise) pauses the whole tree and opens the menu on what is under the cursor, a
panel docked at the left of the screen (so it never covers the teammates or the doorway it is about) and a ring on the clicked point:
- a teammate's body within 28 px of the click: "Select <name>" or "Deselect <name>" (the menu stays open), and "Go into the <room>"
  while it holds a held stack that has had no go (LD16);
- else a doorway, the one nearest the click within its width: "Stack into the <room> (quiet)", "Stack into the <room> with stun" and
  "Stack into the <room> with frag", `<room>` the room the stack goes into as the squad resolves the click (`Squad.resolve`, D3: the far
  side of the wall plane from the click, an exterior door's one room), so the label and the order name the same room; the stun item is
  greyed while no recipient carries a stun (D1), the frag item while none carries a frag (D15); "Go into the <room>" and "Ambush the
  doorway from the <room>" (LD16);
- else a room: "Defend the <room>";
- and "Cancel order" while a recipient holds an order (one radioed done is held no more, LD7);
- below, the "Hold for my go" checkbox (LD16), then the teammates, each a box to tick.
The recipients are the selection, or every living teammate when nothing is selected, never the human. A left-click on a teammate's body
while the menu is open selects or deselects it too. The selection lasts until it is changed, and a dead teammate leaves it. Choosing an
order closes the menu and asks the squad for it (`order_requested` → Main → `Squad.issue`, interface 21): `{ kind: "stack", to, pos, bang, mode,
wait_go }` with `pos` the click itself (the squad works out the doorway, its side and the room, D3), `{ kind: "go", pos }`, `{ kind:
"ambush", to, pos }` (LD16), `{ kind: "defend_room", to, room }` or `{ kind: "cancel", to }` (the recipients holding an order). Escape closes the menu without an order and never reaches the "back to setup" key;
closing unpauses the tree. Space stays the player's Interact. The menu opens only while the human leads: once it is dead and someone else
leads, it stays shut. It holds no AI reference and works out no AI id: it reads its teammates through the Character API and the squad
through its `view()`.

Tests: `ui/command_menu_items` (plain dicts, a fake squad's view and a real squad's `resolve`: the items for a doorway, a room and a teammate, the stun item greyed with no
stun and offered with one, the requests for the whole squad, a selection and a ticked teammate, "Cancel order" for a selected member that
holds an order, Escape, a right-click opening it on the doorway and a left-click on a body while paused; it pauses the tree and unpauses on
close), `ui/command_menu_label_matches_order` (a real squad: by an interior doorway, on either side of the wall and on its plane, the
room the stack item names is the room of the order the squad posts), `general/command_menu_wiring` (a Main-built match with "Lead the team" on: two ticked teammates ordered to stack on the back door
with a stun claim slots there in bang mode once the menu closes), the keybind coverage test (`general/keybinds_overrides`:
every action, `COMMAND` among them, has a settings label and group).

**LD12. Order markers and the squad leaders.** Built with the command menu, only when the human leads (D5; Watch and Endless draw none),
`ui/hud/order_markers.gd`, under `World` at `DrawLayers.ABOVE`. It draws each living member's order target (a dashed line from the member to its target, the doorway's centre for a stack or an ambush or the room's
centre for a defend, as the order's `pos`; the target ringed and named with the order and the member's latest progress, "Defend · in
position", "Stack (stun) · moving", "Stack (frag, hold) · in position" (the mode, and "hold" while it waits for its go, LD13), "Ambush · in
position", red when it refused; an order that is done is no longer drawn), and a ring round each teammate selected in the open menu. It watches the squad's `view()` and the menu's
selection (`selection_changed`, empty once the menu closes), and reads the members through the Character API.

Who leads is a debug overlay, not a marker: the overlay bar's "Squad leaders" (`show_leaders`, a global row of `OverlayRegistry`, off by
default; `ui/overlays/leader_overlay.gd`, under `World` at `DrawLayers.ABOVE`), which Main builds in every match, played, Watch or Endless,
over every squad's `view()`. While it is on it draws a crown over each side's living leader, moving to the next in line when one falls.

Tests: `ui/order_markers_draw` (a fake view: one target per member with an order and none without, no marker on the leader, the selected
teammate ringed where it stands and cleared with the selection, drawn at `DrawLayers.ABOVE`), `ui/leader_overlay_draw` (the `show_leaders`
row, global and off by default; with fake views nothing while off, then a crown over each squad's leader, moved to a new leader and gone
with none; Main's `_build_leader_overlay` over two real squads, shown and hidden by the bar's toggle).

**LD13. Hold for go.** A stack order carries `wait_go` (false unless asked: it goes when ready, LD9, as before). A held stack forms, claims
its slots and radios `ready` as any stack, then holds: the point holds its slot, gun on the door, and nobody slices the pie, calls the bang,
slices a split stack's own half or crosses until its go (`entry.gd` `_held`, ahead of the bang and the pie in `_tick_stack`). Each member
ready and held radios `order_step` `in_position` (`Entry.holding_for_go`), which the markers show. Its claims carry `order_hold`, and
`order_go` once the go has come; an unordered member that joins a held ordered stack holds with it (D10). While held the order's
sentence for Von ends " when they give the go".
- **Go (D13).** `go` is an order kind of its own, `{ opening, pos }`: the squad posts it to every living member holding a held stack order
  at the doorway nearest the request's `pos`, whatever its `to` and the menu's selection, and posts nothing where no held stack waits. It
  replaces nothing: the member's perception marks its live stack order `go: true` (`process_order`) and asks for no new decision, and the
  squad's `view()` marks the released orders `go`. It is latched: given while the members still walk to their slots, the stack goes the
  moment the ready barrier (D7) is met. After it the entry runs as a go-when-ready stack of its mode (the pie for a quiet one, the bang
  for a stun or a frag). The entry latches its go (`_note_go`) from any of: its own order's `go`; a teammate under the same order whose
  claims say `order_go`; a member of the stack going in or through (D14); the order's leader dead or gone (D12); and radios it in its next
  claim.
- **The human in the stack (D14).** When the human leader holds a slot at the held doorway through its `PlayerStack`, the held stack waits
  for the human's Go: the menu's Go releases it, and so does the human stepping into the doorway (its `going_in` / `in` on the radio is a
  member crossing): the AIs follow it in by the crossing order. The human joins behind the AIs (`PlayerStack` reserves the first free slot
  once a team is stacking). `PlayerStack` leaves an ally's progress-only callout (an `order_step` with no `entry_step`) out of its radio, as
  the perception does (LD7), so an AI's `in_position` never takes that AI's claim off the human's stack.
- **No leader to say go (D12).** When the leader who gave a held order dies, the squad releases the held stacks it ordered itself (a `go`
  with `auto: true`, posted on its `died`), and an entry whose order's `leader` is dead or gone latches the go on its own: the stack goes on
  the ready barrier, or at once if it is ready.
- **The walk into the slot.** A member arrives at its slot from a point past it that stops a body's clearance (32 px) short of the next
  slot along its side a teammate claims, re-planned as claims come in (`docs/tactical-entry.md` E2, for every stack): a held stack whose
  last member claims after the one ahead of it set off (`order_stack_hold_for_go`) never has that member walk into the other's body.
- **The wording.** " when they give the go", not the plan's " and wait for my go": measured with `tools/von_probe.py` on the 38
  `tools/von_scenarios` levels as in LD6 (by the coding worker, 2026-10-16), the plan's ending flipped the combat level
  `bind_most_dangerous` (a 0.57 / 0.43 near-tie: t_1 to t_2, the expected pick at 0.49) with the quiet sentence, as did every other ending
  tried ("and wait for their go", "and wait for the go", "and wait there for their go", ", then wait for their signal", "and wait for
  their signal", "and wait at the doorway for their signal", ", then wait for your leader's signal", "and hold there until they say go", the
  sentence reordered ("stack by the kitchen doorway and go in quietly on their go", "wait by the kitchen doorway for their go, then go in
  quietly"), and ", on their go", which flipped `tactic_target_fleeing` instead). " when they give the go" keeps the combat
  top pick in 18 of 18 levels in all three modes (`bind_most_dangerous` t_1 at 0.53), the expected pick moving 0.025 / 0.024 / 0.022 on
  average (quiet / stun / frag; 0.125 / 0.086 / 0.108 at most). At the levels an ordered member never reaches the held quiet sentence pulls
  `enter_short_unsearched_over_long_unexplored` toward the kitchen's doorway and the held stun and frag sentences
  `stun_entry_quiet_unexplored` toward STUN ENTRY, as the part-1 sentences do, and the held frag sentence moves
  `investigate_outside_lead_invader_goes` to `stay` (0.51 to 0.49).

Tests (scripted, the Terrace house's back door, `tests/ai/entry/` unless said): `order_stack_hold_for_go` (three members held: ready, no
pie, bang or crossing for 15 s, each radios `in_position`; the go, then in by slot), `order_stack_go_latched` (the go posted while they
walk: they go once ready, with no second go), `order_stack_hold_human_go` (D14: the human puppet holds slot 3 through `PlayerStack`; the
stack waits 10 s, the human walks in and both AIs follow), `order_stack_hold_leader_dies` (D12: the leader killed while the stack holds,
it goes on its own), `ai/grenade/order_frag_held_then_go` (LD14: no bang call or throw while held), `general/squad_go_and_ambush` (the go's
recipients, its latch in `view()`, the leader's death posting one `go` with `auto`), `general/command_menu_wiring` (LD16). Part 1's
`order_stack_*` tests, unchanged, cover a stack that goes when ready.

**LD14. Frag entry.** The stack order's `mode` is `quiet`, `stun` or `frag` (LD5). With `frag` the stack throws a frag into the room
before the point crosses, the bang of E17 (`docs/tactical-entry.md`) with a frag:
- **The thrower** is picked as a stun's (`_thrower`, from the claims' `frags`): the second of the stack if it carries one, else the lowest
  slot that does.
- **The stack's safety (D16).** `_plan_bang` aims as for a stun, at the frag's reach, and leaves out every target whose burst would have a
  claimed slot of the stack, the thrower's own included, inside the frag's danger zone (`AgentPerception.in_grenade_zone`: a clear line
  within `danger_radius` + `evade_margin`, 370 px, the G16 zone of `docs/grenades.md`): the wall beside the door shields the stack. With no
  such target the frag is given up and the stack goes in quietly, radioing `bang_off`.
- **Frag out.** The thrower radios `bang`, steps out, throws (`Combat.begin_throw` on `FRAG_SLOT`), radios `frag_out` as the frag leaves
  its hand (as GRENADE's thrower does, G17) and walks back to its slot; every member holds its slot crouched (`Entry.holds_crouched`) and
  turned away from the door until the burst, at most `FRAG_BURST_CAP` (7 s) from the call (a stun's is 5 s). A member whose slot is out of
  the frag's zone keeps the entry when the evade reflex would fire (`Entry.expects_burst`: the frag in flight, or come down where the slot
  is out of its zone: the slot is its cover); one whose slot the frag reaches (a frag that came back to the door) evades as anywhere.
- **In on the burst.** On the burst in the room the stack is over the bang: the point crosses at once with no pie, E14's hold lifted for
  `BANG_WINDOW` (3 s).
- **No frag (D15).** The menu greys the frag items while no recipient carries a frag; a frag stack whose frag is gone by the time it is in
  goes in quietly and radios `bang_off` (its claims still say `order_mode` `frag`), and the order is still done at the cleared room (as D1).
- Only an order throws a frag at entry: the bang's grenade is a frag only for a stack under an order whose mode is frag (`_bang_kind`);
  an unordered stack and Von's STUN ENTRY throw a stun, as before.
- **The wording.** "Your leader ordered you to go into the kitchen by its doorway with a frag grenade first.": the combat top pick
  unchanged in 18 of 18 levels, the expected pick moving 0.024 on average (0.088 at most) (the coding worker, 2026-10-16, as LD6).

Tests: `ai/grenade/order_frag_entry` (two frag carriers: a frag thrown into the kitchen; at the burst no member has a clear line to it within
the zone, by the test's own rays; the point crosses on the burst, no pie), `ai/grenade/order_frag_no_frag_goes_quiet` (D15: the frags taken
before the stack is in: quiet, `bang_off`, claims saying `order_mode` frag, nothing thrown, done at the cleared kitchen),
`ai/grenade/order_frag_held_then_go` (with LD13: nothing thrown until the go, then the throw, the burst and the crossing),
`general/squad_go_and_ambush` (the mode from `mode`, else `bang`), `ui/command_menu_items` (the frag item, greyed or offered).

**LD15. Ambush a door.** An `ambush` order `{ opening, room, beyond, pos }` names a doorway and the room it is ambushed from: the room on
the side of the doorway's wall plane the leader's click lies on (D17; an exterior door: the house's room), `beyond` the room on the other
side ("" for an exterior door). The member waits in that room for whoever comes through the doorway.
- **The post (D17).** `AgentEntry.ambush_spot(opening, room, nth, count, map, space)`, beside `defend_spot`: candidates `AMBUSH_DEPTHS`
  (40 to 160 px) back from the doorway's wall and `AMBUSH_LATERALS` (30 to 260 px) along it past the jamb, inside the room's walls by
  `AMBUSH_INSET` (22 px), snapped onto the navmesh, with a sight line to the threshold and off the doorway's axis (past its jamb by
  `DEFEND_BODY`, 14 px). Ranked by how many of the doorway's lookouts see the post (the slots and pie steps of an entry into the room by
  that doorway, as laid out before they are snapped: `geometry`'s `lookouts`; hidden only when it is hidden from the 8 points
  `AMBUSH_SLACK`, 12 px, round it too, since the ambusher stops a few px off its post), then out of every doorway's fatal funnel, then low
  cover on its line to the threshold, then nearest `AMBUSH_DEPTH` (110 px, E8's `COVER_DEPTH`) back: with no hidden post, the least seen.
  Members alternate sides of the axis by their place in `to` (the side with more wall first), two on one side at least `AMBUSH_SPACING`
  (44 px) apart. A hidden post lies tucked against the door's wall well along from it; in the Terrace house only the hall / living room
  doorway (`door_150_360`, from the living room) has one, every other doorway the least-seen fallback.
- **The primitive.** `ambush` (`behavior.gd`), the ORDER node's option with `{ opening, room, spot, door_pos, order_id }`: `defend`'s walk
  to its post (guarded as any walk, `DEFEND_REACH`, `DEFEND_DRIFT`), then it holds there crouched (with `posture_enabled`), gun on the
  threshold (`Watch.ease_gaze` on `door_pos`); the watch stage fires the moment a line opens. It radios `moving`, then `in_position`, and
  asks for no decision while its order stands (on the way, the walk's commit cap).
- **The end (D18).** On first contact the perception ends the order `done` (`_end_ambush_on_contact`, every observe): a hostile in sight,
  wherever it stands, or the member under fire (hit, or a round landing by it), wherever the shots come from. Footsteps heard and callouts
  are no contact. It radios `done` and decides on its own (Von; a fight is COMBAT). It is no defend: no `confine_room` follows.
- **The wording.** "Your leader ordered you to ambush the doorway into the hall from the living room." (into `beyond` from `room`); an
  exterior door's, "Your leader ordered you to ambush the outside doorway of the kitchen from inside." (the plan's "the doorway into the
  <room> from the <room>" has no room beyond an exterior door). The combat top pick unchanged in 18 of 18 levels for both, the expected
  pick moving 0.023 / 0.026 on average (0.109 / 0.078 at most); outside combat both pull `stun_entry_quiet_unexplored` and
  `_unsearched` toward STUN ENTRY, the exterior one also `enter_short_unsearched_over_long_unexplored` toward the kitchen (the coding
  worker, 2026-10-16, as LD6).

Tests (the Terrace house's `door_150_360`, ambushed from the living room): `ai/combat/ambush_door_post` (scripted: the post off the axis,
unseen from every slot and pie step by the test's own copy of the entry geometry, crouched, gun on the threshold; a puppet steps into the
doorway, it fires, its order ends and it fights on), `ai/combat/ambush_ends_on_shot_at` (scripted, D18: an intruder's footsteps behind the
wall do not end it, gunfire landing beside it does), `ai/combat/ambush_vs_stack` (real Von, `--include-von --require-von`: an ambushing
defender against a real invader stack, posted before the first `going_in`, shoots the first of them into the funnel before any of them
fires), `general/squad_go_and_ambush` (the click side's room, the same doorway, an exterior door's kitchen), `ui/command_menu_items`,
`ui/order_markers_draw` (LD16).

**LD16. The menu's new entries.** On a doorway the command menu (LD11) offers, in this order: "Go into the <room>" while a member of the
squad's view holds a held stack there that has had no go (whoever is selected: the go goes to the doorway's holders, D13); "Stack into the
<room> (quiet)", "... with stun", "... with frag" (each grenade item greyed while no recipient carries one, its tooltip saying which);
"Ambush the doorway from the <room>" (`<room>` the room `Squad.resolve` names for an ambush at the click: its side of the wall); then
"Cancel order" as before. On a teammate that holds a held stack it offers "Go into the <room>" too, after "Select" / "Deselect". The
panel's "Hold for my go" checkbox (D19: off at first, kept across opens while the match runs) sets `wait_go` on the stack chosen. The
requests: `{ kind: "stack", to, pos, bang, mode, wait_go }` (`bang` = mode != quiet), `{ kind: "go", pos }` (the click, or the doorway's
centre for a teammate's item), `{ kind: "ambush", to, pos }`. The order markers name a stack's mode and hold and an ambush (LD12).

Tests: `ui/command_menu_items` (the frag item greyed and offered, the checkbox off by default, setting `wait_go` and still ticked on the
next open, "Go into" only on a held stack's doorway, never for a go-when-ready stack or another doorway, and its request; "Ambush the
doorway from the kitchen" at an exterior door and "... from the living room" by an interior one; the extended dicts),
`ui/order_markers_draw` ("Stack (frag, hold) · in position", "Ambush · in position", a part-1 stun stack still "Stack (stun)"),
`general/command_menu_wiring` (a Main-built match: a stun stack ordered with "Hold for my go" ticked holds, no bang call or crossing for
8 s; "Go into the kitchen" on its door; the bang, then in).

**LD17. The stack waits for its leader.** When the human leads, its `PlayerStack` is handed the squad (`MatchSpawner.bind_squad`) and its
claims carry `leader: true` while the squad's `leader()` is the human. An ordered stack waits for the leader that gave its order when the
leader holds a slot in it (`Entry._leads`: the claim says `leader` and is the order's leader's): nobody crosses, slices the pie or calls the
bang while that claim is still at `claim`, whatever the wait, until `order_ready_cap` (D7) runs out; the leader standing in its slot
(`ready`) lets the stack go. Its claim withdrawn (`abort`: its walk back to the doorway grew past `reserve_range * leave_factor`, 450 px, or it died) frees the
stack at once. An AI leader holds no `PlayerStack` and gives no orders, so only the human is waited for this way (D22).
- **The joiners' clock (D23).** A member the order does not name is waited for `entry_ready_timeout` (6 s) from the moment every living
  recipient of the order, the member itself among them, stands in its slot (`Entry._all_in_at`, `_note_all_in`), or from when the stack last
  grew if that is later: not from the point's own `ready`. A point that has stood in its slot a long while for a far recipient still gives
  an unordered joiner arriving after that recipient its full 6 s. The point's debug countdown (`ready_left`) counts from the same moment.

Tests (scripted, `tests/ai/entry/`): `order_stack_waits_for_leader` (the human leader holds a slot in the stack it ordered on the Terrace
house's back door and dawdles 20 s out of it: nobody crosses and its claim says `leader`; it steps in and they go, only after it; at a
second door it dawdles 10 s, nobody crosses, then it walks away: its withdrawn claim frees them), `order_stack_joiner_grace` (an unordered
joiner reaching its slot 2 s after the last ordered member is waited for, though the point stood in its slot 15 s).

**LD18. Rings for every stack of the human's side.** The squad reads the entry claims its members radio (the human's `PlayerStack` among
them; each current as long as the NPCs keep a callout they heard, their `callout_ttl` (6 s), which Main hands the squad, a dead speaker's
dropped) and gives every stack its side is forming, ordered or its own, in
`view()["stacks"]`: `[{ opening, into, door, slots: [{ n, point, holder, held, there, mine, side, row }] }]`, from the stack's first claim
while any member is still on its way in (`claim`, `ready`, `bang` or `going_in`). Its slots run from 1 to the last claimed, each laid where
the AI stands it with the squad's own copy of the doorway geometry (`AgentEntry.stack_slots`, `side_for`, `stack_point`: the holder's side
and place in that side's file; a free slot on the stack's side; a slot a dead end does not hold left out); `there` is its holder standing
in it (`ready` or `bang`), `mine` the human's, `row` its file (1 against the wall, 2 a step out). In every played match, whoever leads,
Main points the stack markers (`ui/hud/stack_markers.gd`, `watch_squad(squad.view)`) at the human's side's squad, and they draw each slot
as a numbered ring: dim while its holder is on the way, filled once it is there (`ALPHA_THERE_FILL`), the human's own bright, a free one
faint, both sides of a split stack and a second file, until everyone is through. A slot both the squad's view and the human's own
`PlayerStack` give is drawn once, the squad's ring with the human's flag; the human's reserved doorway is drawn from its `PlayerStack`
when the squad has no stack there (E16). Watch and Endless, with no human, draw none.

Tests: `ui/stack_markers_draw` (a fake view: every stack of the side, ordered or its own, with no human slot: dim on the way, filled once
there, free faint, each where its slot is, both sides and a second file's ring, gone once through; then the human's own bright, and the
only one; with the human's reserved doorway alone, its slots and its own highlighted, cleared when the reservation ends).

## Decisions

The cases the behaviours above cite as D1 to D23.

| # | Case | Decision | Where |
|---|---|---|---|
| D1 | Ordered with a stun, no stun in the stack | The menu greys "with stun" while no recipient carries one; a stack whose stun is gone by the time it is in goes in quietly and radios `bang_off`, and the order is still done at `cleared_room`. | LD9, LD11 |
| D2 | Where the defenders of a room stand | They share out its doorways, each on a spot back in the room, off its doorway's axis, cover preferred, gun on that doorway; extras double up in turn; a lone member takes the spot that sees the most doorways and turns among them. | LD8 |
| D3 | What a click on a doorway decides | The side of the wall plane clicked is where the stack forms (it goes into the other room); left or right of the opening along the wall is the stack's side of the door; a click on the opening is a split stack; an exterior door always goes into the house. | LD5, LD9 |
| D4 | Defenders and stack orders | An ordered stack runs whatever `entry_enabled` says. Its whole way to the slot is read before the claim goes out: a room not cleared on it is entered first, and a doorway view on it secured first when no other recipient is coming; the approach then goes round the views, uncapped. | LD9 |
| D5 | Markers | Only when the human leads, for its own squad: each member's target, the selection while paused; the leader's crown is a debug overlay ("Squad leaders") for every squad in any match. | LD12 |
| D6 | A split stack's members | Each takes the side it reaches without crossing the view, balanced so the sides differ by one at most. | LD9 |
| D7 | Go when ready | The point waits for every living recipient's `ready` (and the human leader's in the stack, D22), at most `order_ready_cap`; an unordered joiner is waited for `entry_ready_timeout` (D23). | LD9, LD17 |
| D8 | A defender and a live grenade | The evade reflex may leave the room; after the burst the member walks back in and holds. | LD8 |
| D9 | The clock and the tests | Moving to the game clock may change a test's timing; `memory_matches_reference` takes its reference "now" from the new clock (the clock source only), and any other test turned red is reported with its cause before it is changed. | LD1 |
| D10 | Unordered entries | Unchanged: Von's ENTER and STUN ENTRY, the first claimer's mode, the suspect-room bang, the `bang_off` veto, the late upgrade, the listen and the ready timeout; the order's rules apply only to a stack with a claim carrying an `order_id`, and an unordered joiner follows the order's mode and side. | LD9 |
| D11 | A defender's ordered walk across its own house | A room it has stood in and seen empty within `entry_pass_clear_time` counts as clear for passing, for thresholds and views; any other room gets an entry. | LD9 |
| D12 | A held stack whose leader can no longer say go | When the leader who gave it is dead, the squad releases it (a `go` with `auto: true`) and the entry latches its go on its own: it goes on the ready barrier, or at once if ready. | LD13 |
| D13 | Who a go goes to | Every living member holding a held stack order at that doorway, whatever the selection; it releases the order, never replaces it, and is latched until the stack is ready. | LD13, LD16 |
| D14 | The human in a held stack | The stack waits for the human's go: the menu's Go, or the human stepping into the doorway (its `going_in` / `in`); the AIs follow it in. | LD13 |
| D15 | Ordered with a frag, no frag in the stack | The menu greys "with frag" while no recipient carries one; a stack whose frag is gone by the time it is in goes in quietly and radios `bang_off`, and the order is still done at `cleared_room`. | LD14, LD16 |
| D16 | Where the frag is aimed | Only where its burst leaves every claimed slot of the stack, the thrower's own too, out of its danger zone (the wall between shields it); nowhere such: the frag is given up, quiet. | LD14 |
| D17 | Where an ambush waits | In the room on the click's side of the wall (an exterior door: the house's), at a post off the axis, back from the wall, out of the funnel, seeing the threshold and hidden from every slot and pie step of an entry by that doorway; with none hidden, the least seen. | LD15 |
| D18 | When an ambush ends | On first contact, `done`: a hostile in sight anywhere, or under fire; footsteps and callouts do not end it. The member then decides on its own. | LD15 |
| D19 | The menu's "Hold for my go" | A panel checkbox, off at first, kept across opens while the match runs; it sets `wait_go` on the stack chosen. | LD16 |
| D20 | The room an ordered stack stands in | Once a member under the order holds its slot there (`ready` or `bang`), it counts as cleared for passing: the members still coming walk through it, not into it by entry. | LD9 |
| D21 | More members than a dead end holds | Each past what its wall and open floor hold claims no slot, holds where it is and radios `refused`; the order is kept (still held, drawn red), unlike a refused unknown room, which is dropped. | LD7, LD9 |
| D22 | The human leader in a stack it ordered | The stack waits for it as for a recipient: nobody goes while its claim is at `claim`, until `order_ready_cap`; its withdrawn claim frees the stack. | LD17 |
| D23 | When an unordered joiner's wait starts | From the moment every living recipient of the order stands in its slot (or the stack last grew), not from the point's own `ready`. | LD17 |

## Numbers

| What | Value | Where |
|---|---|---|
| A defend spot: back from its doorway's wall | 60 to 150 px, best 100 | `AgentEntry.DEFEND_DEPTHS`, `DEFEND_DEPTH` |
| ... along the wall past the jamb | 30 to 100 px, best 50 | `DEFEND_LATERALS`, `DEFEND_LATERAL` |
| ... inside the room's walls by | 22 px | `DEFEND_INSET` |
| The fatal funnel: within a body of a doorway's width, nearer its wall than | 14 px, 200 px | `DEFEND_BODY`, `DEFEND_FUNNEL_DEPTH` |
| A defender walks into its spot to within, and back to it when pushed off by more than | 8 px, 24 px | `Behavior.DEFEND_REACH`, `DEFEND_DRIFT` |
| An ordered stack waits for its recipients at most (from the first ordered `ready`) | 60 s | `GoalController.order_ready_cap` |
| A room seen empty counts as clear for a defender's ordered walk for | 60 s | `GoalController.entry_pass_clear_time` |
| The command menu picks a teammate's body within | 28 px | `CommandMenu.PICK_RADIUS` |
| An ambush post: back from its doorway's wall | 40 to 160 px, best 110 | `AgentEntry.AMBUSH_DEPTHS`, `AMBUSH_DEPTH` |
| ... along the wall past the jamb | 30 to 260 px | `AMBUSH_LATERALS` |
| ... inside the room's walls by | 22 px | `AMBUSH_INSET` |
| ... hidden too from the points this far round it | 12 px | `AMBUSH_SLACK` |
| Two ambushers' posts on one side, at least | 44 px apart | `AMBUSH_SPACING` |
| A frag entry waits for its frag to go off at most (from the call) | 7 s | `Entry.FRAG_BURST_CAP` |
| A frag entry keeps every slot out of the frag's danger zone | 370 px (250 + 120) | `throw_stats().danger_radius` + `GoalController.evade_margin` |
| An ordered member waits for the map round the views before reading its way at most | 2 s | `Behavior.ROUTE_WAIT` |
| A stack's approach is given up after its own walk at walking pace plus | 20 s | `GoalController.entry_approach_time` (`Entry._approach_cap`) |
| A member stands in its slot within, and steps back in when further off than | 6 px | `Entry.SLOT_REACH` |
| A member in its slot looks for a lower slot to move up into every | 0.25 s | `Entry.MOVE_UP_EVERY` |
| ... within (1.5 x the stack's spacing) | 66 px | `Entry.MOVE_UP_REACH` (`SPOT_SPACING` 44) |
| ... by a plain walk no longer than 1.5 x the straight line plus | 32 px | `Locomotion.PASS_CLEARANCE` |
| A walk round resting bodies may end this far short, the rest walked on the plain map | 64 px | `Locomotion.LAST_LEG` |
| A walk held short of a body re-plans once the steering map shows the body this far off it, or after | 16 px, 2 s | `Locomotion.CARVED_GAP`, `CARVE_WAIT` |
| An unordered joiner is waited for, from when every recipient stands in its slot | 6 s | `GoalController.entry_ready_timeout` |
| The human's slot is withdrawn once its walk back to the doorway is longer than | 450 px (300 x 1.5) | `PlayerStack.reserve_range` x `leave_factor` |
| The squad's view keeps a member's entry claim for | 6 s | `GoalController.callout_ttl` (handed to `Squad.setup` by Main) |
| A ring whose holder stands in its slot is filled at | 0.3 alpha | `StackMarkers.ALPHA_THERE_FILL` |

## Performance

The perf guards (`tools/run_tests.sh --domain=perf`, eleven tests) with LD13 to LD18 and the stack geometry of `docs/tactical-entry.md`
E20 to E22, against the base commit (c8821b0, a clean checkout). Measured on 2026-10-17 from 13:57 to 14:07, 8 full runs of each,
alternated base then change. The machine was shared with other sessions: the 1-min load average was 3.6 to 5.9 on 12 cores, read with
`uptime` before and after every run, and no run was discarded. Means in ms per frame, avg / p95 / max:

| Guard | Base (c8821b0) | Change |
|---|---|---|
| 10v10 match | 10.77 / 14.50 / 19.81 | 10.71 / 14.43 / 19.96 |
| 5v5 match | 6.01 / 9.70 / 13.43 | 5.60 / 9.19 / 13.98 |
| NPC crowd | 4.49 / 9.72 / 16.38 | 4.63 / 10.64 / 16.09 |
| grenades in a 5v5 match | 10.15 / 15.72 / 30.13 | 10.33 / 15.76 / 33.32 |
| hit overload | 10.45 / 12.60 / 16.19 | 10.30 / 12.64 / 14.34 |
| crowd fall | 7.64 / 11.80 / 16.56 | 7.66 / 11.85 / 16.31 |
| frag and stun burst | 6.61 / 8.41 / 24.20 | 6.75 / 8.68 / 24.20 |
| gunfire | 5.50 / 8.49 / 10.91 | 5.76 / 9.47 / 14.80 |
| furniture pile moving | 0.70 / 2.02 / 2.80 | 0.71 / 2.04 / 2.64 |

The other two guards, `bake_and_path_stress` and `generate_houses_stress`, time one-shot work (a nav re-bake with its path queries, house
generation) against a budget of their own (`Perf.time_ms`), not frames: they have no avg / p95 / max to compare, so they are not in the
table. Both stayed within their budgets in every run of both trees.

**The mean frame.** It is the same in both trees, within the run-to-run spread. The 8 runs' avg, mean ± sd:

| Guard | Base | Change |
|---|---|---|
| 10v10 | 10.77 ± 0.25 | 10.71 ± 0.70 |
| grenades | 10.15 ± 0.73 | 10.33 ± 0.99 |

**The worst frame.** The grenade match's worst frame per run, in the 8 runs above:
- Change: 22.75, 44.26, 28.10, 25.92, 23.58, 63.13, 25.70, 33.12.
- Base: 57.60, 23.42, 26.25, 23.86, 25.16, 24.15, 34.34, 26.24.

Each tree went over a 33.4 ms max budget in 3 of its 8 runs:
- Base: grenades 57.60 and 34.34, and hit overload (no AI) 34.07.
- Change: grenades 44.26 and 63.13, and gunfire (no AI) 40.29.

A per-frame log of navigation bakes found none of those frames on a frame where an avoid or planning bake started, landed or was in flight.

**Against the base the change is rebased on (0e19010), the grenade match's worst frame was over budget more often before the shared escape work below.** On 2026-10-17
the change was measured again: 3 runs of `--domain=perf`, each with a 1-min load under 4 before and after. Every guard is within the
run-to-run spread of the Change column above. The grenade match's worst frame went over 33.4 ms in 2 of the 3 runs (36.85, 35.66).
Then `--id=perf/grenade_match_stress --repeat=10` was run in 5 pairs, base then change, one Godot at a time, from 23:06 to 23:23, with
the 1-min load 4.0 to 6.7 before and after each run. Per pair, the worst frame's median / its worst / the runs over 33.4 ms:

| Pair | Base (0e19010) | Change |
|---|---|---|
| 1 | 24.27 / 28.70 / 0 | 23.01 / 43.90 / 1 |
| 2 | 24.74 / 33.15 / 0 | 26.49 / 33.72 / 1 |
| 3 | 24.72 / 32.99 / 0 | 24.14 / 43.13 / 2 |
| 4 | 23.79 / 26.99 / 0 | 26.27 / 37.79 / 2 |
| 5 | 25.88 / 33.30 / 0 | 26.23 / 55.24 / 2 |

The medians of the 50 runs are the same in both trees:

| Tree | avg | p95 | max |
|---|---|---|---|
| Base | 10.13 | 15.58 | 24.48 |
| Change | 10.23 | 15.36 | 24.80 |

The tail is not the same:
- **Base:** 0 of 50 runs go over 33.4 ms (worst 33.30).
- **Change:** 8 of 50 go over (33.72 to 55.24), at least one in every pair.

**Where that frame's time goes.** A throwaway per-function timer (since removed) ran in 2 alternated pairs of 10 runs at a load of 4.6
to 6.3. Under the timer, 5 change frames and 4 base frames went over 33.4 ms.
- **Change:** 4 of its 5 are frames on which 4 to 8 NPCs are evading a grenade.
- **Base:** 2 of its 4 are such frames (6 NPCs each). One more mixes an evade plan with a decision, and one has no evade in it.

Most of such a frame is `AgentGrenades.plan`: the escape plan, `AgentThrow.escape`, with its `NavBuilder.route` calls. The timer also
read each run's three slowest frames where the plan took over 5 ms: 21 a tree, with 2 to 9 NPCs evading. On those frames:

| | Change | Base |
|---|---|---|
| `AgentGrenades.plan`, average | 16.87 ms | 13.63 ms |
| `AgentGrenades.plan`, worst | 37.81 ms | 30.26 ms |
| `NavBuilder.route` calls | 371 | 301 |
| Cost per route call | about 11.5 µs | about 11.5 µs |
| The rest of the AI tick | 3.08 ms | 3.01 ms |

`AgentThrow.escape` and the plan's search were the same code in both profiled trees, before the fix below. On the change they routed
about a quarter more spots on those frames. Which of the change's behaviours puts the NPCs where more of the candidates survive is not
traced: the fix below takes the repeated work out of every such frame, whatever the count.

**What a plan costs, and the fix (2026-10-18).** A throwaway timer inside `AgentThrow.escape` (since removed) split the plan, on the
grenade match's slowest frames:
- **Per escape** (one NPC's plan, made alone): about 2.5 ms of work that depends only on the burst (the candidates round it, about
  50 rays, 0.4 to 0.5 ms; snapping them onto the navmesh, 0.45 to 0.55 ms; judging each spot by the blast's lines, `Explosion.shields`,
  1.5 to 2.2 ms) and about 1.2 ms of routing (about 90 `NavBuilder.route` calls). The routes are a third of it, the rest the burst's.
- **Per frame:** an evade wave is 3 to 8 escapes on one frame, mostly for one grenade. On the slowest wave measured (7 NPCs, 37.7 ms
  of planning) the candidates cost 3.6 ms, the snaps 3.6 ms (1176 snaps of 412 different points), the verdicts 17.2 ms (991 of 362
  different spots) and the routes 7.7 ms (625).

So most of a wave's cost was the same burst work done once per NPC. `AgentThrow` now keeps it for the physics frame (`_shared_burst`,
`_shared_snaps`: the candidates round the burst, each candidate's navmesh spot, each spot's verdict, keyed by the burst, its kind, the
zone, the NPC's heights and the bodies the lines pass through); each NPC keeps its own ring of candidates and its own routes. Inside a
physics frame the walls, furniture and navigation map hold still for these queries, so every NPC picks the spot its own search would
(test `ai/grenade/evade_wave_spots_match_own_plan`: five defenders plan together, every plan's spot equals the plain search's for that
NPC on that frame). The same timer, 10 runs of each tree in alternated rounds of 5 (load 5.2 to 7.1), then 30 more of the change
(load 4.9 to 5.9): the worst evade wave, 8 NPCs planning on one frame, took 35.9 ms of planning before the fix and 17.4 ms after (a
26.1 ms frame); a plan made alone costs what it did. In those 30 timed runs no frame went over 33.4 ms (worst 33.25 ms, a frame with no
evade plan in it), and of each run's worst frame, 3 are evade waves (26.75, 26.11 and 23.20 ms, with 3, 8 and 5 NPCs planning), the
others burst frames with no plan in them.

**The A/B after the fix** (2026-10-18, 02:28 to 02:45 and 03:14 to 03:30): `--id=perf/grenade_match_stress --repeat=10` in 10 pairs,
base (a `git archive` of 0e19010) then change, one Godot at a time, the 1-min load 4.3 to 7.2 before and after each run but for pair 7's
change run and pair 8's base run, between which it rose to 11.4 (another worktree's work; both runs kept). No run was replaced or dropped.
Per pair, the worst frame's median / its worst / the runs over 33.4 ms:

| Pair | Base (0e19010) | Change |
|---|---|---|
| 1 | 25.86 / 32.24 / 0 | 23.66 / 30.02 / 0 |
| 2 | 27.89 / 35.57 / 2 | 24.76 / 27.97 / 0 |
| 3 | 25.85 / 32.37 / 0 | 24.89 / 30.14 / 0 |
| 4 | 23.71 / 31.56 / 0 | 24.27 / 43.84 / 1 |
| 5 | 25.70 / 28.64 / 0 | 26.82 / 59.34 / 2 |
| 6 | 24.19 / 47.76 / 1 | 25.12 / 30.19 / 0 |
| 7 | 25.01 / 39.52 / 1 | 24.18 / 32.00 / 0 |
| 8 | 23.82 / 34.14 / 1 | 24.09 / 31.18 / 0 |
| 9 | 24.79 / 33.51 / 1 | 22.87 / 25.19 / 0 |
| 10 | 26.08 / 31.04 / 0 | 24.81 / 38.41 / 1 |

The 100 runs of each tree, pooled (medians, ms):

| Tree | avg | p95 | max | Runs over 33.4 ms |
|---|---|---|---|---|
| Base | 10.04 | 15.35 | 25.33 | 6 of 100 (33.41, 33.51, 34.14, 35.57, 39.52, 47.76) |
| Change | 10.46 | 15.80 | 24.31 | 4 of 100 (33.56, 38.41, 43.84, 59.34) |

The change's worst frame is now lower than the base's in the median and goes over the budget no more often. Pairs 1 to 5 alone gave the
base 2 of 50 and the change 3, pairs 6 to 10 the base 4 and the change 1: at this load the tail is a few runs in 50 in both trees. The timed runs
put no evade wave near the budget; what the change's 43.84 and 59.34 ms frames were is not known (no timer ran in those runs).

**The perf guards after the fix** (2026-10-18, 03:13, `--domain=perf`, 1-min load 3.84 before and 3.55 after): 11 of 11 pass. The
grenade match 10.06 / 14.31 / 21.60 ms (avg / p95 / max), the frag and stun burst 6.12 / 8.12 / 24.77, the 10v10 10.83 / 14.08 / 19.44,
the 5v5 6.02 / 9.37 / 14.30. An earlier run at 03:06 also passed 11 of 11 and is not counted: the load rose from 3.87 to 6.45 during it.

**What the profile found** (2026-10-17, profiled pairs of both trees, load 3.4 to 4.7):
- **The slowest frames in the measured window are grenade evade planning, in both trees.** `AgentGrenades.plan` / `AgentThrow.escape`
  cost 3 to 10 ms per NPC per plan, and 2 to 5 NPCs plan on one frame. Measured against c8821b0, the same in both trees: 23.0 ms of evade
  planning in one frame across 5 defenders on the change, 22.9 ms (34.3 ms wall) on the base. The code was shared and unchanged when
  profiled (against 0e19010 the plan routed more spots on the change, above).
- **The stack geometry is laid before the window opens.** Each way in costs 7 to 52 ms to lay (its bands 2 to 15, the overflow 10 to 28),
  one a physics frame among every NPC (`AgentEntry.warm_geometry`). All of Garage Home's are laid by 0.22 s, well before the guards' 6 s
  warm-up ends. Once a pass finds every way in laid, `warm_geometry` stops looking until the house, a tunable or the map's shared geometry
  changes (`_warm_done_in` / `_warm_done_for`). That brought its per-tick cost from 0.10 to 0.21 ms a frame down to the profiler's floor,
  0.04 ms.
- **The room an approach enters is carved only when the way round would go into it (D4).**
  - `AgentDoorViews.walk_route` routes an approach on the uncarved views map, the one every walk shares, and asks for a map with the
    entered room's floor carved too only when that route goes into the room (test
    `ai/entry/entry_ordered_approach_keeps_out_of_entered_room`). Each avoid map is re-baked after every planning bake while approaches
    walk (furniture shoved by a blast, say), so a carved map per approach is a cost: priced on the base commit, 4 of them take the
    grenade match's avg from 9.55 to 10.19 ms and bring 40 ms worst frames, and leave the 10v10's avg as it is (10.96 and 10.85; 7
    alternated runs, load 3.3 to 6.5).
  - In the AI match guards no room-carved map is built. A match bakes 2 to 9 avoid maps against the base's 1 to 3: the extra ones are
    the single-doorway sets of `_entering_set`.
- **The AI tick's own extra cost on the 10v10 is +0.2 to 0.3 ms a frame, profiled** over 3 + 3 pairs with every approach's room
  carved (the costlier routing above). It is mostly the entry choreography and the rest of `observe`. It does not show in the unprofiled
  mean above, where the gap is within the spread.
