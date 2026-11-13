# Navigation: a district's tiles, planning ring and the avoid maps

Side file of `domain-navigation` (`SKILL.md`): the parts of the nav domain a district and the AI's doorway-view walks lean on.

## A district's steering map: tiles (`nav_tiles.gd`)

`build` with a `bounds` rect (a district: `house` its root, `rooms` every tower's, `bounds` = `WorldGen.district_bounds`) bakes the planning
region over the whole rect and the steering map as 512 px tile regions (`NavSteering_<column>_<row>`, children of the planning
region, `steering_regions(region)`). A tile is baked from its own walls, furniture and characters (`BORDER` 40 px past its edge, so neighbours meet) **only when those changed since its last bake**, so a character
stopping re-bakes one to four tiles: ~5 ms a tick, not ~57
(`steering_tiles_rebake_touched_test.gd`, `perf/bake_and_path_stress`). A lone house keeps one `NavSteering` region.

- **The grid is on whole pixels, and its borders are welded** (`NavTiles.whole_pixels`, `nav_seams.gd`; `navigation/steering_seams_welded`, `seams_split_at_neighbour_vertices`): the baker rounds a bake's rect to whole pixels (toward zero), so tiles laid on a fractional footprint were baked to edges a pixel apart; `whole_pixels` grows the footprint to whole pixels first. Along a border a tile's polygon edge spans a stretch where its neighbour's has more vertices (a wall tip or a hole edge on the line); the server joins two polygons by an edge both hold (the same two 1 px cells), and joins the rest only in its edge-connection pass. `NavSeams.weld` therefore splits each tile's border edges at the vertices the neighbour has there, in a cell of their own (a polygon whose edge is cut is fanned into triangles from its next corner: three collinear vertices on a polygon make the server's queries answer wrongly), after a bake lands (`NavTiles.rebake`, `land`) for the tiles that landed and their neighbours. The tile keeps the polygon it was baked with (`NavSeams.RAW_META`) and holds a split copy, so a neighbour's re-bake always splits from the baked one, and a vertex a hair (the baker's 1/128 px) off the border is put on it. The steering map's edge-connection pass: `steering-edge-connections.md`.
- **Walls are parsed tower by tower** and kept on the planning region (`NavTiles.walls_reaching`, or `walls_all` for every tower): a tile re-parses the towers reaching it,
  the planning re-bake takes every tower's from the cache and re-parses those near a moved piece. A wall shot up where nothing stands or
  moves waits for the next change there (a trade-off accepted for the district's speed; no test pins it).
- **Steering outlines are binned by grid range** (`NavTiles.bin`): an outline's bounds, grown by `BORDER` for the candidate
  range, select only the tile cells it can touch, then the original exact rectangle tests preserve border contact and outline
  order. Reaches that are not a steering-tile grid (the planning ring's one large footprint) keep the every-reach scan. Bounds
  are remembered by outline contents, so unchanged furniture is not measured again and a moved outline gets a fresh bound.
  Test: `navigation/steering_bins_match_full_scan`.
- **A district's steering tiles bake one a frame and land together** (`rebake.md`): a tick with several tiles due bakes them a physics frame each (a moving walker's own first) and lands them in one frame, one steering-map sync.
- **A lone house's steering re-bake lands in its tick's frame** (`nav_updater.gd`; `steering_rebake_lands_in_its_tick_test.gd`; a district's
  tiles land as a burst, above): a held walker re-looks for a way round a body every `RECHECK` s and the map answers a frame after the
  re-bake, so a late one costs a whole `RECHECK`. A district's planning gather is not in the tick: it runs a step a physics frame after it (`NavGather`, `rebake.md`) and its
  bake is async; the planning region stays whole, swapped in as one.

## Avoid maps (`avoid_map`)

A walk that should keep out of some floor (the AI's doorway views, `docs/tactical-entry.md` E18) plans on a map with it carved out:
`avoid_map(region, key, holes) -> RID` (`region` is the planning region, `planning_region(planning_map)` finds it; `holes` closed
world-space polygons; `key` names the set). The planning bake keeps its source on its region, so the avoid
bake is the same geometry plus the holes, fused, snapped, welded. Each key gets a map of its own with one child region `NavAvoid`,
baked on a worker thread and landed on the fixed frame `NavBake.frames_for` after the ask (`avoid_frames` in a district, `house_frames` in a house) (`NavBake`; `ready(map)` is false until it answers). Asking again returns the same map and marks it
asked; once the planning bake is redone it is baked again in place, the old mesh answering meanwhile. A map nobody asked for in
`avoid_idle_frames` (`GameClock` frames, 1200 = 20 s, so a run frees the same maps on the same frame) is freed with its region by the next ask for another key on the same planning map (the sweep runs only inside
`avoid_map`), and every one is freed with its world. Invalid when the region has no bake. Test:
`tests/navigation/avoid_map_carves_the_views_test.gd`.

## The planning ring (`nav_ring.gd`)

The AI plans on the world's navigation map, and the server scans **every polygon** of a map to place a query's two ends (Godot 4.4 `_query_task_find_start_end_positions`, `map_iteration_get_closest_point_to_segment`: no culling by region box), so a district's map (~800 polygons) costs ten times what a lone house's (~130) does: a route 54 us against 11 us, a snap 15 us against 3.4 us, hundreds a decision. The match is fought in one building, so `NavBuilder.plan_ring(region, house, focus)` (called by `MatchBuilder.stage` for a district, `focus` the match building's rooms) adds `NavRing` (`NavRing.region_of`), a child region on a map of its own (`NavRing.map_of`): the building's rooms and an outdoor ring (`BOUNDS_PAD`, 160 px) round them, ~80 polygons, baked from the same walls and furniture holes as the district map (`NavRing.job`).

- **Only `snap`, `snap_within` and `route` look at it.** The AI is handed the district map as always; each query asks `NavRing.map_for(map, points)`: the ring map when every point lies `NavRing.MARGIN` (32 px, past the bake's edge erosion) inside the ring's rect and the ring answers, else the district's. A `route` whose ring path stops short of a goal that is on the floor (a way out round the ring's edge) is asked of the district map too, so no query goes unanswered (a goal off the floor keeps the ring's path, which ends where the district's does; a kept path may be longer than the district's when the shortest leaves the ring). `ready(map)` of the district map holds only once the ring is `ready`. Walking, steering, the avoid maps and the streets stay on the district's maps.
- **Re-baked with the planning map**, in the same call (`NavRebake.planning` and the sync `rebake`), from the footprints and walls the tick measured: the planning map lands on the fixed frame `NavBakeConfig.district_frames` after the start and the ring on `ring_frames` (`rebake.md`); the planning bake's `done` waits for both. Each map is whole at any time.
- **A lone house has none** (`NavRing.region_of` null, `map_of` invalid; `map_for` returns the map): one planning map, no behaviour change.
- Tests: `plan_ring_answers_like_the_district` (same reachability, path length within a few px, outside the ring the district's answer), `plan_ring_follows_a_rebake`, `lone_house_has_one_planning_map`; the guard `perf/nav_plan_ring_stress`.
