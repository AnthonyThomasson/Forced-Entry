# Navigation: a district's steering tiles and the avoid maps

Side file of `domain-navigation` (`SKILL.md`): the parts of the nav domain a district and the AI's doorway-view walks lean on.

## A district's steering map: tiles (`nav_tiles.gd`)

`build` with a `bounds` rect (a district: `house` its root, `rooms` every tower's, `bounds` = `WorldGen.district_bounds`) bakes the planning
region over the whole rect and the steering map as 512 px tile regions (`NavSteering_<column>_<row>`, children of the planning
region, `steering_regions(region)`). A tile is baked from its own walls, furniture and characters (`BORDER` 40 px past its edge, so neighbours meet) **only when those changed since its last bake**, so a character
stopping re-bakes one to four tiles: ~5 ms a tick, not ~57
(`steering_tiles_rebake_touched_test.gd`, `perf/bake_and_path_stress`). A lone house keeps one `NavSteering` region.

- **Walls are parsed tower by tower** and kept on the planning region (`NavTiles.walls_reaching`): a tile re-parses the towers reaching it,
  the planning re-bake takes every tower's from the cache and re-parses those near a moved piece. A wall shot up where nothing stands or
  moves waits for the next change there.
- **The steering re-bake lands in its tick's frame, house or district** (`nav_updater.gd`; `steering_rebake_lands_in_its_tick_test.gd`): a
  held walker re-looks for a way round a body every `RECHECK` s and the map answers a frame after the re-bake, so a late one costs a whole
  `RECHECK`. A district's planning gather waits a frame; the planning region stays whole and async.

## Avoid maps (`avoid_map`)

A walk that should keep out of some floor (the AI's doorway views, `docs/tactical-entry.md` E18) plans on a map with it carved out:
`avoid_map(region, key, holes) -> RID` (`region` is the planning region, `planning_region(planning_map)` finds it; `holes` closed
world-space polygons; `key` names the set). The planning bake keeps its source on its region, so the avoid
bake is the same geometry plus the holes, fused, snapped, welded. Each key gets a map of its own with one child region `NavAvoid`,
baked on the server's worker thread (`ready(map)` is false until it answers). Asking again returns the same map and marks it
asked; once the planning bake is redone it is baked again in place, the old mesh answering meanwhile. A map nobody asked for in
`avoid_idle_ms` is freed with its region by the next ask for another key on the same planning map (the sweep runs only inside
`avoid_map`), and every one is freed with its world. Invalid when the region has no bake. Test:
`tests/navigation/avoid_map_carves_the_views_test.gd`.
