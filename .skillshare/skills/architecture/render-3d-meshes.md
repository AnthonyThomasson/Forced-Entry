# The 3D render's meshes: the hook's per-node rules and which domain has what (interface 27)

Side file of `interfaces/27-render-3d.md`; the full hook rules are `domain-art/mesh-hook.md`, the how-to `domain-art/meshes.md`.

## A mesh node's own hooks

A mesh node the carrier or follower shows may carry (all duck-typed, all optional):

- `mirror_update(body)` runs each frame the mesh shows;
- `on_body_died(body) -> bool` decides its death (true: stay shown);
- `remirror(node)` (a `MeshCarrier` or `MeshFollower` method) rebuilds a mesh at once through its builder;
- a wall's mesh replaces the one segment that changed itself (`segment_rebuilt`): the carrier builds a mesh again only on `remirror` or `reshaped`;
- the signal `MeshCarrier.built(body, mesh)` says each mesh a builder made for a body (the wall fade listens).

## Which domain has meshes (a body without one shows nothing)

| Domain | Meshes | Plugged in by |
|---|---|---|
| Objects | furniture and street props (`ObjectMeshes`, the pattern), structure (`StructureMeshes`: walls, doors, floors, the street), floor stencils (`StencilMesh`), wear and decals (`WearMesh`, `WallWearMesh`: decals on floors, wall faces and the street; a wall's marks are children of its segment and fade with it) | `ObjectMeshes.register(builders)`; `ObjectMeshes.track(mirror)` shows each floor stencil |
| Vehicles | cars and vans (`VehicleMeshes`) | `VehicleMeshes.register(builders)` |
| Character | the body (`CharacterMeshes`) | `CharacterMeshes.register(builders)` |
| Items | loose items (`ItemMeshes`) | `ItemMeshes.register(follower)` (Art's `MeshFollower`) |
| Projectile | shots (`ProjectileMeshes`: 12) | `ProjectileMeshes.install(viewport, world)` |
| Physics | debris chips, hit particles, blood (splats, prints, smears, pools), an explosion's fireball, smoke and scorch (`PhysicsMeshes`: `domain-physics/meshes.md`) | `PhysicsMeshes.install(viewport, ground)`; `ground` is Objects' `StreetGround.offset_at` (the road a kerb lower) |

Main's `main_view3d.gd` `_register_meshes()` calls each. Objects' wear and decals: `domain-objects/meshes.md`.

## What the 3D mirror wears, and the look gate

Every mesh wears its domain's 2D art, never a flat colour (`domain-art/textured-toon.md`): furniture through `FurnitureRig` (a builder returns `FurnitureMesh.show(piece, mesh)`, as the table's does since the look gate; a builder that returns a bare `MeshInstance3D` leaves its piece a plain slab and a dent unfollowed), structure, vehicles, the body (`domain-character/body-textures.md`), a held and a lying gun (a lying item is tinted `ItemMeshConfig.lying_brighten`, 1: as painted). A burst's smoke puff is a flat disc, not a dome, so it reads as the 2D blob (`domain-physics/meshes.md`).

The look gate's shots: `tests/general/render_3d_look_gate_windowed_test.gd` (one scene per run: `LOOK_SCENE`, `LOOK_DIR`, `LOOK_ZOOMS`, `LOOK_YAWS`; `turn` and `pan` print the picture's flicker) and `tools/look_gate_sheets.py DIR` (a contact sheet per scene). A windowed test reads the picture after `RenderingServer.force_draw(false)`, never after `await frame_post_draw`: a window the desktop covers is not drawn, never signals it, and the test runs its sim clock out to a silent timeout.

Known cost: Physics' ink rebuilds a whole 128 px chunk when one mark in it changes (dries a step, a smear grows), O(marks in the chunk); the pool and blast cost is one pool a frame.

**Off the camera** (`mirror_reach() -> float`, optional, 3D units): a mesh that says all it draws stays that far round its origin, none of it casting a shadow, is asked for its pose (`mirror_update`) only while the camera of the carrier's viewport reaches that sphere. The carrier runs before the camera rig, so a skipped one is looked at again after the rig has moved (`process_priority` 60), before the picture: it is posed in the frame it comes back. No camera: every shown mesh is posed. `BodyMesh` gives one while it lives.

**Still meshes** (no `mirror_update`, turn or rider, of a body the view remembers): looked at only when the body hides or shows, its view layer is written (`ViewLayers.CHANGED`) or the mesh leaves the tree (`still_rows.gd`).
