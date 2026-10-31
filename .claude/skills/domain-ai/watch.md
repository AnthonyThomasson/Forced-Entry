# AI watch stage

Where an NPC looks and when it takes the shot, in every primitive: `scenes/ai/behavior/watch.gd` (`Watch`, a `RefCounted` built in `Behavior.setup`, bound once) and its stage `Watch.apply(behavior, delta)`. Spec and tests: `docs/gaze-and-fire.md` (W1 to W6; `tools/run_tests.sh gaze`).

**Invariant:** an NPC is always either looking at (and, when it can, shooting) a threat, or watching its doors; never a wall, never with its back to a known threat.

`Character.movement.aim_point` is the only thing that sets facing. It is never reset and defaults to the world origin (an unset one means "where the body points"). Primitives set it only as they steer; the watch stage runs after them in `Behavior.apply` and has the last word. It is the one place a threat is shot at (`Combat.fire_at_will`), so no primitive or entry phase has its own fire call.

## The stage

1. It clears `threat` and does nothing when the character is busy (`use.is_busy()`) or the primitive keeps its own gaze (`_own_gaze`): `melee`, `interact`, an arrived `engage`, a `throw` whose grenade is not yet away, an `entry` in its `bang` phase.
2. **Threat** (`_pick_threat`): the engaged contact if visible, else the nearest visible, else the engaged one as last seen, else the nearest younger than `tuning.watch.lost_gaze`. A contact not visible counts only while `has_line_to` its last-seen spot is clear (no staring at a wall someone is behind).
3. With a threat: `aim_point` = its position BEFORE any gate, then `Combat.fire_at_will` and, unless the entry is crossing (`committed()`, E4), `Combat.reload_if_dry`. Steps 2 and 3 are `fight_threat(behavior) -> bool`, which the evade reflex calls too while it holds its spot (the stage itself does not run during an evade; `docs/grenades.md` G16, `behavior.md`).
4. With none and the primitive resting (`_resting`: `hold`, `reload`, an arrived `move` not covering a room, a `throw` once the grenade is away, an arrived `defend` / `ambush`): `idle_gaze` turns among the room's doorways. A `defend` or `ambush` whose params carry `door_pos` eases the gaze onto it instead (D2, LD15). An ambusher at its post is primed by the controller's reflexes (D37), so this stage sees an entrant on the frame the step opens the line, with no change here.

`gaze` (`threat` / `doors` / `primitive`, `evade`) and `threat` are in `debug_state()["gaze"]`.

## Gotchas

- **Walkers look ahead:** `travel_point()` is the farthest point down the walk the nav agent was just given (`Locomotion.path_ahead()`) with a clear line, up to `tuning.watch.look_ahead`. The next waypoint alone hugs the door jamb. `errand.aim_move` and `Entry.sweep.aim_travel` use it.
- **Every gaze turn goes through the static `Watch.ease_gaze(character, point, rate, delta)`** (doors here, `Entry.sweep.look_toward`, `SearchCoverage.step`; rate `tuning.coverage.look_rate`). It eases from the actual facing, not a private angle, so the gaze does not snap back when a threat lets go.
- **Doors:** `idle_gaze` turns among `perception.entry.room_doorways(room)` (outer doors included, each with a clear line and not under `DOOR_MIN_DISTANCE`), nearest first on entering a room, `door_dwell` apiece. Nothing outdoors or with no door in line. `reset()` on every new order.
- **No sprinting with a shot to take:** `gait.should_run` is false while `Combat.can_fire_at(threat)` or `Combat.reload_due()`, unless the leaf has `run_through_fire` (RETREAT). A running character can neither shoot nor reload.
- **Entry flags:** `state.gaze_held` (set from `threat` each tick) makes `sweep.look_toward` report settled, so a threat the gaze cannot settle on does not hold the pie. `state.hostile_in_view` (`entries._hostile_in_view`: threat plus line of fire) stops the pie and a follower's crossing while the stage fires (E14, `entry.md`).
- An arrived `move` zeroes `movement.move_input`, so the NPC stands still while the next decision is in flight. `Combat.peek_cover` shoots only once facing; `ambush` waits for the facing.
- A held NPC needs a look direction to see a target at start (test helper `Flank.npc`'s `opts.look_at`).

Tunables: `tuning.watch` (`look_ahead`, `door_dwell`, `lost_gaze`), read live; `Behavior` reads `lost_gaze` for `entries._hostile_in_view` too.

Tests: `tests/ai/gaze/`, with the helper `tests/_ai/gaze_probe.gd`; also `tests/ai/movement/` (`ai_runs_to_destination`, `retreat_keeps_running`) and `tests/ai/combat/combat_waits_for_facing_test.gd`.
