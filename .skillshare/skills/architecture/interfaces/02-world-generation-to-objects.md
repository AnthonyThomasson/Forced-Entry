2. **World Generation → Objects** (the only way world-gen makes entities)
   - What an emptied piece carries (`PieceCarries`, the prop palette): `interfaces/28-piece-heights.md`.
   - `SharedTextures.requests() -> Array` — the complete PixelArt request dictionaries every district shares:
	 road glyphs, crossings, podiums, awnings and glyph signs, shell decor, and the tower shadows derived from the supplied
	 `{ size, half, length, depth, podium }` footprints (`podium`: the segment lengths a plan stands with). `WorldGen.prewarm` hands these to Art; no nodes are built. `ObjectArt.flat_request(art, size, color, opts)` and `tile_flat_request(art, color, material, opts)` are the flat (`"flat": true`, no `facing`) twins of a request, for the 3D render's textures (`flat`, `tile_flat` paint them; empty for an unknown art id).
   - `FurnitureArt.requests(art, sizes, colors, opts, overhang := Vector2.ZERO) -> Array` and `ObjectArt.neon_variants(art, opts) -> Array` — the flat (`"flat": true`) PixelArt requests of a piece's 3D art (canonical footprint sizes, its colours, painter options, the overhang part's size), and the neon trims a kind can take; `DistrictPrewarm.furniture_requests` walks the catalogue, the podium plans and the clutter through them for `WorldGen.prewarm(true)`.
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
	 overhead part beyond the footprint, shown by the piece's 3D mesh from its painter with `part: "overhang"`, no collider; kept as a plain field of the piece's look,
	 `piece.look.overhang`, with `overhang_rect() -> Rect2` its area in the piece's frame (empty for none), which the 3D mesh and the street
	 lamp's light read; with `fade_under: true` the 3D render fades it while a character stands under it: the door awning and glyph sign).
   - `ObjectFactory.spawn_on(definition: Dictionary, base: Node2D, offset: Vector2, parent: Node, opts) -> Node` — a small item (`ItemsCatalog`) set on `base`'s top, `offset` px from its origin; its body starts at `ObjectFactory.top_at(base, point) -> float` (px above the floor: a ray down against the twin space, so an item already there raises it) and settles asleep; `opts.rest_at` (px above the floor) sets where it is put down when the caller knows it, instead of the top (an emptied piece's carried item: `PieceCarries`, set by World-Gen's `RoomItems`) (`docs/stacked-items.md`).
   - `ObjectFactory.flat_top(base: Node2D) -> Dictionary` — `{ top: Rect2, raised: Array[Rect2] }` in `base`'s parent space: the rect of `base`'s main flat top (the widest part) and the rects of the parts that rise over it (a counter's backsplash); an item set against one leans on it, so World-Gen keeps an item's footprint inside `top` and off `raised`.
   - `WallFactory.spawn(rect: Rect2, walls: RoomWalls, name, parent) -> Node` — `RoomWalls` (`objects/room_walls.gd`): `thickness`,
	 `openings`, `seams` (the stretches another room's wall already stands on, `{ side, from, to }`), `style` (the cap's look: `art`, `color`,
	 `art_opts`; empty = a flat gray line). A wall two rooms share is built once: the room built first owns it, and the other's `Wall` keeps the
	 stretch as a segment (its doorways stay cut) with no collider, 2D or 3D, and no lintel over a doorway there (`Wall.has_segment`).
   - `WallFactory.openings_for(rect: Rect2, doors: Array) -> Array` — the `{ pos, width }` doorways on `rect`'s walls, as `spawn` takes
	 them (World-Gen and Testing's layouts use it). `Wall.Side` is the enum inside those `openings`.
   - `WallFactory.seams_for(rect: Rect2, built: Array) -> Array` — the stretches of `rect`'s walls that run along a wall of one of `built` (the
	 `Rect2` outlines of the walls built so far), as `RoomWalls.seams`: World-Gen's house rooms and district shells and Testing's layouts pass
	 the rooms laid before.
   - `FloorFactory.spawn(rect: Rect2, definition: Dictionary, name, parent) -> Node` — a room's floor or a piece of the street (no
	 collider). Definition: `art`, `color`, `material`, `art_opts`, optionally `sound_surface` (false: registers no `SoundSurface`, the
	 street), `marks` (`{ seed, lane, edges, crossings, glyphs }`: the street's world-placed curb and gutter litter, laid by Objects; a road's
	 `crossings` `[{ side, reach }]` are a worn zebra crossing with its stop line at the road's end `side`, `reach` px deep, and its
	 `glyphs` `[{ side, from, length, text }]` a lane number and an arrow on the approach to the junction at `side`, `from` px in from
	 that end; a tests' read: the floor's `StreetMarks` child, whose `laid(kind)` lists where each kind went), `tile_from` (the
	 point in `parent`'s space its repeating tile starts from, so neighbouring pieces share a grid) and `light_layer` (`"street"`: the
	 piece is lit by the street's lights only, interface 20).
   - `DecalFactory` (`objects/decals/decal_factory.gd`): decals on the floor, no collider, nothing registered; World-Gen gives
	 where and what, Objects makes the data and the 3D render shows it. `stencil(rect: Rect2, spec: Dictionary, decal_name, parent) -> Node2D` — a floor stencil (a plain `StencilDecal` node at `rect`'s corner, its flat picture the `texture` property)
	 over `rect` in `parent`'s space; `spec`: `text` (one line per line), laid in yellow and black hazard stripes round the edge,
	 the words in stencil letters inside; painted upright on a canvas the size of the area, so it reads the same however the building is
	 turned, over the floors laid before it; the node joins the group
	 `DecalFactory.STENCIL_GROUP`, which `ObjectMeshes.track(follower)` (Main's 3D view, Art's `MeshFollower`) shows as a decal. A tower's shadow is the sun's.
   - `WearFactory.spawn(rect: Rect2, plan: WearPlan, name, parent) -> Node2D` — a room's wear (one node per room, built after the
	 floors and walls). `WearPlan` (`objects/wear_plan.gd`): `floor_definition`, `wall_thickness`, `clusters` (`{ pos, wall, seed }`:
	 centre, the free stretch of wall `[a, b]` it is by or `[]`, the seed of its marks, in `parent`'s space). World-Gen places the
	 clusters; Objects decides each one's marks and draws them.
	 In the 3D render (27) the same marks are decals on the room's surfaces: `spawn` also hands the room's `Floor` and `Wall` (those at
	 `rect`'s corner in `parent`) the node as their `wear` property, and the wear node (`RoomWear`) answers `floor_marks()` (`[texture,
	 rect, kind]` each) and `wall_marks()` (`{ kind, v, at, dir, normal, length }` each: where a mark stands on the wall's centre line and
	 which face it is on). Its `DecalLayer` takes a mark's `kind` (`add(texture, rect, kind)`) and answers `decals()`; the street's
	 `StreetMarks` layer does too. Objects' meshes read them (`domain-objects/meshes.md`); World-Gen touches none of it.
