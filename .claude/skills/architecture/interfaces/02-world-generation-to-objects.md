2. **World Generation → Objects** (the only way world-gen makes entities)
   World-Gen owns the *catalogue*; Objects owns the *field schema* and turns a plain definition dict into a node. World-Gen never
   touches an object's fields.
   - `ObjectFactory.spawn(definition: Dictionary, position, parent, opts) -> Node` — `opts`: `name`, `rotated`, `color`, `facing`, `neon`
	 (`"cyan"` / `"magenta"` / `""`: the piece's neon trim or screen; omitted, Objects picks per piece for a share of the light-giving
	 pieces, from where it stands). Two definition fields shape a piece beyond its look: `anchored` (true: a solid piece frozen static, no
	 push, kick, round or blast shoves or turns it; it is still struck, dented and throws debris) and `overhang` (`{ size, reach }`: an
	 overhead part drawn beyond the footprint by the piece's painter with `part: "overhang"`; a child CanvasItem named `Overhang` with
	 `get_rect() -> Rect2`, at `DrawLayers.OVERHEAD`, no collider).
   - `WallFactory.spawn(rect: Rect2, walls: RoomWalls, name, parent) -> Node` — `RoomWalls` (`objects/room_walls.gd`): `thickness`,
	 `openings`, `style` (the cap's look: `art`, `color`, `art_opts`; empty = a flat gray line).
   - `WallFactory.openings_for(rect: Rect2, doors: Array) -> Array` — the `{ pos, width }` doorways on `rect`'s walls, as `spawn` takes
	 them (World-Gen and Testing's layouts use it). `Wall.Side` is the enum inside those `openings`.
   - `FloorFactory.spawn(rect: Rect2, definition: Dictionary, name, parent) -> Node` — a room's floor or a piece of the street (no
	 collider). Definition: `art`, `color`, `material`, `art_opts`, optionally `sound_surface` (false: registers no `SoundSurface`, the
	 street), `marks` (`{ seed, lane, edges }`: the street's world-placed curb and gutter litter, laid by Objects), `tile_from` (the
	 point in `parent`'s space its repeating tile starts from, so neighbouring pieces share a grid) and `light_layer` (`"street"`: the
	 piece and its canvas items on `LightMasks.STREET`, interface 20).
   - `WearFactory.spawn(rect: Rect2, plan: WearPlan, name, parent) -> Node2D` — a room's wear (one node per room, built after the
	 floors and walls). `WearPlan` (`objects/wear_plan.gd`): `floor_definition`, `wall_thickness`, `clusters` (`{ pos, wall, seed }`:
	 centre, the free stretch of wall `[a, b]` it is by or `[]`, the seed of its marks, in `parent`'s space). World-Gen places the
	 clusters; Objects decides each one's marks and draws them.
