---
name: domain-objects
description: Use when editing scenes/objects/ or working on furniture, walls, floors, doors, wear, a piece's lights and colliders, or the hittable / pushable contracts. Painters and pixel art: `art.md`.
---

# Objects domain (`scenes/objects/`)

Owns the world's objects (furniture, walls, floors, the street round a house, the doors), their wear and decals: their field schema, how
they are hit and pushed, how they compose Physics, what they give the lighting, and their painters. It turns a plain definition
dict from World-Gen into a node. Interfaces: 2 (World Generation → Objects, incl. `WearFactory`, `DecalFactory`, the floor's `sound_surface` /
`marks` / `tile_from` / `light_layer` and `DoorFactory`), 3 (hittable), 4 (→ Physics), 5 (pushable), 8 (interactable), 10 (a door's
`&"door"`), 11 (`DrawLayers` for the floor and rug z, `LightMasks`), 12 (→ Art), 16 (`SoundSurface`), 20 (`get_lights()`, occluders,
unshaded overlays), 24 (the door contract).

| File | Role |
|---|---|
| `environment_object.gd` (a `RigidBody2D`), `object_physics.gd`, `object_look.gd`, `object_lights.gd`, `environment_object_visuals.gd`, `overhang_visuals.gd`, `emissive_layer.gd` | A piece: control node, its physics part, its art fields (`piece.look.<field>`: `art`, `art_opts`, `facing`, `text_color`), its lights, its drawing. |
| `wall/wall.gd`, `wall/wall_visuals.gd`, `room_walls.gd` | Walls: segment math (`wall_segments()`), colliders; `RoomWalls` is `thickness`, `openings` (`{ side, offset, width }`), `style`. |
| `floor/floor.gd`, `floor/floor_visuals.gd` | Floors. |
| `object_factory.gd`, `wall_factory.gd`, `floor_factory.gd`, `wear_factory.gd`, `wear_plan.gd`, `door_factory.gd` | The interface-2 factories. `shared_textures.gd`: shared art (pre-warm). |
| `door/` (`door.gd` and its parts), `door_config.gd`, `door_push_config.gd`, `door_material_config.gd` | A hinged house door: `doors.md`. |
| `collider_cuts.gd` (`ColliderCuts`) | The shared queue of convex collider cuts, run on worker threads. |
| `decals/` | `decal_layer.gd`, `room_wear.gd`, `street_marks.gd`, `decal_factory.gd` (`DecalFactory`: the floor stencil and the tower shadow). |
| `art/` | The painters and their holders (the door's: `art/door_painter.gd`): `art.md`. |

Layering: `environment_object.gd` / `wall.gd` / `floor/floor.gd` hold geometry, colliders and look data and never draw; their
`*_visuals` child `Node2D`s read them and draw. Colliders are built at runtime (`wall.gd._build_walls()`, `object_physics.gd`),
so the editor's "no shape" warning on each `Wall` is expected.

## The contracts

- **Hittable (3):** every piece and wall implements it. The striker decides the ballistic outcome and hands over a `HitInfo`; the
  object decides what the hit *does to it* (shove, deform, debris). A melee punch or kick shoves through the pushable contract and does
  **not** deform.
- **Pushable (5):** furniture is a `RigidBody2D`, so its native `apply_impulse(v, at)` and `get_mass()` serve the contract. A
  character's shoves pass the contact offset as `at`, so a piece pushed near one end turns about the far end (the body's own
  torque, `PhysicsImpactConfig.body_angular_damp`). An **anchored** piece (`anchored: true`, the streetlight's post) is frozen static
  in `_ready`: every shove is ignored and its `take_hit` skips `Knockback`, but it is still found by queries, struck, dented, throws
  debris and is carved into the nav map (`tests/objects/anchored_piece_test.gd`, `tests/navigation/anchored_hole_test.gd`).
- **Door (24):** a `Door` is hittable (coverage 100, its material's `penetration`) and pushable (a shut one never moves; an ajar one turns about its hinge): `doors.md`. A piece's `coverage` and a door's `transparent` are fixed at spawn: Vision caches them for the piece's life (interface 3).
- **Interactable (8):** `get_interactions()` returns the `interactions` field of the definition; interaction is catalogue data.

## Physics parts

`object_physics.gd` (`compose()`, `add_smear()`, `soak()`, `release()`) adds the Physics components as child nodes and holds them
(`physics.knockback`, `physics.deformable`), the collider and its rebuild. A collider exists only when `solid`; non-solid decor is
frozen with no shape and draws at `DrawLayers.RUG` (`ObjectArtLayerConfig.rug_z_index`). A non-solid piece of cloth (`material`
`fabric`: rug, mat, cardboard) registers a porous `BloodSurface` rect; other walk-over decor registers none. `BloodSmear` goes on
solid pieces only, re-fed the footprint polygon when the collider is rebuilt.

## Drawing and rebuilding a hit piece

- The drop shadow (the visuals' `DropShadow` child) is the art's own alpha through the deformed outline, offset away from the
  light by `coverage × drop_shadow_per_coverage`, capped; non-solid decor casts none. A turn moves the child (`_shadow_shift`),
  it repaints nothing (`tests/objects/drop_shadow_follows_turn_test.gd`).
- A piece repaints (art and shadow) only when its `Deformable` records an impact, not each frame (a district has hundreds); the visuals run no `_process` at all: the Deformable is wired once the object is ready, and the shadow follows a turn on `NOTIFICATION_TRANSFORM_CHANGED` (`tests/objects/resting_piece_runs_no_per_frame_callback_test.gd`); the
  art is drawn through `Deformation.draw_shape(..., shape_look)` so dents cut into it. A wall draws each segment in its own child
  (`Segment<i>`), so a hit repaints that segment alone (`tests/objects/wall_segment_repaints_alone_test.gd`).
- A hit queues one deferred collider rebuild however many hits land first (a wall: one per struck segment, `_rebuild_queued`).
  A blast dents a room's worth of pieces in one frame and cutting a dented silhouette into convex pieces is the costly part, so a
  hit that queues a rebuild also queues its cut in `ColliderCuts` (`queue(make)`; `make` runs on the main thread, copies the dents,
  returns a pure job: `Deformation.cut_shape` / `cut_wall`). The first rebuild's `take()` starts every other waiting cut on a worker
  thread; later `take()`s wait for theirs and use it only if its polygon is still the silhouette (else cut there, `_pieces_of`). A
  cut whose piece leaves the tree is dropped (`cancel()`, in `_exit_tree`; a running one is waited for). Tests:
  `tests/objects/blast_colliders_match_plain_test.gd` (also checks cuts ran on workers, `ColliderCuts.started`),
  `wall_dents_share_a_rebuild_test.gd`.

## The overhang (`overhang_visuals.gd`, interface 2)

A definition's `overhang` (`{ size, reach }`) makes `ObjectFactory` add a child `Overhang`: the part that reaches beyond the
footprint (a streetlight's arm). It draws the piece's own painter with `part: "overhang"` at `size`, centred `reach` px out
along the facing, at `DrawLayers.OVERHEAD` (`ObjectArtLayerConfig.overhang_z_index`, over the living and vehicles), with no
collider; `get_rect()` is the area it draws, and it has its own `emissive_layer()` (`tests/objects/overhang_test.gd`).
`fade_under: true` (a tower's awning and glyph sign) fades its `modulate` to `ObjectFadeConfig.alpha` (0.25) over `seconds` (0.15)
while a `characters` node stands in `get_rect()`; one shared watcher steps those fading or with a character near (a server area over `get_rect()` wakes it), writing alpha only on change
(`overhang_fades_under_character_test.gd`).

## Lights and shadows (interface 20; spec `docs/lighting.md`, skill `domain-lighting`)

Objects declares and builds what its pieces, walls and floors give the Lighting domain, on General's `LightMasks`:

- **`get_lights()`** is worked out once in `_ready`, after the visuals, by `object_lights.gd`: one plain dict per light in the
  piece's frame. What gives light is what its painter draws `glowing`; the kind is read off the painter and its options (`_kind`,
  through `ObjectArt.light_kind` for variant pieces) and the numbers are that kind's row of `ObjectArtLightConfig.specs`. The light's
  colour is the painter's glowing colour. A screen's pool lies across its front (`turn` = facing + 90°), a tube's along it. Lighting
  parents each kept light to the piece, so a shove carries it (`tests/lighting/shoved_lamp_light_follows_test.gd`).
- **Occluders**, through `LightMasks.occluder` (none while `LightMasks.shadows` is off): a door one over its leaf (`doors.md`); a solid piece one over its undented
  footprint (its rect, or a 12-gon, `OCCLUDER_SIDES`, for a round one), a child so it follows a shove, on `EMITTER` when
  `get_lights()` is not empty, `TALL` when `coverage` ≥ `LightMasks.TALL_COVERAGE`, else `FURNITURE`; walk-over decor none; a wall
  one per segment, its collider's rect (`WALL`), in `_build_walls`. Dents are not followed.
- **The street's light layer:** a floor whose definition says `light_layer: "street"` puts itself and its canvas items on
  `LightMasks.STREET`.
- **Emissive overlays:** each visuals node keeps the pixels its painter drew `glowing` (`ObjectArt.emissive` / `tile_emissive`, null
  when none) and exposes `emissive_layer()`, a child `Emissive` drawing them over the art through the same geometry (deformed
  silhouette, tiled floor, dented wall segments) with one shared unshaded `CanvasItemMaterial`, so the dusk and the lights never
  change a light source (`tests/lighting/emissive_overlays_unshaded_test.gd`). Lighting dims it with the piece's light.

## Floors (`floor/`)

`FloorFactory.spawn(rect, definition, name, parent)` builds a `Floor` (`Node2D`, no collider: shots, navigation and perception pass
over it) in the group `floors` (Lighting's per-floor budget walks it), at `DrawLayers.FLOOR` (beneath blood, casings and rugs).
`floor_visuals.gd` repeats `ObjectArt.tile(...)` across the rect, the grid starting `tile_offset` px into the tile (`rect.position - tile_from`, the definition's
`tile_from` point: 0 for a room's floor, the street's pieces share one grid); a floor with `marks` gets a `StreetMarks` child.
On `_ready` a floor registers (and unregisters on exit):

- with Physics' `BloodSurface`, `flow_groove` asking `ObjectArt.groove` (analytic, mirroring the painted lines; 0 for painters that
  model none, the street) and `ObjectArt.porous` (carpet), so blood follows the texture and soaks into carpet;
- with Audio's `SoundSurface` (interface 16: its rect, `floor_material`, `art_opts.pattern`) so footsteps sound like the floor,
  unless `sound_surface` is off: the street registers none, so steps out there stay `outdoor`.

## Wear and the street's marks (`decals/`, interface 2)

Damage is decals placed in the world, never in a tile (a tile carries only even grain and seam dirt, so no mark repeats on its
grid). `decal_layer.gd` is a draw-only batch of `[texture, rect]` marks.

- **A room's wear** (`WearFactory.spawn` over a `WearPlan`; `room_wear.gd`): World-Gen places the clusters (seeded); the room's
  wear node decides each cluster's 1-3 floor marks by the floor's pattern (planks break along a row, tiles go missing on the grid,
  carpet wears bald, concrete cracks and takes oil; grid marks snap to the painter's own numbers, `FloorPainter.row_px` /
  `cell_px` / `parquet_strip`), and with `ObjectArtWearConfig.wall_chance` a mark on the free stretch of wall beside it. Two layers,
  `FloorWear` and `WallWear`, built after every room's floor and walls so they draw over them; one node per room, so it takes that
  room's floor lights (the budget, `docs/lighting.md` L4).
- **The street's marks** (`street_marks.gd`, from the definition's `marks` `{ seed, lane, edges, crossings, glyphs }`): sidewalk slabs,
  cracks, stains, gum, weeds and the curb along `edges`; on a road the lane dashes, cracks, patches, oil, and gutter litter and puddles,
  and at a junction's end a worn zebra crossing with its stop line (`crossings`) and a lane number with an arrow (`glyphs`); `laid(kind)`
  says where they went.
- **`DecalFactory`** (`decals/decal_factory.gd`, interface 2) lays draw-only sprites with no collider: `stencil` (floor text in a hazard border,
  painted upright on a canvas the size of the area so a turned building does not turn it) and `shadow` (a tower's footprint dragged away
  from the art light, on `LightMasks.STREET` at `DrawLayers.RUG`, so only the street's lights reach it).

Tests: `tests/objects/`.
