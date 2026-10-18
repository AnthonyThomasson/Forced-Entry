---
name: domain-ai-team
description: Deep implementation detail for the AI TEAM module (scenes/ai/team/: player_stack.gd, squad.gd) — the human's place in an AI entry stack and each side's squad. The human's stack radio (PlayerStack, interface 17): claiming the first free slot when an allied team stacks at a doorway near the human, the split stack (E19), the dead-end refusal (E20), the other side of the door (E21), human / leader on its claims, the steps read from where the human stands, withdrawing, and view() for the stack markers. The squad (Squad, interface 21, docs/leadership.md): the leader and succession (highest rank, the human when it leads, the &"leader" post), issue / resolve of a leader's request into an &"order" (defend_room / stack / go / ambush / cancel: which doorway a click means, the room "into", stack_at or split, quiet / stun / frag modes, held stacks and the go that releases them, the automatic go when the leader dies), view() (each member's order, step and held, and the side's stacks laid slot by slot) and the seam into perception it reuses (AgentEntry statics, AgentGrenades.is_call). Use when editing scenes/ai/team/ or working on the squad, leaders, orders, the command menu's resolution, the stack markers' data or the human's stack claim. Complements the light `domain-ai` overview, `domain-ai-entry` (how the NPCs carry a stack out) and the `architecture` skill (interfaces 17, 21).
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
fields plus `human: true` (no AI moves up into its slot, E2) and `leader` (true while its `squad`'s `leader()` is the human; `squad` is handed in by
`MatchSpawner.bind_squad`, LD17: a stack the human ordered waits for it), with the human as `speaker`, repeated every 2 s. It reads the human's step
from where it stands (`claim` / `ready` / `going_in` / `in`) and withdraws on leaving, dying, nobody left stacking, or `go_timeout` after the AI
ahead in the crossing order is through, or (`abort`) when the stack grows past what a dead end holds for its slot. It reuses perception's `AgentEntry` (the statics `claims`, `free_slot`, `stack_side`, `crossing_order`,
`side_for`, `stack_point`, `holds_slot`, and `geometry` / `stack_side_from`) and `AgentGrenades.is_call` (a grenade call is not a stack claim; nor is a callout that is
only an order's progress, `order_step` with no `entry_step`, LD7), and never moves the
character. `view()` feeds `StackMarkers` (UI). `entry.gd` has no case for a human: the barrier, the lone entrant's pie and the follow rule just
see one more teammate, and a held stack (LD13) takes a teammate's `going_in`, the human's too, as its go (D14).

**The squad (`ai/team/squad.gd`, `docs/leadership.md` LD3 to LD7, interface 21).** One per side, a `Node` Main builds under `World` after
arming the characters (`setup(faction, roster, openings, rooms, human := null, claim_ttl := 0.0)`) and hands each NPC (`MatchSpawner.bind_squad`: the
controller's `squad`). Its leader is the highest `rank`, the first spawned among equals (the human when it leads); on the leader's `died`
the next leads within the frame and it posts `&"leader"` `{ faction, leader, previous }`. `issue(request)` turns a leader's plain request
(`{ kind, to, pos?, room?, bang?, mode?, wait_go? }`) into an `&"order"` (`defend_room` / `stack` / `ambush` / `cancel`: the room key, or
the doorway nearest `pos` within its width, a stack's room on the far side of the wall plane, `stack_at` or `split`, its `mode` quiet / stun /
frag (`bang` true for any but quiet; a request with no `mode` reads it from `bang`) and `wait_go` (LD13); an ambush's `room` on the click's
side of the wall plane and `beyond` the room on the other, "" for an exterior door, LD15, D17; a `defend_room`, `stack` or `ambush` order
also carries its target point `pos`, the room's centre or the doorway's, which the UI's order markers draw) and posts it; no `to` is every
living member but the leader. A `go` request (`{ kind: "go", pos }`, LD13) posts a `go` order (`opening`, `pos`) to every living member
holding a held stack (`wait_go`) at the doorway nearest `pos` that no go has released yet, whatever its `to` (D13), and replaces nothing; when
the leader that gave held stacks dies the squad posts their go itself (`auto: true`, D12). `resolve(request)` is that resolution read-only,
without posting (`{ room, pos }`, `{ opening, pos, into, split, stack_at? }`, `{ opening, pos }` for a go, `{ opening, pos, room, beyond }` for
an ambush: what the UI's command menu names its stack and ambush items from); `view()` is `{ leader, members: [{ node, order, step, held }], stacks }`, the
steps read off the members' progress callouts (`order_step`), a released held stack carrying `go: true`, `held` whether the order is a stack
still waiting for the leader's go (`_waits_for_go`, LD13: the one place that rule is worked out; the UI reads it); an order radioed `done` is no longer
held (`order` {}, `step` `done`), a `refused` one still is. `stacks` (LD18, `_stacks` / `_slots_of`) is every stack the side is forming, ordered
or its own, from the members' entry claims it hears (`_claims`, the latest per speaker, current for `_claim_ttl`: the NPCs' `callout_ttl` (6 s), handed in by `setup`, which Main reads off
the side's NPCs with `MatchSpawner.callout_ttl_of`; a dead speaker's dropped;
the human's `PlayerStack` among them), while a claim is at `claim` / `ready` / `bang` / `going_in` (`STACKING`): `[{ opening, into, door, slots:
[{ n, point, holder, held, there, mine, side, row }] }]`, slots 1 to the last claimed laid with its own `AgentEntry` (`stack_slots`, `side_for`,
`stack_point`; a slot a dead end does not hold left out), `there` its holder at `ready` / `bang` (`IN_SLOT`), `mine` the human's; the UI's stack
markers draw it, laid on the navigation map and physics space of the world the squad itself is in (its viewport's `World2D`). It reads its
members only through the Character API (`rank`, `is_dead`, `died`) and the bus, and reuses `AgentEntry.opening_id` / `normal_into` and the slot statics. An AI leader issues no orders.

Tests: `tests/general/` (`squad_*`, `lead_rank`, `stack_player_wiring`), `tests/ai/stack/` (the human's stack claim), the ordered entries in
`tests/ai/entry/` (`order_*`) and the UI's `tests/ui/` (`stack_markers_draw`, `order_markers_draw`, `command_menu_*`, `leader_overlay_draw`).

**Interfaces:** 7 (the Character API a squad reads: `rank`, `is_dead`, `died`), 9 (the map queries `PlayerStack` and the squad's stack slots
go through), 10 (EventBus: `&"callout"` entry claims and order steps in, `&"callout"` the human's claim, `&"order"`, `&"leader"` out), 17
(`PlayerStack`, `StackMarkers`), 21 (`Squad`, the command menu, order markers and leader overlay) — signatures in `architecture`.
