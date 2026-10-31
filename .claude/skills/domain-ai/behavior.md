# AI behaviour sub-domain

The ACT half of the AI (`scenes/ai/behavior/`): `Behavior` runs the LEAF the decision planner chose, one primitive with its params, as movement and actions, and holds the System-Two state Von (a stateless ranker) lacks. It never chooses WHAT to do. It reads the world only through perception and drives the character only through the controller contract (interface 7: `movement.move_input` / `aim_point` / `run_input`, `movement.set_posture`, `inventory.select_slot`, `weapon.shoot`, `weapon.melee`, `anatomy.leg_kick`, `ammo.reload`, `use.interact_with`).

## Files

- `behavior.gd`: the executor (a `Node`): the commitment state and the read-outs. Its parts are nodes built once in `setup`, reached by preload const: `fight` (`behavior_fight.gd`: hostiles known, the contact fought; `engage`, `melee`, `reload`), `errand` (`behavior_errand.gd`: `move`, `interact`, `hold`, the search `coverage`, `set_up_walk`), `gait` (`behavior_gait.gd`: run and posture policy), `grenades` (`behavior_grenades.gd`: `throw`, the evade reflex, blind fire), `orders` (`behavior_orders.gd`: `defend`, `ambush`, `follow`, order steps, ordered stacks and joins), `entries` (`behavior_entries.gd`: the `entry` primitive over `Entry`, the entry guard and its detours).
- `combat.gd` (`combat.md`), `search_coverage.gd` (`coverage.md`), `watch.gd` and the watch stage (`watch.md`), `entry.gd` and `entry/` (`entry.md`).
- `locomotion.gd` and `locomotion/`: pathing, bodies, doorway views (`behavior-locomotion.md`).
- `running_leaf.gd`: the data leaf `task` (`primitive`, `params`, `path`, `labels`, `arrived`, `resolved`, `resolve_reason`, `held`, `take_resolved()`, ...).

The controller calls `setup(perception, nav_agent, tuning)` once, then `apply_config(npc_squad)` each decision (squad into `orders.squad` and `Entry.world.squad`), and `bind(character)` on its first `control()`, which hands the body to each module so no module function takes the character. No module keeps a tuning copy: each reads `tuning.<topic>.<name>` live, so a retune holds from the next read.

## Primitives

| Primitive | Part | Notes | Re-decides |
|---|---|---|---|
| `move` | errand | Stops on arrival and zeroes `move_input` every tick after, so the NPC stands while the next decision is in flight. A `look_around` move walks INTO the room, then covers it by sight (`coverage.md`). ADVANCE is a `move` with `aim: target`. | Arrival; a `look_around` only once covered or out of budget (`max_commit_time` caps the walk in) |
| `engage` | fight | Walk to the anchor firing at will, then peek-and-cover or ambush (`combat.md`). ENGAGE and FLANK use it. | Moving: `max_commit_time`. In position: `tactic_interval`, or `engaged` lapse |
| `melee` | fight | Closes in only while the confinement allows the contact's last-known spot. | `tactic_interval` / `engaged` lapse |
| `interact` | errand | Walk to the object, face it, run it, hold `interaction_dwell`. | Dwell over, or approach cap |
| `reload` | fight | Equip the gun, stand, `ammo.reload()`. | The reload ending, or `max_commit_time` |
| `entry` | entries | A tactical entry through a doorway (`entry.md`). The entry guard also runs it as a detour in the middle of another order. | When the entry is over; never on the cadence |
| `throw` | grenades | The GRENADE tactic (G17): optional walk to the throw spot (guarded like an engage's), take the grenade, aim, throw, radio `frag_out` / `bang_out` (`grenades.take_throw_calls`), gun back, stand out the fuse. | The grenade has gone off or the throw failed; none in the wind-up (committed) |
| `defend` | orders | Walk to the post (`DEFEND_REACH`), stand, the watch stage on `door_pos`; walks back when pushed `DEFEND_DRIFT` off. Crouches in a fight like a hold. LD8, D2. | Walking: `max_commit_time`. At the post: only when `engaged` is fresh or forced |
| `ambush` | orders | The `defend` walk and hold, crouched once arrived. LD15. | Its order no longer live (`_live()`: first contact ends it, D18; a cancel; a new order) or, walking, `max_commit_time` |
| `follow` | orders | Keep to `squad.follow_spot(character)`, re-aimed only once the spot moved `SquadFollowConfig.retarget`; at the spot, face away from the leader (`confinement.leash_center`, refreshed by the controller's reflexes, no `squad.leader()` read) and top up a low magazine after `still_time` (`Combat.top_off`). LD20 to LD22. | Never on the cadence (`ongoing`); its spot gone (`Vector2.INF`) resolves it as a hold |
| `hold` | errand | Stand; the watch stage looks and shoots or turns among the room's doors. | Decide cadence |

The policies after a primitive steers (confinement, running, posture, orders, the evade reflex, the blind NPC) are `behavior-policy.md`. Option params are built in `scenes/ai/perception/snapshot/snapshot_options.gd`. A throw keeps its spot when the contact ages out on the way: `salient_key()` keeps that hostile while the perception holds it lost (`contacts.lost_hostiles()`, which drops the dead), and `update_known` ends a throw not yet in its wind-up whose target is neither a contact nor lost (`grenades.throw_target_gone`), so nothing is thrown onto a body.

## What the orchestrator calls

- `set_leaf(leaf)`: adopt (snap the point onto the navmesh, capture the target; a fight whose target is no longer known drops to hold and forces a decision). `update_known(known, delta) -> bool`: adopt the perception's hostiles, retarget a lost engaged contact to the nearest other, return true when a leaf that needs a target has none (re-decide).
- `task.take_resolved()` with `task.resolve_reason` read just before it ("way blocked" when a body seals the only way, "" for a finished task); `wants_decision(...)`; `apply(delta)`; `fallback()` (steady hold with no decision to be had; abandons any entry).
- `committed()`: crossing a doorway, throwing the bang, a throw's wind-up. No decision starts and `set_leaf` adopts none.
- `ongoing()`: the running choice is in progress; only then does the planner mark the option continuing it "(your current plan)", so a finished move is not re-picked just because it was last.
- `salient_key()`: the known-hostile ids and the engaged contact's inside state; a change forces a decision.
- `errand.reached_lead()`: the investigation lead a move reached, handed to perception's `check_lead()` so it is not offered again.
- Calls the controller radios or overlays read: `entries.take_calls()`, `entries.take_turned()` and `adopt_bang(path, labels)` (an ENTER turned bang is re-adopted as STUN ENTRY, E17), `grenades.throw_plan()`, `orders.take_steps()`, `entries.debug()` / `debug_view()`, `fight.debug_combat()`, `errand.debug_coverage()`, `debug_progress()`, `order()`.
- Read-only: `current_act()`, `in_combat()`, `debug_status()` (the full decision path joined with " - ", then progress), `activity_text()` (the same plus how long, for Von's "current activity" line), `debug_state()` (JSON-safe).

Interfaces: 7 (the character), 9 (nav map via `Locomotion`), 10 (callouts through the controller), 21 (`Squad.follow_spot`). Tests: `tests/ai/movement/`, `tests/ai/combat/`, `tests/ai/grenade/`, `tests/ai/posture/`, `tests/ai/ai_parts_free_suite.gd` (no part holds its owner).
