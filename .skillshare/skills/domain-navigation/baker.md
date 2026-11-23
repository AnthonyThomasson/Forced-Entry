# Navigation: the grid baker

Side file of `domain-navigation` (`SKILL.md`). ADR 0016: [the nav mesh is baked by the 3D baker from projected plan footprints](../../../docs/adr/0016-the-nav-mesh-is-baked-by-the-3d-baker-from-projected-plan-footprints.md).

**Every bake** (`NavSource.bake_polygon`; planning, re-bake, steering tiles, ring and avoid maps alike): the walkable
  outlines are the floor of a plan-space 3D world, each obstruction outline a projected obstruction standing on it, baked by `NavigationServer3D`
  on `NavSource.CELL_SIZE` (4 px) cells laid on the world's grid (the map's `2d/default_cell_size` is 4 as well). The agent radius is taken off in the plan (obstructions grown,
  the floor shrunk), not by the baker's own erosion, which rounds the radius up to whole cells and closes a 40 px doorway; so a mesh edge stands up
  to half a cell's diagonal (2.8 px) nearer an obstruction than the radius. Every vertex lies on a cell, so no weld is needed (the 2D baker's mesh needed
  one for vertices a fraction of a pixel apart: `NavWeld`, removed once it changed none of 1042 bakes of a full run). Tiles' borders: `NavSeams`.
  Tests: `furniture_beside_wall_bakes_clean_test.gd`, `character_beside_wall_bakes_clean_test.gd`, `district_seed_35_bakes_clean_test.gd` (the 2D mesh logged
  "Attempted to merge a navigation mesh polygon edge" there). The regions, maps and queries (`ready`, `snap`, `route`) are `NavigationServer2D`'s still, on a map the 3D baker's cell size matches (nav3d-b moves them).

- **A mesh edge is nearer than the radius.** An edge stands up to half a cell's diagonal (2.8 px) closer to an obstruction than the agent radius, and a route is the true shortest path over the mesh, not the 2D baker's polygon chain: a few AI tests' set-ups leaned on that chain (`tests/_ai/flank_maps.gd` `RAIL`, `FENCE`, the reach probe's `ROUTE_REACH`, each says why).
- **Tile borders** are held by `NavSeams` (`district-tiles-and-avoid.md`): a tile is baked with a border and its neighbours' border cells closed.
- The baker's own settings: `NavSource.CELL_SIZE` 4, `CELL_HEIGHT` 2, `AGENT_HEIGHT` 8, `OBSTRUCTION_HEIGHT` 100 (over the agent, a wall or a body alike), `EDGE_MAX_ERROR` 0.8 cells (1 would drop a one-cell stair step off a hole's outline: 853 polygons rather than 1142, and a lane 4 px narrower), watershed partition.
- **The merge pass** (`NavMerge`, after every bake): the baker cuts the floor into regions (a district: 2590 polygons, 2.9 times the 2D baker's), and a path query pays for every polygon it crosses (300 queries across the district: 47 ms; the 2D baker's mesh 24 ms). Neighbouring polygons whose union is convex (at most 12 corners) are one, every vertex kept so the edges the map and `NavSeams` join by stand: 1142 polygons, 36 ms (the contour error at 1 cell would give 853, 28 ms, but closes a 140 px hall's lane beside a sofa). A ring starts where both its neighbours are real corners, and a union with no such start is refused: the server's closest-point test fans a polygon from its first vertex, and a fan whose first or last triangle is flat (the second vertex, or the one before the first, on a straight run) loses the polygon (a point 8 px inside one was 8 px off the map: `navigation/district_paths_into_neighbour`; measured by rotating one ring in a mesh of its own). Test: `navigation/mesh_merge`.
