---
name: domain-navigation
description: Use when editing scenes/navigation/ or working on nav baking, furniture and character holes, the steering and avoid maps, re-baking, or the nav-ready rule.
---

# Navigation domain (`scenes/navigation/`)

A leaf: it builds the maps; everyone else pathfinds. It takes a plain `rooms` array and a Node and depends only on Godot's
`NavigationServer2D`. Interface 9 (Main / Testing / AI → Navigation). Tests: `tests/navigation/`.

| File | Role |
|---|---|
| `nav_builder.gd` (`NavBuilder`) | All static: bake, re-bake, the holes, the steering and avoid maps, `ready` / `snap` / `route` / `path_length`. |
| `nav_site.gd` (`NavSite`) | The source geometry's inputs: the house, its rooms and the agent radius. |
| `nav_updater.gd` | Script-only Node that re-bakes on an interval. |
| `nav_debug.gd` | Draw-only overlay of the holes. |

## Baking

`NavBuilder.build(house, rooms, parent, agent_radius)` bakes one `NavigationRegion2D`: the house footprint (the `rooms` rects grown by
`BOUNDS_PAD`, so a walkable **outdoor ring** lets an outside NPC path round to the front entrance) minus the house's **static**
wall colliders, so doorways stay open, minus a **hole per solid furniture footprint** (`_add_furniture_holes`), so paths route
round furniture and through another doorway when the near one is blocked (a piece sealing the only route leaves the far side
unreachable: the AI's cue to shove through). The bake runs in the house's local frame and the region is offset by `house.position`.
`MatchBuilder.stage` calls it once after the house is built (Main's match and every test world alike). Every bake gathers
through `_source_for`, so all carve holes identically; the default radius is `NavBuilder.AGENT_RADIUS`.

- Solid furniture is recognised by engine type alone: a `RigidBody2D` with a `CollisionShape2D` (shoved furniture, and an anchored
  piece such as a streetlight's post, `tests/navigation/anchored_hole_test.gd`). Walls are `StaticBody2D` (parsed, not carved);
  non-solid decor has no collider and so no hole. That keeps Navigation importing nothing.
- A hole is the **convex hull** of all the body's collider shapes (intact primitives and the `ConvexPolygonShape2D` pieces a dented
  piece is rebuilt into), grown by `OBSTACLE_MARGIN`. A dent's notches are far smaller than the agent, and baked in they leave
  sub-pixel edges the server cannot merge ("navigation map synchronization error"); using every shape keeps a dented piece's hole
  from vanishing on a re-bake. Overlapping footprints are fused (`_union_outlines`, skipped for outlines whose boxes are apart:
  `tests/navigation/furniture_union_fast_path_test.gd`) and every outline is snapped to the 1 px grid (`_on_grid`).
- **Every bake is welded** (`_finish`: `_weld_vertices`, then `_drop_slivers`, run by `_bake_job`, `_rebake_async` and
  `_bake_avoid`): a hole meeting a wall leaves vertices a fraction of a pixel apart, which the server rejects.
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
them. Only a `NavigationAgent2D` walks the steering map, chosen per walk by the AI's `Locomotion` (`domain-ai`, `behavior.md`).
The map carves every body at rest, seen or not; which bodies a walk accounts for is the walker's business.

## Avoid maps (`avoid_map`)

A walk that should keep out of some floor (the AI's doorway views, `docs/tactical-entry.md` E18) plans on a map with it carved out:
`avoid_map(region, key, holes) -> RID` (`region` is the planning region, `planning_region(planning_map)` finds it; `holes` closed
world-space polygons; `key` names the set). The planning bake keeps its source on its region (`_remember_source`), so the avoid
bake is the same geometry plus the holes, fused, snapped, welded. Each key gets a map of its own with one child region `NavAvoid`,
baked on the server's worker thread (`ready(map)` is false until it answers). Asking again returns the same map and marks it
asked; once the planning bake is redone it is baked again in place, the old mesh answering meanwhile. A map nobody asked for in
`avoid_idle_ms` is freed with its region by the next ask for another key on the same planning map (the sweep runs only inside
`avoid_map`), and every one is freed with its world. Invalid when the region has no bake. Test:
`tests/navigation/avoid_map_carves_the_views_test.gd`.

## Keeping the holes current (`nav_updater.gd`)

A bake is a snapshot, and furniture is shoved in play. `nav_updater.gd` (built once by `MatchBuilder.stage` right after the bake,
handed the region, house, rooms and the overlay) recomputes `furniture_holes` and `character_holes` each `interval` (cheap:
transforms only) and re-bakes **only** when something moved past `move_threshold`: furniture re-bakes both regions (the planning
one on the server's worker thread, `_rebake_async`; a tick while it is in flight (`_baking`) leaves the planning region alone, and
the baseline is set from what the bake carved when it lands, so a move during a bake is caught by the next tick); a character that
stopped, set off, appeared or died re-bakes the steering region in place. An at-rest scene costs the compare.

- The domain-internal `_rebake_async` / `_rebake_steering` take the footprints the tick just measured, so it measures furniture
  once and parses the walls once (`_walls_of`, `tests/navigation/walls_parsed_once_bake_the_same_test.gd`). The public `rebake`,
  `rebake_async`, `rebake_steering` are **test-facing seams** that measure their own footprints; only tests call them.
- `rebake` re-bakes a region's polygon in place with holes re-measured at the furniture's **current** `global_transform`.
  `rebake_async` gathers the geometry on the main thread and assigns the polygon when the bake lands, then runs `done`; the
  callback holds the region by a `WeakRef` because a lambda capturing a node freed before it runs logs an engine error into
  whatever runs next (`tests/navigation/rebake_outlives_region_test.gd`). The sync `rebake` is for a test that needs the map now
  (`perf/bake_and_path_stress` times it); no frame pays for a bake (`rebake_runs_off_the_main_thread_test.gd`).
- `furniture_holes` keeps each body's hull (`_hulls`) with what it was made from (`_hull_inputs`), so only a piece that moved,
  turned or was dented is measured again (`furniture_holes_follow_the_pieces_test.gd`); `_simplified` is pinned to the plain
  version by `outline_simplify_matches_plain_test.gd`.
- After each re-bake, and again when the planning one lands, it calls the overlay's `setup` so the overlay re-snapshots.
- **Between re-bakes bulldozing is the behaviour** (and for non-solid decor, never carved): a piece just shoved is run over by the
  character's push physics until the next re-bake routes round its new position.

Any `NavigationAgent2D` pathfinds against the map automatically; the AI's locomotion sets `target_position` and steers at
`get_next_path_position()`, and leaves the agent's RVO avoidance off.

## Map queries (`ready` / `snap` / `route` / `path_length`)

The AI weighs points and routes against the planning map many times a decision, and every read must cope with the first frames
before a bake, when the map is valid but has never synchronized. `NavBuilder.ready(map)` is the one rule: `map.is_valid()`,
`map_get_iteration_id(map) != 0`, **and** every region `build` put on the map has been taken in. At a match's start the world's
map is live with the previous mesh and takes the new house a frame later on a worker thread; a query in between answers from the
old mesh (`map_force_update` does not change that) and a room's centre snaps to a corner nowhere near the house (issue #49). So
`build` records each region with a probe point (`_awaiting`) and `ready` stays false until a query at the probe is answered by
that region. `tests/ai/perception/room_zones_inside_their_rooms_test.gd` pins it; the match builder's stage waits on it
(`wait_nav`: planning and steering map) before any NPC is placed (`tests/general/match_nav_ready_before_spawn_test.gd`).

`snap(map, p)` returns `p` until then, else the closest navmesh point (a room's centre is often inside furniture);
`route(map, from, to)` returns a straight `[from, to]` until then and when the server finds no path; `path_length(path)` sums a
path. The AI (`Locomotion`'s `reachable` / `on_navmesh` and its steering-map choice, `agent_tactics.gd`, `agent_entry.gd`,
`snapshot_options.gd`, `routes_debug.gd`) calls these rather than keeping its own guard.

## Debug overlay (`nav_debug.gd`)

A draw-only world-space `Node2D` (the map is global, not per NPC) drawing the furniture holes as filled polygons with outlines,
and the characters' holes in another colour. `MatchBuilder.stage` builds it; `setup(house)` snapshots the holes via
`NavBuilder.furniture_holes(house)`, the same selection and footprint helpers the bake uses, so it cannot drift from what was
carved; `show_holes` toggles it (`MatchBuilder.set_overlay`, the toggle bar's "Navigation holes"; with Debug on). It reads nothing
back and feeds nothing in.
