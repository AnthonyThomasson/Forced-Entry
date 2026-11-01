# AI tactical entry

How an NPC gets through a doorway into a room as police and soldiers do, alone or as one of a team over the radio: `scenes/ai/behavior/entry.gd` (`Entry`), its parts in `scenes/ai/behavior/entry/`, and the entry guard in `behavior_entries.gd`. Spec and tests: `docs/tactical-entry.md` (E1 to E22) and `tests/ai/entry/`. Rules are cited by id here; read the spec for what an NPC does and this skill for how the code is laid out.

Side files, by topic:
- `entry-bang.md`: the stun or frag thrown in first (E17, G18, LD14), quiet-entry upgrades and the listen.
- `entry-orders.md`: a stack a leader ordered, held for a go, a join, the human leader's rally (LD9, LD13, LD17, LD24, LD25, D38).
- `entry-guard.md`: the entry guard and detours, doorway views, bodies on the walk, move-up, dead ends and held walks (E2, E9, E15, E18 to E22).

Von only picks the doorway (the ENTER or STUN ENTRY tactic, `decision.md`). The choreography is this phase machine, so it runs with the server down.

## Seams

- **Doorway geometry** (stack slots, pie arc, corners, capacity) is perception's: `agent_entry.gd` and its parts under `scenes/ai/perception/entry/`, read through `AgentPerception` wrappers (`perception.md`).
- **The team's claims off the radio and every slot rule** are perception's stack module, `scenes/ai/perception/stack/`: `StackClaim`, `ClaimLedger`, `DoorStack`, `StackLayout`, `StackMember`. The entry reads one `DoorStack` a tick (`AgentPerception.entry.stack(opening, into)`, `claim.read_stack`) and claims through its `StackMember` (`state.member`). A rule that reads a claim keeps to the stale-claim rule in `perception-stack.md`.
- **The room is cleared by sight** with `SearchCoverage` (`coverage.md`). **The human's side of the radio** is `PlayerStack` (`team.md`, interface 17). **Where it looks** is the entry's own (`sweep.look_toward`, via `Watch.ease_gaze`), but the watch stage runs after it every tick and has the last word: a threat in sight takes eyes and gun in every phase but `bang` (`watch.md`).

## Shape

`Entry` is a `RefCounted` built in `Behavior.setup`. It holds two data leaves in `entry/`: `state` (`entry_state.gd`: phase, doorway, `member`, flags `Behavior` reads, the geometry `geo`, clocks) and `world` (`entry_world.gd`: `squad`, `loco`, `perception`, `coverage`, `combat`, `eyes`, `character`, `self_id`, `tuning`). Ten parts, built once on those leaves and held as public vars (`entry/entry_<part>.gd`, preload const, no `class_name`): `claim` (slot, side, where it stands, the move-up, the back of the stack), `approach` (walk to the slot, phase changes, top-off), `readiness` (waiting for its turn: `ready`, the barrier, crossing order, last man, security), `orders` (an ordered stack's terms, recipients, the go), `grenade` (the bang), `listen` (how the mode turns), `pie`, `sweep` (looking, crossing, corner, clear), `hold` (cover and rear) and `radio` (steps and heartbeat).

- **A part holds nothing but the two leaves.** A method that needs the entry or another part takes the entry as its first parameter at the call and never keeps it, so no part holds its `RefCounted` owner (`tests/ai/ai_parts_free_suite.gd`).
- A member read off another part is public on it, underscore and part prefix dropped (the order's id is `orders.id`). A constant more than one part reads stays on `Entry`.
- `Behavior.apply_config(squad)` hands in `world.squad`; tuning is read live as `world.tuning`.

## Public surface (what `Behavior` calls)

`begin(params) -> bool` (false when the doorway is unknown: the leaf is dropped and the NPC re-decides), `step(delta) -> bool` (true when over), `laid(params)` (the slots are laid: only once the nav map is baked), `approach_points()`, `abandon()` (radios `abort` only if a step of this entry went out), `reset()`, `committed()`, `throwing()`, `take_calls()`, `take_turned()`, `take_thrown()`, `way_blocked()`, `expects_burst(plan)`, `holding_for_go()`, `holds_crouched()`. `Behavior.entries.apply` sets `state.held_back`, `state.gaze_held` and `state.hostile_in_view` each tick.

## Phases

A shut door on a walk is opened: `behavior-doors.md`.

`approach` (to its slot, off the line of sight: E1, E2), `stack` (in the slot facing the door, radios `ready`), `pie` (the point slices the arc: E3), `bang` (E17), `cross` (E4, E5: radios `going_in`, `in` once past the wall plane and off the axis), `corner` (E5), `clear` (`SearchCoverage`; radios `clear` once the rest are in: E8), `cover` (guns on the doorways on, E8), `rear` (a member left over holds just inside the door it came by, facing out; E8, E13).

- **Claim:** a member claims the lowest slot the claims heard leave free (`member.slot_in(stack)`, `DoorStack.slot_for`); the option's `slot` is only the snapshot's guess. Two claims on one slot in the same `GameClock` frame and side settle by distance (E2). A slot past what a dead end holds ends the entry `done` with no claim (E20). `claim.keep_slot` re-picks every tick; a changed slot or side is radioed as a new claim. A slot pushed past a dead end's capacity is refused (`abort`, `done`; an ordered member's next decision is the ORDER node's `hold_<opening>`, LD9).
- **Barrier and order (E6, E7):** the point crosses when every other claimant radioed past `claim`, or `tuning.entry.ready_timeout` after it was ready. A follower crosses `follow_gap` after the member ahead goes (`readiness.follow`): an AI on its own side at that member's `going_in`, one across the door (E19) or the human (E16) at its `in`. The crossing order is `DoorStack.crossing` / `ahead`.
- **Commitment:** `committed()` is true while crossing and while the bang's thrower throws; the controller starts no decision, so a hit or a hostile in the doorway is fought once through. The NPC never runs in an entry, not even under fire: a running character cannot shoot (test `entry_never_runs`).
- **Top off (E11):** `approach.topping_off` calls `Combat.top_off` at the stack; skipped while a hostile holds the eyes and past `TOP_OFF_CAP`.
- **Last man (E12)** faces back (`readiness._covers_rear`); **a short room takes two (E13)** (`readiness._holds_outside`, `_tick_security`); **E14**: while `state.hostile_in_view` the pie holds and a follower does not cross (the watch stage fires). The rule is the entry's, so it holds whatever order brought the NPC to the door.
- **Holding the cleared room (E8):** `hold.finish` marks it cleared, then each member claims the nearest doorway on out of it that no teammate's `cover` call names (a tie goes to the lower instance id); one left over goes to `rear`, each rear member with its own spot (`hold._hold_rear_or_done`).
- **Corners (E5):** an entrant walks all the way into its corner (`CORNER_REACH`): a corner a stride short sits in the doorway of the one behind. Which corner each member takes is `sweep.start_cross`, by its place in the crossing order.

## Radio

Steps are queued as claims in `StackClaim`'s fields: `take_calls()` through `Behavior.entries.take_calls()` (adds `opening`, `into`, `slot`, `side`), posted by the controller's radio (`npc_comms.gd` `post_entry_call`, with its callout header plus `StackClaim.encode`). `PlayerStack` posts the same for the human, so the team counts it like an ally. The latest call repeats every `StackClaim.HEARTBEAT` so the claim stays live. `radio.say` stamps `claim_frame` / `claim_pos` only on a new claim (a heartbeat or re-claim keeps the pair that same-frame settling reads) and `crossed_frame` the first time its step is `going_in` or a through step (cleared by `reset`), plus the bang and order fields.

## Read-outs and tunables

`Behavior.entries.debug()` and `debug_view()` feed the entry overlays (`debug.md`). Tunables: `tuning.entry` (`enabled`, `ready_timeout`, `listen_time`, `follow_gap`, `pie_dwell`, `corner_dwell`, `rear_security_time`, `cover_time`, `watch_dwell`, `approach_time`, `order_ready_cap`), `tuning.entry_geometry` (`stack_spacing`, `wall_standoff`, `pie_radius`, `pie_steps`, `corner_inset`, `short_room`; handed through `AgentPerception.apply_config`), `tuning.entry_guard` (`enabled`, `reach`, `rearm`, `secure_time`), plus `tuning.coverage.look_rate` for gaze turns.
