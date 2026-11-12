---
name: domain-ai
description: Use when editing scenes/ai/ or working on NPC goals and behaviour, or to find which AI sub-domain owns a concern. The map of the AI: its shape, sub-domains and the side file for each.
---

# AI domain (`scenes/ai/`)

Non-player brains. **One** generic, data-driven controller drives every NPC (house defender and invader alike): no per-NPC-type or per-goal code. An NPC's behaviour is DATA on its scene: a plain-language `goal` string (`{gun}` stands for its own gun) plus generic primitives (hostility rules, pursuit, territory) and decision-tree config. The controller writes the character's intent and calls its public action API; it never reaches into character internals. Nothing is written per weapon: the NPC fights with `Character.inventory.gun_slot()` and reacts to generic conditions the character reports (a long gun blocked by a wall: it steps back until it can fire).

**Key idea: Von picks, perception informs, behaviour executes.** Von ranks distinct, verb-like options well but cannot do arithmetic or compare near-identical spatial points, so every level offers a few DISTINCT options whose text carries the deciding facts as bands. The NPC acts only on what it has PERCEIVED: it fights a hostile's last-KNOWN position, loses a contact once its sighting decays (it becomes an investigation lead), and (unless `tuning.memory.familiar_with_house`) must see rooms and objects before it can use them.

## Shape: sense → decision-tree walk → primitive

Each tick the orchestrator (`goal_controller.gd`, `orchestrator.md`) folds queued events into **perception**, which `observe()`s; **behaviour** resolves contacts and honours commitments. When free or forced it asks its **decision job** for a decision: a claim on the frame's pool of work units, then perception's **snapshot** built in pieces and a **decision** walk (the planner asks Von one `choice` per tree level), each piece run as the pool allows; the returned leaf is adopted into behaviour, which runs it as a **primitive** (move / engage / melee / interact / hold / reload / entry / throw / defend / ambush / follow). The sub-domains are isolated modules under `scenes/ai/`, each talking to the others only through a small published interface, as the game's top-level domains do.

| Sub-domain | Folder | Role |
|---|---|---|
| Orchestrator | `goal_controller.gd`, `npc_cadence.gd`, `npc_comms.gd`, `npc_reflexes.gd`, `tuning/` | The AI's composition root; the single authoring surface (`tuning`) and observer surface. |
| Perception | `perception/` | SENSE: what the NPC knows (sight, hostility, memory, hearing, tactics geometry, doorway geometry, grenades known) and the **snapshot** (`agent_snapshot.gd`, `perception/snapshot/`) worded for Von. |
| Decision | `decision/` | THINK: the tree (data), the planner that walks it, the Von transport and dev server launcher. |
| Behaviour | `behavior/` | ACT: runs the leaf's primitive and the state Von lacks (engagement, commitment, pathing). Its modules: `combat.gd`, `search_coverage.gd`, `watch.gd`, `entry.gd`. |
| Debug | `debug/` | Draw-only overlays. |
| Team | `team/` | Not a sub-domain: the human's `PlayerStack` (interface 17) and each side's `Squad` (interface 21). |

The **stack seam** is `perception/stack/` (`StackClaim`, `ClaimLedger`, `DoorStack`, `StackLayout`, `StackMember`): a doorway's stack as the radio describes it, held once. Behaviour reads it as `AgentPerception.entry.stack(opening, into := "")` and preloads the files; the team preloads them, plus `AgentEntry`, `AgentVision.wall_hit` and `HouseRooms`. `perception-stack.md`.

## Side files: read the one that matches the task

Orchestrator and decision flow
- `orchestrator.md` — editing `goal_controller.gd`, `npc_cadence.gd`, `npc_comms.gd` or `npc_reflexes.gd`; when a decision starts or is interrupted, how orders and following reach the loop, ambush priming, the EventBus intake.
- `decision.md` — editing `scenes/ai/decision/`: the decision tree, adding a mode or tactic, entry rules (under fire → combat), what Von is asked at each level, how an option is chosen, the confinement filter. Then `decision-job.md` for one decision as a job against the work-unit pool (`DecisionBudget`, `decision_job.gd`: claim, pieces, interrupt), and `decision-von.md` for the Von transport, the server-down fallback, `DecisionStub`, and auto-starting or reusing the Von server.

Perception (what the NPC knows)
- `perception.md` — editing `scenes/ai/perception/` (except the snapshot): vision, memory and eviction, hostility, hearing, orders intake, the confinement rules. It lists the parts and points on.
- `perception-tactics.md` — flank sides, fire / advance / retreat spots, route safety and exposure, cover, throw spots (`agent_tactics.gd`).
- `perception-entry.md` — doorway geometry for a tactical entry: stack slots, pie arc, corners, defend and ambush posts, where an entry's grenade lands.
- `perception-bookkeeping.md` — what perceptions share: `known()` in one pass, one character list per frame, the house intake's skips, the early hit and callout filter.
- `perception-views.md` — doorway views and the walk that keeps out of them, the entry guard's reads (`agent_door_views.gd`).
- `perception-stack.md` — the claim wire format, the ledger, slot rules and a member's claim (`stack/`).
- `perception-grenades.md` — live grenades known, the danger zone, the evade plan, `can_lob`, a blinded or deafened NPC.
- `snapshot.md` — editing `agent_snapshot.gd` or `snapshot/`: adding a fact, a state section or an option group, or changing what Von is told. Then `snapshot-wording.md` for the measured wording rules and the grenade and suspect-room phrases.
- `snapshot-staged.md` — the snapshot build in resumable pieces (`begin_build`, `SnapshotBuild`, `AgentPerception.begin_sense`): the piece kinds, the start's gathering and the frozen confinement copy.
- `snapshot-demand.md` — the groups, facts and sections built when the walk first reads them (`SnapshotDemand`), `complete()` for the overlay and tests, the `grenade_ready` existence search, the heard leads' route memo.

Behaviour (how a chosen option is run)
- `behavior.md` — editing `scenes/ai/behavior/` (`behavior.gd`, `locomotion.gd`): how a chosen option becomes movement, holding ground, commitment and dwell timers, pathing, opening a door in the way (`behavior-doors.md`), posture and run policy, engagement and retargeting.
- `combat.md` — `combat.gd` and `combat_throw.gd`: how NPCs shoot, reload, take cover, step back from a blocked gun, punch, throw a grenade, peek and duck, ambush.
- `coverage.md` — `search_coverage.gd`: search and explore behaviour, covering a room by sight, the `search_coverage_*` tunables and overlay data.
- `watch.md` — `watch.gd` (`Watch.apply`), `errand.aim_move`, `gait.should_run`: where an NPC looks and when it takes the shot; an NPC turning its back on a threat, staring at a wall, or seeing an enemy and not shooting (spec `docs/gaze-and-fire.md`).
- `entry.md` — `entry.gd`, `entry/` and the entry guard in `behavior_entries.gd`: the tactical entry through a doorway, alone or as a team over the radio (stack, pie, bang, cross, corners, clear, rear security), the guard's detours, slots, ordered and held stacks.

Team and debug
- `team.md` — `scenes/ai/team/`: the human's place in an AI entry stack (`PlayerStack`), each side's squad (`Squad`), its leader, orders, following, rally and the defenders' ambush rule (`docs/leadership.md`).
- `debug.md` — editing `scenes/ai/debug/`: the vision cone, action label, path, tactics, search and behaviour overlays, and the controller's observer getters.
- `debug-words.md` — the overlays' words: `text_in_world`, the brain's `brain_labels`, `card_lines()` for the spectator's detail card, `drawn_texts()` and `BrainDebug.drawn()` for tests.

## The decision tree

ORDER (auto-picked) → COMBAT (engage, flank, grenade, advance, melee, reload, retreat, locate) → FOLLOW (auto-picked) → RELOAD_QUIET → INVESTIGATE (asked of Von; STAY declines an outside lead) → SEARCH (enter, stun entry, a room or unexplored area) → IDLE (use, go, wait). Entry rules skip the broad levels when the situation is clear (under fire or engaged → COMBAT; ordered → ORDER; pursuing and a hostile known → COMBAT; a follower → FOLLOW); a level with one option is taken without asking. `decision_tree.gd` is the source.

## The two presets

Spawned by `MatchBuilder.populate` (Main's `run.defender_count` / `run.invader_count`, default 1 each) and bound before they join the tree (`MatchBuilder.bind_npc`: the house's rooms and openings, an invader's front entrance); a test world binds its NPC actors the same way.
- **Defender** — `npc_defender.tscn` (faction `household`): `tuning.hostility.on_trespass` + `on_attack`, `tuning.decision.defend_territory` (combat options stay inside the house), familiar with the house. Dropped at a clear spot in a random room.
- **Invader** — `npc_invader.tscn`, an inherited scene overriding only data (faction `invader`): `on_sight`, not territorial, unfamiliar with the house (learns rooms by sight, is offered unexplored areas by direction), `tuning.entry.enabled` on (`docs/tactical-entry.md`). The match's invader team spawns in one group away from and to the side of the front door, on a side drawn from the house seed (`match_spawner.gd` `spawn_invader_team`, LD27), and follows its leader as a squad. A quiet stack that carries a stun listens at the stack before the pie (`tuning.entry.listen_time`, E17).

Both pursue hostiles (`tuning.decision.pursue_hostiles`, default on): IDLE is never offered and a known hostile sends every decision to COMBAT. Both know their ammo: the snapshot's `loadout` section and the `gun_loaded` / `weapon_low` / `can_reload` facts feed the RELOAD tactic, and `tuning.combat.auto_reload` reloads an empty gun as a reflex.

## Specs and tests

Behaviour specs the tests assert: `docs/flanking-behavior.md`, `docs/cover-and-stance.md`, `docs/tactical-entry.md`, `docs/gaze-and-fire.md`, `docs/grenades.md` (G15 stunned, G16 evade, G17 GRENADE, G18 STUN ENTRY), `docs/hearing.md` (H1: footsteps heard through walls, by gait), `docs/leadership.md`. Game tests: `tests/ai/<topic>/`; unit suites `tests/ai/*_suite.gd`; probes `tests/_ai/`. Von wording: `tools/von_probe.py`.

## Interfaces used (signatures in `architecture`)

3 (`Explosion.shields` / `first_stop`: the blast's cover rule), 6 (`ItemRegistry` slot ids, `Character.inventory.throw_stats()`, `weapon.aim_target()`), 7 (Character ↔ Controller: the observer reads, overlay exports, group `npc_controllers`), 9 (AI → Navigation), 10 (EventBus), 11 (`PhysicsLayers`, `GameClock`), 13 (`DecisionStub` / `DecisionServerLauncher` for tests), 15 (`GameLog`), 17 (`PlayerStack`), 21 (`Squad`), 22 (`DecisionServerLauncher`: Main's Von-server wait).
