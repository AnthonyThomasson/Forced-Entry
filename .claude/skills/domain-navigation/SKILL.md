---
name: domain-navigation
description: Use when editing scenes/navigation/ or working on nav baking, furniture and character holes, the steering and avoid maps, re-baking, or the nav-ready rule.
---

# Navigation domain (`scenes/navigation/`)

A leaf: it builds the maps; everyone else pathfinds. Takes a plain `rooms` array and a Node and depends only on Godot's
`NavigationServer2D`. Interface 9 (Main / Testing / AI → Navigation). Tests: `tests/navigation/`.

| File | Role |
|---|---|
| `nav_builder.gd` (`NavBuilder`) | All static: bake, re-bake, the holes, the steering and avoid maps, `ready` / `snap` / `route` / `path_length`. |
| `nav_site.gd` (`NavSite`) | The source geometry's inputs: the house, its rooms, the agent radius and a district's explicit `bounds`. |
| `nav_leaves.gd` (`NavLeaves`) | All static: the house doors (`doors_of`, by the group) and the hole an open leaf leaves (`hole`). |
| `nav_updater.gd` | Script-only Node that re-bakes on an interval. |
| `nav_holes.gd` (`NavHoles`), `nav_pieces.gd` (`NavPieces`) | `NavHoles`: a body's footprint (`cut`, `hull_of`), the furniture's (`furniture`) and the reference that cuts every piece afresh (`plain`). `NavPieces`: one tracker per house, the pieces and the hull each was last cut to. |
| `nav_gather.gd` (`NavGather`) | A district's planning re-bake gathered a step a physics frame, swapped in whole (`NavRebake.swap`). |
| `nav_source.gd` (`NavSource`) | All static: what a bake is gathered from (the parsed walls, `walls` / `walls_of`, the `job` of polygon and source) and running it (`bake`), the outline helpers. |
| `nav_rebake.gd` (`NavRebake`) | All static: the updater's re-bakes, the planning one (its `swap` onto the worker thread) and the steering one. |
| `nav_tiles.gd` (`NavTiles`) | A district's steering tiles, the per-tower wall cache and the remembered outline bounds. |
| `nav_ring.gd` (`NavRing`) | A district's planning ring: a small map of the match building. |
| `nav_ready.gd`, `nav_snaps.gd` | `NavReady`: does a map answer yet. `NavSnaps`: what `snap` learned. |
| `nav_routes.gd` (`NavRoutes`) | The exact route answers remembered between planning-map re-bakes. |
| `nav_union.gd` (`NavUnion`) | Fuses overlapping footprints. |
| `nav_weld.gd` (`NavWeld`) | A bake's end: vertices welded, slivers dropped. |
| `nav_debug.gd` | Draw-only overlay of the holes. |

## Baking

`NavBuilder.build(house, rooms, parent, agent_radius, bounds)` bakes one `NavigationRegion2D`: the house footprint (the `rooms` rects grown by
`BOUNDS_PAD`, so a walkable **outdoor ring** lets an outside NPC path round to the front entrance) minus the house's **static**
wall colliders, so doorways stay open, minus a **hole per solid furniture footprint** so paths route
round furniture and through another doorway when the near one is blocked (a piece sealing the only route leaves the far side
unreachable: the AI's cue to shove through). The bake runs in the house's local frame and the region is offset by `house.position`.
`MatchBuilder.stage` calls it once after the house is built (Main's match and every test world alike). Every bake gathers
its source the same way, so all carve holes identically (default radius `NavBuilder.AGENT_RADIUS`).

- **Doors are left out of every bake** (interface 9, `docs/adr/0010-doors-are-driven-bodies-left-out-of-the-nav-bake.md`). A house `Door`
  is an `AnimatableBody2D`, which the engine's static-collider parse reads as a wall, so a shut door would seal its doorway in the map.
  `NavSource.walls_of` takes the bodies of the group `doors` under the house (`NavLeaves.doors_of`: the group and `is_ancestor_of`, nothing of Objects imported)
  off the solid layer for the length of the parse and puts them back. The planning bake, the steering bake (they share `NavSource.walls_of`) and the
  avoid maps (made from the planning bake's remembered source) all path through a doorway as if it were open, and the walker opens the
  door (`docs/doors.md` DR14). Test: `tests/navigation/door_not_baked_test.gd`.
- **A leaf at its open stop is carved where it stands** (issue #183): `NavLeaves.hole(door)` (`furniture_holes` adds it, so every bake,
  re-bake, the updater's move check and the overlay take it) once the door stands within `NavLeaves.OPEN_SLACK` (10°) of `open_angle` and
  not down, read through interface 24. The hole is a strip
  `NavLeaves.HALF` (1 px) each side of the leaf's middle line, not the grown leaf: the bake's 18 px clearance off the strip is what a body
  needs, and the grown footprint sealed a 48 px doorway. A leaf further shut stands across its doorway's mouth, where no carve leaves the
  way open (sealed up to 75°), so it is left out, as is one with under `MIN_PASS` (4 px) of way past it. `NavBuilder.leaf_in_map(door)` is that rule for the AI. Tests:
  `tests/navigation/door_open_leaf_carved_test.gd` (shut and ajar left out, open carved, the doorway open past it on both maps),
  `ai/movement/door_open_leaf_walked_round`.
- Solid furniture is recognised by engine type alone: a `RigidBody2D` with a `CollisionShape2D` (shoved furniture, and an anchored
  piece such as a streetlight's post, `tests/navigation/anchored_hole_test.gd`). Walls are `StaticBody2D` (parsed, not carved);
  non-solid decor has no collider and so no hole. That keeps Navigation importing nothing.
- A hole is the **convex hull** of all the body's collider shapes (intact primitives and the `ConvexPolygonShape2D` pieces a dented
  piece is rebuilt into), grown by `OBSTACLE_MARGIN`. A dent's notches are far smaller than the agent, and baked in they leave
  sub-pixel edges the server cannot merge ("navigation map synchronization error"); using every shape keeps a dented piece's hole
  from vanishing on a re-bake. Overlapping footprints are fused (skipped for outlines whose boxes are apart:
  `tests/navigation/furniture_union_fast_path_test.gd`) and every outline is snapped to the 1 px grid.
- **Every bake is welded** (vertices merged, then slivers dropped; planning, re-bake and avoid bakes alike): a hole meeting a wall leaves vertices a fraction of a pixel apart, which the server rejects.
  Tests: `furniture_beside_wall_bakes_clean_test.gd`, `character_beside_wall_bakes_clean_test.gd`.

## The steering map: characters at rest are holes too

`NavBuilder.character_holes(root)` returns the footprint of each **living character at rest** (a `CharacterBody2D` that still has
a collision layer, since death clears it and a corpse is walked over, moving slower than `REST_SPEED`) under `root`
(`house.get_parent()`), grown by `OBSTACLE_MARGIN`, through the same union and snap. Only characters at rest: every character is
inside its own hole, and a walking one's would seal the passage round itself and send its own path the long way.

These holes live in a **second map**: `build` adds a child region `NavSteering` (`steering_region(region)`) on a map of its own
(`steering_map(planning_map)`, made on first use, freed with its last region). `steering_map` names the map from NavBuilder's own
count, so it is valid the moment `build` returns, before the server takes the region in; whether it answers queries yet is `ready`
(`tests/navigation/steering_map_named_once_built_test.gd`). The world's own map stays furniture-only because the AI **plans** on
it (flank, fire and retreat spots, route length and exposure, entry slots, search coverage) and a body's hole would bend all of
them. Only a `NavigationAgent2D` walks the steering map, chosen per walk by the AI's `Locomotion` (`domain-ai` (`behavior-locomotion.md`)).
The map carves every body at rest, seen or not; which bodies a walk accounts for is the walker's business.

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
that region. `tests/ai/perception/room_zones_inside_their_rooms_test.gd` pins it; the match builder's stage waits on it
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
`path_length(path)` sums a path. The AI calls these rather than keeping its own guard.

## Debug overlay (`nav_debug.gd`)

A draw-only world-space `Node2D` (the map is global, not per NPC) drawing the furniture holes as filled polygons with outlines,
and the characters' holes in another colour. `MatchBuilder.stage` builds it; `setup(house)` remembers the house; the holes are snapshotted (only while `show_holes` is on) via `NavBuilder.furniture_holes(house)`, the same selection and footprint helpers the bake uses, so it cannot drift from what was
carved; `show_holes` toggles it (`MatchBuilder.set_overlay`, the toggle bar's "Navigation holes"; with Debug on).
