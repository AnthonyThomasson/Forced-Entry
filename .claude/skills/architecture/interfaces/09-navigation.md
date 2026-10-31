9. **Main / Testing (through `MatchBuilder`) / AI → Navigation** (leaf: builds the map, everyone else just pathfinds)
   - `NavBuilder.build(house, rooms, parent, agent_radius = NavBuilder.AGENT_RADIUS) -> NavigationRegion2D` — bakes one region whose
	 walkable area is the house footprint plus an outdoor ring, minus the house's **static** wall colliders (doorways stay open) **and each
	 solid furniture footprint** (every `RigidBody2D` with a collider, anchored pieces frozen static among them; walk-over decor has none).
   - **Re-bake** is the Navigation domain's own: `nav_updater.gd` (built by `MatchBuilder.stage`) re-carves the furniture holes in place at
	 the pieces' **current** positions, only when a piece has moved, the planning bake on the NavigationServer's worker thread.
	 `NavBuilder.rebake` / `rebake_async` / `rebake_steering` are test-facing seams, not part of this surface (`domain-navigation`).
   - `NavBuilder.furniture_holes(house) -> Array` — the carved footprints (anchored pieces included) as world-space polygons: what
	 `nav_debug.gd` draws, `nav_updater.gd` watches for a moved piece, and `match_spawner.gd` keeps a spawn's clearance from.
   - **Characters at rest are holes too, on a second map.** `NavBuilder.character_holes(root) -> Array` (footprints of the living characters
	 at rest under the region's parent), `NavBuilder.OBSTACLE_MARGIN` (px every carved footprint is grown by; the AI's entry geometry grows
	 a body at rest by it to match the carve), `NavBuilder.steering_map(planning_map) -> RID` (a map of its own holding the furniture *and*
	 those holes; named from the frame `build` returns, before it has synchronized (`ready` tells when it answers); invalid when the world
	 has none) and `steering_region(region)` (re-baked by `nav_updater.gd` too). The world's own map stays furniture-only because the AI
	 plans on it; the AI's `Locomotion` puts its `NavigationAgent2D` on the steering map for a walk round a body at rest it knows of (what
	 a walker accounts for is the AI's rule, `domain-ai` (`behavior-locomotion.md`)).
   - **Map queries**, what the AI asks of a baked map: `NavBuilder.ready(map) -> bool` (valid, synchronized at least once and has taken in
	 every region `build` put on it, so a map still showing the previous navmesh counts as unbaked), `snap(map, p) -> Vector2` (`p` on the
	 navmesh; unchanged before the bake), `route(map, from, to) -> PackedVector2Array` (the navigated waypoints; a straight segment before
	 the bake or with no path), `path_length(path) -> float`. Every user goes through these (AI locomotion, tactics and entry geometry,
	 grenade escape plan, snapshot options, routes overlay, the squad's follow spots, `PlayerStack`, the match builder's wait), so the "is
	 the map baked yet" rule lives in one place.
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
