1. **Main (through `MatchBuilder`, interface 23) → World Generation**
   - `WorldGen.generate(seed, force_plan, front_entrance_world, parent) -> Node2D` — one lone house, unturned (its front door on the
	 south wall), from `HouseDefinitions.PLANS` only; one RNG for the whole run (the plan pick is its first draw), prints `House: <plan>
	 seed: N`; a doorway with no door (the roll, or `worldgen.doors` off) is an open archway, one with a door holds a `Door`
	 (`docs/doors.md` DR2 to DR4).
   - `WorldGen.generate_district(seed, force_plan, front_entrance_world, parent) -> Node2D` — a downtown district: a 3 x 3 grid of
	 blocks, a **tower** in each (ground floors from `TowerDefinitions`, six plans, built as a house is), asphalt streets and sidewalks
	 between and round them, and a ring of 16 roofless **shells**. The centre tower is the **house**: `force_plan` (any house or tower
	 plan, else a tower plan by the seed). Every tower is turned in quarter turns by the seed so its front door faces one of its block's
	 streets, and the house's front door lands on `front_entrance_world`. One seed reproduces the whole district. The root (a `Node2D`
	 `District` at the origin, so every position is world space) carries the metas `house`, `towers`, `rooms`, `streets`, `shells`,
	 `streetlights` and `clutter`. `MatchBuilder.stage` generates one when the spec names no `house`.
   - District reads: `WorldGen.house_of(district) -> Node2D` (the house node, on which `get_rooms`, `get_openings`, `get_doors` and
	 `get_lobbies` read as for a lone house; null for no district), `district_rooms(district) -> Array` (every tower's rooms in world
	 space, the house's keys plain and a neighbour's `<block>:<key>`, block 0 to 8, so no two clash) and `district_bounds(district) ->
	 Rect2` (the street pieces' rect out to where the shells begin: what the nav bake must cover). The test reads are `DistrictReads`
	 (`get_towers(district)`: `{ block, plan, turn, node, rect, front, shadow, podium, awning, sign }` per tower, block 4 the house;
	 `get_shells(district)`: `{ rect, node, holder }`; `get_district_street(district)`: `{ kind, role, rect, node, block }` per street
	 floor) and `WorldGen.get_streetlights` / `get_clutter` on the district root (the lamps of every sidewalk, the sidewalk clutter).
   - `WorldGen.get_rooms(house) -> Array` — `{ key, type, rect }` dicts (world-space `rect`), from the house's `rooms` metadata.
   - `WorldGen.get_openings(house) -> Array` — `{ pos, width, front, exit, rooms, outward, door }` dicts, from its `openings` metadata:
	 `rooms` = keys of the rooms the doorway joins, `outward` parallel to `rooms` (each the unit normal out of that room through the
	 doorway's wall), `front` = the one front entrance (the south wall of a lone house; a tower faces whichever way it was turned), `exit` = a back/side/garage door (one room each), `door` = whether a door stands in it.
   - `WorldGen.get_doors(house) -> Array` — `{ node, opening, material, style }` dicts, from its `doors` metadata: `node` the `Door`
	 (interface 24, a child of the house's `Doors` node), `opening` that doorway's `get_openings` entry. Every front and exit doorway has
	 one, an interior doorway by its more private room's type (`DoorRules`), as its plan forces or forbids. Empty for a hand-laid layout
	 or with `worldgen.doors` off.
   - `WorldGen.get_lobbies(house) -> Array` — `{ room, rect, node, text }` per elevator lobby (a test read): `room` its key, `rect` its
	 world rect, `node` the floor stencil laid in it, `text` what it says ("WIP ELEVATOR LOBBY"). A tower has exactly one, empty of pieces
	 and clutter; a house plan has none.
   - `WorldGen.bounds(rooms) -> Rect2` — the bounding box of room dicts (zero `Rect2` for none).
   - Run-down dressing, read from the `wear`, `clutter`, `street` and `streetlights` metadata (empty for a hand-laid layout; only tests
	 call these four getters): `WorldGen.get_wear(house)` — `{ room, pos, layer }` per wear cluster (`layer` the CanvasItem drawing that
	 room's wear, one per room); `WorldGen.get_clutter(house)` — `{ room, key, node }` per walk-over clutter piece (non-solid, never
	 carved into the nav map); `WorldGen.get_street(house)` — `{ kind, rect, node }` per piece of the street ring (`kind` `street` /
	 `sidewalk`; none registers a `SoundSurface`, interface 16, so footsteps out there stay `outdoor`); `WorldGen.get_streetlights(house)`
	 — `{ pos, node }` per lamp along the front sidewalk (`node`: a solid, anchored post carved into the nav map, its arm and head an
	 overhang; spacing `WorldGenStreetConfig.streetlight_every`; a lamp within `streetlight_door_clear` of a front or exit doorway, or
	 in the strip straight out of one, is dropped).
   - Read-only catalogue lookups (Testing places single pieces with them): `WorldGen.object_definition(key)` (for
	 `ObjectFactory.spawn`), `WorldGen.floor_definition(key)` (for `FloorFactory.spawn`), `WorldGen.door_definition(material, style)` (for `DoorFactory.spawn`),
	 `WorldGen.wall_style()` (the house wall `style` for `WallFactory.spawn`).
   - `WorldGen.annotate_layout(root, rooms, doors = [])` — for Testing's hand-built arenas: stores the same `rooms` / `openings`
	 metadata a generated house carries (a doorway declaring a `door` reports `door` true; a door on one room's wall only is the front entrance), so `get_rooms`, `get_openings` and
	 `NavBuilder` read them unchanged. No other caller writes those keys.

   `MatchBuilder` (interface 23) generates a district (else stages the spec's house) with the house's front entrance where the spec puts
   it, fixes draw order and builds the nav map over every tower and street (interface 9). Its `match_spawner.gd` places defenders and the invader team through the house's `get_rooms` / `get_openings`
   only (a neighbour tower is outside for the AI) (rules: `spawn_clearance` / `invader_margin` of the match spec read off `NavBuilder.furniture_holes`; the invader group beside
   the front door, `docs/leadership.md` LD27), and hands every NPC the house's `get_openings` (tactical entry) and an invader the
   front entrance. It never touches world-gen internals.
