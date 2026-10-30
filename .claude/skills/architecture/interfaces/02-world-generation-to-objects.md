2. **World Generation → Objects** (the only way world-gen makes entities)
   - `ObjectFactory.spawn(definition: Dictionary, position, parent, opts) -> Node` — `opts`: `name`, `rotated`, `color`, `facing`,
	 and `neon` (`"cyan"` / `"magenta"` / `""`: the piece's neon trim or screen; omitted, Objects picks it per piece for a share of
	 the light-giving pieces, from where it stands). Two definition fields shape a piece beyond its look: `anchored` (true: a solid
	 piece that never moves, frozen static: no push, kick, round or blast shoves or turns it, it is still struck, dented and throws
	 debris) and `overhang` (`{ size, reach }`: an overhead part drawn beyond the footprint by the piece's painter with
	 `part: "overhang"`, `size` across x out, centred `reach` px out along its facing; a child CanvasItem named `Overhang` with
	 `get_rect() -> Rect2` (the area it draws, in its own frame), at `DrawLayers.OVERHEAD` above the characters, with no collider).
   - `WallFactory.spawn(rect: Rect2, walls: RoomWalls, name, parent) -> Node` — `RoomWalls` (`objects/room_walls.gd`):
	 `thickness`, `openings` and `style`, the cap's look (`art`, `color`, `art_opts`); an empty `style` = a flat gray line.
   - `FloorFactory.spawn(rect: Rect2, definition: Dictionary, name, parent) -> Node` — a room's
	 floor or a piece of the street (no collider), from a floor definition (`art`, `color`, `material`, `art_opts`, and optionally
	 `sound_surface` (false: registers no `SoundSurface`, the street), `marks` (`{ seed, lane, edges }`: the street's world-placed
	 marks, curb and gutter litter, laid by Objects over the piece), `tile_from` (the point in `parent`'s space its repeating
	 tile is laid from, so neighbouring pieces share one grid) and `light_layer` (`"street"`: the piece and its canvas items on
	 `LightMasks.STREET`, interface 20)).
   - `WearFactory.spawn(rect: Rect2, plan: WearPlan, name, parent) -> Node2D` — a room's wear, from a `WearPlan`
	 (`objects/wear_plan.gd`: `floor_definition`, `wall_thickness`, `clusters`): World-Gen places the clusters (`{ pos, wall, seed }`: centre, the free stretch of wall `[a, b]` it is by or `[]`,
	 the seed of its marks, in `parent`'s space); Objects decides each cluster's marks (on the floor, following its pattern, and
	 often on that wall) and draws them. Built after the house's floors and walls; one node per room.
   - `WallFactory.openings_for(rect: Rect2, doors: Array) -> Array` — the `{ pos, width }` doorways that lie
	 on `rect`'s walls, as the `openings` `spawn` takes (World-Gen and the Testing domain's layouts use it).
   - `Wall.Side` — the enum inside those `openings` (callers get them from `openings_for`).
   World-Gen owns the *catalogue*; Objects owns the *field schema* and turns a plain definition
   dict into a node. World-Gen never touches an object's fields.
