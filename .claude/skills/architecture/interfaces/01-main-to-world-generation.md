1. **Main (through `MatchBuilder`, interface 23) → World Generation**
   - `WorldGen.generate(seed, force_plan, front_entrance_world, parent) -> Node2D` — seeds one RNG
	 for the whole run (plan pick is its first draw), prints `House: <plan>  seed: N`, builds
	 the house; every doorway is an open archway.
   - `WorldGen.get_rooms(house) -> Array` — the house's rooms as `{ key, type, rect }` dicts
	 (world-space `rect`), read from the house's `rooms` metadata.
   - `WorldGen.get_openings(house) -> Array` — the house's doorways as `{ pos, width, front, exit, rooms, outward }` dicts
	 (world-space `pos`, `rooms` = keys of the rooms it joins, `outward` = parallel to `rooms`, each the unit normal out of
	 that room through the doorway's wall; `front` = the one front entrance, on the south
	 wall, `exit` = a back/side/garage door, each with one room), read from the house's `openings` metadata.
   - `WorldGen.bounds(rooms) -> Rect2` — the one bounding box of a list of `{ rect, ... }` room dicts (a zero `Rect2` for none).
   - The run-down dressing a generated house carries (test reads: no game code calls these four getters), read from its `wear`, `clutter` and `street` metadata the same way (empty
	 for a hand-laid layout): `WorldGen.get_wear(house) -> Array` — `{ room, pos, layer }` per wear cluster (0-3 a room, by a wall,
	 a corner or furniture; `pos` its world-space centre, `layer` the CanvasItem drawing that room's wear, one per room);
	 `WorldGen.get_clutter(house) -> Array` — `{ room, key, node }` per walk-over clutter piece (0-2 a room, no `key` twice; a
	 non-solid catalogue piece, never carved into the nav map); `WorldGen.get_street(house) -> Array` — `{ kind, rect, node }` per
	 piece of the street ring round the house (`kind` `street` or `sidewalk`, world-space `rect`, `node` the floor drawing it;
	 none registers a `SoundSurface`, interface 16, so footsteps out there stay `outdoor`); `WorldGen.get_streetlights(house) -> Array`
	 (its `streetlights` metadata) — `{ pos, node }` per street lamp along the front sidewalk (`pos` its world-space centre, `node` the
	 placed piece under the house: a solid, anchored metal post, carved into the nav map, its arm and head an overhang; about
	 `WorldGenStreetConfig.streetlight_every` px apart, none within `streetlight_door_clear` px of a front or exit doorway's centre nor in the
	 strip straight out of one: a lamp that would be is dropped).
   - Read-only catalogue lookups (used by the Testing domain to place single pieces):
	 `WorldGen.object_definition(key) -> Dictionary` (for `ObjectFactory.spawn`),
	 `WorldGen.floor_definition(key) -> Dictionary` (for `FloorFactory.spawn`) and
	 `WorldGen.wall_style() -> Dictionary` (the house wall `style` for `WallFactory.spawn`).
   - `WorldGen.annotate_layout(root, rooms, doors = [])` — for the Testing domain's hand-built arenas and layouts: stores the
	 same `rooms` / `openings` metadata a generated house carries (a door on one room's wall only is the front entrance), so
	 `get_rooms`, `get_openings` and `NavBuilder` read them unchanged. No other caller writes those keys.
   `MatchBuilder` (interface 23) generates the house with its front entrance where the spec puts it, fixes draw order and builds the nav
   map from the rooms (interface 9); its `match_spawner.gd` drops each defender at a clear spot in a random room (its centre unless solid
   furniture is within `spawn_clearance` or another combatant within twice that — read off `NavBuilder.furniture_holes` — else a random
   clear point) and the invader team in one group just outside the house (`spawn_invader_team`, `docs/leadership.md` LD27: packed round a
   point away from and to the side of the front entrance, 220 px along the wall from the doorway's centre on a side drawn from the house
   seed and 120 px out from the wall (kept on the walkable ring), no member in the doorway's straight strip; round the human invader's spot when there is one; in a house with no front entrance,
   round a point of the ring `invader_margin` out of the rooms' bounding box, drawn from the house seed) (all via `get_rooms` /
   `get_openings`), and hands every NPC the house's `get_openings` (for tactical entry) and an invader the front entrance; it never touches
   world-gen internals.
