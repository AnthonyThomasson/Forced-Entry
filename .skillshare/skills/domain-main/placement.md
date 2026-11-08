# Main: NPC placement

Side file of `domain-main` (`SKILL.md`).

## `match_spawner.gd`

`populate` builds one per match and records every NPC it places in `combatants` (spawn order); `match_spawn_clear_test` builds
one with no `bind`.

- **Clear** (`is_clear`): at least `spawn_clearance` from every solid furniture footprint (`NavBuilder.furniture_holes`, read
  off shapes, right on the frame the house is built) and twice that from every placed combatant. `clear_spot` tries the room's
  centre, then `SPAWN_TRIES` random points; nothing clear logs and falls back to the centre. A body spawned inside a piece is
  ejected with the piece's momentum and flung.
- **Invader team** (`spawn_invader_team`, `docs/leadership.md` LD27), one group packed round a point:
  - beside the front door (`_beside_front_door`): `DOOR_SIDE_OFFSET` along the outside wall from the doorway's centre, on a
    side drawn from `rng`, and `DOOR_OUT_OFFSET` out from the wall, clamped into the rooms' bounds grown by twice
    `invader_margin` less two `spawn_clearance`, so the first ring stays on the walkable ring round the house;
  - round a human invader (`around`, whose start every member keeps clear of);
  - no front door: `perimeter_point` of the bounds grown by `invader_margin`.

  `_group_spot` walks rings twice `spawn_clearance` apart (`GROUP_RINGS`) for the first spot that is clear, `_outdoors` and,
  beside the front door, outside the doorway's straight strip (`_in_strip`); none logs and falls back to the point.
- **`add_npc` binds, then adds.** A body added at the world origin and moved afterwards overlaps whatever stands there for a
  frame, and physics launches that piece across the map (`match_spawn_origin_test`).
