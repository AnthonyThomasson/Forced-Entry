# AI · Perception (`scenes/ai/perception/`)

SENSE: turns the world into what the NPC *knows*, then into the snapshot the planner walks (`snapshot.md`). It holds no policy: it never decides, picks or gates by goal. One public face, `agent_perception.gd` (a `Node`); nothing outside this folder holds its internal modules.

## Files

- `agent_perception.gd` — lifecycle (`setup`, `apply_config`, `bind`), SEE (`observe`), the per-tick reads, BUILD (`sense`).
- The face's parts, preloaded consts with no `class_name`, built once in `setup()`, each holding the perception: `perception_sight.gd` (`sight`), `perception_house.gd` (`house`), `perception_hearing.gd` (`hearing`), `perception_orders.gd` (`orders`), `perception_contacts.gd` (`contacts`), `perception_grenades.gd` (`grenades`), `perception_entry.gd` (`entry`), `perception_views.gd` (`views`). `perception_confinement.gd` (`confinement`) is a data leaf that holds no owner (`tests/ai/ai_parts_free_suite.gd`).
- `agent_vision.gd` (sight and the one owner of the ray query), `agent_hostility.gd`, `agent_memory.gd`, `agent_suspicion.gd`, `house_rooms.gd` (`HouseRooms`: room lookups and how a doorway joins rooms; perception, snapshot, door views, entry geometry and the team all share it).
- `agent_tactics.gd` → `perception-tactics.md`; `agent_entry.gd`, `entry/`, `agent_door_views.gd` → `perception-entry.md`, `perception-views.md`; `stack/` → `perception-stack.md`; `agent_grenades.gd`, `agent_throw.gd` → `perception-grenades.md`; `agent_snapshot.gd`, `snapshot/` → `snapshot.md`.

## Lifecycle

The controller calls `setup()` once, then `apply_config(tuning)`, then `bind(character)` on its first `control()`. `apply_config` runs **again every decision** so a tunable retuned at runtime (a behaviour test, the dev command server) reaches the modules without a rebuild that would wipe the event memory. Tunables are `NpcTuning` topics read live (`tuning.memory`, `tuning.senses`, ...); modules built without a controller (`AgentVision`, `AgentMemory`, `AgentThrow`, `AgentEntry`, `AgentDoorViews`: the tests, `scenes/ai/team/`) keep their own defaults. After `bind` no function takes the character.

## Seeing

- Sight cadence is staggered per NPC (`SIGHT_EVERY_FRAMES` in `perception_sight.gd`, `LEARN_EVERY_FRAMES` in `perception_house.gd`, both offset by the node's instance id) and `sense()` re-runs the learning look, so what is known at a decision is what is seen then. The range/cone test runs every frame: a character entering the cone is sighted at once, one leaving is dropped at once. A primed ambusher at its post (`sight.primed`) sights every frame (`docs/leadership.md` D37). `tests/ai/perception/sight_follows_a_moving_target_test.gd`.
- `can_see` needs range, the awareness bubble or the forward cone, and a clear line on `PhysicsLayers.SOLID`. The sight line looks **over** low cover (`coverage` at or below `see_over_coverage`); `blocked()` / `raycast()` stay fully physical for line of fire and cover, so a table stops a bullet but not a glance. `enabled = false` is omniscient.
- `tuning.memory.familiar_with_house` pre-knows every room and object; otherwise each must be seen. People are never pre-known.
- A blinded NPC (`Character.stun.is_blind()`, G15) skips the sighting pass and the learning look. `contacts.known()` keeps every sighting the memory holds (`lead_ttl`, not `contact_ttl`) while blind, so it fires at the last-known spot of the one it fought. It is back to `contact_ttl` the tick it sees again.
- `contacts.known()` is the list the behaviour hands to its locomotion: a walk goes round, stops short of or gives way to only these, never a body the NPC has not seen.

## Hostility

Allies (same faction) are never hostile. `on_sight`, `trespass` (seen inside the house) and `retaliate` (attacked it) come from `tuning.hostility`; a verdict is a `&"hostile"` memory event with ttl `tuning.hostility.ttl` (≤ 0: permanent).

## Memory (`agent_memory.gd`)

A behaviour-agnostic event log. Writes with a `key` **supersede** the live event of the same topic and key, so something re-observed every tick stays one entry instead of volume-evicting the rest. Permanent events (ttl ≤ 0) never age out and are never volume-evicted. Events live in one list per topic with a cross-topic `seq`, so a read costs the topic's size. **The clock is `GameClock`** (interface 11, `docs/leadership.md` LD1): a pause expires nothing and a headless `--fixed-fps` run ages at sim pace; every other perception age reads it too. `tests/ai/perception/memory_matches_reference_test.gd` compares each reader to a plain log, `clock_pauses_test.gd` pins the pause.

## Hearing and the radio

- A hit on or near the NPC → `under_fire`, `engaged`, hostility. An ally's round (same faction) striking near it is not under fire; one that hits it, or one from a hostile or unknown shooter, is. A farther hit is a `heard_gunfire` lead **only from a shooter not already known hostile**. A hit from anyone but an ally also leaves `shot_from` (the line back to the first wall), which outlives `under_fire` and makes the rooms on that line suspect (`agent_suspicion.gd`, G18). `tests/ai/perception/ally_round_nearby_not_under_fire_test.gd`.
- Footsteps of other factions are heard through walls by gait (`tuning.senses` `hear_walk` / `hear_run` / `hear_crouch`, `docs/hearing.md` H1): a lead and a reason to suspect the room.
- A deaf NPC's callouts, hits not on it, footfalls and grenade landings are dropped by the controller (G15).
- `hearing.process_callout`: every callout goes to the NPC's `ClaimLedger`; a callout that is only an order's progress (`order_step`, no `entry_step`) returns before the memory so it never replaces the ally's entry claim; a grenade status (`grenade` / `frag_out` / `bang_out`) goes to the grenade tracker and returns before the memory; `cleared_room` teaches and marks the room cleared.

## Orders (`perception_orders.gd`, `docs/leadership.md`)

An `&"order"` naming the NPC from its own side becomes its live order (memory topic `order`, permanent, keyed `live`); a `cancel` ends it; `process` returns true when the order changed (the controller decides at once). A `go` replaces nothing: it latches `go: true` on the held `stack` order and returns false. `orders.held_room()` is the room a held stack is to enter, which the reflexes feed to `confinement.keep_out`. An `ambush` ends `done` on first contact (under fire or a hostile in sight; steps and callouts are no contact), run at the end of every `observe`.

## Confinement (`perception_confinement.gd`, `GLOSSARY.md` Confinement)

Where the NPC may act: four rules that must all hold at a point — `inside_only` (territory), `room` (a `defend_room` order), `leash_center` / `leash` (a squad follower holding no order), `keep_out` (the room a held stack is to enter). The reflexes `refresh` it once a tick in SENSE, after the order intake, and again as `_start_decision` refuses an order. `allows_option` judges an option where it acts (`params.from`, else `params.point`; an option with no place is allowed). `sense()` freezes a `copy()` into `snapshot["confinement"]` for the planner's COMBAT filter (`decision.md`); behaviour, `Combat` and the reflexes read the live one. `debug_state()["confinement"]` is the live `view()`. Tests: `tests/ai/perception/confinement_suite.gd`, `ai/decision/combat_options_within_confinement`, `ai/combat/combat_spot_within_confinement`.
