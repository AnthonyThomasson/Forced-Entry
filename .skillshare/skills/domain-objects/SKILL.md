---
name: domain-objects
description: Use when editing scenes/objects/ or working on furniture, walls, floors, doors, wear, a piece's lights and colliders, or the hittable / pushable contracts. Painters and pixel art: `art.md`.
---

# Objects domain (`scenes/objects/`)

Owns the world's objects (furniture, walls, floors, the street round a house, the doors), their wear and decals: their field schema, how
they are hit and pushed, how they compose Physics, what they give the lighting, and their painters. It turns a plain definition
dict from World-Gen into a node. Interfaces: 2 (World Generation → Objects, incl. `WearFactory`, `DecalFactory`, the floor's `sound_surface` /
`marks` / `tile_from` / `light_layer` and `DoorFactory`), 3 (hittable), 4 (→ Physics), 5 (pushable), 8 (interactable), 10 (a door's
`&"door"`), 11 (`PhysicsLayers`), 12 (→ Art), 16 (`SoundSurface`), 20 (`get_lights()`), 24 (the door contract).

| File | Role |
|---|---|
| `environment_object.gd` (a `RigidBody2D`), `object_physics.gd`, `object_look.gd`, `object_lights.gd` | A piece: control node, its physics part, its art fields (`piece.look.<field>`: `art`, `art_opts`, `facing`, `overhang`), its lights. It draws nothing: its 3D mesh (`art/`) shows it. |
| `wall/wall.gd`, `room_walls.gd` | Walls: segment math (`wall_segments()`), colliders; `RoomWalls` is `thickness`, `openings` (`{ side, offset, width }`), `style`. |
| `floor/floor.gd` | Floors. |
| `object_factory.gd`, `wall_factory.gd`, `floor_factory.gd`, `wear_factory.gd`, `wear_plan.gd`, `door_factory.gd` | The interface-2 factories. `shared_textures.gd`: the shared flat art (pre-warm). |
| `door/` (`door.gd` and its parts), `door_config.gd`, `door_push_config.gd`, `door_material_config.gd` | A hinged house door: `doors.md`. |
| `collider_cuts.gd` (`ColliderCuts`) | The shared queue of convex collider cuts, run on worker threads. |
| `decals/` | `decal_layer.gd`, `room_wear.gd`, `street_marks.gd`, `stencil_decal.gd`, `decal_factory.gd` (`DecalFactory`: the floor stencil). |
| `art/` | Painters and holders: `art.md`, `meshes.md`, `furniture-art.md`, `structure-meshes.md`. |

Layering: `environment_object.gd` / `wall.gd` / `floor/floor.gd` hold geometry, colliders and look data and draw nothing:
the 3D meshes (`art/`, `meshes.md`) read them through the mirror. Colliders are built at runtime (`wall.gd._build_walls()`, `object_physics.gd`): the editor's "no shape" warning on a `Wall` is expected.

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
(`physics.knockback`, `physics.deformable`), the collider and its rebuild. A collider exists only when `solid`; non-solid decor is frozen and shapeless. A non-solid piece of cloth (`material`
`fabric`: rug, mat, cardboard) registers a porous `BloodSurface` rect; other walk-over decor registers none. `BloodSmear` goes on
solid pieces only, re-fed the footprint polygon when the collider is rebuilt.

## Rebuilding a hit piece

- A piece's dents are its `Deformable`'s records; the 3D mesh and the collider both follow them (the mesh through the mirror's
  own change check, a wall segment's mesh `Segment<i>` alone).
- A hit queues one deferred collider rebuild however many hits land first (a wall: one per struck segment, `_rebuild_queued`).
  A blast dents a room's worth of pieces in one frame and cutting a dented silhouette into convex pieces is the costly part, so a
  hit that queues a rebuild also queues its cut in `ColliderCuts` (`queue(make)`; `make` runs on the main thread, copies the dents,
  returns a pure job: `Deformation.cut_shape` / `cut_wall`). The first rebuild's `take()` starts every other waiting cut on a worker
  thread; later `take()`s wait for theirs and use it only if its polygon is still the silhouette (else cut there, `_pieces_of`). A
  cut whose piece leaves the tree is dropped (`cancel()`, in `_exit_tree`; a running one is waited for). Tests:
  `tests/objects/blast_colliders_match_plain_test.gd`, `wall_dents_share_a_rebuild_test.gd`.

## The overhang (interface 2)

A definition's `overhang` (`{ size, reach }`) is kept as the plain field `piece.look.overhang`; `piece.look.overhang_rect()` is the
area it covers in the piece's frame (`size` across x out, centred `reach` px along the facing; a streetlight's arm and head). The
3D mesh of the piece shows it with the painter's `part: "overhang"`, above the characters, with no collider. `fade_under: true`
(a tower's awning and glyph sign) is read by Art's wall fade, which thins it while a character stands under it
(`tests/objects/overhead_fade_test.gd`).

## Lights (interface 20; spec `docs/lighting.md`, skill `domain-lighting`)

Objects declares what its pieces give the Lighting domain:

- **`get_lights()`** is worked out once in `_ready` by `object_lights.gd`: one plain dict per light in the piece's frame. What gives
  light is what its painter draws `glowing`; the kind is read off the painter and its options (`_kind`, through `ObjectArt.light_kind`
  for variant pieces) and the numbers are that kind's row of `ObjectArtLightConfig.specs`. The light's colour is the painter's
  glowing colour. A screen's pool lies across its front (`turn` = facing + 90°), a tube's along it. Lighting keeps each light
  at the piece, so a shove carries it (`tests/lighting/light_3d_follows_and_flickers_test.gd`). The 3D mesh glows with it
  (`WorldLighting3D`).
- **The street's light layer:** a floor whose definition says `light_layer: "street"` is lit only by the street's lights.

## Floors (`floor/`)

`FloorFactory.spawn(rect, definition, name, parent)` builds a `Floor` (`Node2D`, no collider: shots, navigation and perception pass
over it) in the group `floors` (Lighting's per-floor budget walks it). Its 3D mesh (`floor_mesh.gd`, `street_mesh.gd`) repeats
`ObjectArt.tile_flat(...)` across the rect, the grid starting `tile_offset` px into the tile (`rect.position - tile_from`, the definition's
`tile_from` point: 0 for a room's floor, the street's pieces share one grid); a floor with `marks` gets a `StreetMarks` data child.
On `_ready` a floor registers (and unregisters on exit):

- with Physics' `BloodSurface`, `flow_groove` asking `ObjectArt.groove` (analytic, mirroring the painted lines; 0 for painters that
  model none, the street) and `ObjectArt.porous` (carpet), so blood follows the texture and soaks into carpet;
- with Audio's `SoundSurface` (interface 16: its rect, `floor_material`, `art_opts.pattern`) so footsteps sound like the floor,
  unless `sound_surface` is off: the street registers none, so steps out there stay `outdoor`.

## Wear and the street's marks (`decals/`, interface 2)

Damage is decals placed in the world, never in a tile (a tile carries only even grain and seam dirt, so no mark repeats on its
grid). `decal_layer.gd` is a plain holder of `[texture, rect, kind]` marks; the 3D render lays them as flat decals (`wear-meshes.md`), their textures the painters' flat art (`ObjectArt.flat_facing`).

- **A room's wear** (`WearFactory.spawn` over a `WearPlan`; `room_wear.gd`): World-Gen places the clusters (seeded); the room's
  wear node decides each cluster's 1-3 floor marks by the floor's pattern (planks break along a row, tiles go missing on the grid,
  carpet wears bald, concrete cracks and takes oil; grid marks snap to the painter's own numbers, `FloorPainter.row_px` /
  `cell_px` / `parquet_strip`), and with `ObjectArtWearConfig.wall_chance` a mark on the free stretch of wall beside it. Two layers,
  `FloorWear` and `WallWear`, built after every room's floor and walls so they draw over them; one node per room.
- **The street's marks** (`street_marks.gd`, from the definition's `marks` `{ seed, lane, edges, crossings, glyphs }`): sidewalk slabs,
  cracks, stains, gum, weeds and the curb along `edges`; on a road the lane dashes, cracks, patches, oil, and gutter litter and puddles,
  and at a junction's end a worn zebra crossing with its stop line (`crossings`) and a lane number with an arrow (`glyphs`); `laid(kind)`
  says where they went.
- **`DecalFactory`** (`decals/decal_factory.gd`, interface 2) lays the floor `stencil` (floor text in a hazard border, painted upright on a canvas
  the size of the area so a turned building does not turn it): a plain `StencilDecal` node at the area's corner holding the flat texture,
  with no collider; the 3D render lays it (`StencilMesh`). A tower's shadow is the sun's, cast by the 3D walls.

Tests: `tests/objects/`.
