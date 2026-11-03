9. **Main / Testing (through `MatchBuilder`) / AI → Navigation** (leaf: builds the map, everyone else just pathfinds)
   - `NavBuilder.build(house, rooms, parent, agent_radius = NavBuilder.AGENT_RADIUS, bounds = Rect2()) -> NavigationRegion2D` — bakes one
	 region whose walkable area is the house footprint plus an outdoor ring (or, with a `bounds` rect, that rect: a district's streets out
	 to where its shells begin (they stand past it, off the map), `WorldGen.district_bounds`; `house` is then the district root and `rooms` every tower's), minus the house's **static** wall colliders (doorways stay open) **and each
	 solid furniture footprint** (every `RigidBody2D` with a collider, anchored pieces frozen static among them; walk-over decor has none).
	 **Doors are left out of every bake** (planning, steering and avoid maps): the bodies of the group `doors` (interface 24, an
	 `AnimatableBody2D`, a static collider to the parse) are taken off the solid layer for the parse, so paths cross a doorway as if open and
	 the walker opens the door (`docs/adr/0010-doors-are-driven-bodies-left-out-of-the-nav-bake.md`). **A door at its open stop** (within
	 `NavLeaves.OPEN_SLACK`, 10°, standing) is carved where its leaf stands, as a 2 px strip along the leaf (a furniture hole, so every bake,
	 re-bake and the overlay take it) where at least `NavLeaves.MIN_PASS` (4 px) of way past it stays open (not in a 52 px doorway): its
	 doorway stays open past it and a path goes round the leaf in the room it swings into. `NavBuilder.leaf_in_map(door) -> bool` tells
	 whether a door's leaf is in the map so (the AI's walker goes through any other door by a clean gap or opens it, DR14).
   - **Re-bake** is the Navigation domain's own: `nav_updater.gd` (built by `MatchBuilder.stage`) re-carves the furniture holes in place at
	 the pieces' **current** positions, only when a piece has moved, the planning bake on the NavigationServer's worker thread. The steering re-bake lands in the frame of the tick that measured the change (house and district alike: the AI's held walkers look for a way round a body on a timer, and a late map misses the look); a district's planning gather waits a frame.
	 `NavBuilder.rebake` / `rebake_async` / `rebake_steering` are test-facing seams, not part of this surface (`domain-navigation`).
   - `NavBuilder.furniture_holes(house) -> Array` — the carved footprints (anchored pieces and open door leaves included) as world-space polygons: what
	 `nav_debug.gd` draws, `nav_updater.gd` watches for a moved piece, and `match_spawner.gd` keeps a spawn's clearance from.
   - **Characters at rest are holes too, on a second map.** `NavBuilder.character_holes(root) -> Array` (footprints of the living characters
	 at rest under the region's parent), `NavBuilder.OBSTACLE_MARGIN` (px every carved footprint is grown by; the AI's entry geometry grows
	 a body at rest by it to match the carve), `NavBuilder.steering_map(planning_map) -> RID` (a map of its own holding the furniture *and*
	 those holes; named from the frame `build` returns, before it has synchronized (`ready` tells when it answers); invalid when the world
	 has none), `steering_region(region)` and `steering_regions(region)` (re-baked by `nav_updater.gd` too). A lone house's steering map is the one
	 region; a district's (a `bounds` was given) is a grid of 512 px tiles (`nav_tiles.gd`), each baked from what reaches it and re-baked only
	 when that changes, so a character stopping re-bakes the tile it stands in, not the district. The world's own map stays furniture-only because the AI
	 plans on it; the AI's `Locomotion` puts its `NavigationAgent2D` on the steering map for a walk round a body at rest it knows of (what
	 a walker accounts for is the AI's rule, `domain-ai` (`behavior-locomotion.md`)).
   - **Map queries**, what the AI asks of a baked map: `NavBuilder.ready(map) -> bool` (valid, synchronized at least once and has taken in
	 every region `build` put on it, so a map still showing the previous navmesh counts as unbaked), `snap(map, p) -> Vector2` (`p` on the
	 navmesh; unchanged before the bake), `snap_within(map, p, rect, from) -> Vector2` (the same kept inside `rect`, a room, on floor a
	 route from `from` reaches: `p` stepped toward its centre, then toward `from`, until its snap lands in it and is reached, so a point
	 by a thin wall never snaps to the far side, nor into a pocket furniture walls off; the entry's corners), `route(map, from, to) -> PackedVector2Array` (the navigated waypoints; a straight segment before
	 the bake or with no path), `path_length(path) -> float`. Every user goes through these (AI locomotion, tactics and entry geometry,
	 grenade escape plan, snapshot options, routes overlay, the squad's follow spots, `PlayerStack`, the match builder's wait), so the "is
	 the map baked yet" rule lives in one place.
   - **A district's planning ring**, the AI's planning map in a district: `NavBuilder.plan_ring(region, house, focus, agent_radius = NavBuilder.AGENT_RADIUS)`
	 (`MatchBuilder.stage` calls it for a district; `focus` the rooms of the building the match is fought in) adds `NavRing`, a small map of that
	 building and its outdoor ring (`NavRing.PAD`, 300 px), baked from the same walls and furniture as the world's map and re-baked with it, because
	 the server scans every polygon of a map for a query (a route is 54 us on a district's ~800 polygons, 11 us on a house's). **The AI does not
	 know of it**: `snap`, `snap_within` and `route` take the world map as ever and answer from the ring when every point they weigh lies well
	 inside it (`NavRing.MARGIN`), else from the world's map, and a route the ring cannot finish is asked of the world's map; `ready(map)` also
	 waits for the ring. A lone house has no ring and one planning map. Walking, steering and the avoid maps stay on the world's maps.
	 `NavRing.region_of(region)` / `map_of(planning_map)` / `map_for(map, points)` are for Navigation's tests and the perf guard.
   - **Avoid maps**, for a walk that keeps out of some floor (the AI's doorway views, `docs/tactical-entry.md` E18):
	 `NavBuilder.avoid_map(region, key, holes) -> RID` (`region`: the planning region `build` returned, found from a world map by
	 `NavBuilder.planning_region(planning_map) -> NavigationRegion2D`; `holes`: world-space polygons; `key` names the set): a map of its own
	 with the planning bake plus those holes, baked on the worker thread, cached by `key` (re-baked when the planning bake has been redone),
	 freed by the next ask for another set once nobody has asked for `avoid_idle_ms` (20 s), and with its world; `ready` as any
	 map. The world's and the steering map are untouched. `Locomotion` walks it and `AgentDoorViews.walk_route` measures on it.

   `MatchBuilder.stage` (interface 23: Main's match and every test world) calls `build` once after the house is built (then builds the
   `nav_debug.gd` overlay and the `nav_updater.gd` re-baker), then, with the spec's `wait_nav` (default on), waits until both maps are
   `ready`. A `NavigationAgent2D` then pathfinds against the global map (the AI sets `target_position` and steers at
   `get_next_path_position()`). RVO avoidance is off: shoved furniture is re-carved by the periodic re-bake, and between re-bakes (and for
   non-solid decor, never carved) a displaced piece is simply bulldozed by the character's push physics.
