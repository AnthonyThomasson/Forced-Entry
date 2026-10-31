---
name: domain-ai
description: Light overview of the AI domain (scenes/ai/) — non-player brains, split into four isolated sub-domains under scenes/ai/ around a thin orchestrator. Start here to see the shape of the AI (sense → decision-tree walk → primitive, the sub-domain map, the two NPC presets, which cross-domain interfaces it uses), then load the matching `domain-ai-<name>` skill for deep detail: `domain-ai-perception` (what the NPC knows: vision, hostility, memory, tracks, callouts, tactics geometry, the decision snapshot Von reads), `domain-ai-decision` (the decision tree, its planner walk, the Von round-trip + server), `domain-ai-behavior` (the primitives: move/engage/melee/interact/hold/entry + pathing + commitment; its `combat.gd` is `domain-ai-combat`, `search_coverage.gd` is `domain-ai-coverage`, `watch.gd`, where it looks and when it shoots, is `domain-ai-watch` and `entry.gd`, the tactical entry through a doorway, is `domain-ai-entry`), `domain-ai-debug` (the overlays); the decision snapshot inside perception is `domain-ai-snapshot`, and `ai/team/` (the human's `PlayerStack`, each side's `Squad`, its leader and orders) is `domain-ai-team`. Use when editing scenes/ai/ or working on NPC goals/behaviour, or to find which sub-domain owns a concern. Complements the `architecture` skill (cross-domain interfaces).
---

# AI domain (`scenes/ai/`) — overview

Non-player brains. **One** generic, data-driven controller drives every NPC (house defender and
invader alike) — there is no per-NPC-type or per-goal code. An NPC's behaviour is pure DATA authored
on its scene: a plain-language `goal` string (`{gun}` in it stands for the NPC's own gun; `goal_text()` is the filled-in text)
plus a handful of generic primitives (hostility rules, pursuit, territory) and decision-tree config. A controller writes the character's intent and calls
its public action API — it never reaches into character internals.

The domain is split into **four isolated sub-domains** around a thin orchestrator, each a module
folder under `scenes/ai/` that talks to the others only through a small published interface — the same
isolation the game applies between top-level domains. This skill is the map; load the per-sub-domain
skill for detail.

## The orchestrator + four sub-domains

`ai/goal_controller.gd` is the **orchestrator** — the AI's own composition root (the `main.gd` of the
AI domain). It holds the NPC's tunables, the AI's single **authoring surface**, as `tuning` (`NpcTuning`,
`ai/tuning/`: its `Tuning` child, one topic node per concern, `tuning.<topic>.<name>`, so a defender or
invader preset is all data on those nodes), it wires the sub-domains and hands that hub to each facade (the
perception's `apply_config(tuning)`; the behaviour's `setup`), which sets that sub-domain's modules' fields
straight from the topics (the perception, its snapshot vocabulary, the behaviour and its modules keep none: each reads its topics live, `tuning.combat`, `tuning.entry`, ...) — building
them once, then applying the config again each decision so a tunable retuned at runtime
(a behaviour test, the dev command server) takes effect without a rebuild, and on its first `control(character, delta)` hands the NPC's
body to perception and behaviour once (`bind(character)`, which each passes on to its modules), so no sub-domain function takes the
character — and it runs the
**SENSE → THINK → ACT** loop plus the decide cadence, salient-event detection (a change of belief about hostiles, the behaviour's `salient_key`; the order just
adopted is not one: `_on_decided` re-takes the key after `set_leaf`, since the order sets or clears the engaged contact the key carries, issue #51 R12, test
`ai/decision/adopt_target_no_redecide`), interrupting a decision
walk the situation has overtaken, and the EventBus intake (`&"hit"`, `&"footfall"`s within earshot, allies' `&"callout"`s, `&"grenade"` landings,
`&"explosion"`s and its leader's `&"order"`s (Orders, below), queued and handed to perception on the next tick) and its own callouts (a combat one carries `target_pos`, where its hostile is; an
investigation one `lead_pos`, the freshest lead placing a hostile its decision weighed, which only its squad reads, LD29).
It does that through three parts it builds once in `_ready`, each preloaded (no `class_name`): `_cadence` (`ai/npc_cadence.gd`, a data
leaf: the decide timer, `forced` and why (`force(reason)`), the walks started, an order awaiting its decision (`order_from`), the salient
key and the last snapshot's facts, sections and options; `due(delta)` counts the timer down), `_comms` (`ai/npc_comms.gd`, holding the
controller: the queued events (`event_queue`, `process_events`) and every callout it radios) and `_reflexes` (`ai/npc_reflexes.gd`, holding
the controller: following the squad, the grenade evade and the blind roll, its RNG seeded in `bind`, and priming an ambusher at its post,
`prime`). The planner builds and owns the Von
client (`DecisionPlanner.setup(tuning.decision)`, the NPC's name through its `bind(npc_name)`).

| Sub-domain | Folder | Skill | Owns (role) |
|---|---|---|---|
| **Perception** | `ai/perception/` | `domain-ai-perception` (+ `domain-ai-snapshot` for the snapshot: `agent_snapshot.gd`, `perception/snapshot/`) | SENSE — what the NPC knows (sight, hostility, event memory, movement tracks, gunfire heard, allies' callouts) and the combat geometry (`agent_tactics.gd`: flanks, fire/advance/retreat spots); builds the decision SNAPSHOT — state sections, facts, option groups — worded for Von (`agent_snapshot.gd`). |
| **Decision** | `ai/decision/` | `domain-ai-decision` | THINK — the decision TREE (data), the planner that walks it with Von one `choice` request per level, and the Von transport + dev-only server launcher. |
| **Behaviour** | `ai/behavior/` | `domain-ai-behavior` (+ `domain-ai-combat` for `combat.gd` and its throw `combat_throw.gd`, `domain-ai-coverage` for `search_coverage.gd`, `domain-ai-watch` for `watch.gd`, `domain-ai-entry` for `entry.gd`) | ACT — runs the chosen leaf's primitive (move / engage / melee / interact / hold / reload / entry / throw / defend / ambush / follow) and the commitment state Von lacks; owns a locomotion layer for pathing, and the tactical entry phase machine (`entry.gd`). |
| **Debug** | `ai/debug/` | `domain-ai-debug` | Draw-only overlays: the vision cone/bubble, the decision-path label + movement path, the tactical zones it weighed, search coverage, and behaviour overlays (contacts, hearing/radio, combat, territory, move/use targets, Von/brain, routes, stuck, the entry plan, the entry team and guard). |

**The AI team (`ai/team/`: `player_stack.gd`, `squad.gd`).** Not a fifth sub-domain: the human's side of the entry radio (`PlayerStack`, interface 17) and each side's squad, its leader and its orders (`Squad`, interface 21); its detail is the `domain-ai-team` skill.

**The stack (`ai/perception/stack/`: `stack_claim.gd`, `claim_ledger.gd`, `door_stack.gd`, `stack_layout.gd`, `stack_member.gd`).** A doorway's stack as the radio describes it,
held once: `StackClaim` the entry claim's wire format (`encode` / `decode`, every field's default), the "not a claim" rule, `is_join` and the
step lists and slot distances; `ClaimLedger` the claims one listener has heard (the NPC's perception, the human's `PlayerStack`, the side's
`Squad`: one each, the latest per speaker, on `GameClock`); `DoorStack` every slot rule over one doorway's claims (E2's same-frame ties and move-up, E16's human slot,
E19 to E22's sides, files, tail and dead ends, the crossing order, the thrower, whether the stack is held for its leader's go and its mode,
`held` / `mode`, LD13's and D38's release), `StackLayout` the statics it settles them by (the slots' points and sides), the same answer for
whoever asks; `StackMember` one member's own claim (claim, keep and settle against a `DoorStack`, its `me()`), which the NPC's entry and the
human's `PlayerStack` each own. It is perception's, and the one seam behaviour and the team cross into it by: behaviour reads a doorway's stack as
`AgentPerception.entry.stack(opening, into := "") -> DoorStack` and preloads `StackClaim` / `DoorStack` / `StackLayout` / `StackMember` (the orchestrator `StackClaim`, for
the radio's `post_entry_call`), and the team preloads `StackClaim`, `ClaimLedger`, `DoorStack`, `StackLayout` and `StackMember`, and three more of perception's: the
doorway geometry `AgentEntry` (`ai/perception/agent_entry.gd`, built with no NPC: `set_house`, `geometry`, `stack_side_from`, `slots.on_stack_side`,
`opening_id`, `normal_into`), `AgentVision.wall_hit` (`ai/perception/agent_vision.gd`: the follow spots out of the leader's sight) and `HouseRooms`
(`ai/perception/house_rooms.gd`: the room a point lies in, `key_at`, and the room with a key, `by_key`). `domain-ai-perception`, "The stack", has the detail.

**Orders (`docs/leadership.md`).** The controller queues `&"order"` events; one that names the NPC (and its side) becomes its live order
(`AgentPerception.orders.process`) and forces a decision (`_cadence.force("ordered")`, in `_comms.process_events`); from that frame until a decision made knowing the order
lands a walk the order replaces stops, while a fight goes on (the cadence's `order_from` = `decisions`, `Behavior.orders.await_next(true)`, `domain-ai-behavior`):
`_maybe_interrupt` restarts a decision walk in flight, and `_on_decided` drops a leaf from a walk begun before the order (LD6). The entry rule `ordered → order` sits after the fight rules
and before `hostile_known`, so an ordered member shot at fights, then goes back to its order. The ORDER node's one option (the snapshot's
`order` group) is auto-picked: `defend` for a room (the behaviour's `defend` primitive, at its D2 spot), an `entry` for a stack, an `ambush`
for an ambush (the behaviour's `ambush` primitive, at its post from `EntryPosts.ambush_spot`, LD15). A `go` is no new order: perception
latches it on the held stack it releases (`go: true`) and no decision is forced. A
defend order's room is a rule of the NPC's confinement (perception's `confinement.room`, refreshed each tick by the reflexes, below), which
keeps the fight to options inside it, and so is the room a held stack is to enter (`confinement.keep_out`, from
`AgentPerception.orders.held_room()`, LD13 / D38), which keeps the fight out of it, and the controller radios the order's progress (`order_id`, `order_step`: `moving` / `in_position` from the behaviour, `done` / `refused` from the perception).
An order the NPC cannot carry out (no option built) is ended `refused` as `_start_decision` begins the walk, which refreshes the confinement
(`_reflexes.refresh_confinement()`: no room nor held room now) and puts its copy in the snapshot, so that walk decides with no room;
a stack at a dead end with no slot for the member is kept instead, its option a `hold` whose params carry `refused` (LD9, D21). An ordered stack (LD9) is an entry that goes in the order's way (its
side, its mode, a wait for every living recipient, and for the human leader holding a slot, up to `order_ready_cap`, LD17), from anywhere and for a defender too, its way read before
it claims and its walk guarded, its claims (the radio's `post_entry_call`) carrying `order_id` / `order_bang` / `order_mode` / `order_hold` / `order_go` / `order_side` / `order_frame`
beside every claim's `stuns`, `frags`, `claim_frame`, `claim_pos`, `move_up`, `pie` and `crossed_frame`; it ends done at the room cleared
(`domain-ai-entry`). A held stack (LD13) waits at its slots, ready, until its go; a frag stack (LD14) has a frag carrier throw a frag in
first. An ambush (LD15) ends done on first contact, a hostile in sight or shots at the member (`AgentPerception.orders.end_ambush_on_contact`, D18);
while it holds the ambush at its post (`Behavior.orders.primed`) the controller's reflexes prime it every tick before it observes
(`_reflexes.prime`: the sight's `primed`, every character in its cone tested every frame, and its own character's
`process_physics_priority` 1, so it moves after every other body; both undone after, D37). Besides the human's orders an AI defender
leader's squad orders an ambush of its own (LD29, `domain-ai-team`): on a callout of its side placing a threat outside the leader's room,
read off a COMBAT callout's `target_pos` or an INVESTIGATE callout's `lead_pos` (the radio part's `post_callout`, from the decision's
snapshot `leads` group, `domain-ai-snapshot`); the leader is one of its recipients and carries it out as any member does.
A **join** (a `stack` order with `mode` `join`, LD24) is the squad's own: its leader's own claim at a doorway rallies every follower holding
no order. Its ORDER option is an `entry` with `join: true` and no side or mode of the order's, and `Entry.begin` runs it as the member's own
unordered entry joining the leader's stack (`domain-ai-entry`); the order's id stays in the leaf's params, so its progress is still radioed.
A join with no slot at a dead end has no option and ends `refused`. A join that ends (done, cancelled on the leader's `abort`, refused)
leaves the member to follow again, at once while its entry is still in `approach` or `stack` (`Behavior.orders.join_over`, LD25).

**Following (`docs/leadership.md` LD19 to LD23).** Each tick the reflexes' `follow_squad` (in SENSE, after `observe`, so after the whole order intake, an ambush ended on contact
included) reads the controller's `squad`:
`follows(character)` into `AgentPerception.follows` (the snapshot's and `quick_facts()`'s `follows`), forcing a decision when it changes
("follows its leader" / "leads its squad"), and refreshes the **confinement** (`refresh_confinement()`: perception's `confinement.refresh`
with the territory, `tuning.decision.defend_territory`, the live order, `perception.orders.current()`, and the leash,
`SquadFollowConfig.leash` round the live position of `leash_lead()`, `Vector2.INF` when it does not follow or holds an order: LD23, the
leash binds only a follower holding no order, so an ordered member fights where its order takes it, and the room its held stack is to
enter, `perception.orders.held_room()`, D38); a leashed follower in a fight (`in_combat`) further than `SquadFollowConfig.leash_break` leashes from the confinement's `leash_center`, neither `committed()` nor
`orders.walk_pending()`, forces one decision ("off the leash", the reflexes' `_leash_broke` re-armed once it is back within that). `_apply_config` disables
INVESTIGATE, SEARCH and IDLE for a follower, adds the entry rule `follows → follow` (after `hostile_known`); it pushes no confinement: the planner reads the snapshot's frozen copy
(`snapshot["confinement"]`, `domain-ai-decision`), behaviour and Combat the live one. `debug_state()["confinement"]` is its `view()`
(`inside_only`, `room`, `leash_center`, `leash`, `keep_out`, `confines`), and `debug_state()["decision"]["confinement"]` the copy the last walk
decided over. The FOLLOW leaf's `follow` primitive keeps the member to `Squad.follow_spot`
(`domain-ai-behavior`) and asks for no decision on the cadence.

Data flow each tick: the orchestrator folds queued hits and callouts into **Perception**, has it
`observe()` and return `contacts.known()`; hands those to **Behaviour** to resolve + honour commitments;
when free (or forced), its routes can be measured as it will walk them (`AgentPerception.views.routes_ready`: the avoid map of the doorway views from the room it
stands in is baked, a few frames at most, `docs/tactical-entry.md` E18) and the frame has a snapshot to spare (`DecisionBudget`: `per_frame` snapshots a physics frame, one by
default, so NPCs deciding together spread over frames), asks **Perception** for a snapshot and starts a **Decision** walk
over it;
adopts the returned leaf into **Behaviour** (and radios it to allies); then has **Behaviour** `apply()`
the running primitive.

**Observer reads** (pure reads, never perturbing the loop). The controller is in the group `npc_controllers`, authored on the node in `npc.tscn` (interface 7):
that is how the HUDs tell an NPC's controller among a character's children (the UI's `hud_probe.gd`). `debug_status()` is the decision path as labels plus the running
primitive's progress. `debug_state() -> Dictionary` is the deep snapshot: every level of the last walk (the state and question
Von saw, the options, its probabilities and pick), the facts, the state sections of the last snapshot (`sections`: the text Von reads
in any question, read even when no level asked, e.g. a join's `order` sentence, LD24), the contacts, the running primitive and pathing (`loco`: the walk's
`way` plain / round / held / doors, `held_for`, `giving_way`), and `decisions` (walks started) with `decision_reason` (why the latest started:
the force reason, e.g. "task resolved", "way blocked", "attacked", or "cadence"); the dev command
server's `ai` verb dumps it and `tools/von_probe.py` replays captured levels against Von. `debug_zones() -> Array` flattens the
last snapshot's option groups to world points, each with its `label`, `desc` (for an inspector to explain a clicked point) and
`tags`, tagged by zone kind (fire / flank / advance / retreat / lead / search / entry / room / interaction / grenade (where a throw
weighed would burst, with `from`, the throw spot or the NPC's own spot), plus `waypoint` for the non-room go-to points: post / entrance / approach). `debug_state()["order"]` is the order leaf the NPC is carrying out (`{ path, primitive, params, paused }`, `paused` while an entry detour of the
entry guard holds it, its primitive and params then the order's, not the detour's; {} with none), beside the running `primitive` / `params`.
`debug_room_zones() -> Array` gives each room `{ rect, type, status }`
by how the NPC regards it (current / searched / unsearched / unknown). Both feed the tactics overlay (`domain-ai-debug`), which also rings
the point an observer asked to highlight: the var `debug_focus` (the spectator inspector's clicked zone, `Vector2.INF` for none; debug only).

## Grenades (`docs/grenades.md`)

Two decisions Von makes and two reflexes outside it. **GRENADE** (G17) is a COMBAT tactic: offered against a hostile hidden from the NPC's line of fire or in a room the NPC is outside of (barricaded), or, shot at by someone unseen from a room it is outside of, where the shots came from, in throw range with a clear lob from where it stands or from a
throw spot a short walk away (`agent_tactics.gd` `throw_spot`, issue #51 R13 / R15), when no known ally would be in the blast and the NPC could get safe
from it itself (judged from where it throws); it runs the `throw` primitive (walk to the throw spot, select, aim, throw, radio `frag_out` / `bang_out`, gun back in hand, wait out the fuse, or the evade plan if it is in the
burst's zone). **STUN ENTRY** (G18) is a SEARCH tactic beside ENTER, offered while the NPC or its stack carries a stun: the same doorways, with a stun thrown into the room from beside the door before the point crosses (the `bang` phase of
`entry.gd`, `docs/tactical-entry.md` E17); Von takes it for a suspect room (gunfire or footsteps heard there, shots from it, an ally's fight in it, a hostile lost in it, by its doorway or heading in). `perception/snapshot` words both (`domain-ai-snapshot`), the tree has the nodes (`domain-ai-decision`), `combat.gd` throws (`domain-ai-combat`), `entry.gd` runs the bang (`domain-ai-entry`); the numbers it
knows of a grenade not yet thrown (throw range, radii, fuses, the flash's cover reach) it reads off the grenades it carries (`Character.inventory.throw_stats(slot)`, interface 6/7; no copy in its tuning).

Two reflexes outside Von, in the orchestrator's loop (the reflexes' `react_to_grenades`, the radio's `process_events`), and the tunables in `tuning.grenades` (`enabled`, `hear_grenade` 300 px, `evade_margin` 120 px, `blind_fire_chance` 0.5):
- **Evade (G16).** Perception knows the live grenades it sees, hears come down, is told of (callout `status` `grenade`, also `frag_out` / `bang_out`) or threw; when it is inside a
  grenade's danger zone it radios an `&"grenade"` callout (`point` = where it landed, `kind`) and the behaviour runs to the nearest safe spot (out of the burst's line, behind furniture that
  shields a crouched body, or outside the zone), holds it facing away and re-decides at the burst. No decision starts or is adopted meanwhile. `perception/agent_grenades.gd`,
  `agent_throw.gd`, `behavior_grenades.gd` (the evade reflex). `debug_grenades()` reads it; the `show_grenades` overlay draws it.
- **Stunned (G15).** Blind: no new sighting, no new decision (it re-decides the tick sight returns), its contacts kept so it fires blind at the last-known spot of the one it fought (the character's aim
  sway applies, one-handed) when its one roll as it goes blind hits `tuning.grenades.blind_fire_chance` (0.5; drawn from the reflexes' own RNG, seeded at bind from the
  character's name and spawn spot, so a seeded run rolls the same; a re-stun while blind does not reroll), else it holds its fire until it can see (`Combat.holds_fire`); deaf: the orchestrator drops gunfire, hits elsewhere, footfalls, callouts and grenade landings it would have heard.

## Hearing (`docs/hearing.md`)

The NPC hears the footsteps of characters not of its faction through walls (H1), out to a range by gait: `tuning.senses`'s `hear_walk` 250 px,
`hear_run` 450 px, `hear_crouch` 100 px. A heard step is an INVESTIGATE lead and a reason to suspect the room it came from; `debug_memory()["footsteps"]` reads it.

## The decision tree

```
root ─┬─ ORDER   → the order the NPC's leader gave it, auto-picked           (defend / entry / ambush)
      ├─ COMBAT (pick the hostile) ─┬─ ENGAGE  → a safe firing spot / ambush   (engage)
      │                             ├─ RELOAD  → swap in a magazine             (reload)
      │                             ├─ FLANK   → a side, route clear of hostiles (engage)
      │                             ├─ GRENADE → frag or stun a hostile hidden or barricaded in a room, or the shots' room (throw)
      │                             ├─ ADVANCE → halfway / close / rush         (move)
      │                             ├─ MELEE   → punch, only when point-blank   (melee)
      │                             ├─ RETREAT → a hidden / farther spot        (move)
      │                             └─ LOCATE  → toward an unseen shooter       (move)
      ├─ FOLLOW  → keep to the spot the squad gives a follower, auto-picked     (follow)
      ├─ INVESTIGATE ─┬─ a lead (last seen, heading, gunfire, footsteps, ally's call) (move)  [always asked of Von]
      │               └─ STAY → hold, when a lead is outside the house          (hold)
      ├─ SEARCH ─┬─ ENTER → a doorway into a room left to search              (entry)
      │          ├─ STUN ENTRY → the same with a stun thrown in first (a stun in the stack) (entry{bang})
      │          └─ a room / unexplored area / the entrance                     (move)
      ├─ RELOAD_QUIET → top up with nobody about                                (reload)
      └─ IDLE ─┬─ USE → an object · GO → a room · WAIT                           (interact / move / hold)
```

Entry rules skip the broad levels when the situation is clear (under fire / engaged → straight to COMBAT; ordered → ORDER; — when
pursuing — a hostile known → COMBAT; a follower → FOLLOW). A level with one option is taken without asking. A follower has INVESTIGATE,
SEARCH and IDLE disabled (below).

## The two presets

Spawned by the match builder (`MatchBuilder.populate`: Main's `run.defender_count` / `run.invader_count`, default 1 each), each bound before it
joins the tree (`MatchBuilder.bind_npc`: the house's rooms and openings, an invader's front entrance), as a test world binds its NPC actors:
- **Defender** — `ai/npc_defender.tscn` (faction `household`): `tuning.hostility.on_trespass` +
  `tuning.hostility.on_attack`, `tuning.decision.defend_territory` (combat options stay inside the house), familiar with the
  house. Dropped at a clear spot in a random room (never inside solid furniture or on another defender).
- **Invader** — `ai/npc_invader.tscn`, an inherited scene overriding only data (faction
  `invader`): `tuning.hostility.on_sight`, not territorial, unfamiliar with the house (it learns rooms by
  sight and is offered unexplored areas by direction); it tints its debug label and path red. Dropped just outside the house: the
  match's invader team in one group against the outside wall beside the front door, on a side drawn from the house seed (`match_spawner.gd`
  `spawn_invader_team`, LD27; round the human invader when there is one, round a seeded point of the ring round the house when it has no front
  door); they coordinate flanks over the callout radio and, as a squad, follow their leader. It enters rooms
  tactically (`tuning.entry.enabled`, `docs/tactical-entry.md`): stack beside the door, slice the pie, cross
  without stopping, take the corners, clear, leave rear security — as a team over the radio, or alone. A quiet stack that carries a stun
  listens at the stack before the pie (`tuning.entry.listen_time` 3 s: E17, issue #51 R17), so a late reason can turn it into a bang.

Both pursue hostiles (`tuning.decision.pursue_hostiles`, default on): IDLE is never offered and a known hostile sends
every decision straight to COMBAT.

Both know their ammo: the snapshot's `loadout` section and the `gun_loaded` / `weapon_low` / `can_reload` facts feed a RELOAD
tactic in the decision tree, the `reload` primitive runs it, and `tuning.combat.auto_reload` (default on) reloads an empty gun
as a reflex. `tuning.context.low_ammo_fraction` sets where "nearly empty" starts.

Nothing in the AI is written per weapon: it fights with `Character.inventory.gun_slot()` (whatever gun it carries — the presets hold a pistol, but a match
arms every NPC with a gun from its side's loadout, one random gun by default) and reacts only to generic conditions the character reports. Notably, when its gun cannot fire because the
barrel is against a wall or object (`weapon.blocked()`, a long gun), it steps back until it can; a pistol is never blocked. See `domain-ai-behavior`.

## Key idea: Von picks, perceptions inform, behaviour executes

Von ranks distinct, verb-like options well but cannot do arithmetic or compare near-identical spatial
points, so every level offers a few DISTINCT options whose text carries the deciding facts as bands
("short hidden route", "in pistol range", "held by Invader2"). The NPC acts only on what it has
PERCEIVED: it fights a hostile's last-KNOWN position, loses a contact once its sighting decays (it
becomes an investigation lead), and (unless `tuning.memory.familiar_with_house`) must see rooms/objects before it can
use them. The detail lives in `domain-ai-perception`, `domain-ai-decision` and `domain-ai-behavior`.

**Interfaces:** 3 (`Explosion.shields` / `first_stop`, the blast's cover rule perception asks of a grenade), 6 (`ItemRegistry`'s
slot ids, `throw_stats()`, `weapon.aim_target()`), 7 (Character ↔ Controller, the observer reads and overlay exports), 9 (AI → Navigation), 10 (EventBus), 11 (`PhysicsLayers`, `GameClock`), 13 (`DecisionStub` / `DecisionServerLauncher` for tests), 15 (`GameLog`: the decision log line, entry phases, the Von launcher), 17 (the human's `PlayerStack`), 21 (the `Squad`: leader, succession, orders, following, the rally), 22 (`DecisionServerLauncher`: Main's Von-server wait) — signatures in `architecture`.
