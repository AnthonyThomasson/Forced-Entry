2. **World Generation → Objects** (the only way world-gen makes entities)
   - `DoorFactory.spawn(opening: Dictionary, definition: Dictionary, parent: Node) -> Door` — a hinged door in a doorway (interface 24).
	 `definition` (`DoorCatalog`, via `WorldGen.door_definition`): `name`, `material` (`hollow` / `solid` / `steel` / `glass`, a key of
	 `DoorMaterialConfig.materials`), `style` (`flush`, `panelled`, `plank`, `riveted`, `peephole`, `panes`), `color`. `opening`: `pos` (the
	 doorway's centre), `hinge` (the world point on the jamb the leaf turns about), `swing_into` (unit vector into the room it swings
	 into), optionally `name` and `angle` (degrees from shut it starts at, default 0).
   World-Gen owns the *catalogue*; Objects owns the *field schema* and turns a plain definition dict into a node. World-Gen never
   touches an object's fields.
   - `ObjectFactory.spawn(definition: Dictionary, position, parent, opts) -> Node` — `opts`: `name`, `rotated`, `color`, `facing`, `neon`
	 (`"cyan"` / `"magenta"` / `""`: the piece's neon trim or screen; omitted, Objects picks per piece for a share of the light-giving
	 pieces, from where it stands). Two definition fields shape a piece beyond its look: `anchored` (true: a solid piece frozen static, no
	 push, kick, round or blast shoves or turns it; it is still struck, dented and throws debris) and `overhang` (`{ size, reach }`: an
	 overhead part drawn beyond the footprint by the piece's painter with `part: "overhang"`; a child CanvasItem named `Overhang` with
	 `get_rect() -> Rect2`, at `DrawLayers.OVERHEAD`, no collider; with `fade_under: true` it fades to `ObjectFadeConfig.alpha` (0.25) over
	 `ObjectFadeConfig.seconds` (0.15) while any node of the group `characters` stands inside its rect, and back to opaque when none does:
	 the door awning and glyph sign).
   - `WallFactory.spawn(rect: Rect2, walls: RoomWalls, name, parent) -> Node` — `RoomWalls` (`objects/room_walls.gd`): `thickness`,
	 `openings`, `style` (the cap's look: `art`, `color`, `art_opts`; empty = a flat gray line).
   - `WallFactory.openings_for(rect: Rect2, doors: Array) -> Array` — the `{ pos, width }` doorways on `rect`'s walls, as `spawn` takes
	 them (World-Gen and Testing's layouts use it). `Wall.Side` is the enum inside those `openings`.
   - `FloorFactory.spawn(rect: Rect2, definition: Dictionary, name, parent) -> Node` — a room's floor or a piece of the street (no
	 collider). Definition: `art`, `color`, `material`, `art_opts`, optionally `sound_surface` (false: registers no `SoundSurface`, the
	 street), `marks` (`{ seed, lane, edges, crossings, glyphs }`: the street's world-placed curb and gutter litter, laid by Objects; a road's
	 `crossings` `[{ side, reach }]` are a worn zebra crossing with its stop line at the road's end `side`, `reach` px deep, and its
	 `glyphs` `[{ side, from, length, text }]` a lane number and an arrow on the approach to the junction at `side`, `from` px in from
	 that end; a tests' read: the floor's `FloorVisuals/StreetMarks` child, whose `laid(kind)` lists where each kind went), `tile_from` (the
	 point in `parent`'s space its repeating tile starts from, so neighbouring pieces share a grid) and `light_layer` (`"street"`: the
	 piece and its canvas items on `LightMasks.STREET`, interface 20).
   - `DecalFactory` (`objects/decals/decal_factory.gd`): draw-only decals on the floor, no collider, nothing registered; World-Gen gives
	 where and what, Objects draws. `stencil(rect: Rect2, spec: Dictionary, decal_name, parent) -> Node2D` — a floor stencil (a `Sprite2D`)
	 over `rect` in `parent`'s space; `spec`: `text` (one line per line), laid in yellow and black hazard stripes round the edge,
	 the words in stencil letters inside; painted upright on a canvas the size of the area, so it reads the same however the building is
	 turned; at `ObjectArtLayerConfig.floor_z_index`, over the floors laid before it. `shadow(foot: Rect2, spec: Dictionary, decal_name,
	 parent: Node2D) -> Node2D` — the shadow of a tower with footprint `foot`: the footprint dragged `spec.length` px away from the art
	 light (`PixelArt.away_from_light`), the footprint itself left clear, at `DrawLayers.RUG` (over the street, under what stands on it),
	 lit by the street's lights only (`LightMasks.STREET`).
   - `WearFactory.spawn(rect: Rect2, plan: WearPlan, name, parent) -> Node2D` — a room's wear (one node per room, built after the
	 floors and walls). `WearPlan` (`objects/wear_plan.gd`): `floor_definition`, `wall_thickness`, `clusters` (`{ pos, wall, seed }`:
	 centre, the free stretch of wall `[a, b]` it is by or `[]`, the seed of its marks, in `parent`'s space). World-Gen places the
	 clusters; Objects decides each one's marks and draws them.
