# The nav mesh is baked by the 3D baker from projected plan footprints

#194 (D16, job nav3d-a). The nav mesh was baked by `NavigationServer2D.bake_from_source_geometry_data`, which clips polygons: a few big convex polygons made
of the walls' and holes' outlines, on a 1 px map cell grid (the 2D baker's). The sim's walls and pieces are 3D twins now ([ADR 0014](0014-twin-staging-and-plan-space.md)) and the
nav domain reads their plan footprints ([ADR 0010](0010-doors-are-driven-bodies-left-out-of-the-nav-bake.md), `domain-navigation` `twins.md`), but the bake itself stayed 2D.

**Decision.** Every bake (planning, steering tile, ring, avoid map) is made by `NavigationServer3D.bake_from_source_geometry_data` (`NavSource.bake_polygon`): the
walkable outlines are the floor of a plan-space world `(x, 0, z)`, each wall or hole footprint is a *projected obstruction* standing on it, so no height of a
lintel, a door or a piece can close a doorway or leave a walkable top. The voxel grid is 4 px (`NavSource.CELL_SIZE`) laid on the world's grid, and the map's
`2d/default_cell_size` is 4 so the server merges the mesh's edges by the same cell. The regions, the maps and every query (`ready`, `snap`, `route`,
`NavigationAgent2D`) stay `NavigationServer2D`'s: the mesh is a `NavigationPolygon` as before, so interface 9 keeps its signatures. (nav3d-b moves them.)
The source is still gathered as 2D plan outlines (a `NavigationMeshSourceGeometryData2D`, snapped to whole pixels, which the planning region keeps for the avoid maps): `bake_polygon` projects them into the 3D source at the bake, so what a bake reads of the world is unchanged and only the baker differs.

**Why 4 px.** D16 measured a district's bake at 113 ms on 4 px cells against 2.0 s on 1 px: the voxel baker is cubic in its resolution, the 2D clipper is not.

**Consequences**, each found and fixed in the job, none a bug in the baker:
- *The agent radius is taken off in the plan* (obstructions grown by it with round joins, the floor shrunk), not by the baker's own erosion, which rounds the radius
  up to whole cells (18 to 20) and closes a 40 px doorway. A mesh edge then stands up to half a cell's diagonal (2.8 px) nearer an obstruction than the radius, so a
  carved open door leaf is as thick as the leaf (a 2 px strip left a walker pressed against it).
- *Tile borders*: the voxel rule at a tile's edge makes neighbouring tiles' border vertices differ, so a tile is baked with a border and its neighbours' border cells
  held (`NavSeams`), fixed by construction, not by a bound per seed.
- *Routes are the true shortest path.* The 2D mesh's few big polygons made the planner's polygon chain detour (a flank's rear route 790 px round two pillars where 720 px
  ran straight through the target); the AI tests whose set-ups leaned on that detour got set-ups where the shortest route bends for a real reason, assertions unchanged.
- *No weld.* The 2D mesh needed `NavWeld` (vertices a fraction of a pixel apart merged, slivers dropped) and still logged "Attempted to merge a navigation mesh polygon
  edge" on seed 35's district (`navigation/district_seed_35_bakes_clean`, red on the 2D baker). The grid baker's vertices lie on cells: `NavWeld` changed none of 1042 bakes of
  a full test run and was removed.
