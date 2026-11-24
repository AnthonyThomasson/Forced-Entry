---
name: domain-navigation
description: Use when editing scenes/navigation/ or working on nav baking, furniture and character holes, the steering and avoid maps, re-baking, or the nav-ready rule.
---

# Navigation domain (`scenes/navigation/`)

A leaf: it builds the maps; everyone else pathfinds. Takes a plain `rooms` array and a Node and depends only on Godot's
`NavigationServer3D` (the baker, regions, maps, queries; ADR 0016). Interface 9. Tests: `tests/navigation/`.

| File | Role |
|---|---|
| `nav_builder.gd` (`NavBuilder`) | All static: bake, re-bake, the holes, the steering and avoid maps, `ready` / `snap` / `route` / `path_length` / `iterations`. NavBuilder is at 20 public methods, the `max-public-methods` cap: the next one needs a split. |
| `nav_site.gd` (`NavSite`) | The source geometry's inputs: the house, its rooms, the agent radius and a district's explicit `bounds`. |
| `nav_leaves.gd` (`NavLeaves`) | All static: the house doors (`doors_of`, by the group) and the hole an open leaf leaves (`hole`). |
| `nav_updater.gd` | Script-only Node that re-bakes on an interval. |
| `nav_twins.gd` (`NavTwins`) | All static: what a bake reads of a body's 3D twin (`twins.md`): its shapes and their plan footprints. |
| `nav_holes.gd` (`NavHoles`), `nav_pieces.gd` (`NavPieces`) | `NavHoles`: a body's footprint (`cut`, `hull_of`: the hull of its twin's footprints, grown), the furniture's (`furniture`) and the reference that cuts every piece afresh (`plain`). `NavPieces`: one tracker per house, the pieces and the hull each was last cut to. |
| `nav_gather.gd` (`NavGather`) | A district's planning re-bake gathered a step a physics frame, swapped in whole (`NavRebake.swap`). |
| `nav_source.gd` (`NavSource`), `nav_border.gd` (`NavBorder`) | `NavSource`, all static: what a bake is gathered from (the walls read from the twins, the `job` of polygon and source: 2D plan outlines, projected into the 3D baker's at the bake) and running it (`bake_polygon`, `CELL_SIZE` 4 px). `NavBorder`: the raster of a steering tile's border cells (`runs`). |
| `nav_rebake.gd` (`NavRebake`) | All static: the updater's re-bakes, the planning one (its `swap` onto a worker thread) and the steering one. |
| `nav_bake.gd` (`NavBake`), `nav_bake_config.gd` (`NavBakeConfig`) | `NavBake`: one planning bake's worker thread and its landing on a fixed `GameClock` frame (not `Engine.get_physics_frames()`, which runs through a pause). `NavBakeConfig`: that count by kind of bake (`district_frames`, `avoid_frames`, `ring_frames`, `house_frames`, `tile_frames`: a steering burst's landing). |
| `nav_tiles.gd` (`NavTiles`), `nav_tile_bake.gd`, `nav_tile_burst.gd`, `nav_seams.gd`, `nav_settle.gd` | A district's steering tiles (each baked on a worker thread), the wall cache. `NavTileBake`: a bake in flight. `NavTileBurst`: a tick's tiles started a frame each, landed together. `NavSeams`: border welds. `NavSettle`: settling under 0.1 px is no change. |
| `nav_ring.gd` (`NavRing`) | A district's planning ring: a small map of the match building. |
| `nav_ready.gd`, `nav_snaps.gd`, `nav_plan.gd`, `nav_world.gd` | `NavReady`: does a map answer yet. `NavSnaps`: what `snap` learned. `NavPlan`: queries. `NavWorld`: a node's map. |
| `nav_routes.gd` (`NavRoutes`) | The exact route answers remembered between planning-map re-bakes, and `iterations(map)`. |
| `nav_union.gd` (`NavUnion`) | Fuses overlapping footprints. |
| `nav_merge.gd` (`NavMerge`) | Merges the baker's polygons where their union is convex (`baker.md`). |
| `nav_debug.gd` | Draw-only overlay of the holes. |

## Baking

`NavBuilder.build(house, rooms, parent, agent_radius, bounds)` bakes one `NavigationRegion3D`: the house footprint (the `rooms` rects grown by
`BOUNDS_PAD`, so a walkable **outdoor ring** lets an outside NPC path round to the front entrance) minus the plan footprints of the house's **wall twins**
(so doorways stay open), minus a **hole per solid piece's twin** so paths route
round furniture and through another doorway when the near one is blocked (a sealed route leaves the far side unreachable: the AI's cue to shove through). The bake runs in the house's local frame and the region is offset by `house.position`.
`MatchBuilder.stage` calls it once after the house and its twin space are made (default radius `NavBuilder.AGENT_RADIUS`).

- **Doors are left out of every bake** (interface 9, `docs/adr/0010-doors-are-driven-bodies-left-out-of-the-nav-bake.md`). A house `Door`
  is a driven body in its doorway, so a shut door would seal it in the map. `NavSource.walls_of` reads the wall twins only (a door's twin is no wall's;
  a wall's **lintel** is left out too, `twins.md`); `NavLeaves.doors_of` (the group `doors`, nothing of Objects imported) finds the doors for the open leaf's hole. The planning bake, the steering bake (they share `NavSource.walls_of`) and the
  avoid maps (made from the planning bake's remembered source) all path through a doorway as if it were open, and the walker opens the
  door (`docs/doors.md` DR14). Test: `tests/navigation/door_not_baked_test.gd`.
- **A leaf at its open stop is carved where it stands** (issue #183): `NavLeaves.hole(door)` (`furniture_holes` adds it, so every bake,
  re-bake, the updater's move check and the overlay take it) once the door stands within `NavLeaves.OPEN_SLACK` (10°) of `open_angle` and
  not down, read through interface 24. The hole is a strip
  as thick as the leaf (`leaf_size.y`), not the grown leaf: the bake's 18 px clearance off it is what a body needs (the 4 px cells put a
  mesh edge up to 3 px nearer, so a thinner strip left a walker pressed against the leaf; `navigation/door_open_leaf_hole_is_the_leaf_thick`),
  and the grown footprint sealed a 48 px doorway. A leaf further shut stands across its doorway's mouth, where no carve leaves the
  way open (sealed up to 75°), so it is left out, as is one with under `MIN_PASS` (4 px) of way past it. `NavBuilder.leaf_in_map(door)` is that rule for the AI. Tests:
  `tests/navigation/door_open_leaf_carved_test.gd`,
  `ai/movement/door_open_leaf_walked_round`.
- **The bake reads the 3D twins, not the 2D colliders** (`twins.md`): a wall's and a piece's or character's footprint is the plan polygon of its twin's shapes,
  grown by `OBSTACLE_MARGIN` for a hole, a round one the bake's own 10-sided polygon. Overlapping footprints are fused (skipped for outlines whose boxes are apart:
  `tests/navigation/furniture_union_fast_path_test.gd`) and every outline is snapped to whole pixels.
- **Every bake is the grid baker's** (ADR 0016, `NavSource.bake_polygon`, `baker.md`): `NavigationServer3D` on 4 px cells from the footprints projected onto a plan-space floor; no `NavWeld`. Regions, maps and queries are 3D: a plan point is the floor's `(x, 0, y)` (`NavPlan`); a region sits on the twin world's map (`NavWorld.map_of`).

## The steering map: characters at rest are holes too

`NavBuilder.character_holes(root)` returns the footprint of each **living character at rest** (a plan handle of the group `characters` that is not `is_dead`; a corpse is
walked over), moving slower than `REST_SPEED`) under `root`
(`house.get_parent()`), grown by `OBSTACLE_MARGIN`, through the same union and snap. Only characters at rest: every character is
inside its own hole, and a walking one's would seal the passage round itself and send its own path the long way.

These holes live in a **second map**: `build` adds a child region `NavSteering` (`steering_region(region)`) on a map of its own
(`steering_map(planning_map)`, made on first use, freed with its last region). `steering_map` names the map from NavBuilder's own
count, so it is valid the moment `build` returns, before the server takes the region in; whether it answers queries yet is `ready`
(`tests/navigation/steering_map_named_once_built_test.gd`). The world's own map stays furniture-only because the AI **plans** on
it (spots, routes, entry slots, coverage) and a body's hole would bend all of
them. Only a `NavigationAgent3D` walks the steering map, chosen per walk by the AI's `Locomotion` (`domain-ai` (`behavior-locomotion.md`)).
The map carves every body at rest; which a walk accounts for is the walker's business.

## A district's tiles, planning ring and the avoid maps

`district-tiles-and-avoid.md`: with a `bounds` rect `build` bakes the planning region over the whole district and the steering map as 512 px tiles, each re-baked only when its walls, furniture or characters changed; `plan_ring` adds the **planning ring**, a small map of the match building that `snap`, `snap_within` and `route` answer from when every point lies in it; `avoid_map` carves floor out of a walk's map.

## Keeping the holes current (`nav_updater.gd`)

A bake is a snapshot and furniture is shoved in play: `nav_updater.gd` re-bakes the planning and steering regions on an interval, only when something moved past `move_threshold`. The tick, the test seams `rebake` / `rebake_async` / `rebake_steering`, what `furniture_holes` keeps and bulldozing between re-bakes: `rebake.md`.

## Map queries (`ready` / `snap` / `route` / `path_length`)

The AI weighs points and routes against the planning map many times a decision, and every read must cope with the first frames
before a bake, when the map is valid but has never synchronized. `NavBuilder.ready(map)` is the one rule: `map.is_valid()`,
`map_get_iteration_id(map) != 0`, **and** every region `build` put on the map has been taken in. At a match's start the world's
map is live with the previous mesh and takes the new house a frame later on a worker thread; a query in between answers from the
old mesh (`map_force_update` does not change that) and a room's centre snaps to a corner nowhere near the house (issue #49). So
`build` records each region with a probe point and `ready` stays false until a query at the probe is answered by
that region. `navigation/map_with_old_mesh_is_not_ready` pins it; the match builder's stage waits on it
(`wait_nav`: planning and steering map) before any NPC is placed (`tests/general/match_nav_ready_before_spawn_test.gd`).

`snap(map, p)` returns `p` until then, else the closest navmesh point (a room's centre is often inside furniture), kept per map iteration: the server scans every polygon of the map for it, so a point asked again while the map stands is answered from what was learned (a re-bake starts afresh; `navigation/snap_follows_a_rebake`, `perf/nav_snap_repeat_stress`);
`snap_within(map, p, rect, from)` keeps that point in `rect` (a room) on floor a route from `from` (the doorway's) reaches: `p` stepped
toward the room's centre, then `from`, every `SNAP_WITHIN_STEP` (8 px) until its snap lands inside and is reached (`SNAP_REACHED`), else
`from`'s snap: a corner filled with furniture snaps through a thin wall, and a walled-off pocket routes round the outside
(`ai/entry/entry_front_door_corner_reachable`, `navigation/snap_within_reachable`);
`route(map, from, to)` returns a straight `[from, to]` until then and when the server finds no path. Once ready, `NavRoutes`
remembers the exact `(map, from, to)` answer, including the final answer after any ring-to-district fallback, only while both
planning maps' iteration IDs stand; a repeat returns a copy, either map's re-bake starts its answers afresh, and freeing a map
drops its entries. The per-map and whole-cache bounds start full caches afresh (`navigation/route_cache_follows_rebake`);
`path_length(path)` sums a path. `iterations(map)` is `[district, ring]` (-1 without a ring), what an answer is valid for: equal to an earlier read while neither took a re-bake in (the lead-walk memo keys on it). The AI calls these rather than keeping its own guard.

## Debug overlay (`nav_debug.gd`)

A draw-only world-space `Node2D` (the map is global, not per NPC) drawing the furniture holes as filled polygons with outlines,
and the characters' holes in another colour. `MatchBuilder.stage` builds it; `setup(house)` remembers the house; the holes are snapshotted (only while `show_holes` is on) via `NavBuilder.furniture_holes(house)`, the same selection and footprint helpers the bake uses, so it cannot drift from what was
carved; `show_holes` toggles it (`MatchBuilder.set_overlay`, the toggle bar's "Navigation holes", with Debug on).
