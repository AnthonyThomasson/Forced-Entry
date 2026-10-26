---
name: domain-ai-team
description: Deep implementation detail for the AI TEAM module (scenes/ai/team/: player_stack.gd, squad.gd) — the human's place in an AI entry stack and each side's squad. The human's stack radio (PlayerStack, interface 17): claiming the first free slot when an allied team stacks at a doorway near the human, the split stack (E19), the dead-end refusal (E20), the other side of the door (E21), human / leader on its claims, the steps read from where the human stands, withdrawing, the human leader's own claim on stepping up to a doorway (LD24), and view() for the stack markers. The squad (Squad, interface 21, docs/leadership.md): the leader and succession (highest rank, the human when it leads, the &"leader" post), issue / resolve of a leader's request into an &"order" (defend_room / stack / go / ambush / cancel: which doorway a click means, the room "into", stack_at or split, quiet / stun / frag modes, held stacks and the go that releases them, the automatic go when the leader dies), following (follows / follow_spot: the leader's trail, the file and the ring, out of the leader's way, the leash), the rally (a join order on the leader's own claim, cancelled on its abort), the takeover from a dead human leader, view() (each member's order, step, held and follow spot, the side's stacks laid slot by slot, the trail and the leash) and the seam into perception it reuses (the stack module: StackClaim, ClaimLedger, DoorStack; AgentEntry's geometry). Use when editing scenes/ai/team/ or working on the squad, leaders, following, orders, the command menu's resolution, the stack markers' data or the human's stack claim. Complements the light `domain-ai` overview, `domain-ai-entry` (how the NPCs carry a stack out) and the `architecture` skill (interfaces 17, 21).
---

# AI · Team module (`scenes/ai/team/`)

Not a fifth AI sub-domain: two small modules beside them, the human's side of the entry radio and each side's squad. Only the
composition root's match builder (`match_builder.gd`, `MatchBuilder`, for Main's match and the Testing world alike) builds them, the AI controllers hear them over the EventBus, and the UI reads them through
`view()` (and the command menu `resolve()`). How the NPCs carry an order out (the ORDER node, `process_order`, the ordered entry and ambush)
is the `domain-ai` overview's Orders section and `domain-ai-entry`.

**The human's stack (`ai/team/player_stack.gd`).** Not a fifth sub-domain: one small module, the human's side of the entry radio
(`docs/tactical-entry.md` E16). A child of the human's character (the match builder attaches it through `MatchBuilder.bind_player`), it listens to the
`&"callout"` bus like an NPC (through a `ClaimLedger` of its own, perception's `stack/claim_ledger.gd`: its side only, within its
`callout_range`, lapsing after its `callout_ttl` on `GameClock`, LD1; either export, set, reaches the ledger at once through its setter) and, when an allied team is stacking at a doorway the human is near (`reserve_range` 300 px of walking), radios the
human's own claim for the first free slot (none in a dead end with no room left, E20), on the team's side or, when its way there would cross the doorway's view, on its own (a split stack,
E19), standing where the doorway's `DoorStack` settles that slot (`_stack()`, asked with the human's own claim `_me()` through the stack's claim chain, `DoorStack.claim`, as an NPC's entry is: `slot_for`,
`StackLayout.holds_slot`, the side it asks for, `_ask_side`, its own weighing from where it stands, then `settle`, its side `reservation.on`, the other side while its own wall is full, E21, and its point, the move-up rewrite applied as for any member): a
full claim encoded by `StackClaim.encode`, every entry field an NPC's carries (`claim_frame` / `claim_pos` stamped on each new claim and kept
by its repeats, so a same-frame tie with the human settles by distance as for any member, E2; `crossed_frame`, `reservation.crossed_frame`, restamped
to `GameClock.frame()` each time its step goes from `claim` / `ready` to `going_in` / `in` (`StackClaim.crossing`), cleared on a new reservation and on
withdrawal: the start of its latest crossing, since a human that brushed the funnel steps back out of it, unlike an NPC, D14; `bang: true`, `bang_off: false`: it never holds
a stack back nor turns it; `stuns: 0` / `frags: 0`: it throws nothing for the stack; `move_up: 0`, `pie: false`) plus `human: true` (no AI moves up into its slot, E2), `leader` (true while its `squad`'s `leader()` is the human; `squad` is handed in by
`MatchBuilder.bind_squad`, LD17: a stack the human ordered waits for it) and `own` (false for this E16 reservation), with the human as `speaker`,
repeated every `StackClaim.HEARTBEAT` (2 s) (`_post`: its header written by hand, the eight header fields an NPC's controller's radio writes in
`npc_comms.gd` `_callout_header`: speaker, faction, position, status, path, label, target_id and point). `_reserve(id, into, geo, stack)` takes the slot and side from that `DoorStack` and starts the claim, for E16 and the own
claim alike. It reads the human's step
from where it stands (`claim` / `ready` / `going_in` / `in`, `_step_at`: in its slot within `StackClaim.HUMAN_SLOT_REACH`, 20 px, through past
`StackClaim.THROUGH_DEPTH`, in the funnel within `StackClaim.FUNNEL_DEPTH`) and withdraws on leaving, dying, nobody left stacking (no claim
at a `StackClaim.STACKING` step, so an AI on its `bang` still keeps the human's slot reserved), or `go_timeout` after the AI
ahead in the crossing order is through, or (`abort`) when the stack grows past what a dead end holds for its slot. It reuses perception's stack module (`StackClaim`, a `ClaimLedger`, the `DoorStack`s it builds: the slot, side, point, crossing order
(`crossing` / `ahead`), whether anyone is stacking, and the markers' `layout`; `StackLayout.holds_slot` over its geometry; `StackClaim.keeps_claim`: a grenade call is not a
stack claim, nor is a callout that is only an order's progress, `order_step` with no `entry_step`, LD7; a rule that reads
a claim keeps to the **stale claim** rule in "The stack", `domain-ai-perception`) and `AgentEntry`'s geometry
(`set_house`, `geometry`, `stack_side_from`, `slots.on_stack_side`, `opening_id`), and never moves the character. **Its own claim (LD24).** With `own_claims` set (`MatchBuilder.build_squads` sets it through `bind_squad` on the invaders' side only, D29:
false unless set, so a human defender leader claims nothing of its own and rallies nobody), no allied stack forming in reach and the human
leading a squad with another living member (`_leads_team`), `_look_for_team` calls `_claim_own`: once the human has stood stepped up to a doorway for `STEP_UP_TIME` (0.5 s;
`step_up.stepped`, its `step_up` part, `ai/team/player_stack_step_up.gd`, holding the stack: on the doorway's stack side (`AgentEntry`'s `slots.on_stack_side`), out from the wall plane and past the jamb along it each within
`STEP_UP_REACH`, 60 px, at a doorway nobody stacks at and not `_barred`) it claims slot 1 there (an empty `DoorStack`'s `slot_for`) on the side it stands on
(`stack_side_from`), flagged `reservation.own` and radioed `own: true`. The squad hears that claim as the leader's own and rallies the team; a
reservation in an allied stack (E16), the leader's or not, carries `own: false` and never rallies. An own claim is kept while nobody
else stacks there (the "nobody stacking" withdrawal waits until the human is `in`), and with nobody ahead of it the `go_timeout`
withdrawal does not fire; `_withdraw` clears the reservation (`reservation.clear()`: its `reservation` leaf, `ai/team/player_stack_reservation.gd`, the doorway, slot, sides, claim frame and spot, step, clocks and `own`, all but its `heartbeat`). `attach` keeps the house's `openings` for it (`_openings`). `view()` feeds `StackMarkers` (UI): its slots are the `DoorStack`'s `layout(_me())`,
the points the AI stands. `entry.gd` has no case for a human: the barrier, the lone entrant's pie and the follow rule just
see one more teammate, and a held stack (LD13) takes the `going_in` of a teammate under its order, or the human's, into its room as its go (D14),
the human's only on a crossing begun since the order was issued (`crossed_frame` at or after the order's `frame`). Test:
`ai/stack/stack_player_go_after_funnel_brush` (the human brushes the funnel before the order, steps in after it, and the squad releases it).

**The squad (`ai/team/squad.gd`, `docs/leadership.md` LD3 to LD7 and LD19 to LD26, interface 21).** One per side, a `Node` the match builder builds under the match's `World` (or a test world) after
arming the characters (`MatchBuilder.build_squads`: `setup(roster: SquadRoster, openings, rooms)`, the roster (`squad_roster.gd`) its `faction`, `members`, `human` and `claim_ttl`) and hands each NPC (`MatchBuilder.bind_squad`: the
controller's `squad`). Its leader is the highest `wardrobe.rank`, the first spawned among equals (the human when it leads); on the leader's `died`
the next leads within the frame and it posts `&"leader"` `{ faction, leader, previous }`. `issue(request)` turns a leader's plain request
(`{ kind, to, pos?, room?, bang?, mode?, wait_go? }`) into an `&"order"` (each stamped by `_post_order` with the `GameClock.frame()` it is
issued on, `frame`, as is a `go`) (`defend_room` / `stack` / `ambush` / `cancel`: the room key, or
the doorway nearest `pos` within its width, a stack's room on the far side of the wall plane, `stack_at` or `split`, its `mode` quiet / stun /
frag (`MODES`; `bang` true for any but quiet; a request naming none of them reads it from `bang`) and `wait_go` (LD13); an ambush's `room` on the click's
side of the wall plane and `beyond` the room on the other, "" for an exterior door, LD15, D17; a `defend_room`, `stack` or `ambush` order
also carries its target point `pos`, the room's centre or the doorway's, which the UI's order markers draw) and posts it; no `to` is every
living member but the leader. A `go` request (`{ kind: "go", pos }`, LD13) posts a `go` order (`opening`, `pos`) to every living member
holding a held stack (`wait_go`) at the doorway nearest `pos` that no go has released yet, whatever its `to` (D13), and replaces nothing; when
the leader that gave held stacks dies the squad posts their go itself (`auto: true`, D12). `resolve(request)` is that resolution read-only,
without posting (`{ room, pos }`, `{ opening, pos, into, split, stack_at? }`, `{ opening, pos }` for a go, `{ opening, pos, room, beyond }` for
an ambush: what the UI's command menu names its stack and ambush items from); `view()` is `{ leader, members: [{ node, order, step, held, follow_spot }], stacks, trail, leash }` (`follow_spot` `Vector2.INF` for a
non-follower, `trail` the leader's trail oldest point first, `leash` px: what the leader overlay draws, LD28), the
steps read off the members' progress callouts (`order_step`), a released held stack carrying `go: true`, `held` whether the order is a stack
still waiting for the leader's go (`_waits_for_go`, LD13: the one place that rule is worked out; the UI reads it): not released by the
squad's own `go` nor by one read off the claims (`_latch_go`, on each claim heard at that doorway: its `DoorStack.released(order_id, into, since)`, `since` the order's `frame`,
`into` the order's room: a claim under the order saying `order_go`, or a member of that stack, under the order or the human, crossing or
through into that room, D14, the human leader stepping in among them on a crossing begun since; a claim left from an earlier entry releases
nothing), each kept in
`_released` once heard, as each member latches its own go; an order radioed `done` is no longer
held (`order` {}, `step` `done`), a `refused` one still is. `stacks` (LD18, its `stacks` part's `_stacks` (`ai/team/squad_stacks.gd`, built with the squad, holding it), kept as last laid by `stacks.now()` and laid again after `stacks.invalidate()`, on a claim heard or a member's death) is every stack the side is forming, ordered
or its own, from the side's entry claims it hears (its own `ClaimLedger`, `stacks.ledger`: unlimited range, the side's whole view; the latest per
speaker, current for `claim_ttl`: the NPCs' `tuning.radio.callout_ttl` (6 s), handed in by `setup`, which the match builder reads off
the side's NPCs with `MatchBuilder.callout_ttl_of`; a dead speaker's dropped;
the human's `PlayerStack` among them), at each doorway `ClaimLedger.openings_stacking()` names (a claim at a `StackClaim.STACKING` step):
`[{ opening, into, door, slots: [{ n, point, holder, held, there, mine, side, row }] }]`, the slots that doorway's `DoorStack.layout()` gives
(slots 1 to the last claimed over the geometry its own `AgentEntry`, `stacks.entry`, lays, each where its holder stands it, a slot a dead end does not hold
left out), `there` its holder at `ready` / `bang` (`StackClaim.IN_SLOT`), `mine` the human's; the UI's stack
markers draw it, laid on the navigation map and physics space of the world the squad itself is in (its viewport's `World2D`). It reads its
members only through the Character API (`wardrobe.rank`, `is_dead`, `died`, and the leader's `global_position` and `facing`; a member is an NPC, one
that follows, when a child of it is in the group `npc_controllers` at `setup`, `_npcs`) and the bus, and reuses `AgentEntry.opening_id` /
`normal_into` and the stack module (`StackClaim`, `ClaimLedger`). The only orders it posts of its own are the rally's joins and the cancels below; `_post_order` (the id,
`_orders`, the `&"order"` post) serves `issue` and them alike.

**Following (`docs/leadership.md` LD19 to LD23).** `follows(member)`: alive, the squad has a leader, not the leader, an NPC (`_npcs`). The
tunables are the static holder `SquadFollowConfig`'s (`ai/team/squad_follow_config.gd`, the same for every squad): `gap` 55, `step` 45,
`caught_up` 20, `ring` 80, `still_time` 0.8 s, `retarget` 20, `arrive` 10, `leash` 320, `leash_break` 1.3. The trail and the spots are
`SquadFollow`'s (`ai/team/squad_follow.gd`, a `RefCounted` the squad builds in `setup` with its openings and rooms, `_follow`; it reads the
holder, and `leader()`, `members()`, `alive` and `follows` off the squad), with
the constants `SquadFollow.TRAIL_STEP` 15, `SLOT_SNAP` 20, `RINGS` 3, `WAY_CLEARANCE` 32. The squad's `_physics_process` runs `track`: a
trail point each `TRAIL_STEP` the leader moves (`_moved_at` on `GameClock`), trimmed to what the file needs, the rooms it stood in kept
(`_visited`); a new leader starts it afresh (`reset`, also from `_on_died`, which `invalidate`s the spots when a member dies). `trail()` is
what `view()` gives. `follow_spot(member)` (`Vector2.INF` for a non-follower) is `SquadFollow.spot`, which lays every spot at most once a
physics frame and only when the leader moved, turned or stopped or the followers changed (`_lay_spots`, the followers in roster order
from `followers()`): moving, on the trail at `gap + step * i` (`_trail_point`, snapped with `NavBuilder.snap`; a place past the
trail's oldest point and further from the leader than the follower stands keeps it where it stands, `_trail_length`); still
(`still_time`), a slot from `_ring_slots` behind `_heading()` (the trail's last stretch), each on the map within `SLOT_SNAP`, in the
leader's sight (`AgentVision.wall_hit`) and out of doorways (`_open_at`, `_in_doorway`), the rest on the trail, stepped back out of a
doorway. `_clear_of_way` then moves a follower or spot out of the lane ahead of the leader's `facing` (`_in_way`): beside it, own side first
(`_taken`), else further ahead (170 / 215 / 260 px), only into `_visited` rooms; kept in `_aside` (member -> `{ spot, from, way }`: the spot,
where the leader stood and the way it faced) while it clears the way, until the leader has moved a ring or turned back. The controller
reads `follows`, `leader()` and the holder's `leash` and `leash_break`; the behaviour's `follow` primitive reads `follow_spot` and the
holder's `retarget`, `arrive`, `still_time`, `step` and `caught_up` (LD21's catch-up run), and faces away from the leash centre the controller pushes. The leash binds only a
follower holding no order (LD23, the controller's reflexes' `leash_lead`): `follows` stays true for a member carrying an order (its follow spot, its
place in the file and the rally's choice of followers still count it), but its controller pushes no leash while it holds one, so a member
defending a room, ambushing or in a stack (held or a join) fights where the order takes it, however far its leader is.

**The rally, the abort cancel and the takeover (LD24 to LD26).** `_on_event` hands an entry callout of the current leader's (same
faction, any `entry_step`, not a grenade call) with no `order_id` and no `join` (a join's claims, D30: a follower that took over the lead
holding one rallies nobody on it), and from the human only one marked `own` (`_own_claim`), to `_rally`: on
`claim`, once per `"<leader id>:<opening>"` (`_rallied`), one `stack` order with `mode` `JOIN` (`"join"`, not one of `MODES`, `quiet` /
`stun` / `frag`, which a request may name; `is_join(order)`, a thin name for interface 21's callers over `StackClaim.is_join`, tells a join), `opening` / `into` the claim's, `pos` the doorway's centre (`_opening_pos`), `split`, `bang`,
`wait_go` false, to every follower whose `_orders` entry is empty (D24); on the leader's `abort` the key is erased and one `cancel` goes to
the living members holding a join of that leader at that opening (D25). A join radioed `refused` is dropped from `_orders`, as a `done`.
`_on_died`, when the dead member led and was the human, calls `_take_over`: one `cancel` to the living members holding a `defend_room` or
an `ambush`; the held stacks it ordered are released as before (D12).

Tests: `tests/general/` (`squad_*`, `squad_takeover_from_human`, `lead_rank`, `stack_player_wiring`), `tests/ai/stack/` (the human's stack
claim; `human_leader_rallies`, `human_rally_spares_ordered`, `human_stack_slot_no_rally`, `human_defender_leader_no_rally`), `tests/ai/movement/` (`follow_*`, `independent_no_squad`), `tests/ai/combat/`
(`leash_*`, and for an ordered member off the leash `defend_room_stays_inside` and `ordered_melee_off_leash`), the ordered entries and joins in `tests/ai/entry/` (`order_*`, `join_*`), `tests/general/test_world_invader_bound_as_match` and the UI's `tests/ui/` (`stack_markers_draw`, `order_markers_draw`, `command_menu_*`, `leader_overlay_draw`).

**Interfaces:** 7 (the Character API a squad reads: `wardrobe.rank`, `is_dead`, `died`, the leader's `global_position` and `facing`), 9 (the map
queries `PlayerStack`, the squad's stack slots and the follow spots go through), 10 (EventBus: `&"callout"` entry claims, aborts and order steps
in, `&"callout"` the human's claim, `&"order"` (with the rally's `join` and the cancels), `&"leader"` out), 17
(`PlayerStack`, `StackMarkers`), 21 (`Squad`, the command menu, order markers and leader overlay) — signatures in `architecture`.
