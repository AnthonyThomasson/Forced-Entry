# AI · The orchestrator (`scenes/ai/goal_controller.gd` and its parts)

The AI's own composition root. It holds the NPC's tunables as `tuning` (`NpcTuning`, `scenes/ai/tuning/`: its `Tuning` child, one topic node per concern, `tuning.<topic>.<name>`; a defender or invader preset is only data on those nodes), wires the sub-domains, and runs SENSE → THINK → ACT each tick. On its first `control(character, delta)` it binds the body once to perception and behaviour (`bind`), so no sub-domain function takes the character. Perception's `apply_config(tuning)` and the behaviour's `setup` set their modules' fields from the topics; the controller applies the config again each decision so a tunable retuned at runtime takes effect without a rebuild. Both modules and the snapshot vocabulary otherwise read their topics live.

## Parts (preloaded, no `class_name`, built once in `_ready`)

- `npc_cadence.gd` (`_cadence`) — a data leaf: the decide timer (`due(delta)`), `forced` and why (`force(reason)`), the walks started, an order awaiting its decision (`order_from`), the salient key and the last snapshot's facts, sections and options (`last_options`).
- `npc_comms.gd` (`_comms`) — the queued EventBus intake (`event_queue`, `process_events`: `&"hit"`, `&"footfall"` within earshot, allies' `&"callout"`, `&"grenade"`, `&"explosion"`, the leader's `&"order"`) and every callout the NPC radios, entry claims (`post_entry_call`) included. A combat callout carries `target_pos`; an investigation one `lead_pos` (read only by its squad, LD29).
- `npc_reflexes.gd` (`_reflexes`) — following the squad, the grenade evade and the blind roll (its RNG seeded in `bind`), the confinement refresh, and priming an ambusher at its post (`prime`).
- The planner builds and owns the Von client (`DecisionPlanner.setup(tuning.decision)`).

## One tick

1. Queued hits and callouts go into perception; `observe()` refreshes what it sees and remembers; the controller reads `contacts.known()` and behaviour resolves those contacts and honours commitments.
2. When free (or forced), routes can be measured as they will be walked (`AgentPerception.views.routes_ready`, `perception-views.md`) and `DecisionBudget` allows a snapshot (`decision.md`), the controller asks perception for a snapshot and starts a walk.
3. The returned leaf is adopted into behaviour (and radioed to allies); behaviour `apply()`s the running primitive.

**Salient events.** A change of belief about hostiles (the behaviour's `salient_key`) restarts a walk the situation has overtaken (`_maybe_interrupt`). The order just adopted is not one: `_on_decided` re-takes the key after `set_leaf`, because the order sets or clears the engaged contact the key carries (issue #51 R12, test `ai/decision/adopt_target_no_redecide`).

## Orders and following (`docs/leadership.md`)

- A queued `&"order"` that names the NPC and its side becomes its live order (`AgentPerception.orders.process`) and forces a decision (`_cadence.force("ordered")`). From then until a decision made knowing the order lands, a walk the order replaces stops while a fight goes on (`order_from`, `Behavior.orders.await_next(true)`, `behavior.md`): `_maybe_interrupt` restarts a walk in flight and `_on_decided` drops a leaf from a walk begun before the order (LD6). The entry rule `ordered → order` sits after the fight rules, so an ordered member shot at fights, then goes back to its order. The ORDER node's one option is auto-picked (`decision.md`).
- The controller radios the order's progress (`order_id`, `order_step`: `moving` / `in_position` from the behaviour, `done` / `refused` from perception). An order it cannot carry out (no option built) is ended `refused` as `_start_decision` begins the walk, after `refresh_confinement()` clears the room and held room from the snapshot's copy, so that walk decides with no room. A stack at a dead end with no slot for the member is kept instead as a `hold` with `refused` in its params (LD9, D21).
- An ordered stack (LD9) is an `entry` that goes in the order's way (side, mode, a wait for every living recipient and for a human leader's slot, up to `order_ready_cap`, LD17), for a defender too; `entry.md`. A `go` is no new order: perception latches it on the held stack and no decision is forced. A **join** (LD24) is the squad's own `entry` with `join: true`; when it ends (done, cancelled on the leader's `abort`, refused) the member follows again (`Behavior.orders.join_over`, LD25). `team.md` has the squad side.
- **Ambush priming (LD15, D37).** While `Behavior.orders.primed` holds, the reflexes' `prime` runs every tick before `observe`: the sight's `primed` (every character in the cone tested every frame) and the character's `process_physics_priority` 1, so it moves after every other body; both undone after.
- **Following (LD19 to LD23).** The reflexes' `follow_squad` runs in SENSE after `observe` (so after the whole order intake): it reads `squad.follows(character)` into `AgentPerception.follows`, forcing a decision when it changes, and refreshes the confinement (`refresh_confinement()`: territory `tuning.decision.defend_territory`, the live order, the leash `SquadFollowConfig.leash` round `leash_lead()`, and `orders.held_room()`). The leash binds only a follower holding no order (LD23). A leashed follower in a fight further than `SquadFollowConfig.leash_break` (a multiplier of the leash, 1.3) forces one decision ("off the leash"; `_leash_broke` re-arms once it is back within that). A follower has INVESTIGATE, SEARCH and IDLE disabled; the FOLLOW leaf asks for no decision on the cadence (`Squad.follow_spot`).

## Reflexes outside Von (`docs/grenades.md`, `docs/hearing.md`)

`react_to_grenades` (evade, G16) and the blind roll (G15) run in the orchestrator's loop; their perception half is `perception-grenades.md`, the run is `behavior.md`. While the evade plan runs, no decision starts or is adopted. Hearing ranges are `tuning.senses` (H1).

## Observer reads

Pure reads that never perturb the loop. The controller is in the group `npc_controllers` (authored in `npc.tscn`, interface 7): how the HUDs tell an NPC's controller among a character's children (`scenes/ui/hud/hud_probe.gd`). The getters and what reads them: `debug.md`. `debug_state()["decision"]["confinement"]` is the copy the last walk decided over, `debug_state()["confinement"]` the live `view()`. The dev command server's `ai` verb dumps `debug_state()`.
