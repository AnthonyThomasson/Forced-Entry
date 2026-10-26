---
name: domain-ai-entry
description: Deep implementation detail for the AI TACTICAL ENTRY module (scenes/ai/behavior/entry.gd and its parts in entry/, + the entry guard in behavior_entries.gd) — how an NPC gets through a doorway into a room as police and soldiers do, alone or as one of a team over the radio: the phase machine (approach / stack / pie / bang / cross / corner / clear / cover / rear), the team radio steps (claim, ready, bang, going_in, in, clear, cover, rear, done, abort) and their heartbeat, the barrier and follow order, slicing the pie, crossing the fatal funnel without stopping, the corners (buttonhook, hard corner), clearing the room and holding it (covering the doorways on, rear security), the bang (a stun thrown in first), topping off at the stack, the last man facing back, a short room taking two, no crossing with a hostile in view, bodies on the way, commitment, the entry guard's detours and the pass-by securing of a doorway walked past, walks kept out of the doorway views (E18), the split stack (E19), slots in any stack room (E20 to E22: open floor, tail, dead-end refusal, the other side), same-frame claims and the move-up (E2), a stack a leader ordered (docs/leadership.md LD9: its side, mode, wait for every recipient and its way read before the claim; LD13 held for the leader's go; LD14 a frag thrown in first; LD17 the human leader waited for and the joiners' clock; LD24 / LD25 a join, the leader's own stack bringing its team in), and the read-outs for the entry overlays. Use when editing entry.gd, its parts (entry/entry_*.gd) or the behaviour's entries part (behavior_entries.gd: guard / apply / finish), or working on stacking, the pie, crossing, corners, room clearing, rear security, a stun entry, the entry guard or an NPC walking into an uncleared room; the spec and its tests are docs/tactical-entry.md (E1 to E22) and tests/ai/entry/. Complements `domain-ai-behavior`, `domain-ai-perception` (the doorway geometry, agent_entry.gd), `domain-ai-watch` and the `architecture` skill.
---

# AI · Tactical entry (`scenes/ai/behavior/entry.gd`, the entry guard in `behavior_entries.gd`)

The spec and the tests are `docs/tactical-entry.md` (E1 to E22; the bang is also `docs/grenades.md` G18; an ordered stack `docs/leadership.md` LD9, LD13, LD14 and LD17) and `tests/ai/entry/`
(the bang's fallbacks in `tests/ai/grenade/bang_fallback_*`). Von only chooses the doorway (the ENTER or STUN ENTRY tactic,
`domain-ai-decision`); the choreography is this phase machine, so it runs with the server down. The doorway geometry (stack slots,
pie arc, corners, capacity) is the perception's (`agent_entry.gd`, "Entry geometry" in `domain-ai-perception`), read through the
`AgentPerception` wrappers; the team's claims off the radio and every slot rule are the perception's stack module
(`ai/perception/stack/`: `StackClaim`, `ClaimLedger`, `DoorStack`, "The stack" in `domain-ai-perception`), read as one `DoorStack` a
tick (`AgentPerception.entry_stack(opening, into)`, `claim.read_stack`: `claim.stack`; a rule that reads a claim keeps to the **stale
claim** rule there); the room is cleared by sight with `search_coverage.gd`
(`domain-ai-coverage`). The human's side of the same radio is `PlayerStack` (`domain-ai-team`).

## The module

`entry.gd` is a `RefCounted` built in `Behavior.setup`. It holds two data leaves, built once, in `scenes/ai/behavior/entry/`: `state`
(`entry_state.gd`: the entry's own state, which `Behavior` reads, below, with the doorway's geometry `geo`, the phase's `clock` and the entry's
`time`) and `world` (`entry_world.gd`: what it works with, `squad`, `loco`, `perception`, `coverage`, `combat`, `eyes`, `character`, `self_id`
and `tuning`). `Behavior.setup` hands in the NPC's tuning (`world.tuning`, read live, below), then `setup(loco, perception, coverage, eyes, combat)`
captures the locomotion, the perception, the room coverage, the watch module (where a walker looks) and the combat module (the tactical reload and
the bang's throw); `bind(character)` (from `Behavior.bind`) hands in the NPC's body once. `Behavior.apply_config(squad)` hands in the squad
(`world.squad`). Neither leaf holds the entry, so no reference cycle forms (`tests/ai/ai_parts_free_suite.gd`).
Its work is split into ten parts beside the leaves, each built once with the entry on its `state` and `world` and held as a public var
(`entry/entry_<part>.gd`, a preload const, no `class_name`): `claim` (its slot in the stack and where it stands, the stack heard this tick, the
move-up, the back of the stack), `approach` (the walk to the slot and what a hold on it does, with the phase changes, `approach.set_phase`, and
the top-off), `readiness` (in the slot until its turn: `ready`, the barrier, the crossing order, the last man, the security), `orders` (the
order a stack goes in under, its recipients, the leader it waits for, the go), `grenade` (the bang: who throws, the plan and the throw, the
bursts noted, the veto), `listen` (how the mode turns: the suspect room at `begin`, the late upgrade, the quiet point listening), `pie` (slicing
the pie), `sweep` (where it looks, `sweep.look_toward`, the crossing, the corner, the clear), `hold` (holding the cleared room: cover, rear, the
end of the hold) and `radio` (its steps on the team radio, `radio.say`, and the heartbeat). A part holds nothing but the two leaves: a method
that needs the entry or another of its parts takes the entry as its first parameter, `entry`, at the call, and never keeps it, so no part holds
its `RefCounted` owner. The 19 public methods stay on the entry, with the constants more than one part reads (`Entry.WAYPOINT_REACH`,
`Entry.SPOT_SPACING`); a constant one part reads is that part's. A member read off another part is public on it, its underscore and any prefix
the part's name says dropped (`_order_id` is `orders.id`, `_bang_stage` `grenade.stage`); one used only inside its part keeps its name.
- `begin(params) -> bool` — start from an ENTER leaf's `opening`, `into`, `slot` and `bang`, the guard's pass-by `secure`, or an ordered
  stack's `order_id`, `bang`, `mode`, `wait_go`, `go` and `stack_at` / `split` (below), a join's `join: true` (its order's id left out,
  below); false when the doorway is unknown (the leaf is dropped and the NPC re-decides).
  `step(delta) -> bool` — one tick; true once it is over.
- `laid(params)` (the doorway's slots are laid: the geometry has `wall_n`, so only once the nav map is baked; `Behavior.entries` waits up to
  its `ROUTE_WAIT` before `begin`), `approach_points()` (the waypoints still to walk, then the slot: what `Behavior.entries._detour_first` reads),
  `state.held_back` (set by `Behavior.entries` while it reads an ordered entry's way: `take_calls` gives nothing yet).
- `abandon()` (radio `abort`, only once a step of this entry went out, `radio.on_air`; else the queued calls are dropped), `reset()`, `committed()`, `throwing()`, `take_turned()`, `take_calls()`, `take_thrown()`, `way_blocked() -> bool`,
  `expects_burst(plan)`, `holding_for_go()`, `holds_crouched()` (all below).
- State read by `Behavior` and the overlays: `state.phase`, `.opening`, `.into`, `.slot`, `.side`, `.solo`, `.secure`, `.secured`, `.bang`,
  and on its parts `hold.covering`, `pie.seen_fraction`, `pie.sides`, `sweep.corner`; `debug()` / `debug_view()` (the read-outs, below).
- Set every tick by `Behavior.entries.apply` from the watch stage: `state.gaze_held` and `state.hostile_in_view` (below).

## The phases and the team

`Behavior` adopts an ENTER or STUN ENTRY leaf, starts the entry on the next tick (`entries.pending`, then `begin(params)`: it reads
the doorway's geometry and its stack off the perception, `entry_geometry` / `entry_stack`, and runs the stack's claim chain,
`DoorStack.claim(me, want)`, as `claim.keep_slot` does: it claims the lowest slot the claims heard leave free
(`slot_for(me)`, `me` = `{ id, slot: 0, frame, pos }`: two claims on one slot made on the same `GameClock` frame and side settle by
distance, the nearer keeping it; the option's `slot` is only the snapshot's guess; a slot past what a dead end holds, `has_slot` false, ends
it `done` with no claim) and its side (`claim.ask_side`, the entry's own weighing, the `want` it hands the chain: `claim.want`, `entry_stack_side(stack)`, the team's, `DoorStack.team_side`, or its own when the way there
crosses the doorway's view, E19), then stands where `settle` puts it (`claim.stand`; `DoorStack.settle(claim.me())`, `claim._settle`, for a slot taken otherwise: the side asked for while its wall has room, else the other,
E21; its place in that side's file; the slot's point, E20; a claim still on a slot a member moved up into counted at the slot it freed) and
then calls `step(delta)` each tick until it reports done. `claim.me()` is this NPC's own claim as a `DoorStack` reads a member asking about
itself (`{ id, slot, side, want, frame, pos, move_up, stuns, frags, order_* }`: it never hears its own on the radio). `claim.keep_slot`
re-picks with that claim through `DoorStack.claim` (its side weighed again, unless it is the point, only when the team's side changed), so a settled claim keeps settling, and a slot
pushed past what a dead end holds `claim._refuse()`s (radios `abort`, stops, `done`; an ordered member's next decision is the ORDER node's
`hold_<opening>`, refused, `docs/leadership.md` LD9). Phases:
`approach` (to its stack slot, its place in its side's file (`claim.place`, `DoorStack.place`); an open-floor or tail slot (`claim.on_wall()` false: past
`wall_n`) by the plain way, no waypoints; a wall slot: if on the wrong side of the door, out from the wall and across far out first (`approach._cross_depth`:
`CROSS_DEPTH` but a body, `CROSS_INSET`, off the stack room's far wall), or round the view when the way round exists (`approach._way_round`); then to a
point past the slot and along the wall into it, so it never walks the door's axis close in; `approach.enter_approach(stack)`: that point is `APPROACH_LEAD` (60 px) past the slot, or
`Locomotion.PASS_CLEARANCE` (32 px) short of the next slot along that side a teammate claims (`claim.approach_lead`, `claim.lead`), worked out again in `approach.tick_approach` when a claim heard
since brings it nearer, so the walk never aims at a teammate's body, E2; the lead shortened by `LEAD_STEP` until its points are good, each
waypoint kept in the stack room `CROSS_INSET` off its walls and on the navmesh within `WAYPOINT_SNAP` on the stack's ground, `approach._waypoint`; given up,
`abort`, past `approach.cap` = `tuning.entry.approach_time` + `approach.walk_time()`, the walk measured leg by leg on `walk_route` at walking pace, set in
`approach.enter_approach` at every re-plan), `stack` (in the slot facing
the door; radios `ready`; stepped back into when more than `StackClaim.SLOT_REACH` off it, `readiness.tick_stack`), `pie` (the point — the first still waiting in the crossing order — walks the pie arc, at each step turning its
gaze through the door until it settles plus `tuning.entry.pie_dwell`, dropping room sample points (`SearchCoverage.sample_room`)
and corners it sees: `pie.seen_fraction`, hidden corners; alone it then crosses in front, far out, and slices the other
side), `cross` (radios `going_in`; walks to its corner without stopping; `in` once past the wall plane and off the axis),
`corner` (holds it `tuning.entry.corner_dwell` looking across the room), `clear` (`SearchCoverage.begin/step`; radios `clear`
with `cleared_room` once the rest of the stack is in), `cover` (the room is held, guns on the doorways on, below), `rear`
(a member left over holds just inside the door it came by, facing out).

- **Holding the cleared room (E8).** `hold.finish` marks the room cleared, then reads the doorways on out of it into rooms not
  cleared (`entry_watch_doors(into, opening)`, outside doors and the door it came by left out) with a cover spot each:
  `COVER_DEPTH` back inside the cleared room, off the doorway's axis on the NPC's side, the gun aimed through it. With a
  team, each member claims the nearest doorway no teammate's `cover` call names (kept once its own; a tie goes to the lower
  instance id) and radios `cover` with `covering`; one left over (or, with no doorway on, the last one in) goes to `rear`,
  anyone else is done. Each member on the rear has a spot of its own (`hold._hold_rear_or_done`: by slot, the members take turns either
  side of the doorway just inside it, each pair `SPOT_SPACING` (44 px) further along the wall), so two never share one. The hold ends when a teammate seen holding (`cover` / `rear`) is no longer (it radioed `done`,
  `abort`, or claims another doorway), or after `tuning.entry.cover_time` (cover) / `rear_security_time` (rear); a member that
  held radios `done`. Alone, it turns its gaze through each doorway on in turn, `tuning.entry.watch_dwell` once settled, then is
  done. The heartbeat repeats the latest call whole, so `covering` and `cleared_room` stay on the radio.

- **The bang (E17, `docs/grenades.md` G18).** An ENTER or STUN ENTRY leaf with `bang: true` (and a stack that follows the first claimer's mode: every claim carries `bang`, `bang_off` and the `stuns` the member carries; one
  `bang: false` makes the whole stack quiet) adds the `bang` phase between `stack` and `cross`. `grenade._thrower()` (`DoorStack.thrower(kind, claim.me())`) picks the second of the stack (by slot, on either side of a split stack) if it carries a stun, else the lowest slot that does, from the claims, the same on every member, never the human (it throws nothing for the stack);
  `grenade.due` (in `stack`, or in `approach` once the rest are ready) has the thrower plan the throw (`grenade._plan_bang`: a target `BANG_DEPTHS` of the way into the room, on the doorway's axis first, pulled back to the farthest point on its line the stun reaches from the spot
(`grenade._bang_aim`, `AgentPerception.grenade_reach`: a room deeper than a stun reaches, test `ai/grenade/bang_into_long_room`), at least `BANG_MIN_DEPTH` in, and a spot, its own slot or
  `BANG_STEP_ALONG` in front of the door, `BANG_STEP_OUT` out from the wall, from which the lob is clear of the jamb (`AgentPerception.can_lob`: from the thrower's hand, with room to spare either side, the same test as GRENADE's): none = the bang is given up and the stack
  goes in quietly), radio `bang`, and every member that sees the call enters `bang`. In `bang`, the thrower walks out from its slot (clear of the member ahead of it) all the way into the spot (`StackClaim.SLOT_REACH` 6 px: the lob was judged from there, and a stride short of it the jamb can be in the way), throws through `Combat`'s `throw` (`throw.begin` / `throw.step` /
  `throw.released`), and walks back; everyone holds its slot turned away from the door (`sweep.look_toward` away along the door's normal; the watch stage does not turn it to a threat in `bang`). On a stun its own team threw bursting in the room (`AgentPerception.last_burst` with `team`: the stack's own, or one thrown by GRENADE)
  the stack is over the bang (`grenade.over`): the point crosses at once, no pie, and E14's hold on a hostile in view does not apply for `BANG_WINDOW` s; no top-off is waited for. A call not answered by a burst within `BANG_BURST_CAP`
  or never made within `BANG_CALL_CAP` gives the bang up (`grenade.give_up_bang`: `bang` false and `bang_off` true on its claims, a veto), and so does a teammate's veto (its thrower had no lob or lost its stun): a member in `stack` or in `bang`
  follows it at once, its own claims saying quiet too. A member that began in bang mode and hears a claim made before its own say quiet goes quiet without a veto (`grenade._go_quiet`: the first claimer's mode). Tests: `tests/ai/grenade/bang_fallback_*`.
- **The thrower is committed (E17, issue #51 R16).** `Entry.throwing()` (phase `bang`, `grenade.stage` `go` or `throw`: from its call until the stun leaves its hand) makes
  `committed()` true: the controller starts no decision and `set_leaf` adopts none, so a hostile seen on the walk out or in the wind-up does not make it leave. A leaf dropped
  meanwhile sets the behaviour's `task.held`; once `throwing()` ends (the release, or the bang given up) `entries.apply` raises `task.resolved` with `task.resolve_reason` "after the bang" and it decides
  again from where it stands (a forced decision held meanwhile, the cadence's `forced`, starts then too). The caps end it too (`BANG_BURST_CAP`, the stun lost, `way_blocked` in `go`). Test:
  `ai/grenade/bang_kept_through_fight` (real Von).
- **Go in on the burst (E17, issue #51 R8).** `grenade.note_burst`: besides the bang phase's own stun, a stun or frag its own team threw (`last_burst.team`) going off in the room while
  this member is in `approach` / `stack` / `pie` sets `grenade.over`; `grenade.note_burst_before` (at `begin`) does the same for one within `BANG_WINDOW` before the entry began (a GRENADE,
  then the walk in). With `grenade.over` the point slices no pie (a pie under way is dropped, no second side) and crosses as soon as `readiness.stack_ready`, no top-off; E14's hold is lifted while
  `grenade.in_bang_window()` (3 s from the burst, `grenade._burst_at` negative for one before `begin`), in `stack`, `readiness.follow` and the pie alike; no upgrade to a bang follows. Test: `ai/grenade/burst_then_cross`.
- **A suspect room means a bang, for every entry (E17, issue #51 R10).** `begin` makes the entry a bang one when its leaf asks for it (STUN ENTRY) or when the stack carries a stun
  (`grenade.stack_has_stun`: this NPC, or a claim's `stuns`) and the room is suspect now (`AgentPerception.room_suspicion(into)` not empty), whatever brought the NPC to the doorway: an ENTER or a
  walk the entry guard turned into an entry; a pass-by (`secure`) never is. A team already claiming the doorway still sets the mode (the first claimer's). A bang its leaf did not ask for sets
  `readiness.turned` (`take_turned()`), so an ENTER is re-adopted as `search/stun_entry/<door>` (the controller's radio, `npc_comms.gd` `on_entry_turned`); a guard's entry keeps its walk's name. Tests: `ai/entry/entry_guard_bang_suspect_room`,
  `entry_guard_quiet_unsuspected_room` (scripted).
- **A late reason turns a quiet entry (E17, issue #51 R11).** `listen.maybe_upgrade`, every tick in `approach` / `stack` / `pie` while nobody is crossing (`grenade.crossing`: a claim at `going_in` or through), the stack carries a stun and
  no member gave the bang up: when the room's suspicion (`AgentPerception.room_suspicion(into)`, `AgentSuspicion` reason ids, read every `SUSPECT_EVERY` 0.25 s) holds any reason (one that came up after `begin`, or one
  this member knew when it joined a quiet stack, or a stun that joined the stack), or a teammate seen quiet in this entry (`listen.quiet_seen`) now says bang, it sets `bang` and `listen.upgraded` and radios its
  claim; a point in `pie` goes back to `stack`. An `listen.upgraded` member waits for the rest to follow (a quiet teammate is not a veto for it; `grenade.banging` counts its own turn, so a point that turned in its slot holds for the bang rather than starting the pie) and gives the bang up if someone crosses first. A claim without `bang` (the human's
  `PlayerStack`) reads as bang, so it never holds a stack back nor turns one. Tests: `tests/ai/grenade/quiet_entry_turns_bang`, `quiet_entry_crossing_stays_quiet`, and `stun_entry_footsteps_heard` (real Von).
- **A quiet stack listens first (E17, issue #51 R17).** In `readiness.tick_stack` the point of a quiet entry holds in its slot (`listen.listening`) for `tuning.entry.listen_time` s
  (3 s) from `readiness.ready_at` before `pie.start_pie`, while a late reason could still turn it (`listen._may_turn`: the stack carries a stun, nobody crossing, no `bang_off`,
  not over a burst, not `secure`; `listen.maybe_upgrade` uses the same test). `state.hostile_in_view` or `AgentPerception.under_fire()` ends the hold for the entry (`listen._listen_over`). Tests:
  `ai/grenade/quiet_entry_listens_at_stack`, `quiet_entry_listen_turns_bang`, `quiet_entry_listen_ends_on_hit`, `quiet_entry_listen_ends_on_hostile_in_view` (scripted).
- `Entry.expects_burst(plan)` (the evade reflex's plan, `AgentPerception.evade_plan`) makes `Behavior.grenades.set_evade` leave the stack to the bang's
  hold: a stun of a stun bang while the phase runs; a frag of a frag bang (LD14) in flight, or come down (`landed`, at `lies`) where this
  member's slot is out of its zone (`AgentPerception.in_grenade_zone`; a frag that reaches the slot is evaded as anywhere).
- **The stack moves up (E2).** `claim.move_up_now(delta)`, first in `readiness.tick_stack`, every `MOVE_UP_EVERY` (0.25 s) while this member
  stands within `StackClaim.SLOT_REACH` of its slot, has not begun the pie (`pie.begun`) and is not mid move-up. The rule part is the
  stack's (`DoorStack.move_up_vacancies(claim.me())`: none once anybody's claim says `pie`, `bang`, `going_in` or through; each a lower slot on
  its own side (either row) whose holder is at `claim`, not `human`, not itself `move_up`, the only claimant, whose slot stays on this
  member's side with the two swapped, with that swapped stack and the point it would stand on); the walk and the latecomer are the
  entry's: it takes the nearest vacancy not in `claim._moved_for` (one move per vacancy, `"<holder id>:<slot>"`), within `MOVE_UP_REACH` (66 px) and nearer than the holder's radioed `pos`; a plain walk
  (`walk_route(...)["plain_len"]`) at most 1.5 x the distance + `PASS_CLEARANCE`; and not while the holder's way to the slot it would
  take runs through the step (`claim._latecomer_crosses(h, vacancy)`: the holder's worst-case place, its newest known one, seen in
  `Locomotion`'s `crowd.bodies` or radioed, less its age x its `movement.walk_speed()`, is within `MOVE_UP_REACH` + `MOVE_UP_MARGIN` (one more step) of
  this member's slot, and the straight way from there to that slot passes the vacancy closer than `Locomotion.PASS_CLEARANCE`: the
  crossing, not the distance alone, so a holder following on the same lane is let in; tests `stack_move_up_waits_for_near_latecomer`,
  `stack_move_up_lets_follower_in`). It keeps its `claim_frame`, sets `claim.move_up` to the slot it
  left (radioed as `move_up` until `readiness.say_ready` clears it), drops its waypoints and radios a claim; `DoorStack.slot_for` gives the latecomer
  the freed slot (a move-up holds against a plain claim). Every reader's `DoorStack` (this member's `settle`, the human's markers, the
  squad's `stacks`) counts the latecomer's claim at the old slot meanwhile.
- **Tail and dead end (E20).** A tail member (`claim.tail()`: `DoorStack.tail`, past the open floor, in the room beyond the stack room's other
  doorway) says ready, holds for a held stack's go, then runs `readiness._tick_security` as E13's left-over does: it never crosses. A slot no dead
  end holds is never claimed (`begin`, `claim.to_back`, `claim.keep_slot` above).
- **Top off at the stack (E11).** A member short of a full magazine with a spare swaps it in while `stack`ed, the one lull:
  `approach.topping_off` (entry.gd) calls `Combat.top_off` (a tactical reload: `inventory.select_slot(inventory.gun_slot())`, `ammo.reload()`) from `readiness.tick_stack`
  before the point starts the pie or a follower crosses, and from `pie.tick_pie` before the point (or a split stack's other front man) crosses (a pie that fired),
  standing still and waiting for the reload to end. Skipped while a hostile holds the entrant's eyes (`state.gaze_held`: it fires) and
  past `TOP_OFF_CAP` (8 s) per entry; never in `cross` (the watch stage's empty-gun reflex is off while committed too).
- **The last man faces back (E12).** In `stack` a member that is the last of its side's file with two or more crossing ahead of it (`readiness._covers_rear`;
  one per side on a split stack) looks along the wall away from the door (`spot + along * side * 300`,
  at 3x `tuning.coverage.look_rate`) instead of at it, until the member ahead of it is through (`readiness.turn_at`); then it looks at the door as every
  follower does. A threat in sight takes the eyes first (the watch stage).
- **A short room takes two (E13).** The doorway geometry's `capacity` (perception, `domain-ai-perception`) is 2 for a room with a side under
  `tuning.entry_geometry.short_room` (150 px). A member with that many ahead of it in the crossing order, both sides counted (`readiness._holds_outside`), stays in `stack` running `readiness._tick_security`: still,
  facing back (E12), until the room is called clear by the team and a teammate that held it moves on (`hold.team_moved`) or
  `tuning.entry.rear_security_time` has run out since, then radios `done`. It never crosses. Not held back once nobody ahead of it is on the radio and
  the room is not called clear (it takes the lead); gives up (`abort`) after `SECURITY_CAP` (30 s) with no clear call.
- **No crossing on a hostile in view (E14).** `Behavior.entries.apply` hands the entry `state.hostile_in_view` (`entries._hostile_in_view`: the watch
  stage's threat is seen now, or was within `tuning.watch.lost_gaze`, and `Combat.has_line_of_fire` holds: in range on a clear line, so it
  can be engaged from outside; a hostile seen over low cover with no line of fire holds nothing). While it is set the pie holds where it stands
  (no next step, no crossing; the watch stage fires), a follower does not cross after the member ahead, and nothing else changes: it
  crosses once the hostile is out of view. Whatever order brought the NPC to the doorway (ENTER, or a COMBAT advance / engage the
  entry guard sent through an entry) meets the same rule, because it is the entry's, not the order's. An NPC under fire still drops
  a detour and walks in (the guard's exemption), but not into the room the shots came from (E9); for `BANG_WINDOW` after its own team's
  burst in the room the hold is lifted (R8, below).
- **Barrier and order.** The point crosses when every other claimant has radioed past `claim`, or `tuning.entry.ready_timeout`
  after it was ready (restarted when the stack grows; under an order, from `readiness.all_in_at`, LD17 below). A follower crosses `tuning.entry.follow_gap` after the member ahead of
  it in the crossing order radioed `in` (`readiness.follow`). A member still at `claim` once the one behind has waited the timeout is dropped from the order.
  The crossing order is the stack's (`DoorStack.crossing` / `ahead`, read by `readiness.members_before` / `readiness.members_ahead`): by slot, or on a split stack the point, the other side's front man, then the sides in turn.
- **A split stack (E19).** A member whose way to the team's side crosses the doorway's view stacks on its own side (the claim carries
  it); `claim.keep_slot` weighs the side again only when the team's side changes (`DoorStack.team_side`, the point's once known). Its place in its
  side's file is its slot less the claims ahead on the other side (`DoorStack.place`). The other side's front man (`readiness.slices_own_half`: all
  ahead of it on the other side, no pie yet, not a bang entry) slices its own half of the pie from `stack`, radios `ready` only then
  (`readiness.say_ready`; everyone else radios it on reaching its slot), and crosses after the point's `in`. Rear spots are counted from the
  point's side (`claim.lead_side`), the same for every member.
- **Corners.** Point: the door-wall corner on its own side (buttonhook); alone, the door-wall corner on the side away
  from where it ended the pie; on a split stack, the far side's door-wall corner, hard first (the criss-cross). Second: the hard corner
  on the other side from its own (on a split stack, the point's side). Later members: a spot inside off the axis, `SPOT_SPACING`
  apart.
- **Bodies on the way.** Every phase walks through `Locomotion.move_to`, so a member goes round a teammate at rest, stops short of
  one on its slot or spot and takes a free spot beside it (an approach waypoint counts as reached there too, `world.loco.reached`), and gives
  way to a walking one. The crossing never stands in the funnel except while `Locomotion`'s `crowd.holding()` (a body in its way). A walk a body
  seals and stays in re-plans (`Entry.way_blocked`, called by `Behavior._way_blocked` on `Locomotion`'s `crowd.take_blocked`): the approach drops
  the waypoint it was walking to and each next one the hold seals too (`approach.drop_sealed`: within `StackClaim.SLOT_REACH` of the slot, or whose plain way
  passes the body holding it, `Locomotion.seals`) and goes on to the first it does not (E19's point out from the wall on another way is
  still tried; test `entry_held_walks_unsealed_waypoint`). With none left, and on a held walk straight into the slot (no waypoints), it walks on
  into the slot unless the slot is sealed, by a body between it and the slot, not on it (`approach._slot_sealed`: a holder, `held_at()`, within
  `Locomotion.PASS_CLEARANCE` of the slot is Locomotion's body on the goal, no seal: the walk goes on to a free spot beside it, test
  `ai/movement/npc_dest_taken_stops_nearby`; else `Locomotion.seals(slot)` and `AgentPerception.entry_slot_reach(slot, bodies)`
  is 0, no route on the plan map reaches the slot, or ends within a last leg of it walked plain clear of them, with `approach._standing_bodies()`
  standing in it at body width: `Locomotion`'s `crowd.held_at()`, the holder, and every body at rest in `crowd.bodies`, under `Locomotion.REST_SPEED`, seen
  now or within `SEEN_FRESH` 0.5 s (a stale last-seen point must not give the slot up), but a teammate of this stack still at `claim`, on its way; a
  map not baked yet, -1, is no verdict: the member keeps its slot and its walk, and the next re-plan asks again; `approach.tick_approach` asks for the map as soon as
  the walk is held, so it is baked by the re-plan); a member walks round by the hall that way rather than give its slot up (test
  `entry_last_leg_sealed_goes_round`). Until the member has walked `Locomotion.HOLD_MOVED` from where a hold dropped its waypoints
  (`approach.dropped_at`, cleared by `claim.to_back`), a waypoint a re-aim refills that the hold still seals is weighed at once (`way_blocked` again,
  `approach.tick_approach`), so a re-aim never undoes the drop. With the slot sealed, a member the stack keeps from its slot takes the back of the stack (`claim.to_back`, `DoorStack.back_slot`: the slot
  behind the last claimed, if the doorway has it, radioed as a new claim; E2 goes by arrival), and with no slot to take gives the claim up (`abort`; `Behavior`
  re-decides with `task.resolve_reason` "way blocked", or a detour hands the walk back to its order); a member held by a teammate of the same stack still on its way to its own slot (`approach.held_by_forming`: `Locomotion`'s `crowd.held_by()` is a
  claim at `claim`, not `human`, held under `HELD_BY_FORMING_CAP` 3 s of standing held, `Locomotion`'s `crowd.held_time()`, which a walk aimed
  again while it stands does not restart: test `entry_held_cap_despite_reaim`) keeps its slot and waits (`approach.forming_wait`;
  `approach.tick_approach` ends the wait when that hold ends, and weighs the whole rule again, `way_blocked`, when the walk is still held: past
  the cap, or now held by someone else; two members holding each other wait out the cap; tests `entry_held_by_forming_stack_keeps_slot`,
  `entry_held_by_forming_stack_cap`); a pie step is skipped; the thrower
  gives the bang up; a crossing waits out the first signal (the one ahead moves on into the room), then gives the entry up if still
  outside the wall plane, or takes its corner where it stands once through; a corner, cover or rear spot is held where it stands and
  the room is covered from there. An entrant walks all the way into its corner (`CORNER_REACH` 6 px): in a small room a corner
  a stride short sits in the doorway of the one crossing behind it. E13's capacity counts a member's place in the stack (how many
  claim a lower slot), not its slot's number, since a member that took the back leaves its old slot empty. A member back in `stack` stands where it was held (its place). Tests: `entry_held_walk_replans`,
  `stack_ai_goes_round_player_in_slot`.
- **Commitment.** `committed()` is true while crossing (and while the bang's thrower throws, above); the controller starts no decision then (a forced one waits),
  so a hit or a hostile seen in the doorway is fought once the NPC is through. Posture stands throughout, and it never
  runs, not even under fire: a running character cannot shoot, so a sprint to the stack or through the doorway would
  be a lowered gun at the worst moment (test `entry_never_runs`).
- **The radio.** Steps are queued, each a claim in `StackClaim`'s fields (`take_calls()`, via `Behavior.entries.take_calls()`, which adds `opening`, `into`, `slot` and `side`), and the controller's radio part posts them (`npc_comms.gd`'s `post_entry_call`: its callout header, `_callout_header`, the same eight header fields every callout of its starts with: speaker, faction, position, status, path, label, target_id and point, plus `StackClaim.encode(claim)`, every entry field typed, a field the claim leaves out as `StackClaim.DEFAULTS` says it);
  a human invader's `PlayerStack` (`ai/team/`, `domain-ai-team`) posts the same steps for the human, so the team counts it like an ally;
  the latest is repeated every `StackClaim.HEARTBEAT` (2 s) so the claim stays live. Every call (`radio.say`) carries `claim_frame` and `claim_pos` (stamped only on a
  new `claim`, so a heartbeat or a re-claim keeps the pair same-frame settling reads), `bang`, `bang_off`, `stuns`, `frags`, `move_up` and
  `pie` (`pie.begun`, set in `pie.start_pie`), plus the order fields below. Choosing anything else `abandon()`s the entry (radios
  `abort`). Each phase change is a `GameLog` line (`--verbose` in tests).
- **The entry guard (E9).** Entry is not only for an ENTER order: `Behavior.entries.guard()` runs every tick after the
  running primitive steered (a `move` not yet arrived, an `engage` and its repositions, an `interact` walk) and reads the walk the
  nav agent was just given (`Locomotion.path_ahead()`), not the order's destination. When the perception's `threshold_ahead()`
  finds a doorway on that walk into a room that is not cleared, within `tuning.entry_guard.reach` (300 px of walking), it starts a
  **detour**: the order is stashed whole in `entries.resume`, `task.primitive` becomes `entry` for that doorway (`task.params` = opening +
  room; slot and side come from the radio as usual), and when the entry ends `entries.finish()` puts the order back and refills
  its commit timer; the walk carries on from where the entry left the NPC, and meets the next uncleared doorway the same way.
  The labels and path of the order stay, so the status line still says what the NPC is after, with the entry's phase as progress.
  Exempt: `tuning.entry_guard.enabled` off, no `tuning.entry.enabled`, an NPC under fire (not for a doorway into the room the shots came from, seen shooter or not, `fight.into_the_shots` over
  `AgentPerception.shots_from_room`, E9: the walk stops there as an entry, a bang one when the stack carries a stun (the room is suspect,
  "shots at you came from there": `Entry.begin`), the shots do not cancel it and a decision made under fire leaves it running; under fire it secures no view it passes), a leaf whose params say `entry_guard: false` (RETREAT), a
  `move` that has arrived, and a doorway whose entry was given up less than `tuning.entry_guard.rearm` s ago (`entries._guard_off`, on the
  guard's own clock). A new decision while a detour runs (`set_leaf`) replaces the paused order and leaves the entry
  running, unless it is one the guard does not apply to (`entries.guards(leaf, into)`: not a walk, a retreat, or under fire and not into the shots): then the
  detour is dropped and the entry abandoned (`abort` on the radio). Coming under fire before the crossing cancels the detour
  the same way (`entries._cancel_detour`); a crossing already under way is finished. A decision that was in flight when the NPC became
  committed to its own ENTER crossing is ignored (`set_leaf` returns) and the entry's end re-decides. `fallback()` (no decision to
  be had) abandons any entry. Tests: `tests/ai/entry/entry_guard_*_test.gd`, `entry_fallback_aborts`,
  `entry_decision_in_flight_during_cross`.
- **Doorway views a walk crosses (E15 / E18).** The same guard also looks for a doorway view the walk goes **into** without entering the room
  behind it (`Perception.passing_ahead`: the view of any doorway into a room not clear for passing, inside the house or out, exterior doors
  included, however far out from its wall; the walk comes into it from outside) nearer than any doorway it crosses, via `entries._passing_gate`,
  skipping one a teammate is working or that was just secured or given up. It meets only what `Locomotion` could not walk round (below).
  The detour is an `entry` with `secure: true`: `entry.gd` takes no team and radios nothing, stacks beside the jamb, slices one side of
  the pie (the watch stage fires at what it sees, E14 holds it on a hostile in view) and ends `secured` without crossing; `entries.finish`
  then leaves the doorway alone for `tuning.entry_guard.secure_time` (30 s). An ENTER order's own approach walk is guarded the same way
  (`entries._guard_approach`: the entry is abandoned, the doorway secured, the order restarts from `approach`), but not for a member heading for a
  stack others have claimed (`entry_stack(opening).claimed()`): the team goes to its door as one. `entries.stash_order` keeps `entry_pending`
  so a paused ENTER starts afresh. Tests: `entry_guard_secures_passed_doorway` (scripted), `entry_corridor_doors_not_passed`, `entry_secure_exterior_door_then_cross`, `entry_pass_far_out_secured` (real Von).
- **An ordered stack (`docs/leadership.md` LD9).** An `entry` leaf from the ORDER node carries `order_id`, `bang` and `stack_at` or
  `split`; `begin` keeps them (`orders.id`, `orders.bang`, `orders.side`: the side along the wall `stack_at` lies on, `orders._side_named`, 0 for a
  split) and `radio.say` adds `order_id`, `order_bang`, `order_side` to every call (an unordered member's calls carry their defaults, `order_id`
  "": `StackClaim.encode` writes every field); `StackClaim.decode` reads them back (every reader's `ClaimLedger`). A stack is ordered when this member's own entry is, or a teammate's
  claim carries an `order_id` (`orders.claim`: its own, else the lowest slot's; `orders.stack_ordered`); then:
  the side is the order's for every member (`orders.ordered_side`, through `claim.ask_side` in `begin` and `claim.keep_slot`, in place of the team's side and E19), on a split
  stack D6's (`DoorStack.split_side`, from the side it asked for, else the one it began on, `orders._pref_side`, unless that side would hold two more than the other, when the last claimer
  there, the highest slot, takes the other); the mode is the order's (`begin`; an unordered member follows it, `orders.follow_order`, D10), with
  no suspect-room bang, no first claimer's `grenade._go_quiet`, no `listen.maybe_upgrade` and no listen (`listen._may_turn` is false) and no veto but a
  `bang_off` from a claim under the same order (`grenade.vetoed`); `grenade.banging` holds whatever a quiet member says, `grenade.tick_bang` gives up only on its
  own caps, and with the stack in and no stun in it (`grenade.stack_has_stun`) `grenade.due` gives the bang up (D1: quiet, `bang_off` radioed).
  **D7:** `readiness.stack_ready` waits for every other living recipient of the order (`orders.recipients`: the live order's `to` from
  `AgentPerception.order()`, `Squad.alive` through `Entry.world.squad`, which `Behavior.apply_config` hands in from the controller's `squad`) to have radioed past
  `claim`, and the human leader that gave the order while it holds a slot (`orders.waits_for` / `orders.leads`: its `PlayerStack` claim says `leader`
  and its id is `claim.leader_id`, the live order's `leader` at `begin`; `readiness.stack_ready` is false while that claim is at `claim`, LD17), an
  unordered member `tuning.entry.ready_timeout` from `readiness.all_in_at` (`readiness.note_all_in`, each step: when every living recipient, itself among them, is past
  `claim`; or the stack last grew), all of it at most `tuning.entry.order_ready_cap` s from the first ordered `ready`
  (`orders.ready_at`, `orders.capped`); `readiness.members_ahead` drops a recipient still at `claim` only then; `solo` (`orders.alone`) is false while another
  recipient is coming; `grenade.waits_for_bang` holds an ordered bang's point in its slot until the stack is in. The claim `orders.claim` reads is
  `{ order_id, order_bang, order_mode, order_hold, order_go, order_side, order_frame, into }` (`DoorStack.order_claim(claim.me())`), and `radio.say`
  adds `order_mode`, `order_hold`, `order_go` and `order_frame` too (`orders.frame`, the `frame` of the live order at `begin`,
  `orders._held_order_frame`, -1 when unknown). Every call carries `crossed_frame` (`readiness.crossed_frame`, stamped by `radio.say` the first time its step
  is `going_in` or a through step, -1 before it, cleared by `reset`: its `going_in` is committed, so its first crossing is its only one). The order ends when the room is
  cleared (`AgentPerception.mark_cleared` ends it `done`). **The approach (D4, D11):** before the claim goes out `Behavior.entries` (`_begin_pending`)
  sets `state.held_back` (an ordered entry, not resumed from a detour, in `approach`) and `entries._detour_first` reads the whole way (`approach_points()`,
  leg by leg on `AgentPerception.walk_route(p, "<opening>><into>", from)`; up to `ROUTE_WAIT` s, standing, while that map is `pending`): a
  threshold into a room not cleared (`threshold_ahead`, not the doorway it stacks at nor a doorway into the room it enters, nor one in
  `entries._guard_off`), and, unless another recipient is coming (`entries._recipients_coming`), a nearer doorway view it passes (`passing_ahead`, not
  the room being entered, nor a doorway someone stacks at) secured. Either: `_entry.reset()` and `entries._begin_detour(gate)`, no claim made; none:
  the entry `reset`s and `begin`s again from the claims heard meanwhile and its claim goes out. On the walk `entries._guard_approach` catches what
  comes up (a threshold, team or none; a view only with no team coming). `Behavior.orders.ordered_stack()` (the
  ordered entry running, or paused behind a detour) sets `AgentPerception.ordered_walk` each tick (`errand.set_up_walk`), which keeps its walks out of the views
  (`entries.keeps_out_of_views`), counts the room its stack holds as clear (`stack_room`, D20) and, for an NPC with `tuning.entry.enabled` off, a room
  seen empty (`seen_empty`, D11).
  `Behavior.set_leaf` leaves the running ordered entry (or the detour in front of it) alone when the same order is decided again
  (`orders.same`). Tests: `tests/ai/entry/order_stack_*` (LD17: `order_stack_waits_for_leader`, `order_stack_joiner_grace`),
  `stack_dead_end_refused`, the nine `stack_reach_*`.
- **A join (`docs/leadership.md` LD24, LD25).** The squad's rally: the leader's own claim gives each follower holding no order a `stack`
  order with mode `join`, whose ORDER option is an `entry` with `{ opening, into, bang: false, join: true, order_id }` (`StackClaim.is_join(params)`,
  the one test of it the behaviour, the entry, the snapshot and the squad share, for an order, a leaf's params and a claim alike). `begin` leaves the
  order's id out (`orders.id` ""), so the entry is the member's own unordered one joining the leader's stack: the team's side and the first
  claimer's mode (D10), E17's suspect-room bang and `listen.maybe_upgrade`, the listen, the joiner's `tuning.entry.ready_timeout`, no order fields on its claims
  and `orders.bang` false. `orders.join` marks every call `join: true` (`radio.say`, encoded by `StackClaim.encode`), so its squad never takes a join's
  claim for its holder's own: one that takes over the lead holding it rallies nobody on it (D30). `Behavior` keeps the `order_id` in the leaf (the `moving` radio, `orders._live`) and leaves a join out of the ordered
  stack's guarded way (`Orders.ordered_entry`); a join whose `begin` fails (no slot at a dead end) is ended `refused`. Its order ends `done` at the
  room cleared (`AgentPerception.mark_cleared`, as any stack order), `cancel`led when the leader radios `abort` there, or `refused`; in
  `approach` / `stack` its end forces a decision at once (`Behavior.orders.join_over`, "join over"), from the pie on the entry runs to its end. Tests:
  `ai/entry/join_rally_clears_room`, `join_suspect_room_bangs`, `join_unsuspected_quiet`, `join_leader_aborts`,
  `join_cleared_before_reached`, `join_inherited_no_rally`, `ai/stack/human_leader_rallies`, `human_rally_spares_ordered`.
- **Held for the leader's go (`docs/leadership.md` LD13).** An ordered stack with `wait_go` (`orders.hold`, from `begin` or the claim it
  follows) is `orders.held_for_go()` until its go is latched (`readiness.released`): in `readiness.tick_stack` each member then radios `ready` (`readiness.say_ready`) and holds
  in its slot (`readiness.holding`, read through `holding_for_go()` while in `stack`): no pie, no listen, no bang (`grenade.due` calls none) and no
  crossing. `orders.note_go()`, each `step`, latches the go the first time any of these holds: the live order (`AgentPerception.order()`) has
  `go: true` (the leader's `go`, D13, taken by `process_order` whenever it came, before the stack was ready too), the stack's claims say it
  came (`DoorStack.released(order_id, into, since)`, `into` and `since` the order claim's room and `order_frame`: a claim under the same
  order says `order_go`, or a member of this stack, a claim under the order or the human's, is crossing or through into that room, D14: the
  human leader stepping in is its go, on a crossing begun since the order was issued (its `crossed_frame` at or after `since`; a -1 on
  either releases nothing); a claim left from an earlier entry through the doorway, under no order or another, or into the other room, releases nothing; the squad's
  `view()` reads the same rule), or the leader that
  gave the order is gone or dead (D12, beside the squad's own `auto` go); it then re-radios its latest call with `order_go`. Released, the stack
  goes on the ready barrier as any ordered stack. `Behavior.entries.apply` radios the order's `in_position` while `holding_for_go()` (`orders.say_step`). Tests:
  `ai/entry/order_stack_hold_for_go`, `order_stack_go_latched`, `order_stack_hold_human_go`, `order_stack_hold_leader_dies`,
  `order_stack_hold_ignores_earlier_entry` (a `cover` claim left from an earlier entry into the same room releases nothing), and the
  squad's `general/squad_go_and_ambush` and `squad_go_latched_off_claims`; the rule itself, `ai/door_stack_suite`.
- **A frag at entry (`docs/leadership.md` LD14).** A stack under an order whose mode is `frag` (`grenade._bang_kind()`, from `orders.claim`'s
  `order_mode`; any other bang throws a stun) runs the bang with a frag: `grenade.kind` is set in `grenade._enter_bang`; `grenade._thrower` picks among the frag
  carriers (the claims' `frags`, `grenade._carried(grenade_kind)`), by the same rule; `grenade._stack_has(team, grenade_kind)` stands for the stun check (D1 / D15: the stack in
  and no frag in it, the bang is given up and it goes in quietly); `grenade._plan_bang()` reaches with the frag's `grenade_reach` and lobs with
  `grenade._clear_lob(..., kind)`, and skips every target whose burst would put a claimed slot (`grenade._slot_points`: the claims' and its own) in the frag's
  danger zone (`AgentPerception.in_grenade_zone`, D16); `grenade.tick_bang` waits `FRAG_BURST_CAP` (7 s) for it, throws `ItemRegistry.FRAG_SLOT`, and on
  the release keeps `{ kind, point }` for `take_thrown()`, which `Behavior.grenades.poll_throw` hands the controller to radio `frag_out`; `grenade.note_burst`
  ends the phase on a burst of `grenade.kind`. Every member holds its slot crouched meanwhile (`holds_crouched()`: phase `bang`, a frag, not throwing,
  in its slot; `Behavior.gait`'s `_wanted_posture`). Tests: `ai/grenade/order_frag_entry`, `order_frag_held_then_go`, `order_frag_no_frag_goes_quiet`.
- **Keeping out of the views (E18).** `Behavior.entries.keeps_out_of_views()` (set on `Locomotion`'s `doors.avoid_doors` each tick by `errand.set_up_walk`) says whether the walk the primitive
  is on keeps out of the doorway views: a `move`, `engage` or `interact` that does not carry `entry_guard: false` (a retreat), an entry's `approach`
  (with `doors.avoid_entering` = `"<opening>><into>"`: the approach also keeps out of the room it is going into and its own doorway's view,
  cleared or not; set for any `entry` primitive), while `tuning.entry_guard.enabled` and `tuning.entry.enabled` (or an ordered stack's walk, LD9) hold and the NPC
  is not under fire or evading. The rest of an entry (stack, pie, crossing) walks plain. `Locomotion` does the rest (`domain-ai-behavior`).
- **Read-outs.** `Behavior.entries.debug()` (the controller's `debug_entry()`: opening, into, slot, side, place, solo, secure, phase, seen_fraction, pie_sides, covering, watch_doors,
  hidden_corners, corner, stack_point, team, bang, bang_stage, order_id, order_mode, order_hold, released, holding, kind), also under `entry` in `debug_state()`;
  `Behavior.entries.debug_view()` (the controller's `debug_entry_view()`; world-space, under `entry`: entry.gd `debug_view` — doorway frame, slots, pie arc and queue,
  corners with what the pie saw, role, place, the crossing order (`order`), waypoints, gaze, timers, the team off the radio (each with its
  `place`), the doorways covered — plus, under `guard`, the
  entry guard's detour, rearm list, look-ahead and the cleared rooms) for the entry debug overlays; the status line says the phase
  ("stacked at the door", "slicing the pie", "going in" ...).

## With the watch stage (`domain-ai-watch`)

Where the entrant looks is the entry's own (`sweep.look_toward`, eased through the static `Watch.ease_gaze`; a walk looks down its path,
`sweep.aim_travel` via `Watch.travel_point`), but the watch stage still runs after it every tick and has the last word: a threat in sight takes
the eyes and the gun in every phase but `bang` (the stack holds its slots turned away from the door for the stun, and the watch stage does
not turn it back). While the entry is `committed()` (the crossing, and the thrower's wind-up) the watch stage's empty-gun reflex
(`Combat.reload_if_dry`) is off. Two flags carry the stage's verdict back into the entry: `state.gaze_held` (a threat holds the eyes: a gaze step
the threat will not let settle counts as settled, so the pie does not wait on it) and `state.hostile_in_view` (`Behavior.entries._hostile_in_view`: E14,
above).

## Tunables (the NPC's `tuning.entry`, `tuning.entry_geometry` and `tuning.entry_guard`)

`tuning.entry`'s `ready_timeout`, `listen_time`, `follow_gap`, `pie_dwell`, `corner_dwell`, `rear_security_time`, `cover_time`,
`watch_dwell`, `approach_time` and `order_ready_cap` are read live by `Entry` off `world.tuning` (`world.tuning.entry.ready_timeout`, ...),
and the gaze turn speed off `tuning.coverage.look_rate`; the controller's `squad` reaches `world.squad` through `Behavior.apply_config(squad)`. `tuning.entry.enabled` (ENTER
offered, and the guard on) and `tuning.entry_geometry`'s `stack_spacing`, `wall_standoff`, `pie_radius`, `pie_steps`,
`corner_inset` and `short_room` go through `AgentPerception.apply_config(tuning)` to `AgentEntry`. The guard's `tuning.entry_guard`
`enabled`, `reach`, `rearm` and `secure_time` are read live by `Behavior.entries` (`tuning.entry_guard.enabled`, `.reach`, `.rearm`, `.secure_time`).
