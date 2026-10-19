---
name: domain-ai-team
description: Deep implementation detail for the AI TEAM module (scenes/ai/team/: player_stack.gd, squad.gd) — the human's place in an AI entry stack and each side's squad. The human's stack radio (PlayerStack, interface 17): claiming the first free slot when an allied team stacks at a doorway near the human, the split stack (E19), the dead-end refusal (E20), the other side of the door (E21), human / leader on its claims, the steps read from where the human stands, withdrawing, the human leader's own claim on stepping up to a doorway (LD24), and view() for the stack markers. The squad (Squad, interface 21, docs/leadership.md): the leader and succession (highest rank, the human when it leads, the &"leader" post), issue / resolve of a leader's request into an &"order" (defend_room / stack / go / ambush / cancel: which doorway a click means, the room "into", stack_at or split, quiet / stun / frag modes, held stacks and the go that releases them, the automatic go when the leader dies), following (follows / follow_spot: the leader's trail, the file and the ring, out of the leader's way, the leash), the rally (a join order on the leader's own claim, cancelled on its abort), the takeover from a dead human leader, view() (each member's order, step, held and follow spot, the side's stacks laid slot by slot, the trail and the leash) and the seam into perception it reuses (AgentEntry statics, AgentGrenades.is_call). Use when editing scenes/ai/team/ or working on the squad, leaders, following, orders, the command menu's resolution, the stack markers' data or the human's stack claim. Complements the light `domain-ai` overview, `domain-ai-entry` (how the NPCs carry a stack out) and the `architecture` skill (interfaces 17, 21).
---

# AI · Team module (`scenes/ai/team/`)

Not a fifth AI sub-domain: two small modules beside them, the human's side of the entry radio and each side's squad. Only the
composition root (`main.gd`, `match_spawner.gd`) builds them, the AI controllers hear them over the EventBus, and the UI reads them through
`view()` (and the command menu `resolve()`). How the NPCs carry an order out (the ORDER node, `process_order`, the ordered entry and ambush)
is the `domain-ai` overview's Orders section and `domain-ai-entry`.

**The human's stack (`ai/team/player_stack.gd`).** Not a fifth sub-domain: one small module, the human's side of the entry radio
(`docs/tactical-entry.md` E16). A child of the human's character (Main attaches it through `MatchSpawner.bind_player`), it listens to the
`&"callout"` bus like an NPC and, when an allied team is stacking at a doorway the human is near (`reserve_range` 300 px of walking), radios the
human's own claim for the first free slot (none in a dead end with no room left, E20), on the team's side or, when its way there would cross the doorway's view, on its own (a split stack,
E19), standing on the side `side_for` gives that slot (`_on`: the other side while its own wall is full, E21) at `stack_point`: the same entry
fields plus `human: true` (no AI moves up into its slot, E2), `leader` (true while its `squad`'s `leader()` is the human; `squad` is handed in by
`MatchSpawner.bind_squad`, LD17: a stack the human ordered waits for it) and `own` (false for this E16 reservation), with the human as `speaker`,
repeated every 2 s (`_post`). `_reserve(id, into, geo, team)` takes the slot and side and starts the claim, for E16 and the own claim alike. It reads the human's step
from where it stands (`claim` / `ready` / `going_in` / `in`) and withdraws on leaving, dying, nobody left stacking, or `go_timeout` after the AI
ahead in the crossing order is through, or (`abort`) when the stack grows past what a dead end holds for its slot. It reuses perception's `AgentEntry` (the statics `claims`, `free_slot`, `stack_side`, `crossing_order`,
`side_for`, `stack_point`, `holds_slot`, and `geometry` / `stack_side_from`) and `AgentGrenades.is_call` (a grenade call is not a stack claim; nor is a callout that is
only an order's progress, `order_step` with no `entry_step`, LD7), and never moves the
character. **Its own claim (LD24).** With `own_claims` set (Main sets it through `MatchSpawner.bind_squad` on the invaders' side only, D29:
false unless set, so a human defender leader claims nothing of its own and rallies nobody), no allied stack forming in reach and the human
leading a squad with another living member (`_leads_team`), `_look_for_team` calls `_claim_own`: once the human has stood stepped up to a doorway for `STEP_UP_TIME` (0.5 s;
`_stepped_up`: on the doorway's stack side (`AgentEntry.on_stack_side`), out from the wall plane and past the jamb along it each within
`STEP_UP_REACH`, 60 px, at a doorway nobody stacks at and not `_barred`) it claims slot 1 there (`free_slot([])`) on the side it stands on
(`stack_side_from`), flagged `_own` and radioed `own: true`. The squad hears that claim as the leader's own and rallies the team; a
reservation in an allied stack (E16), the leader's or not, carries `own: false` and never rallies. An own claim is kept while nobody
else stacks there (the "nobody stacking" withdrawal waits until the human is `in`), and with nobody ahead of it the `go_timeout`
withdrawal does not fire; `_withdraw` clears `_own`. `attach` keeps the house's `openings` for it (`_openings`). `view()` feeds `StackMarkers` (UI). `entry.gd` has no case for a human: the barrier, the lone entrant's pie and the follow rule just
see one more teammate, and a held stack (LD13) takes a teammate's `going_in`, the human's too, as its go (D14).

**The squad (`ai/team/squad.gd`, `docs/leadership.md` LD3 to LD7 and LD19 to LD26, interface 21).** One per side, a `Node` Main builds under `World` after
arming the characters (`setup(faction, roster, openings, rooms, human := null, claim_ttl := 0.0)`) and hands each NPC (`MatchSpawner.bind_squad`: the
controller's `squad`). Its leader is the highest `rank`, the first spawned among equals (the human when it leads); on the leader's `died`
the next leads within the frame and it posts `&"leader"` `{ faction, leader, previous }`. `issue(request)` turns a leader's plain request
(`{ kind, to, pos?, room?, bang?, mode?, wait_go? }`) into an `&"order"` (`defend_room` / `stack` / `ambush` / `cancel`: the room key, or
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
still waiting for the leader's go (`_waits_for_go`, LD13: the one place that rule is worked out; the UI reads it); an order radioed `done` is no longer
held (`order` {}, `step` `done`), a `refused` one still is. `stacks` (LD18, `_stacks` / `_slots_of`) is every stack the side is forming, ordered
or its own, from the members' entry claims it hears (`_claims`, the latest per speaker, current for `_claim_ttl`: the NPCs' `callout_ttl` (6 s), handed in by `setup`, which Main reads off
the side's NPCs with `MatchSpawner.callout_ttl_of`; a dead speaker's dropped;
the human's `PlayerStack` among them), while a claim is at `claim` / `ready` / `bang` / `going_in` (`STACKING`): `[{ opening, into, door, slots:
[{ n, point, holder, held, there, mine, side, row }] }]`, slots 1 to the last claimed laid with its own `AgentEntry` (`stack_slots`, `side_for`,
`stack_point`; a slot a dead end does not hold left out), `there` its holder at `ready` / `bang` (`IN_SLOT`), `mine` the human's; the UI's stack
markers draw it, laid on the navigation map and physics space of the world the squad itself is in (its viewport's `World2D`). It reads its
members only through the Character API (`rank`, `is_dead`, `died`, and the leader's `global_position` and `facing`; a member is an NPC, one
that follows, when a child of it is in the group `npc_controllers` at `setup`, `_npcs`) and the bus, and reuses `AgentEntry.opening_id` /
`normal_into` and the slot statics. The only orders it posts of its own are the rally's joins and the cancels below; `_post_order` (the id,
`_orders`, the `&"order"` post) serves `issue` and them alike.

**Following (`docs/leadership.md` LD19 to LD23).** `follows(member)`: alive, the squad has a leader, not the leader, an NPC (`_npcs`). The
tunables are vars: `follow_gap` 55, `follow_step` 45, `follow_ring` 80, `follow_still_time` 0.8 s, `follow_retarget` 20, `follow_arrive` 10,
`leash` 320, `leash_break` 1.3. The trail and the spots are `SquadFollow`'s (`ai/team/squad_follow.gd`, a `RefCounted` the squad builds in
`setup` with its openings and rooms, `_follow`; it reads the tunables, `leader()`, `members()`, `alive` and `follows` off the squad), with
the constants `SquadFollow.TRAIL_STEP` 15, `SLOT_SNAP` 20, `RINGS` 3, `WAY_CLEARANCE` 32. The squad's `_physics_process` runs `track`: a
trail point each `TRAIL_STEP` the leader moves (`_moved_at` on `GameClock`), trimmed to what the file needs, the rooms it stood in kept
(`_visited`); a new leader starts it afresh (`reset`, also from `_on_died`, which `invalidate`s the spots when a member dies). `trail()` is
what `view()` gives. `follow_spot(member)` (`Vector2.INF` for a non-follower) is `SquadFollow.spot`, which lays every spot at most once a
physics frame and only when the leader moved, turned or stopped or the followers changed (`_lay_spots`, the followers in roster order
from `followers()`): moving, on the trail at `follow_gap + follow_step * i` (`_trail_point`, snapped with `NavBuilder.snap`; a place past the
trail's oldest point and further from the leader than the follower stands keeps it where it stands, `_trail_length`); still
(`follow_still_time`), a slot from `_ring_slots` behind `_heading()` (the trail's last stretch), each on the map within `SLOT_SNAP`, in the
leader's sight (`AgentVision.wall_hit`) and out of doorways (`_open_at`, `_in_doorway`), the rest on the trail, stepped back out of a
doorway. `_clear_of_way` then moves a follower or spot out of the lane ahead of the leader's `facing` (`_in_way`): beside it, own side first
(`_taken`), else further ahead (170 / 215 / 260 px), only into `_visited` rooms; kept in `_aside` (member -> `{ spot, from, way }`: the spot,
where the leader stood and the way it faced) while it clears the way, until the leader has moved a ring or turned back. The controller
reads `follows`, `leader()`, `leash` and `leash_break`; the behaviour's `follow` primitive reads `follow_spot`, `follow_retarget`,
`follow_arrive`, `follow_still_time` and `follow_step`, and faces away from the leash centre the controller pushes.

**The rally, the abort cancel and the takeover (LD24 to LD26).** `_on_event` hands an entry callout of the current leader's (same
faction, any `entry_step`, not a grenade call) with no `order_id` and no `join` (a join's claims, D30: a follower that took over the lead
holding one rallies nobody on it), and from the human only one marked `own` (`_own_claim`), to `_rally`: on
`claim`, once per `"<leader id>:<opening>"` (`_rallied`), one `stack` order with `mode` `JOIN` (`"join"`, not one of `MODES`, `quiet` /
`stun` / `frag`, which a request may name; `is_join(order)` tells a join), `opening` / `into` the claim's, `pos` the doorway's centre (`_opening_pos`), `split`, `bang`,
`wait_go` false, to every follower whose `_orders` entry is empty (D24); on the leader's `abort` the key is erased and one `cancel` goes to
the living members holding a join of that leader at that opening (D25). A join radioed `refused` is dropped from `_orders`, as a `done`.
`_on_died`, when the dead member led and was the human, calls `_take_over`: one `cancel` to the living members holding a `defend_room` or
an `ambush`; the held stacks it ordered are released as before (D12).

Tests: `tests/general/` (`squad_*`, `squad_takeover_from_human`, `lead_rank`, `stack_player_wiring`), `tests/ai/stack/` (the human's stack
claim; `human_leader_rallies`, `human_rally_spares_ordered`, `human_stack_slot_no_rally`, `human_defender_leader_no_rally`), `tests/ai/movement/` (`follow_*`, `independent_no_squad`), `tests/ai/combat/`
(`leash_*`), the ordered entries and joins in `tests/ai/entry/` (`order_*`, `join_*`), `tests/perf/match_10v10_team_stress` and the UI's `tests/ui/` (`stack_markers_draw`, `order_markers_draw`, `command_menu_*`, `leader_overlay_draw`).

**Interfaces:** 7 (the Character API a squad reads: `rank`, `is_dead`, `died`, the leader's `global_position` and `facing`), 9 (the map
queries `PlayerStack`, the squad's stack slots and the follow spots go through), 10 (EventBus: `&"callout"` entry claims, aborts and order steps
in, `&"callout"` the human's claim, `&"order"` (with the rally's `join` and the cancels), `&"leader"` out), 17
(`PlayerStack`, `StackMarkers`), 21 (`Squad`, the command menu, order markers and leader overlay) — signatures in `architecture`.
