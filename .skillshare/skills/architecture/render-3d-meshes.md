# The 3D render's meshes: the hook's per-node rules and which domain has what (interface 27)

Side file of `interfaces/27-render-3d.md`; the full hook rules are `domain-art/mesh-hook.md`, the how-to `domain-art/meshes.md`.

## A mesh node's own hooks

A mesh node the mirror shows may carry (all duck-typed, all optional):

- `mirror_update(body)` runs each frame the mesh shows;
- `on_body_died(body) -> bool` decides its death (true: stay shown);
- `remirror(node)` (a `WorldMirror` method) rebuilds a mesh at once through its builder;
- `follows_shapes() -> true` spares it the rebuild when a collision shape comes or goes (a wall's mesh replaces the one segment that changed);
- the signal `WorldMirror.built(body, mesh)` says each mesh a builder made for a body (the wall fade listens).

## Which domain has meshes (the rest are still proxies)

| Domain | Meshes | Plugged in by |
|---|---|---|
| Objects | furniture and street props (`ObjectMeshes`, the pattern), structure (`StructureMeshes`: walls, doors, floors, the street), floor stencils (`StencilMesh`), wear and decals (`WearMesh`, `WallWearMesh`: decals on floors, wall faces and the street; a wall's marks are children of its segment and fade with it) | `ObjectMeshes.register(builders)`; `ObjectMeshes.track(mirror)` shows each floor stencil |
| Vehicles | cars and vans (`VehicleMeshes`) | `VehicleMeshes.register(builders)` |
| Character | the body (`CharacterMeshes`) | `CharacterMeshes.register(builders)` |
| Items | loose items (`ItemMeshes`) | `ItemMeshes.register(mirror)` |
| Projectile | shots (`ProjectileMeshes`: 12) | `ProjectileMeshes.install(mirror, world)` |
| Physics | debris chips, hit particles, blood (splats, prints, smears, pools), an explosion's fireball, smoke and scorch (`PhysicsMeshes`: `domain-physics/meshes.md`) | `PhysicsMeshes.install(mirror)` |

Main's `main_view3d.gd` `_register_meshes()` calls each. Objects' wear and decals: `domain-objects/meshes.md`.
