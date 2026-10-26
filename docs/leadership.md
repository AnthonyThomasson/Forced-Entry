# Leadership

Each side has a squad and a leader, and a squad is a coordinated team. Its members with no order follow their leader, AI or human: they
pick no goal of their own, keep to a file on its trail or a ring round it, fight only within a leash of it, and go in by its doorway as one
stack when it makes its own claim there (LD19 to LD26). The leader can order members to defend a room, to stack on a door (quietly, with a
stun or with a frag first, going in when ready or holding for the leader's go) or to ambush a door; a member carries its order out until
the order ends, then follows again. An NPC with no squad handed to it picks its own goals. The human can choose to lead its side from the
setup window; a right-click then pauses the game and opens a menu to order the selected teammates. In a played match the human sees the
slots of every stack its side forms, ordered or its own (LD18). A match's invader team starts in one group beside the front door (LD27), and the squad-leaders
debug overlay draws the leader, its leash, its trail and the follow spots (LD12, LD28). The tests named under each behaviour assert this
document.

The pieces: `general/game_clock.gd` (the pausable clock every AI timer reads), `ai/team/squad.gd` (the squad: roster, leader, succession,
`issue` and `view`; the leader's trail, the follow spots and the leash; the rally, the abort cancel and the takeover), `goal_controller.gd`
(the order intake, the `ordered → order` and `follows → follow` entry rules, the progress radio, the squad's follow reads, the leash it
pushes for a follower holding no order and the leash break), `agent_perception.gd` (`process_order`, the live order, its end, the ambush's end on contact, `_stack_room`, the `follows` fact),
`agent_entry.gd` (`defend_spot`, `ambush_spot`), `stack/` (`stack_layout.gd`'s `slots`, `door_stack.gd`'s `layout` and `released`), the snapshot
(`snapshot_orders.gd` `group`, `snapshot_options.gd` `tag_rooms`, `snapshot_sections.gd` `order_text`), the decision tree's `order` and `follow` nodes and
the planner's `confines` (`room` and the leash), the behaviour's `defend`, `ambush` and `follow` primitives (`behavior_orders.gd`, `combat.gd`: the leash)
and its ordered stack and joins (`entry.gd`: the hold for go, the frag entry, a join run as the member's own entry; the entry guard in
`behavior_entries.gd`, and the perception's `ordered_walk` and `_seen_empty`), and the human's `PlayerStack` (`ai/team/player_stack.gd`) in a held
stack, as the leader a stack waits for (LD17) and as the leader's own claim (LD24). The match builder (`match_builder.gd`, `MatchBuilder`,
for Main's match and the Testing world alike) builds the squads and the squad-leaders overlay (`squads_over`: `build_squads`,
`bind_squad`, `build_leader_overlay`) and places the invader team in one group (`match_spawner.gd` `spawn_invader_team`, LD27); Main builds, when the
human leads, the command menu and the order markers (`main.gd` `_build_command_menu`; `ui/hud/command_menu.gd`, `ui/hud/order_markers.gd`;
the setup window's "Lead the team", `ui/menus/setup_menu.gd`; `Keybinds.COMMAND`), and in every played match points the stack markers at
the human's side's squad (`main.gd` `_watch_side_stacks`, `ui/hud/stack_markers.gd`); the squad-leaders overlay is
`ui/overlays/leader_overlay.gd`. See the `architecture` skill (interfaces 1, 7, 10, 11, 17 and 21), the `domain-ai-*` skills, `domain-main`,
`domain-general`, `domain-ui-menus`, `domain-ui-hud` and `domain-ui-overlays`. The real-world practice the following rules were weighed
against is `docs/research/squad-following.md` (where the game differs from it: "Doctrine", after LD28).

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
squad the human leads is led by the human. The match builder builds one per side after arming the characters (`MatchBuilder.build_squads`:
under `World` in Main's match, under a test world that declares a match or its squads), and hands each NPC its own
(`MatchBuilder.bind_squad`). Every squad coordinates, with no switch: its members with no order follow the leader (LD19 to LD23), and the
leader's own claim at a doorway brings them in with it (LD24). An AI leader decides through Von as any NPC does, fights and enters like
any member and takes whatever slot its stack gives it; the only orders given in its name are the squad's own (a join, LD24; the cancels of
LD25 and LD26), never one of the human's kinds. An NPC with no squad handed to its controller is no follower and picks its own goals.

Tests: `general/squad_leader_rule` (invaders by rank, then spawn order; defenders by the first spawned; the human when leading).

**LD4. Succession.** When the leader dies, the next in line by the same rule leads within the frame, and the squad says so on the bus:
`&"leader"` `{ faction, leader, previous }`. The orders already given stand (but for the dead human leader's defends and ambushes, LD26); a
later order, from the new leader, replaces them. The followers re-centre on the new leader, which stops following (LD19).

Tests: `general/squad_succession` (a match built as Main builds one, `s.declared_match` on the bare Terrace house: the lead invader killed, the sergeant leads within a frame, one `leader` event, the
trooper keeps its order, a newer order from the sergeant replaces it).

**LD5. Order transport.** A squad posts each order its leader gives as `&"order"` `{ id, leader, faction, to, kind, ... }`, kinds
`defend_room` (`room`), `stack` (`opening`, `into`, `stack_at` or `split`, `mode`, `bang`, `wait_go`), `go` (`opening`; LD13), `ambush`
(`opening`, `room`, `beyond`; LD15) and `cancel`; a `defend_room`, `stack`, `go` or `ambush` order also carries its target point, `pos` (the
room's centre, the doorway's), for the order markers (LD12). Every order carries the `GameClock` frame it was issued on, `frame` (D14).
`Squad.issue` turns a leader's request in plain terms (`{ kind, to, pos?,
room?, bang?, mode?, wait_go? }`) into one: a room key or the room under `pos`; for a stack the doorway nearest `pos` within its width, the
room on the far side of the wall plane from `pos` (an exterior door always goes into the house), and the side of the door `pos` lies on
along the wall (`stack_at`) or, for a click on the opening itself, both (`split`); its `mode` (`quiet` / `stun` / `frag`, `Squad.MODES`;
a request naming none of them reads it from `bang`: true is a stun, else quiet) and `bang` (true for any mode but `quiet`), and `wait_go`
(false unless asked). The one other mode is `join` (`Squad.JOIN`, not one of `MODES`): the squad's own rally posts it (LD24), no request
names it and the command menu never offers it. No `to` means every living
member but the leader; an order to a dead member is dropped (a `go` ignores `to`: D13). Range is unlimited. Only the recipients named in `to`, of the squad's side, take it: each
holds it as its live order (the memory topic `order`, permanent) until it is done, cancelled or replaced, and never on a timer. While it
holds one the snapshot fact `ordered` is true.

Tests: `ai/decision/order_transport` (`ordered` on the recipients only; still held after three times the callout ttl; a newer order
replaces it; a cancel clears it).

**LD6. The ORDER node.** An arriving order forces a decision at once, as a hit does (after a crossing or an evade, which hold every
decision). The entry rules run in the order `under_fire → combat`, `engaged → combat`, `ordered → order`, `hostile_known → combat` (and,
for a follower, `follows → follow` last, LD20): an ordered member that is shot at or fighting fights, and goes back to its order once the
fight lapses; a hostile merely known does not hide the order. The ORDER node offers one option, the order itself, built by the snapshot with the primitive it runs (`defend` for a room, an
`entry` for a stack, `ambush` for an ambush) and its params, each carrying the order's `order_id`; it is taken without asking Von. At Von's
other levels the state carries one sentence, after the goal, while the member holds an order: "Your leader ordered you to defend the
kitchen." or "Your leader ordered you to go into the kitchen by its doorway quietly." ("with a stun grenade first", "with a frag grenade
first", LD14; a held stack adds " when they give the go", LD13), the ambush's (LD15), or a join's, "Your leader ordered you to go into
the kitchen by its doorway with them." (LD24). A member with no order reads no such sentence: the same state text as an NPC outside any
squad.

An order stops a walk, not a fight. From the frame it takes an order until the decision made knowing it lands (`Behavior.orders.await_next`,
set by the controller as its cadence's `order_from` is), a decision walk already in flight is restarted and its answer, when it comes, dropped, and a
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
it and the command menu offers no "Cancel order" for it. A `refused` order is still held, and drawn red; a join radioed `refused` is not
(the member follows again, LD25).

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
only among the options inside that room (every option naming a place is tagged with its room, `tags.room`; the planner's `confines.room`
drops the engage, flank, advance, retreat and locate spots and the throw spots outside it), and `fight.hold_ground` and `Combat.peek_cover` keep
it inside against a contact outside the room. A live grenade (D8) sets off the evade reflex as it would anywhere, which may take the member
out of the room; once the grenade has burst it decides again, takes its order up and walks back in to its spot. "Never leaves the room" is
a rule on its fight options, not on the reflex. The order lasts until it is cancelled or replaced.

Tests: `ai/combat/defend_room_stays_inside` (real Von: an ordered defender shot at from the hall fights and never leaves the kitchen; its
squad bound, `s.squads`, its leader left in the hall about 510 px off, beyond the leash, which binds no ordered member, LD23),
`ai/combat/defend_room_shares_doorways` (two members, two doorways, one each, off-axis and back from the wall, guns on them),
`ai/combat/defend_room_evade_returns` (a frag drives a defender out of the box room; after the burst it walks back in and holds).

**LD9. Stack on a door.** Ordered to stack on a doorway, the members go in by it as one stack (`docs/tactical-entry.md` E1 to E22), from
wherever in the house they are, invaders and defenders alike, whatever `tuning.entry.enabled` says (D4). The ORDER node's option is an `entry`
whose params carry the order: `opening`, `into`, `bang`, `mode`, `wait_go`, `go`, `stack_at` or `split`, `order_id`. Its claims carry it on
the radio (`order_id`, `order_bang` (a grenade first), `order_mode` (`quiet` / `stun` / `frag`), `order_hold` (held for the leader's go,
LD13), `order_go` (that go has come), `order_side`, the side it names, 0 for a split stack, and `order_frame`, the order's `frame`; every
claim also carries the `stuns` and `frags` the member carries, and `crossed_frame`, the frame its crossing began on, -1 before it), and the order's rules hold for any stack that has a claim carrying an `order_id`; a stack nobody was ordered
to keeps its own (D10).
- **The side (D3, D6).** With `stack_at` (the leader's click beside the opening) every member stacks on the side of the door the click lies
  on along the wall, whichever side it comes from. On a split stack (a click on the opening) each member takes the side it begins on (it
  reaches it without crossing the doorway's view, E19), but when that side would hold two more of the stack than the other, the last to
  claim it takes the other side: the sides differ by one at most, and once they do nobody moves again.
- **The mode wins.** The stack goes in quietly, with a stun or with a frag (LD14) as ordered: no suspect-room bang (E17, `entry.gd` `begin`), no first claimer's
  mode, no late upgrade (`listen.maybe_upgrade`) nor the listen at the stack that waits for one, and no veto from anyone outside the order (a
  teammate's `bang_off`). An unordered member that joins an ordered stack follows the order's mode and side (D10). **D1:** ordered with a
  stun when, the stack in place, nobody in it carries one, it goes in quietly and radios `bang_off` (the order's members follow it), and
  the order is still done at `cleared_room`; the throw's own failures give the bang up as they always do.
- **Go when ready (D7).** Unless the order holds for the leader's go (LD13), the point crosses (or the thrower calls the bang) once every living recipient of the order (the order's `to`,
  `Squad.alive` through the controller's `squad`) has radioed past `claim` at the doorway, or `tuning.entry.order_ready_cap` (60 s) after
  the first ordered `ready` it heard or said, and for the human leader that gave the order when it holds a slot (LD17); a member the order
  does not name is waited for `tuning.entry.ready_timeout` from the moment every recipient is in its slot (LD17). A member does
  not go in alone (no second side of the pie) while another recipient is coming, and an ordered bang holds the point in its slot until
  the stack is in.
- **The way there is guarded (D4).** Before its claim goes out the ordered entry works out its slot, its side and its approach and holds
  the claim back (`Entry.state.held_back`), and the whole walk to the slot, leg by leg as the approach walks it (out of the room being entered and
  its doorway's view, E18), is read (`Behavior.entries._detour_first`; at most `ROUTE_WAIT`, 2 s, waiting for the map round the views): a threshold
  into a room that is not cleared, other than the room being entered, is entered first, as a detour (E9), and with no other recipient of
  the order coming, a doorway view the walk would cross is secured first (E15; not one of the room being entered, nor one a stack already
  claims). The entry is dropped unheard, so no claim was made, and starts afresh after the detour, reading the way again. The ordered
  member's approach goes round every doorway view it can, uncapped (E18), and its walk to the slot is guarded as any walk. **The stack's
  room (D20):** once a member under the same order holds its slot (its claim radioed `ready` or `bang`), the room that stack stands in
  counts as cleared for passing (`AgentPerception._stack_room`): the members still coming walk through it to their slots and are not sent
  into it by entry. **D11:** on that walk an NPC that does not
  clear rooms by entry (`tuning.entry.enabled` off: a defender) counts a room it has stood in within `tuning.entry_guard.pass_clear_time` (60 s) and seen no
  hostile in (`AgentPerception._seen_empty`) as clear for passing, for thresholds and views alike; any other room still gets an entry. A
  room only glimpsed through a doorway was not stood in. An invader's way is unchanged: it clears rooms by entry.
- **No room (D21).** A doorway whose stack room is a dead end holds only as many slots as its wall and open floor hold at the normal spacing (E20). A member whose place
  in the stack is past that claims no slot: the ORDER node offers it, instead of the entry, `hold_<opening>` ("hold where you are: no room
  at the doorway into the <room>"), a `hold` whose params carry `refused`, so it holds where it is and radios `refused`. The order is kept
  (still held in the squad's view, drawn red; a cancel or a new order replaces it), unlike LD7's refusal of a room it does not know, which
  drops it. A member pushed past what the room holds after it claimed (the stack grew in front of it) withdraws its claim (`abort`) and
  its next decision holds it the same way.
- **The end.** The order is done when its room is cleared (`cleared_room`, by the member or radioed by a teammate): the member radios
  `order_step` `done` and, once the rest of the entry (covering the doorways on) has run to its end, follows its leader (LD20; the leader
  itself, or an NPC with no squad, decides on its own). The same
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
window reopens with it as it was left. With it on, the human leads its side's squad (the `human` of `Squad.setup`'s `SquadRoster`), and a human invader is the
unit's lead (`rank` 2): the first NPC invader is its sergeant (1) and the rest troopers (0). The style draws are the same either way: each
character gets the style, look seed and weapon style it would get with it off. With it off, nothing changes: the human invader is ranked
last of the unit as before, the squads are led by their own rule, and neither the command menu nor the order markers are built.

Tests: `ui/setup_menu_config` (the checkbox: off by default, reported as `lead` by `current_config()` and Start, ticked again from a
remembered config), `general/lead_rank` (on: the human invader rank 2, the first NPC 1, the next 0, the same styles and look seeds; off:
the human last; `Settings.set_setup` keeps and saves `lead`).

**LD11. Command menu.** Built only when the human leads (`ui/hud/command_menu.gd`). `Keybinds.COMMAND` ("Command teammates", right
mouse by default; nothing reads the right button otherwise) pauses the whole tree and opens the menu on what is under the cursor, a
panel docked on the side of the screen away from the click (on the left, or on the right when the click lies in the left half, so it
never covers the teammates or the doorway it is about) and a ring on the clicked point. Docked on the left, its top is 120 px down (below
the match timer), 24 px in from the edge. Docked on the right, its right edge sits `right_clear` + 24 px from the screen's right edge
(`CommandMenu.setup`'s `right_clear`: with Debug on, Main hands it the overlay toggle bar's fixed column, `OverlayToggles.RESERVED_WIDTH`,
as the inspector's outfit panel keeps clear of it; else 0): the bar's fixed column, not where it has been dragged or collapsed to.
There, where its top at 120 px would cover the click or a selected teammate's body (within 24 px: a click near the centre on a narrow
window), it docks at the top or the bottom of the screen instead (24 px from it, over the paused match timer at the top), the side away
from the centre of the click and those bodies first: the first dock that covers none of them, else the first that leaves the click clear,
else that side away. The click and the bar are kept clear in every case the screen allows; a selected body may be covered only when every
dock on the right covers one (a crowded selection spread over the middle of the screen: the panel is about 520 x 524 px on the 1152 x 648
window). The dock is worked out again whenever the selection changes while the menu is open:
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
room the stack item names is the room of the order the squad posts), `ui/command_menu_docks_left` and `ui/command_menu_docks_right`
(on a player's screen: a click in the right half, on a teammate's body, docks the panel on the left, and a click in the left half, on the
back doorway, docks it on the right, each clear of the click and of the selected bodies), `ui/command_menu_clear_of_overlay_bar`,
`ui/command_menu_clear_of_overlay_bar_centre` and `ui/command_menu_clear_of_overlay_bar_crowded` (Debug on, a real overlay toggle bar, a
click in the left half: docked on the right `right_clear` + 24 px in, beside the click and the bodies when they leave it room, else above or
below them, and with a body in the middle of the screen at the top, away from them; clear of the bar and the click every time, and of the
bodies but in the crowded case), `general/command_menu_wiring` (a Main-built match with "Lead the team" on: two ticked teammates ordered to stack on the back door
with a stun claim slots there in bang mode once the menu closes), the keybind coverage test (`general/keybinds_overrides`:
every action, `COMMAND` among them, has a settings label and group).

**LD12. Order markers and the squad leaders.** Built with the command menu, only when the human leads (D5; Watch and Endless draw none),
`ui/hud/order_markers.gd`, under `World` at `DrawLayers.ABOVE`. It draws each living member's order target (a dashed line from the member to its target, the doorway's centre for a stack or an ambush or the room's
centre for a defend, as the order's `pos`; the target ringed and named with the order and the member's latest progress, "Defend · in
position", "Stack (stun) · moving", "Stack (frag, hold) · in position" (the mode, and "hold" while it waits for its go, LD13), "Ambush · in
position", red when it refused; an order that is done is no longer drawn), and a ring round each teammate selected in the open menu. It watches the squad's `view()` and the menu's
selection (`selection_changed`, empty once the menu closes), and reads the members through the Character API.

Who leads is a debug overlay, not a marker: the overlay bar's "Squad leaders" (`show_leaders`, a global row of `OverlayRegistry`, off by
default; `ui/overlays/leader_overlay.gd`, under `World` at `DrawLayers.ABOVE`), which the match builder builds with the squads
(`MatchBuilder.build_leader_overlay`) in every match, played, Watch or Endless, and in a test world that declares squads or a match, over
every squad's `view()`; the toggle reaches it through `MatchBuilder.set_overlay`, from Main's bar and the test runner's alike. While it is on it draws a crown over each side's living leader, moving to the next in line when one falls, and
how the squad follows it: the leash, the follow spots and the trail (LD28). A join is marked "Join stack · moving" (LD24).

Tests: `ui/order_markers_draw` (a fake view: one target per member with an order and none without, no marker on the leader, the selected
teammate ringed where it stands and cleared with the selection, a join "Join stack · moving", drawn at `DrawLayers.ABOVE`),
`ui/leader_overlay_draw` (the `show_leaders` row, global and off by default; with fake views nothing while off, then a crown over each
squad's leader, moved to a new leader and gone with none; the toggle through `MatchBuilder.set_overlay` on a test world's declared squads,
`s.squads`, and on Main's match, `Main.start_match`, two real squads, each shown and hidden by the bar's toggle; LD28's marks).

**LD13. Hold for go.** A stack order carries `wait_go` (false unless asked: it goes when ready, LD9, as before). A held stack forms, claims
its slots and radios `ready` as any stack, then holds: the point holds its slot, gun on the door, and nobody slices the pie, calls the bang,
slices a split stack's own half or crosses until its go (`Entry.orders.held_for_go`, ahead of the bang and the pie in `readiness.tick_stack`). Each member
ready and held radios `order_step` `in_position` (`Entry.holding_for_go`), which the markers show. Its claims carry `order_hold`, and
`order_go` once the go has come; an unordered member that joins a held ordered stack holds with it (D10). While held the order's
sentence for Von ends " when they give the go".
- **Go (D13).** `go` is an order kind of its own, `{ opening, pos }`: the squad posts it to every living member holding a held stack order
  at the doorway nearest the request's `pos`, whatever its `to` and the menu's selection, and posts nothing where no held stack waits. It
  replaces nothing: the member's perception marks its live stack order `go: true` (`process_order`) and asks for no new decision, and the
  squad's `view()` marks the released orders `go`. The squad reads the go off the claims as well (`scenes/ai/perception/stack/door_stack.gd`
  `released`): once a claim under the held order says `order_go`, or a member of that stack is crossing or through into the order's room
  (a claim under the order, or the human's on a crossing begun since the order was issued, D14), its `view()` says those orders are no longer `held`, latched as each member latches its
  own, so the order markers stop saying "hold" and the command menu stops offering "Go into the …". A claim left on the radio from an
  earlier entry through the same doorway (a member still holding the room on `cover` / `rear` under no order, or another order's member
  through) and a crossing into the other room release nothing: the held stack's go comes from its own stack only. It is latched:
  given while the members still walk to their slots, the stack goes the
  moment the ready barrier (D7) is met. After it the entry runs as a go-when-ready stack of its mode (the pie for a quiet one, the bang
  for a stun or a frag). The entry latches its go (`orders.note_go`) from any of: its own order's `go`; a teammate under the same order whose
  claims say `order_go`; a member of the stack, under the order or the human (on a crossing begun since the order), going in or through
  into its room (D14); the order's leader
  dead or gone (D12); and radios it in its next claim. Both read the one rule (`DoorStack.released`).
- **The human in the stack (D14).** When the human leader holds a slot at the held doorway through its `PlayerStack`, the held stack waits
  for the human's Go: the menu's Go releases it, and so does the human stepping into the doorway into the stack's room (its `going_in` /
  `in` on the radio, marked `human`, is a member of the stack crossing): the AIs follow it in by the crossing order. The human's claim
  carries no order to scope it by, so its crossing counts only when it began since the order was issued: its claim's `crossed_frame` at
  or after the order's `frame` (`DoorStack.released(order_id, into, since)`, `since` that frame; a claim or an order whose frame is
  unknown, -1, releases nothing). `PlayerStack` restamps `crossed_frame` each time the human's step goes from `claim` / `ready` to
  `going_in` / `in` (and clears it on a new reservation and on withdrawal), so it is the human's latest crossing: a human that brushed
  the funnel before the order and stepped back to its slot, then steps in after it, releases the stack; an `in` left on the radio from
  before the order does not, nor does a crossing already under way when the order is issued (a human standing in the funnel walking
  on in): it steps back to its slot and in again, or gives the menu's Go. An NPC's `crossed_frame` is its first crossing, its `going_in` being committed. Any other crossing counts
  only under the held order: an earlier entry's claims left at the doorway are not this stack's. The human joins behind the
  AIs (`PlayerStack` reserves the first free slot once a team is stacking). `PlayerStack` leaves an ally's progress-only callout (an
  `order_step` with no `entry_step`) out of its radio, as the perception does (LD7), so an AI's `in_position` never takes that AI's
  claim off the human's stack.
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
stack waits 10 s, the human walks in and both AIs follow; the squad's `view()` then no longer says their orders are held, nor do the order
markers say hold), `order_stack_hold_leader_dies` (D12: the leader killed while the stack holds,
it goes on its own), `ai/grenade/order_frag_held_then_go` (LD14: no bang call or throw while held), `general/squad_go_and_ambush` (the go's
recipients, its latch in `view()`, the leader's death posting one `go` with `auto`), `general/squad_go_latched_off_claims` (a go read
off the claims, `order_go` or a member crossing, stays latched in `view()` once the claims stop saying it),
`order_stack_hold_ignores_earlier_entry` (real Von: a `cover` claim left from an earlier entry into the same room releases nothing; the
stack holds and `view()` says held until the leader's go), `ai/stack/stack_player_go_after_funnel_brush` (D14: the human brushes the
funnel before the order and steps in after it; the squad's `view()` then no longer says held), `ai/door_stack_suite` (the rule:
`released` against the order's frame), `general/command_menu_wiring` (LD16). Part 1's
`order_stack_*` tests, unchanged, cover a stack that goes when ready.

**LD14. Frag entry.** The stack order's `mode` is `quiet`, `stun` or `frag` (LD5). With `frag` the stack throws a frag into the room
before the point crosses, the bang of E17 (`docs/tactical-entry.md`) with a frag:
- **The thrower** is picked as a stun's (`grenade._thrower`, from the claims' `frags`): the second of the stack if it carries one, else the lowest
  slot that does.
- **The stack's safety (D16).** `grenade._plan_bang` aims as for a stun, at the frag's reach, and leaves out every target whose burst would have a
  claimed slot of the stack, the thrower's own included, inside the frag's danger zone (`AgentPerception.in_grenade_zone`: a clear line
  within `danger_radius` + `evade_margin`, 370 px, the G16 zone of `docs/grenades.md`): the wall beside the door shields the stack. With no
  such target the frag is given up and the stack goes in quietly, radioing `bang_off`.
- **Frag out.** The thrower radios `bang`, steps out, throws (`Combat`'s `throw.begin` on `FRAG_SLOT`), radios `frag_out` as the frag leaves
  its hand (as GRENADE's thrower does, G17) and walks back to its slot; every member holds its slot crouched (`Entry.holds_crouched`) and
  turned away from the door until the burst, at most `FRAG_BURST_CAP` (7 s) from the call (a stun's is 5 s). A member whose slot is out of
  the frag's zone keeps the entry when the evade reflex would fire (`Entry.expects_burst`: the frag in flight, or come down where the slot
  is out of its zone: the slot is its cover); one whose slot the frag reaches (a frag that came back to the door) evades as anywhere.
- **In on the burst.** On the burst in the room the stack is over the bang: the point crosses at once with no pie, E14's hold lifted for
  `BANG_WINDOW` (3 s).
- **No frag (D15).** The menu greys the frag items while no recipient carries a frag; a frag stack whose frag is gone by the time it is in
  goes in quietly and radios `bang_off` (its claims still say `order_mode` `frag`), and the order is still done at the cleared room (as D1).
- Only an order throws a frag at entry: the bang's grenade is a frag only for a stack under an order whose mode is frag (`grenade._bang_kind`);
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
- **The post (D17).** `AgentEntry.ambush_spot(geometry, nth, count, map, space)` (`geometry` the entry geometry of `opening` into `room`), beside `defend_spot`: candidates `AMBUSH_DEPTHS`
  (40 to 160 px) back from the doorway's wall and `AMBUSH_LATERALS` (30 to 260 px) along it past the jamb, inside the room's walls by
  `AMBUSH_INSET` (22 px), snapped onto the navmesh, with a sight line to the threshold and off the doorway's axis (past its jamb by
  `DEFEND_BODY`, 14 px). Ranked by how many of the doorway's lookouts see the post (the slots and pie steps of an entry into the room by
  that doorway, as laid out before they are snapped: `geometry`'s `lookouts`; hidden only when it is hidden from the 8 points
  `AMBUSH_SLACK`, 12 px, round it too, since the ambusher stops a few px off its post), then out of every doorway's fatal funnel, then low
  cover on its line to the threshold, then nearest `AMBUSH_DEPTH` (110 px, E8's `COVER_DEPTH`) back: with no hidden post, the least seen.
  Members alternate sides of the axis by their place in `to` (the side with more wall first), two on one side at least `AMBUSH_SPACING`
  (44 px) apart. A hidden post lies tucked against the door's wall well along from it; in the Terrace house only the hall / living room
  doorway (`door_150_360`, from the living room) has one, every other doorway the least-seen fallback.
- **The primitive.** `ambush` (`behavior_orders.gd`), the ORDER node's option with `{ opening, room, spot, door_pos, order_id }`: `defend`'s walk
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

**LD17. The stack waits for its leader.** When the human leads, its `PlayerStack` is handed the squad (`MatchBuilder.bind_squad`) and its
claims carry `leader: true` while the squad's `leader()` is the human. An ordered stack waits for the leader that gave its order when the
leader holds a slot in it (`Entry.orders.leads`: the claim says `leader` and is the order's leader's): nobody crosses, slices the pie or calls the
bang while that claim is still at `claim`, whatever the wait, until `order_ready_cap` (D7) runs out; the leader standing in its slot
(`ready`) lets the stack go. Its claim withdrawn (`abort`: its walk back to the doorway grew past `reserve_range * leave_factor`, 450 px, or it died) frees the
stack at once. An AI leader holds no `PlayerStack`, and the joins its own claims bring (LD24) are no ordered stack (a join runs as the
member's own entry), so only the human is waited for this way (D22).
- **The joiners' clock (D23).** A member the order does not name is waited for `tuning.entry.ready_timeout` (6 s) from the moment every living
  recipient of the order, the member itself among them, stands in its slot (`Entry.readiness.all_in_at`, `readiness.note_all_in`), or from when the stack last
  grew if that is later: not from the point's own `ready`. A point that has stood in its slot a long while for a far recipient still gives
  an unordered joiner arriving after that recipient its full 6 s. The point's debug countdown (`ready_left`) counts from the same moment.

Tests (scripted, `tests/ai/entry/`): `order_stack_waits_for_leader` (the human leader holds a slot in the stack it ordered on the Terrace
house's back door and dawdles 20 s out of it: nobody crosses and its claim says `leader`; it steps in and they go, only after it; at a
second door it dawdles 10 s, nobody crosses, then it walks away: its withdrawn claim frees them), `order_stack_joiner_grace` (an unordered
joiner reaching its slot 2 s after the last ordered member is waited for, though the point stood in its slot 15 s).

**LD18. Rings for every stack of the human's side.** The squad reads the entry claims its members radio through its own `ClaimLedger` (the
human's `PlayerStack` among them; unlimited range, the side's whole view; each current as long as the NPCs keep a callout they heard, their `callout_ttl` (6 s), which the match builder hands the squad, a dead speaker's
dropped) and gives every stack its side is forming, ordered or its own, in
`view()["stacks"]`: `[{ opening, into, door, slots: [{ n, point, holder, held, there, mine, side, row }] }]`, from the stack's first claim
while any member is still on its way in (`claim`, `ready`, `bang` or `going_in`). Its slots run from 1 to the last claimed, each laid where
the AI stands it with the squad's own copy of the doorway geometry (`DoorStack.layout`, over `StackLayout.slots`, `side_for`, `point`: the holder's side
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

**LD19. Who follows.** A member follows its leader (`Squad.follows(member)`) while it is alive, its squad has a leader, it is not the
leader and an NPC controller drives it (a child in the group `npc_controllers` when the squad is set up): a human member who does not lead
is never given a spot, and a squad of one has no followers. Each tick the controller's reflexes read it (`follow_squad`) into the perception's
`follows` (a snapshot fact and a `quick_facts()` entry) and forces a decision when it changes ("follows its leader" / "leads its squad").
The rule is the same whoever leads: an AI leader, the human (its AI teammates follow the human and ring it when it stops, LD21), or a
defenders' crew's first spawned, from the start of the match. When the leader dies (LD4) the squad starts its trail afresh at the new
leader within the frame, so every follower's spot comes round it, and the new leader, a follower no more, decides on its own again.

Tests: `ai/movement/follow_leader_search` (real Von, three invaders on the furnished Terrace house: while the leader, its own entries off
(`tuning.entry.enabled`), searches the house, the two followers stay within a band of it (the median under its place in the file plus 45 px of walking lag,
`Follow.band_p50`: 100 px for the first follower, 145 for the second, the lag measured 5 to 38 px; nine samples in ten under `BAND_P90`,
260 px), go through two doorways after it and put no question to Von while no hostile is known), `ai/movement/follow_defenders` (three
defenders on a pinned house, placed and bound as Main does, their leader investigating gunfire across the house: within the band, through
its doorways, each follower's spot at the median between its place in the file and the outermost ring (LD21), no question to Von, and no
follower more than 80 px off its spot for more than 8 s), `ai/movement/follow_human_leader` (a puppet human leader walks the garden and
stops: the two NPCs follow it in a file, each spot 55 and 100 px behind it at the median, re-aiming their walks only once their spots have
moved 20 px, then take spots on the ring behind it and face outward; the squad's tunables are this document's numbers, and mid-walk its
`view()` holds a trail of two points or more, the 320 px leash and each member's own follow spot), `ai/movement/follow_leader_dies` (the lead killed: the sergeant
leads within the frame and decides on its own, not FOLLOW; the trooper's spot comes round the sergeant), `ai/movement/independent_no_squad`
(one invader with no squad: its root level is asked of Von, its `follows` is false, it never takes FOLLOW, and it claims a doorway of its
own and goes in).

**LD20. The FOLLOW node.** A follower picks no goal of its own: while it follows, INVESTIGATE, SEARCH and IDLE are disabled for it and the
controller adds the entry rule `follows → follow`, after the fight rules, ORDER and `hostile_known` (LD6). FOLLOW is a root leaf
(`requires` `follows` and `!ordered`, primitive `follow`): with no fight, no order and no hostile known, the walk starts there and takes it
without asking Von. The `follow` primitive keeps the member to the spot the squad gives it (LD21) and asks for no decision on the cadence
(`Behavior.wants_decision` is false for it); a decision comes only when one is forced (a hostile seen, a hit or shots landing by it, an
order, the leader's death, the leash break of LD23) or when its spot is gone (it leads now, or follows no more: the primitive resolves,
holding). A follower in a fight decides through Von as any member, within its leash (LD23), and follows again once the fight lapses. Its
status reads "keeping up with its leader" on the way and "by its leader" at its spot.

**LD21. Where a follower stands.** The squad keeps the leader's trail and lays the follow spots through its `SquadFollow`
(`scenes/ai/team/squad_follow.gd`, the squad's tunables read off it): the trail every physics frame (`track`: a point each `TRAIL_STEP`,
15 px, the leader moves, kept as long as the file needs), and every follower's spot (`Squad.follow_spot`, laid at most once a physics frame, and only when the leader moved, turned or stopped or the followers changed), the followers taken in roster order:
- **The leader moving.** The spot is on the trail, `follow_gap` (55 px) back for the first follower and `follow_step` (45 px) further for
  each next one, snapped onto the navigation map: a file behind the leader, through its doorways after it, with no tactical entry of its
  own. A follower whose place lies past the trail's oldest point (the leader has not walked that far since it led) keeps where it stands
  while that place lies further from the leader than it does, so a file setting off never walks away from its leader and across itself.
- **The leader still** (`follow_still_time`, 0.8 s, since it last moved a trail step). The spot is a slot on a ring behind the way the
  leader came (`follow_ring`, 80 px; the way is the last stretch of its trail, so a leader looking round its doors does not swing the ring
  round it): slots `follow_step` apart either side of straight behind it and less than a right angle off it, then on two wider rings
  (`RINGS` 3, each `follow_step` further out), each on the navigation map within `SLOT_SNAP` (20 px), in the leader's sight and out of
  every doorway. A follower the rings hold no slot for keeps to the trail, stepped back along it out of a doorway.
- **Out of the leader's way** (`_clear_of_way`). A follower, or its spot, in the lane ahead of the leader's facing (`WAY_CLEARANCE`, 32 px
  either side of its line, a ring and a step deep) is sent beside that lane, on its own side (the other when a member stands there), else
  further ahead along it (170, 215 or 260 px), each such spot in the leader's sight, on the navigation map, out of every doorway and in a
  room the leader has stood in since it led: a follower never goes first into a room its leader has not entered, and a leader turning back
  walks through its file. A spot beside the way is kept while it still clears the way, until the leader has moved a ring on or turned
  back, so a leader's swinging gaze (slicing a pie) does not send the follower to and fro.
- **The walk** (`follow`). It is re-aimed only once the spot has moved `follow_retarget` (20 px) from where it is going (or, catching
  up, on reaching where it was going: below), and is over within
  `follow_arrive` (10 px) of it, where its path ends short of a spot it cannot reach (the navigation agent done at the nearest reachable
  point), or when a body seals its only way. The member walks with its gun up (the watch stage shoots what it sees on the way).
- **Catching up.** A follower runs, when a run can start, once it is more than `follow_step` (45 px) from its live spot, and from then
  on is catching up until it is back within `follow_caught_up` (20 px) of it: it runs whenever it steps, and on reaching where its walk
  was going, short of its live spot, re-aims at that spot, until it is that near. A walk over short of the spot (its path ends there, or
  a body seals its only way) ends the catch-up too. A moment with no step (giving way to a walker, held short of a body, a step
  `keep_off` stops) does not end the catch-up: the follower runs on when it steps again, on whatever stamina it has left (the stamina a
  run needs to start is not asked again). The run rule's other gates stay and end it (no run with a shot to take or a reload due, the
  stamina run dry, never in a tactical entry, `domain-ai-behavior`), and so does any other primitive than `follow`. A run that stopped
  at `follow_step` would leave a follower on a long walk without stops walking at its leader's pace that far behind its spot. Nor does a
  follower give way to its leader walking on ahead of it: the give-way check looks ahead only for the time a walker's own walk still
  takes (at most its 1.2 s; Locomotion's give-way, `domain-ai-behavior`), and a follower's walk ends at its spot, short of its leader.

Tests: LD19's, `follow_human_leader` for the file's spacing, the re-aim and the ring, `follow_catches_up` for the catch-up (a follower far
behind a leader walking a long straight line comes back within `follow_caught_up` of its spot after each catch-up, through a teammate
stepping into its way for a moment, and again after the leader has paused to look back), `npc_give_way_walk_ends_short` for the
give-way (a walk ending short of a walker's course does not give way to it; one passing through it still does).

**LD22. At rest.** At its spot a follower stands facing away from its leader. Once it has stood there `follow_still_time` (0.8 s) with no
threat and not under fire, it tops up a low magazine (at or below `low_ammo_fraction`, 0.34, of the gun's capacity: not only a dry one)
with a tactical reload (`Combat.top_off`), without a decision.

Tests: `ai/movement/follow_top_up` (a follower starting with 2 rounds in its pistol takes its spot on the ring round a still puppet leader
and reloads there, at rest, while its decision walks put no question to Von).

**LD23. The leash.** A follower holding no order fights within `leash` (320 px) of its leader's live position. A member carrying an order
(defending a room, an ambush, a stack, a held one or a join included) is not leashed: it fights where its order takes it, whatever the
distance to its leader, and is leashed again once its order ends. It still follows (LD19: its follow spot, its place in the file); only the
leash is dropped (the controller's reflexes' `leash_lead` hands the planner and the behaviour its leader while its order is empty, and none
otherwise). For a leashed follower:
- **Its options.** Inside a `confine` subtree (COMBAT) the planner drops every option placed beyond the leash (`leash_center`, pushed each
  decision as the leader's position, and `leash`, beside `inside_only` and `room`): where the option acts from (`params.from`, else
  `params.point`), so the fire spots, flank sides, advances, retreats and throw spots out there are not offered; an option that names no
  place (a reload, a punch) stays.
- **Its spots.** The combat module keeps its peek and cover spots within the leash; with none there it holds where it is instead of
  closing in, and melee holds its ground while its target is off the leash.
- **The break.** A fighting follower (`in_combat`) further than `leash_break` (1.3) leashes from its leader, neither committed nor on its
  way somewhere it chose (`Behavior.orders.walk_pending`: a move or an engage not there yet, a throw's walk), decides again ("off the leash"),
  once until it has been back within that; with no COMBAT option left within the leash the decision is FOLLOW, which fires at what it sees
  on the way.

Tests: `ai/combat/leash_no_chase` (real Von: a target the follower fights flees far down an open hall; the follower never stands more than
the leash and 40 px from its puppet leader), `ai/combat/leash_free_chase` (its contrast: the same hall with no squad bound, and the NPC goes
after the target past the leash and 40 px from the puppet, so the leash is what holds the follower back), `ai/combat/leash_walks_back` (the leader runs 650 px off while the follower fights: it takes
FOLLOW at or after the break and comes back within the leash), `ai/combat/leash_pinned_cover` (an SMG gunman pins the follower: it fights
from cover within the leash, or follows, never more than the leash and 40 px from its leader). An ordered member off the leash:
`ai/combat/ordered_melee_off_leash` (real Von: ordered to defend an open hall with a dry gun, its puppet leader more than two leashes off,
it closes on a gunman beyond the leash and strikes it, which a leash would hold it short of) and `ai/combat/defend_room_stays_inside`
(LD8: its leader about 510 px off, the ordered defender still fights from inside the kitchen).

**LD24. The leader's stack brings the team in.** When the leader makes an entry claim of its own at a doorway (a callout from it with
`entry_step` `claim`, no `order_id` and no `join`: an AI leader's ENTER or STUN ENTRY, or the human's own claim through its `PlayerStack`, below), the
squad rallies its team (`_rally`): one `stack` order with mode `join`, `opening` and `into` the claim's, `pos` the doorway's centre, `split`,
`bang` and `wait_go` false, to every follower holding no order (D24: a member carrying out another order keeps it). Once per doorway per
leader (keyed `<leader>:<opening>`), until that stack is given up (LD25); a new leader rallies again. The rule keys on the speaker being the
leader, never on whether the squad has a human. A join's claims are never its holder's own: they carry `join: true`, so a follower that
takes over the lead while it holds a join rallies nobody on it; its next claim of its own does (D30).
- **The join.** The ORDER node's option is the entry `stack_<opening>` with `{ opening, into, bang: false, join: true, order_id }`: no side,
  mode, `wait_go` or `split` of the order's. `Entry.begin` leaves the order's id out of the entry, so the member runs its own unordered entry,
  joining the leader's stack: the team's side and the first claimer's mode (D10), the suspect-room bang and its late upgrade
  (`docs/tactical-entry.md` E17), the listen at the stack, the joiner's ready wait (`tuning.entry.ready_timeout`), and no bang of its own. Its walk
  there is any entry's, not an ordered stack's guarded way (D4). The order still names it, so its progress is radioed (`moving`, `done`) and
  the squad's view and the order markers show it ("Join stack · moving"). The human's quiet / stun / frag orders keep LD9's "the mode wins";
  the command menu never offers a join.
- **No slot.** A join at a dead end with no slot for the member offers no option (and a join whose entry cannot begin is ended), so it ends
  `refused` and the member follows again (LD25), instead of an ordered stack's refused hold (D21).
- **The wording.** "Your leader ordered you to go into the kitchen by its doorway with them." (LD6): measured with `tools/von_probe.py` over
  the 38 `tools/von_scenarios` levels in spike #66, it moved no combat level's top pick (the expected pick's probability moving 0.020 on
  average).
- **The human's own claim** (`PlayerStack`, interface 17). The invaders' alone (D29): the match builder sets the human's `PlayerStack.own_claims` through
  `MatchBuilder.bind_squad` on the invaders' side only, so a human defender leader makes no claim of its own and its step-ups rally nobody
  (its teammates still follow it). While the human leads a squad with
  another living member and no allied stack is forming within its reach, the human stepping up to a doorway claims slot 1 there of its own (`_claim_own`, `_stepped_up`): standing on the
  doorway's stack side, out from its wall plane by at most `STEP_UP_REACH` (60 px) and past its jamb along the wall by at most as much, for
  `STEP_UP_TIME` (0.5 s), at a doorway nobody stacks at and the human has not declined. It claims on the side it stands on, marked `own`,
  and the squad hears it as the leader's own claim: of the human's claims only one marked `own` rallies the team, so the slot the human is
  reserved in a stack already forming (E16) never does. That claim is kept while nobody else stacks there yet (the "nobody stacking" withdrawal waits until
  the human is `in`), and the `go_timeout` withdrawal waits for somebody ahead of it; otherwise it is withdrawn as any reservation (the walk
  back past `reserve_range` x `leave_factor`, death). The human's other claims are E16's (`docs/tactical-entry.md`).

Tests: `ai/entry/join_rally_clears_room` (real Von: the lead's own claim gives both others a join; all three go in within 15 s of each
other and the room is called clear), `ai/entry/join_suspect_room_bangs` (scripted: gunfire heard in the kitchen first, the stun the
sergeant's: the join stack turns bang and a stun goes off in the kitchen before anyone goes in), `ai/entry/join_unsuspected_quiet`
(scripted: nothing heard: each joiner's state reads the join's sentence above verbatim, no claim says bang, no stun goes off, all three go
in), `ai/stack/human_leader_rallies` (a puppet human leader
steps up beside the back door: its own claim, a join to both NPCs, both ready in the stack with it within 20 s),
`ai/stack/human_rally_spares_ordered` (D24: the member the human ordered to defend the living room gets no join, keeps its order and
claims no slot; the two free members join and stand ready), `ai/stack/human_stack_slot_no_rally` (scripted: the human ordered two
members to stack and is reserved a slot in that stack (E16): it steps in and radios ready, and no join is posted, the free follower making
no claim there), `ai/stack/human_defender_leader_no_rally` (D29: in a Main-wired match with "Lead the team" on, a human defender leading
its crew stands beside the hall doorway into the living room: no claim of its own, no join, and its teammate keeps following it),
`ai/entry/join_inherited_no_rally` (D30: the human leader rallies the sergeant to the back door and dies while the sergeant is on its way;
the sergeant leads holding the join, and its claims there give the trooper, freed of its defend by the takeover, no join; once the join
is done, its next claim of its own rallies the trooper). The human's own orders, quiet / stun / frag and held, are LD9's, LD13's and
LD14's tests, their squads bound.

**LD25. A join's end.** When the leader gives its stack up (its own `entry_step` `abort` there: a decision forced on it replaced the entry,
or it withdrew), the squad posts one `cancel` to the living members holding a join it gave at that doorway and forgets that rally, so a
later claim of its there rallies again (D25). A member whose join ends follows again: done (the room cleared, by it or radioed by a
teammate), cancelled, or refused (the squad drops a refused join from what the member holds, so the next rally counts it free). While its
entry is still in its `approach` or `stack` phase, a join whose order has ended forces a decision at once (`Behavior.orders.join_over`, "join
over": the entry would not end on its own there); in the later phases (the pie, the crossing, the corner, the clear, the cover, the rear) the
entry runs to its end first, then the member follows (D26). A cancel forces a decision as any order does.

Tests: `ai/entry/join_leader_aborts` (the lead is hit just after its claim and radios `abort`: the joins are cancelled and both members
drop their entries and follow within 3 s), `ai/entry/join_cleared_before_reached` (a slow trooper still on its way when the lead and the
sergeant have cleared the room: it follows within 1 s and never goes in).

**LD26. Taking over from a dead human leader.** When the human leader dies the next in line leads (LD4) and the squad posts one `cancel` to
the living members holding a `defend_room` or an `ambush` order (`_take_over`), so each follows the new AI leader. The human's held stacks
are released as any dead leader's (D12) and its other stack orders are carried to their end (the room cleared); each member follows once
its order ends, and the new leader's next own claim rallies the members then holding no order (LD24).

Tests: `general/squad_takeover_from_human` (a puppet human leader orders a defend, an ambush and a held stack, then dies: the sergeant leads
within the frame; one `cancel`, to the defender and the ambusher; the held stack is released (`auto`), goes in and clears the kitchen; each
member follows the sergeant once its order ends; the sergeant's next own claim gives a join to every member then holding no order and to
nobody holding one).

**LD27. The invader team spawns together.** A match places its invader team in one group (`match_spawner.gd` `spawn_invader_team`,
through `MatchBuilder.populate`, Main's match and a test's declared match alike), beside the front door: round a point against the house's
outside wall next to the front entrance, on one side of the doorway (the side drawn from the match's RNG seeded with the house seed, so a
pinned seed pins it), 120 px along the wall from the doorway's centre (`DOOR_SIDE_OFFSET`: past the jamb, out of the doorway's straight
line) and `spawn_clearance` (20 px) out from the wall, where the wall hides the team from inside. With a human invader in a played match the
group packs round the human's spot instead (the human starts where it stands: Main's player just outside the front entrance). In a house
with no front door it packs round a point of the perimeter of the rooms' bounding box grown by `invader_margin` (80 px), drawn from the same
RNG. Each member takes the first spot that is clear (`is_clear`: `spawn_clearance` from every furniture footprint and twice that from every
combatant placed, the human's spot among them), out of doors (out of every room grown by `spawn_clearance`, within twice `invader_margin`
of the bounds) and, beside the front door, out of the doorway's straight strip (within half its width of its centre along the wall): the
centre, then the spots of up to `GROUP_RINGS` (6) rings twice `spawn_clearance` apart round it; the centre, logged, when none is. Each
member heads for the front entrance first (its `entry_point`). Defenders keep spawning in random rooms.

Tests: `general/match_spawn_team_beside_front_door` (every floorplan, fixed seeds, each match built whole by `MatchBuilder.build`: every
invader outside the house, within 150 px of the front door's centre and its rings, out of the doorway's strip; the team on both sides of
the door across the seeds; no defender knowing a hostile on the first frame), `general/match_spawn_team_grouped` (Main run whole on house
seed 101 with four invaders and two defenders: watched, every invader within 110 px of the group's centre, which stands outside the house
beside its front door, the same point for the same seed, every defender in a room; played as an invader, every invader within 110 px of the
human), `general/match_spawn_team_no_front_door` (a one-room layout with no doorway: the team packed round a point of the ring round it, each
member on a spot of its own and outside the house).

**LD28. The squad-leaders overlay draws the following.** With `show_leaders` on (LD12) the `LeaderOverlay` draws, per squad and read
through `Squad.view()` alone: the crown over the living leader, the leash ring round it (the view's `leash`), each follower's follow spot as
a small ring with a thin line from the follower to it (each member row's `follow_spot`, none at `Vector2.INF`), and the leader's trail as a
dotted line (the view's `trail`, oldest point first, drawn from two points). `drawn()` lists them: `{ kind: "crown", point, node }`,
`{ kind: "leash", point, radius, node }`, `{ kind: "spot", point, node }`, `{ kind: "line", from, to, node }` and `{ kind: "trail",
points }`; off, nothing.

Tests: `ui/leader_overlay_draw`.

**Doctrine.** `docs/research/squad-following.md` sets these rules beside fire-team and entry-team practice (US Army FM 3-21.8 and FM 3-06.11,
USMC MCWP 3-11.2, police SWAT outlines). The game keeps the prototype's numbers from spike #66, the user's choice, and differs from doctrine
in four ways: the file is stack-tight everywhere (55 + 45 px against 3 to 5 m between buildings and 10 m in the open); the leader leads the
file (the Army's "follow me"; a USMC column and an entry stack put the team leader second); a halted team rings its leader at 80 px
instead of holding its movement intervals facing out (facing out matches); and the leash is a radius (320 px) where doctrine's is sight or
voice of the leader. The leader's succession and each member keeping its own entry drill match.

## Decisions

The cases the behaviours above cite as D1 to D30.

| # | Case | Decision | Where |
|---|---|---|---|
| D1 | Ordered with a stun, no stun in the stack | The menu greys "with stun" while no recipient carries one; a stack whose stun is gone by the time it is in goes in quietly and radios `bang_off`, and the order is still done at `cleared_room`. | LD9, LD11 |
| D2 | Where the defenders of a room stand | They share out its doorways, each on a spot back in the room, off its doorway's axis, cover preferred, gun on that doorway; extras double up in turn; a lone member takes the spot that sees the most doorways and turns among them. | LD8 |
| D3 | What a click on a doorway decides | The side of the wall plane clicked is where the stack forms (it goes into the other room); left or right of the opening along the wall is the stack's side of the door; a click on the opening is a split stack; an exterior door always goes into the house. | LD5, LD9 |
| D4 | Defenders and stack orders | An ordered stack runs whatever `tuning.entry.enabled` says. Its whole way to the slot is read before the claim goes out: a room not cleared on it is entered first, and a doorway view on it secured first when no other recipient is coming; the approach then goes round the views, uncapped. | LD9 |
| D5 | Markers | Only when the human leads, for its own squad: each member's target, the selection while paused; the leader's crown is a debug overlay ("Squad leaders") for every squad in any match. | LD12 |
| D6 | A split stack's members | Each takes the side it reaches without crossing the view, balanced so the sides differ by one at most. | LD9 |
| D7 | Go when ready | The point waits for every living recipient's `ready` (and the human leader's in the stack, D22), at most `order_ready_cap`; an unordered joiner is waited for `tuning.entry.ready_timeout` (D23). | LD9, LD17 |
| D8 | A defender and a live grenade | The evade reflex may leave the room; after the burst the member walks back in and holds. | LD8 |
| D9 | The clock and the tests | Moving to the game clock may change a test's timing; `memory_matches_reference` takes its reference "now" from the new clock (the clock source only), and any other test turned red is reported with its cause before it is changed. | LD1 |
| D10 | Unordered entries | Unchanged: Von's ENTER and STUN ENTRY, the first claimer's mode, the suspect-room bang, the `bang_off` veto, the late upgrade, the listen and the ready timeout; the order's rules apply only to a stack with a claim carrying an `order_id`, and an unordered joiner follows the order's mode and side. | LD9 |
| D11 | A defender's ordered walk across its own house | A room it has stood in and seen empty within `tuning.entry_guard.pass_clear_time` counts as clear for passing, for thresholds and views; any other room gets an entry. | LD9 |
| D12 | A held stack whose leader can no longer say go | When the leader who gave it is dead, the squad releases it (a `go` with `auto: true`) and the entry latches its go on its own: it goes on the ready barrier, or at once if ready. | LD13 |
| D13 | Who a go goes to | Every living member holding a held stack order at that doorway, whatever the selection; it releases the order, never replaces it, and is latched until the stack is ready. | LD13, LD16 |
| D14 | The human in a held stack | The stack waits for the human's go: the menu's Go, or the human stepping into the doorway (its `going_in` / `in`) on a crossing begun since the order was issued (`crossed_frame` at or after the order's `frame`; the human's latest crossing); the AIs follow it in. | LD13 |
| D15 | Ordered with a frag, no frag in the stack | The menu greys "with frag" while no recipient carries one; a stack whose frag is gone by the time it is in goes in quietly and radios `bang_off`, and the order is still done at `cleared_room`. | LD14, LD16 |
| D16 | Where the frag is aimed | Only where its burst leaves every claimed slot of the stack, the thrower's own too, out of its danger zone (the wall between shields it); nowhere such: the frag is given up, quiet. | LD14 |
| D17 | Where an ambush waits | In the room on the click's side of the wall (an exterior door: the house's), at a post off the axis, back from the wall, out of the funnel, seeing the threshold and hidden from every slot and pie step of an entry by that doorway; with none hidden, the least seen. | LD15 |
| D18 | When an ambush ends | On first contact, `done`: a hostile in sight anywhere, or under fire; footsteps and callouts do not end it. The member then decides on its own. | LD15 |
| D19 | The menu's "Hold for my go" | A panel checkbox, off at first, kept across opens while the match runs; it sets `wait_go` on the stack chosen. | LD16 |
| D20 | The room an ordered stack stands in | Once a member under the order holds its slot there (`ready` or `bang`), it counts as cleared for passing: the members still coming walk through it, not into it by entry. | LD9 |
| D21 | More members than a dead end holds | Each past what its wall and open floor hold claims no slot, holds where it is and radios `refused`; the order is kept (still held, drawn red), unlike a refused unknown room, which is dropped. | LD7, LD9 |
| D22 | The human leader in a stack it ordered | The stack waits for it as for a recipient: nobody goes while its claim is at `claim`, until `order_ready_cap`; its withdrawn claim frees the stack. | LD17 |
| D23 | When an unordered joiner's wait starts | From the moment every living recipient of the order stands in its slot (or the stack last grew), not from the point's own `ready`. | LD17 |
| D24 | Who a rally's join goes to | Only the followers holding no order: a member carrying out another of the human's orders (a defend, an ambush, a stack elsewhere or at the same doorway) keeps it; the same for an AI leader's rally. | LD24 |
| D25 | "Once per doorway per leader" and a stack given up | The leader's `abort` there forgets the rally, so its next claim there rallies again (a leader whose approach the entry guard paused, or that comes back after a fight, brings its team in); heartbeats, re-claims and move-ups never rally twice. | LD24, LD25 |
| D26 | A join that ends mid-entry | A decision is forced only in the `approach` and `stack` phases, where the entry would not end on its own; from the pie on the entry runs to its end, then the member follows. | LD25 |
| D27 | What "stepping up" to a doorway is, for the human | Standing on its stack side against its wall beside the opening (out from the wall plane and past the jamb, each within 60 px) for 0.5 s, so a human walking past a door does not rally the team. | LD24 |
| D28 | A follower and its leader's way | It never stands in the lane ahead of its leader: it steps beside it (its own side first) or further ahead, only into rooms the leader has entered, and keeps that spot while it clears the way, so a leader turning back or slicing a pie walks through its file. | LD21 |
| D29 | Whose human leader rallies by stepping up | The invaders' only: a human defender leader makes no claim of its own at a doorway (the match builder sets `PlayerStack.own_claims` for the invaders' side alone, `MatchBuilder.bind_squad`), so its step-ups rally nobody and its teammates go on following it. | LD24 |
| D30 | A follower that takes over the lead holding a join | The join's claims are not its own claim: they carry `join: true` and the squad's own-claim check rejects them, so it does not rally again at that doorway; its next claim of its own, at any doorway, rallies the members then holding no order. | LD24 |

## Numbers

| What | Value | Where |
|---|---|---|
| A defend spot: back from its doorway's wall | 60 to 150 px, best 100 | `AgentEntry.DEFEND_DEPTHS`, `DEFEND_DEPTH` |
| ... along the wall past the jamb | 30 to 100 px, best 50 | `DEFEND_LATERALS`, `DEFEND_LATERAL` |
| ... inside the room's walls by | 22 px | `DEFEND_INSET` |
| The fatal funnel: within a body of a doorway's width, nearer its wall than | 14 px, 200 px | `DEFEND_BODY`, `DEFEND_FUNNEL_DEPTH` |
| A defender walks into its spot to within, and back to it when pushed off by more than | 8 px, 24 px | `DEFEND_REACH`, `DEFEND_DRIFT` (`behavior_orders.gd`) |
| An ordered stack waits for its recipients at most (from the first ordered `ready`) | 60 s | `tuning.entry.order_ready_cap` |
| A room seen empty counts as clear for a defender's ordered walk for | 60 s | `tuning.entry_guard.pass_clear_time` |
| The command menu picks a teammate's body within | 28 px | `CommandMenu.PICK_RADIUS` |
| An ambush post: back from its doorway's wall | 40 to 160 px, best 110 | `AgentEntry.AMBUSH_DEPTHS`, `AMBUSH_DEPTH` |
| ... along the wall past the jamb | 30 to 260 px | `AMBUSH_LATERALS` |
| ... inside the room's walls by | 22 px | `AMBUSH_INSET` |
| ... hidden too from the points this far round it | 12 px | `AMBUSH_SLACK` |
| Two ambushers' posts on one side, at least | 44 px apart | `AMBUSH_SPACING` |
| A frag entry waits for its frag to go off at most (from the call) | 7 s | `EntryGrenade.FRAG_BURST_CAP` |
| A frag entry keeps every slot out of the frag's danger zone | 370 px (250 + 120) | `throw_stats().danger_radius` + `tuning.grenades.evade_margin` |
| An ordered member waits for the map round the views before reading its way at most | 2 s | `ROUTE_WAIT` (`behavior_entries.gd`) |
| A stack's approach is given up after its own walk at walking pace plus | 20 s | `tuning.entry.approach_time` (`Entry.approach.cap`) |
| A member stands in its slot within, and steps back in when further off than | 6 px | `StackClaim.SLOT_REACH` |
| A member in its slot looks for a lower slot to move up into every | 0.25 s | `EntryClaim.MOVE_UP_EVERY` |
| ... within (1.5 x the stack's spacing) | 66 px | `EntryClaim.MOVE_UP_REACH` (`Entry.SPOT_SPACING` 44) |
| ... by a plain walk no longer than 1.5 x the straight line plus | 32 px | `Locomotion.PASS_CLEARANCE` |
| A walk round resting bodies may end this far short, the rest walked on the plain map | 64 px | `Locomotion`'s `crowd.LAST_LEG` |
| A walk held short of a body re-plans once the steering map shows the body this far off it, or after | 16 px, 2 s | `Locomotion`'s `crowd.CARVED_GAP`, `CARVE_WAIT` |
| An unordered joiner is waited for, from when every recipient stands in its slot | 6 s | `tuning.entry.ready_timeout` |
| The human's slot is withdrawn once its walk back to the doorway is longer than | 450 px (300 x 1.5) | `PlayerStack.reserve_range` x `leave_factor` |
| The squad's view keeps a member's entry claim for | 6 s | `tuning.radio.callout_ttl` (handed to `Squad.setup` by the match builder) |
| A ring whose holder stands in its slot is filled at | 0.3 alpha | `StackMarkers.ALPHA_THERE_FILL` |
| The first follower keeps back along the leader's trail, and each next one further | 55 px, 45 px | `Squad.follow_gap`, `follow_step` |
| The leader takes a trail point each | 15 px | `SquadFollow.TRAIL_STEP` |
| The leader counts as still after standing | 0.8 s | `Squad.follow_still_time` |
| The ring round a still leader, and the rings after it | 80 px, then 125 and 170 px (3 rings) | `Squad.follow_ring`, `follow_step`, `SquadFollow.RINGS` |
| A ring slot or a spot beside the way lies on the navigation map within | 20 px | `SquadFollow.SLOT_SNAP` |
| The leader's way: either side of its line | 32 px | `SquadFollow.WAY_CLEARANCE` |
| A follower re-aims its walk once its spot has moved | 20 px | `Squad.follow_retarget` |
| A follower is at its spot within | 10 px | `Squad.follow_arrive` |
| A follower runs once it is further from its spot than | 45 px | `Squad.follow_step` |
| ... and keeps running until it is back within | 20 px | `Squad.follow_caught_up` |
| A follower at rest tops up a magazine at or below | 0.34 of its capacity | `tuning.context.low_ammo_fraction` |
| A follower fights within, of its leader's live position | 320 px | `Squad.leash` |
| ... and re-decides in a fight further than | 1.3 leashes (416 px) | `Squad.leash_break` |
| The human has stepped up to a doorway within, and after | 60 px, 0.5 s | `PlayerStack.STEP_UP_REACH`, `STEP_UP_TIME` |
| The invader team's point lies along the wall from the front door's centre by | 120 px | `match_spawner.gd` `DOOR_SIDE_OFFSET` |
| ... and out from the wall by | 20 px (`spawn_clearance`) | the match spec's `spawn_clearance` (Main's export) |
| With no front door, it lies out of the rooms' bounds by | 80 px | the match spec's `invader_margin` (Main's export) |
| ... its members packed on rings round it, apart | 40 px (twice `spawn_clearance`), 6 rings | the match spec's `spawn_clearance`, `match_spawner.gd` `GROUP_RINGS` |

## Baseline

AI against AI, with squads following their leaders and before them (main, e6cdbf7: every member decides on its own, nobody
follows), scored by `tools/match.py` (`--seed 101 --rounds 10 --timeout 180`: seeds 101 to 110, one round each) on
2026-10-19 from 11:55 to 12:19, the two trees alternated (squads 3v3, main 3v3, squads 5v5, main 5v5). Each tree was a scratch
`git worktree` of its commit; for each run a headless game ran on its own command port from an uncommitted scene inheriting
`main.tscn` with `defender_count` and `invader_count` set, spectator mode, the default loadouts, and the real Von server (one shared
server). A round ends when one side is wiped out (the `match` verdict, `scenes/general/command_server.gd` `verdict_of`, deciding by
General's `MatchVerdict`, the rule the MatchHUD decides by too). Main's own `match` verdict calls a match larger than 1v1 a draw at
its first death, so main's tree was run with the squads tree's `scenes/general/match_verdict.gd` and the calls to it in
`command_server.gd` and `match_hud.gd` copied onto it, and nothing else. The round length is the `match` line's `elapsed`, over the rounds a side won. The load is the 1-min average
from `uptime` before and after the run, on 12 cores; the machine was shared, and other work raised it during the runs.

| Size | Tree | Invader wins | Defender wins | Draws | Timeouts | Round length, mean (min to max) | Load |
|---|---|---|---|---|---|---|---|
| 3v3 | squads | 10 | 0 | 0 | 0 | 29.6 s (4.0 to 66.9) | 3.95 → 11.67 |
| 3v3 | main (e6cdbf7) | 9 | 1 (seed 105) | 0 | 0 | 31.8 s (14.2 to 47.7) | 12.26 → 8.15 |
| 5v5 | squads | 10 | 0 | 0 | 0 | 35.0 s (13.1 to 50.5) | 7.57 → 7.81 |
| 5v5 | main (e6cdbf7) | 7 | 2 (seeds 104, 105) | 0 | 1 (seed 107) | 32.4 s (16.2 to 82.0), 9 rounds | 7.34 → 11.30 |

Main's 5v5 timeout on seed 107 was still undecided at 180 s, one defender and three invaders standing. A run of the squads tree
before its audit fixes, the same morning (06:52 to 07:03, load 3.07 to 7.28), gave the same tallies: 10 invader wins in 10 at both sizes.

## Performance

**Since the match builder (issue #95).** The three match guards (`match_5v5_stress`, `match_10v10_stress`, `grenade_match_stress`) build
their match through `MatchBuilder` as Main builds one (`s.declared_match`): the invader team beside the front door with its plates and grenades,
styled and ranked, one squad a side, every member but the leader following it. `perf/match_10v10_team_stress` is folded into
`match_10v10_stress`, which keeps its premises (one squad a side, the rank rule's leader, every member but the leader following, contact
within `Perf.MATCH_CONTACT_WITHIN`) and its logs; the 5v5 and the grenade match now require contact too (`Perf.warm_until_contact`). So `tools/run_tests.sh
--domain=perf` runs eleven guards. Re-baselined headless (`--domain=perf --verbose --summary --no-lint`, three valid runs a side, each
started at a 1-min load under 3.5 with no other headless Godot and discarded if the load went over 4; before 4af0b43, after 91400e6's
guard code, measured before the branch was rebased onto #81), medians in ms per frame, avg / p95 / max against 16.7 / 20 / 33.4 (bold
misses):

| Guard | Before (4af0b43) | After (91400e6) |
|---|---|---|
| 10v10 match (`match_10v10_stress`) | 10.88 / 14.69 / 22.42 | 11.74 / **22.04** / **65.34** |
| 10v10 team match (`match_10v10_team_stress`) | 8.91 / 11.94 / 14.41 | (folded into the 10v10) |
| 5v5 match (`match_5v5_stress`) | 5.93 / 9.10 / 12.47 | 5.55 / 11.31 / 22.89 |
| grenades in a 5v5 match (`grenade_match_stress`) | 10.16 / 15.09 / 24.20 | 10.58 / 17.29 / 33.18 |

The averages barely move; the tails do, because the guards now measure a real match. The 10v10's window holds 10 to 16 NPCs knowing a
hostile and 21 to 48 shots (the team guard's held 2 and 0), and its p95 and max miss in every run: one invader's decision that weighs its
grenades (the throw spots and the escape from the burst, in its decision snapshot) takes 20 to 47 ms in one frame. With the invaders' stuns
and frags set to 0 its max fell to 29.02. By the user's decision the guard stays red on a quiet machine and the standard is untouched; the
fix is #98. The 5v5 and the grenade match medians pass, each grazing or missing its max in one run of three. The other guards' numbers are
in the `domain-testing` skill.

**Re-measured after the review fixes** (7d067bf: the give-way's look-ahead cut to the walk left and the follower's catch-up run, both
on a per-frame path, and the three guards on one `Perf` helper). `tools/run_tests.sh --domain=perf --verbose`, three runs back to back on
2026-10-24 from 12:35 to 12:38, each started at a 1-min load under 4 (3.60-3.96, 3.62-4.22 and 3.15-3.32 through the runs, sampled
every 10 s; none discarded), medians avg / p95 / max: 10v10 12.11 / **25.91** / **51.13** (p95 23.19 to 34.42, max 50.72 to 51.77), 5v5
5.28 / 9.22 / 23.40, grenades in a 5v5 match 10.80 / 17.14 / **35.51** (max 25.30, 35.51, 50.28). Within the runs' spread of the
medians above: the 10v10 misses its p95 and max in every run (#98), the grenade match its max in two runs of three, and the 5v5 missed its
max in one run of three (38.26), as before. Every other guard held its budget in all three runs. The runs below are from before issue
#95.

**With squads following their leaders (LD19 to LD28).** `tools/run_tests.sh --domain=perf` (twelve guards, the eleven below and
`perf/match_10v10_team_stress`: the 10v10 guard's match, the same house, placement and scripted Von, with one squad a side bound as Main
binds it, so its members follow their leaders), `--verbose` for the `PERF` lines, with the squads, 3 runs back to back on
2026-10-19 from 12:36 to 12:39, the 1-min load 3.19 → 3.08, 3.08 → 3.29 and 3.29 → 4.06 (`uptime` before and after each, on 12 cores;
none discarded). Each passed 12 of 12. In ms per frame, avg / p95 / max, against the smooth-match budgets 16.7 / 20 / 33.4:

| Guard | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| 10v10 match (`match_10v10_stress`) | 10.80 / 14.79 / 20.18 | 10.45 / 13.72 / 18.40 | 10.37 / 13.87 / 19.87 |
| 10v10 team match (`match_10v10_team_stress`) | 7.59 / 9.16 / 13.11 | 8.25 / 10.76 / 13.42 | 11.06 / 15.07 / 19.34 |
| 5v5 match (`match_5v5_stress`) | 5.83 / 8.65 / 12.38 | 5.06 / 8.90 / 12.99 | 5.82 / 8.90 / 12.73 |
| grenades in a 5v5 match (`grenade_match_stress`) | 8.65 / 13.97 / 22.06 | 8.86 / 14.29 / 24.14 | 10.88 / 15.70 / 24.06 |

The team guard opens its window only once the sides are in contact (a shot fired; the warm-up runs on past its 6 s for at most
`Perf.MATCH_CONTACT_WITHIN`, 20 s, and the guard fails without it), so what it measures is the teams' fight; in all three runs the first shot came
within the warm-up (`PERF 10v10 team match contact at 6.0 s`), and the window ended with 13, 18 and 9 members following. The guard
also requires that some NPC knows a hostile as the window opens (`known_contacts_for_display()`): in 8 runs on 2026-10-19 (14:10 to
14:12, load 3.97 to 5.54) two NPCs did each time, while shots fired inside the window came in 1 of those 8 (12 shots) and 1 of 5 runs
just before them (11 shots), none in the rest, so the shots are logged, not required. Every frame
guard of all three runs was within its budget: the worst frame of these four guards, 24.14 ms (the grenade match), is under the 33.4 ms
max, so the budgets stand. Then those four guards ran `--repeat=10` in one process (12:41 to 12:46, load 3.59 → 4.53): 40 of 40 passed.
Over the ten runs of each, avg / p95 / max ranged 4.30 to 6.60 / 7.31 to 10.34 / 11.04 to 30.80 (5v5), 9.88 to 11.15 / 12.85 to 14.72 /
15.30 to 24.78 (10v10), 6.55 to 9.46 / 8.16 to 11.87 / 11.49 to 17.05 (10v10 team, contact at 6.0 s in all ten) and 8.51 to 11.98 /
12.75 to 19.18 / 19.85 to 30.73 (grenades in a 5v5).

**Before the audit fixes.** The same three `--domain=perf` runs on the squads tree before its audit fixes, the same morning (07:42 to
07:44, load 2.06 to 2.70, the team guard not yet waiting for contact), gave the 10v10 9.81 to 10.59 ms avg (max at most 18.95), the team
match 7.04 to 9.74 (max at most 20.07) and the 5v5 4.36 to 5.85 (max at most 14.62). Runs 1 and 3 passed 12 of 12. Run 2 passed 11: the log gate failed
`perf/crowd_deaths_stress` (ten puppets killed at once; no AI, no squad) on one engine error, "Invalid polygon data, triangulation
failed" (`canvas_item_add_polygon`), on the frame the deaths were dealt. That guard then passed 40 of 40 on its own (four at a time), and 300 more runs
(six at a time, so their frame times do not count) logged no such error, with every polygon draw on its path that has no triangulation check (`FillBatch.fill` and `fill_convex`, a limb's
strip, the trunk, the shoulders' shadow, `Deformation.draw_shape` and `draw_wall`) checked for an outline the engine cannot cut. The
error is not reproduced and its source is not known.

**Before following.** The perf guards (`tools/run_tests.sh --domain=perf`, eleven tests then) with LD13 to LD18 and the stack geometry of `docs/tactical-entry.md`
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
