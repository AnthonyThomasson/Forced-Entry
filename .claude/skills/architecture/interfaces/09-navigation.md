9. **Main / Testing (through `MatchBuilder`) / AI → Navigation** (leaf: builds the map, everyone else just pathfinds)
   - `NavBuilder.build(house, rooms, parent, agent_radius = NavBuilder.AGENT_RADIUS) -> NavigationRegion2D` (14 px, the radius the re-bakes share too) — bakes
	 one `NavigationRegion2D` whose walkable area is the house footprint plus an outdoor ring minus the house's
	 **static** wall colliders (doorways stay open) **and minus each solid furniture footprint**
	 (baked in as a hole: every `RigidBody2D` with a collider, an anchored piece frozen static among them; walk-over decor has
	 none), so paths route around furniture.
   - The re-bake is the Navigation domain's own: its `nav_updater.gd` (built by `MatchBuilder.stage`, below) re-carves the furniture holes in place at the
	 pieces' **current** positions, the planning bake on the NavigationServer's worker thread. `NavBuilder.rebake` / `rebake_async` /
	 `rebake_steering` are test-facing seams, not part of this surface (`domain-navigation`).
   - `NavBuilder.furniture_holes(house) -> Array` — the carved furniture footprints (the anchored pieces' included) as world-space
	 polygons: what the Navigation domain's draw-only `nav_debug.gd` overlay draws and its `nav_updater.gd` watches for a
	 moved piece, and what the match builder's `match_spawner.gd` keeps a spawn's clearance from.
   - **Characters at rest are holes too, on a second map.** `NavBuilder.character_holes(root) -> Array` (the footprints of the
	 living characters at rest under the region's parent), `NavBuilder.OBSTACLE_MARGIN` (the px every carved footprint is grown by: the AI's
	 entry geometry grows a body at rest by it to match the steering map's carve), `NavBuilder.steering_map(planning_map) -> RID` (a map of its own, holding
	 the furniture *and* those holes; named from the frame `build` returns, before it has synchronized (`ready` tells when it answers);
	 invalid when the world has none) and `steering_region(region)` (re-baked by `nav_updater.gd` too). The world's own map stays furniture-only, because the AI
	 plans on it; the AI's `Locomotion` puts its `NavigationAgent2D` on the steering map for a walk that goes round a body at rest it
	 knows of (the map carves every one; what a walker accounts for is the AI's rule, `domain-ai-behavior`).
   - **Map queries**, what the AI asks of a baked map when it weighs a point or a route: `NavBuilder.ready(map) -> bool`
	 (valid, synchronized at least once and has taken in every region `build` put on it, so a map still showing the previous
	 navmesh counts as unbaked), `snap(map, p) -> Vector2` (`p` on the navmesh; unchanged before the bake),
	 `route(map, from, to) -> PackedVector2Array` (the navigated waypoints; a straight segment before the bake or with no
	 path) and `path_length(path) -> float`. The AI's locomotion, tactics geometry, entry geometry, grenade escape plan, snapshot options and
	 routes overlay, the squad's follow spots (`snap`), the human's `PlayerStack` (how near a doorway it is) and the match builder's wait for the
	 maps (`MatchBuilder.stage`, interface 23: `ready` on the planning map and the steering map before any NPC is placed), all go through these, so the "is the map baked yet" rule lives in one place.
   - **Avoid maps**, for a walk that keeps out of some stretch of floor (the AI's doorway views, `docs/tactical-entry.md` E18):
	 `NavBuilder.avoid_map(region, key, holes) -> RID` (`region`: the planning region `build` returned, found from a world map by
	 `NavBuilder.planning_region(planning_map) -> NavigationRegion2D`; `holes`: world-space polygons; `key` names the set): a map of its
	 own with the planning bake plus those holes, baked on the NavigationServer's worker thread, cached by `key` (re-baked when the
	 planning bake has been redone since), freed by the next ask for another set once nobody has asked for it for 20 s, and with its
	 world, and `ready` as any map. The world's map and the
	 steering map are untouched. The AI's `Locomotion` walks it and `AgentDoorViews.walk_route` measures on it.
   `MatchBuilder.stage` (interface 23: Main's match and every test world alike) calls `build` once after the house is built (and builds the
   `nav_debug.gd` overlay and the `nav_updater.gd` re-baker right after), then, with the spec's `wait_nav` (on by default), waits until both
   maps are `ready`. Any `NavigationAgent2D` then pathfinds
   against the global map automatically — the AI's locomotion sets `target_position` and steers at
   `get_next_path_position()`. It does **not** enable RVO avoidance: instead the navmesh is
   **periodically re-baked** (`nav_updater.gd`, only when a piece has moved) so furniture that gets
   shoved around is re-carved as a hole at its new spot and paths route around scattered objects.
   Between re-bakes (and for non-solid decor, never carved) a displaced piece is simply bulldozed by
   the character's push physics.
