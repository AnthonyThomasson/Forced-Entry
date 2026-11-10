class_name NavBuilder
extends RefCounted
## Navigation domain (leaf): turns a generated house, or a whole district, into walkable navigation
## maps for the global NavigationServer2D. A bake is the walkable footprint (the rooms grown by
## `BOUNDS_PAD`, or a district's explicit `bounds`) minus the STATIC wall colliders, so doorways
## stay open, minus a hole per solid furniture footprint, so paths route around furniture and
## through another doorway when the near one is blocked. Any NavigationAgent2D pathfinds against
## the map. The maps: the PLANNING map (furniture only, what the AI plans and measures
## with: routes, flank and entry geometry, snapping a point to open floor), a STEERING map of its
## own that is also carved by every living character at rest (`character_holes`; what a
## NavigationAgent2D walks, since carving characters into the planning map would bend every route
## weighed against a hostile), and, for a district, 512 px steering tiles (`NavTiles`) and a small
## planning ring of the match building (`NavRing`). Imports nothing from other domains: it reads a
## plain `rooms` array and a Node, and recognises furniture (RigidBody2D) and characters
## (CharacterBody2D) by engine type alone.

## Extra clearance (px) baked around walls, on top of the agent radius, so paths don't hug walls.
const WALL_MARGIN := 4.0
## Padding (px) added around the room-union footprint: a walkable outdoor ring around the house, so
## characters outside (e.g. an invader) can path around it to the front entrance.
const BOUNDS_PAD := 160.0
## Padding (px) grown around a furniture footprint before it is baked in as a hole, so paths clear
## it.
const OBSTACLE_MARGIN := 6.0
## A character slower than this (px/s) is at rest, and only a character at rest is a hole (see
## `character_holes`). A walking pace is 150; a character pressed against a wall or another body
## reads about 0.
const REST_SPEED := 10.0
## An outline vertex closer than this (px) to the line between its neighbours is dropped before the
## bake (`NavSource.simplified`).
const SIMPLIFY_TOLERANCE := 1.5
## Name of the steering region, the planning region's child (see `steering_region`).
const STEERING_NAME := "NavSteering"
## Name of an avoid region, and the meta on the planning region that keeps its bake's source
## geometry (see `NavSource.remember`).
const AVOID_NAME := "NavAvoid"
const SOURCE_META := "nav_source"
## The meta on the planning region that keeps the explicit walkable footprint `build` was given, so
## every re-bake of the region bakes the same map (see `site_of`).
const BOUNDS_META := "nav_bounds"
## The agent radius (px, the character body's) every bake erodes the map by unless handed another:
## the first bake (`build`) and the re-bakes (`nav_updater.gd`, `NavSite`) share it.
const AGENT_RADIUS := 14.0
## How far (px) `snap_within` steps a point toward its room's centre between two tries.
const SNAP_WITHIN_STEP := 8.0
## Within this many px of a point a route `snap_within` reads has reached it.
const SNAP_REACHED := 2.0

## The steering map made for each world navigation map (planning map RID -> steering map RID), and
## how many steering regions stand on it. The map is freed with its last region.
static var _steering_maps: Dictionary = {}
static var _steering_regions: Dictionary = {}
## The planning region `build` put on each world map (planning map RID -> region), for
## `planning_region`.
static var _planning_regions: Dictionary = {}
## The avoid maps made for each world navigation map (planning map RID -> key -> entry), see
## `avoid_map`. An entry is `{ map: RID, region: NavigationRegion2D, version: int, baking: bool,
## asked_ms: int }`.
static var _avoid_maps: Dictionary = {}
## An avoid map nobody has asked for in this many ms (wall clock) is freed by the next ask for
## another set (`avoid_map`).
static var avoid_idle_ms: int = 20_000


## Build and add a NavigationRegion2D under `parent`, covering `rooms` (each `{ key, type, rect }`
## with a world-space `rect`, from WorldGen.get_rooms) minus `house`'s wall colliders.
## `agent_radius` is the pathing clearance (character body radius). Returns the region, or null if
## there are no rooms. `bounds` (world space; empty = from the rooms) is the walkable footprint when
## it is more than the rooms and a ring of `BOUNDS_PAD` round them: a district's streets out to its
## shells. The furniture holes baked in here are not permanent: `nav_updater.gd` re-carves them at
## the furniture's live positions when a piece has moved (`NavRebake`) so paths follow scattered
## pieces. The returned region is the PLANNING one, on the world's own navigation map; its child
## (`steering_region`) is baked with the living characters at rest too and sits on the steering
## map.
static func build(
	house: Node2D,
	rooms: Array,
	parent: Node,
	agent_radius: float = AGENT_RADIUS,
	bounds := Rect2(),
) -> NavigationRegion2D:
	var job := NavSource.job(
		NavSite.new(house, rooms, agent_radius, bounds),
		furniture_holes(house),
	)
	if job.is_empty():
		return null
	var nav_poly := NavSource.bake(job, house.position)
	var region := NavigationRegion2D.new()
	region.name = "NavRegion"
	region.position = house.position
	region.navigation_polygon = nav_poly
	region.set_meta(BOUNDS_META, bounds)
	NavSource.remember(region, job)
	parent.add_child(region)
	if region.is_inside_tree():
		var planning_map := region.get_navigation_map()
		_planning_regions[planning_map] = region
		region.tree_exited.connect(
			func() -> void:
				_planning_regions.erase(planning_map)
				NavRoutes.forget(planning_map),
			CONNECT_ONE_SHOT,
		)
		_add_steering_region(region, NavSite.new(house, rooms, agent_radius, bounds), nav_poly)
		var probe: Vector2 = (rooms[0]["rect"] as Rect2).get_center()
		NavReady.await_region(region.get_world_2d().navigation_map, region, probe)
		for steering in steering_regions(region):
			var at: Vector2 = NavTiles.probe_of(steering, probe)
			if at != Vector2.INF:
				NavReady.await_region(steering.get_navigation_map(), steering, at)
	return region


## Give a district's planning `region` (what `build` returned for it) its planning ring: a second,
## small planning map of `focus` (the rooms of the building the match is fought in, world space) and
## the outdoor ring round them, which `snap`, `snap_within` and `route` answer from when every point
## they weigh lies in it (`NavRing`). A lone house has none and plans on its one map.
static func plan_ring(
	region: NavigationRegion2D,
	house: Node2D,
	focus: Array,
	agent_radius: float = AGENT_RADIUS,
) -> void:
	NavRing.add(region, house, focus, agent_radius)


## What a re-bake of `region` (the planning region `build` returned) over `house` and its `rooms` is
## made from: the footprint `build` was given, so a district's re-bake covers its streets as its
## first bake did.
static func site_of(
	region: NavigationRegion2D,
	house: Node2D,
	rooms: Array,
	agent_radius: float = AGENT_RADIUS,
) -> NavSite:
	return NavSite.new(house, rooms, agent_radius, region.get_meta(BOUNDS_META, Rect2()))


## Re-bake `region`'s navigation polygon in place, re-carving the furniture holes at each piece's
## CURRENT position so paths route around furniture that has been shoved off its original spot. The
## region keeps its world offset; reassigning `navigation_polygon` re-registers the mesh with the
## NavigationServer2D. A test-facing seam that measures its own footprints; the game re-bakes
## through `nav_updater.gd`, which drives `NavRebake`.
static func rebake(
	region: NavigationRegion2D,
	house: Node2D,
	rooms: Array,
	agent_radius: float = AGENT_RADIUS,
) -> void:
	var site := site_of(region, house, rooms, agent_radius)
	var furniture := furniture_holes(house)
	var job := NavSource.job(site, furniture)
	if job.is_empty():
		return
	region.navigation_polygon = NavSource.bake(job, house.position)
	NavSource.remember(region, job)
	var ring := NavRing.job(region, site, furniture, {})
	if not ring.is_empty():
		NavRing.region_of(region).navigation_polygon = NavSource.bake(ring, house.position)


## Re-bake the steering region under `region` (the planning one `build` returned) with the furniture
## and the living characters at rest at their CURRENT positions. A test-facing seam that measures
## its own footprints; `nav_updater.gd` drives `NavRebake.steering`. Does nothing when the region
## has no steering child.
static func rebake_steering(
	region: NavigationRegion2D,
	house: Node2D,
	rooms: Array,
	agent_radius: float = AGENT_RADIUS,
) -> void:
	NavRebake.steering(
		region,
		site_of(region, house, rooms, agent_radius),
		furniture_holes(house),
		character_holes(house.get_parent()),
	)


## The steering region of `region` (the planning region `build` returned): the same house with the
## living characters carved out too, on its own navigation map. Null if it has none.
static func steering_region(region: NavigationRegion2D) -> NavigationRegion2D:
	return region.get_node_or_null(STEERING_NAME) as NavigationRegion2D


## Every steering region of `region`: the one `steering_region` names, or a district's tiles
## (`NavTiles`), each baked from what reaches it. Empty with none.
static func steering_regions(region: NavigationRegion2D) -> Array[NavigationRegion2D]:
	var out: Array[NavigationRegion2D] = []
	for child in region.get_children():
		if child is NavigationRegion2D and String(child.name).begins_with(STEERING_NAME):
			out.append(child)
	return out


## The steering map that goes with the world's navigation map `planning_map`, the one a
## NavigationAgent2D should walk (`agent.set_navigation_map`): paths on it route around the
## characters at rest. Invalid (keep the planning map) when no steering region is on it, so an agent
## in a world that never baked one walks the plain map. Named from the moment `build` has added the
## steering region, before the map has synchronized (whether it answers yet is `ready`, which
## `MatchBuilder.stage` waits on).
static func steering_map(planning_map: RID) -> RID:
	if int(_steering_regions.get(planning_map, 0)) > 0:
		return _steering_maps.get(planning_map, RID())
	return RID()


## Add the steering region as a child of the planning `region`, on the steering map of the world's
## map (created on first use, freed with its last region). With no character yet standing, its
## polygon is the planning one.
static func _add_steering_region(
	region: NavigationRegion2D,
	site: NavSite,
	planning_poly: NavigationPolygon,
) -> void:
	var map := _steering_map_for(region.get_world_2d().navigation_map)
	if site.bounds.has_area():
		_add_steering_tiles(region, map, site)
		return
	var characters := character_holes(site.house.get_parent())
	var nav_poly := (planning_poly
			if characters.is_empty()
			else _bake_polygon(site, characters))
	_add_steering(region, map, STEERING_NAME, nav_poly)


## The steering regions of a district: a tile over each part of its footprint (`NavTiles`), baked
## from the furniture and the characters at rest as they stand.
static func _add_steering_tiles(region: NavigationRegion2D, map: RID, site: NavSite) -> void:
	var footprint := site.footprint()
	for rect in NavTiles.grid(footprint):
		var tile := _add_steering(
			region,
			map,
			NavTiles.name_of(rect, footprint),
			NavigationPolygon.new(),
		)
		tile.set_meta(NavTiles.RECT_META, rect)
	NavTiles.rebake(
		region,
		site,
		furniture_holes(site.house),
		character_holes(site.house.get_parent()),
	)


## A steering region named `region_name` over `nav_poly`, a child of the planning `region` and on
## the steering `map`; counted, so the map is freed with its last one.
static func _add_steering(
	region: NavigationRegion2D,
	map: RID,
	region_name: String,
	nav_poly: NavigationPolygon,
) -> NavigationRegion2D:
	var steering := NavigationRegion2D.new()
	steering.name = region_name
	steering.navigation_polygon = nav_poly
	steering.set_navigation_map(map)
	region.add_child(steering)
	var planning_map := region.get_world_2d().navigation_map
	_steering_regions[planning_map] = int(_steering_regions.get(planning_map, 0)) + 1
	steering.tree_exited.connect(_on_steering_region_exited.bind(planning_map))
	return steering


## A steering region left the tree: free the steering map of `planning_map` once its last one has
## gone.
static func _on_steering_region_exited(planning_map: RID) -> void:
	var left := int(_steering_regions.get(planning_map, 1)) - 1
	if left > 0:
		_steering_regions[planning_map] = left
		return
	_steering_regions.erase(planning_map)
	if _steering_maps.has(planning_map):
		NavRoutes.forget(_steering_maps[planning_map])
		NavigationServer2D.free_rid(_steering_maps[planning_map])
		_steering_maps.erase(planning_map)


## The steering map for the world map `planning_map`, created on first use (regions come and go with
## each world, the way they do on the world's own map). It gets the project's
## 2D navigation defaults, which are what the world's own map is made with (a freshly made map has
## the 3D ones, and the server refuses a navmesh baked with another cell size).
static func _steering_map_for(planning_map: RID) -> RID:
	if _steering_maps.has(planning_map):
		return _steering_maps[planning_map]
	var map := NavSource.new_map()
	_steering_maps[planning_map] = map
	return map


## `rebake` with the bake itself on a worker thread, so a frame never pays for it: the source
## geometry is gathered on the main thread now (the walls are read from the scene tree, the
## furniture from its live positions), the bake runs in the background, and the polygon is assigned
## to `region` on the physics frame `NavBakeConfig.district_frames` after the call (`NavBake`), when
## `done` is called. A region freed meanwhile is left alone. `done` is called even when there is
## nothing to bake. The planning region only: the
## steering one is re-baked by `rebake_steering`. A test-facing seam that measures its own
## footprints; `nav_updater.gd` drives `NavRebake.planning`.
static func rebake_async(region: NavigationRegion2D, house: Node2D, rooms: Array,
		agent_radius: float = AGENT_RADIUS, done: Callable = Callable()) -> void:
	NavRebake.planning(
		region,
		site_of(region, house, rooms, agent_radius),
		furniture_holes(house),
		done,
	)


## Bake a NavigationPolygon for `site` (its house over its rooms at its agent radius): the house
## bounds minus the static wall colliders (doorways stay open) minus each solid furniture footprint
## (carved as a hole) and minus each of `characters` (footprints from `character_holes`; none = the
## planning bake). Returns null if there are no rooms. In the house's LOCAL frame — the region
## offsets it into world space. `build` bakes its steering region's first polygon with it. It
## gathers through `NavSource.job`, as the planning and steering bakes do, so all carve furniture
## holes identically, and bakes through `NavSource.bake`, which welds the result to the 1 px grid:
## every hole that meets a wall, a character's and a piece of furniture's, needs it.
static func _bake_polygon(site: NavSite, characters: Array = []) -> NavigationPolygon:
	var job := NavSource.job(site, furniture_holes(site.house), characters)
	if job.is_empty():
		return null
	return NavSource.bake(job, site.house.position)


## The furniture footprint holes a bake of `house` carves, each a closed WORLD-space polygon — the
## same solid-furniture selection and grown footprints `NavSource.add_holes` feeds the baker, so a
## debug overlay drawing these shows exactly what was carved out. Re-measured from each collider's
## live `global_transform` on every call, so it reflects where the furniture stands NOW — the
## re-bakes `nav_updater.gd` drives rely on that to re-carve holes as pieces are shoved around in
## play. A damaged piece has its primitive collider rebuilt into several deformed
## ConvexPolygonShape2D pieces, so EACH of a body's collision shapes contributes to its footprint —
## otherwise a dented piece's hole would vanish. A body's footprint is the convex hull of those
## shapes: a dent's notches are far smaller than the agent, and baked in they leave sub-pixel
## navmesh edges the NavigationServer cannot merge ("navigation map synchronization error"). Every
## RigidBody2D with a collider is carved: shoved furniture, and an anchored piece (frozen static: a
## streetlight's post), which never moves; walk-over decor is frozen too but has no collider, so it
## leaves no hole. A door's leaf standing clear of its doorway is carved too, where it stands now
## (`NavLeaves.hole`): out of the doorway, in the room it swings into, it is as solid as a piece of
## furniture there.
static func furniture_holes(house: Node2D) -> Array:
	return NavHoles.furniture(house)


## The footprint holes of the living characters AT REST under `root` (the node the nav region lives
## under, which is also the house's parent), each a closed WORLD-space polygon, like
## `furniture_holes`. A character is a CharacterBody2D with a collision layer (death clears the
## layer: a corpse is walked over) that moves slower than `REST_SPEED`. Only the ones at rest: a
## hole sits where a body stands in the way until it moves, and one that walks leaves none, because
## every character is inside its own hole and a walker's would seal or split the passage around
## itself (the hall, a doorway) and lead its own path the long way round. A character that stands
## still is carved, and so is one pushing against a wall or another body without getting anywhere;
## when it sets off its hole goes at the next re-bake. Every body at rest is carved, seen or not:
## which of them a walk accounts for is up to the walker (the AI's `Locomotion` goes round by this
## map only for a body it knows of). Re-measured on every call from the live collider transform, so
## the steering re-bakes `nav_updater.gd` drives follow the characters as they stop, set off, appear
## and die.
static func character_holes(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for node in root.get_children():
		var body := node as CharacterBody2D
		if (body == null
				or body.collision_layer == 0
				or body.get_real_velocity().length() >= REST_SPEED):
			continue
		var hull := NavHoles.hull_of(body)
		if not hull.is_empty():
			out.append(hull)
	return out


# --- Avoid maps -----------------------------------------------------------------------------------


## The planning region `build` put on world map `planning_map`, or null when none stands there (or
## it has left the tree).
static func planning_region(planning_map: RID) -> NavigationRegion2D:
	var region := _planning_regions.get(planning_map) as NavigationRegion2D
	if region == null or not is_instance_valid(region) or not region.is_inside_tree():
		return null
	return region


## A map of its own that holds the planning bake (the furniture) and the extra `holes` too, each a
## closed WORLD-space polygon: where the AI plans a walk that keeps out of some stretch of floor (a
## doorway's view). Made for `region`, the planning region `build` returned, and named by `key` (the
## same holes, the same key): the first ask makes the map and bakes it on a worker thread, so a
## frame never pays for it, `NavBake.frames_for` physics frames later it lands (`NavBake`)
## and `ready` tells when it answers queries, as for any map; the map is kept for the key and
## re-baked (the old mesh answers meanwhile) when the planning bake has been redone since. One
## nobody has asked for in `avoid_idle_ms` (20 s) is freed by the next ask for another key on the
## same planning map, and every one is freed with its region (its world). Invalid when the region
## has no bake to start from.
static func avoid_map(region: NavigationRegion2D, key: String, holes: Array) -> RID:
	if region == null or not region.has_meta(SOURCE_META):
		return RID()
	var planning_map := region.get_navigation_map()
	var entries: Dictionary = _avoid_maps.get(planning_map, {})
	_avoid_maps[planning_map] = entries
	var now := Time.get_ticks_msec()
	for k in entries.keys():
		var old: Dictionary = entries[k]
		if (k != key
				and now - int(old["asked_ms"]) > avoid_idle_ms
				and is_instance_valid(old["region"])):
			(old["region"] as Node).queue_free()  # Its tree exit frees the map.
	var stored: Dictionary = region.get_meta(SOURCE_META)
	if entries.has(key):
		var kept: Dictionary = entries[key]
		kept["asked_ms"] = now
		if not bool(kept["baking"]) and int(kept["version"]) != int(stored["version"]):
			_bake_avoid(region, kept, holes)
		return kept["map"]
	var map := NavSource.new_map()
	var avoid_region := NavigationRegion2D.new()
	avoid_region.name = AVOID_NAME
	avoid_region.set_navigation_map(map)
	var entry := {
		"map": map,
		"region": avoid_region,
		"version": -1,
		"baking": false,
		"asked_ms": now,
	}
	entries[key] = entry
	region.add_child(avoid_region)
	NavReady.await_region(map, avoid_region, region.global_position)
	avoid_region.tree_exited.connect(_on_avoid_region_exited.bind(planning_map, key, map))
	_bake_avoid(region, entry, holes)
	return map


## An avoid region left the tree (freed for being idle, or with its world): free its map and forget
## it.
static func _on_avoid_region_exited(planning_map: RID, key: String, map: RID) -> void:
	var entries: Dictionary = _avoid_maps.get(planning_map, {})
	if entries.has(key) and entries[key]["map"] == map:
		entries.erase(key)
	if entries.is_empty():
		_avoid_maps.erase(planning_map)
	NavRoutes.forget(map)
	NavigationServer2D.free_rid(map)


## Bake `entry`'s avoid region on a worker thread: the planning source geometry kept by
## `NavSource.remember`, with `holes` (world space) added as obstructions, fused and snapped like
## the furniture's. The polygon is assigned on the fixed frame the bake lands on (`NavBake`).
static func _bake_avoid(region: NavigationRegion2D, entry: Dictionary, holes: Array) -> void:
	var stored: Dictionary = region.get_meta(SOURCE_META)
	var origin := region.global_position
	var source := NavigationMeshSourceGeometryData2D.new()
	source.set_traversable_outlines(stored["traversable"])
	source.set_obstruction_outlines(stored["obstructions"])
	NavSource.add_holes(source, origin, holes)
	var nav_poly := NavSource.new_polygon(float(stored["agent_radius"]))
	entry["baking"] = true
	entry["version"] = int(stored["version"])
	NavBake.start(
		entry["region"] as NavigationRegion2D,
		{ "poly": nav_poly, "source": source },
		origin,
		func() -> void: entry["baking"] = false,
		NavBake.frames_for(region),
	)


# --- Map queries ---------------------------------------------------------------------------------
# What the AI asks of a baked map (interface 9) when it weighs a point or a route: one home for the
# "is the map baked yet" guard, so every caller treats the first frames before the bake the same
# way.


## Whether `map` is a baked map: valid, synchronized at least once, and has taken in every region
## `build` put on it. The last part matters at the start of a match: the world's map is already live
## with the previous navmesh (the menu's, the last match's), and it takes the new house in only a
## frame or so later. Until then a query still answers from the old mesh (a point snapped onto it
## lies nowhere near the house), so the callers treat the map as unbaked, the way they do before the
## first bake, and read the plain point and a straight route instead. A district's map is ready once
## its planning ring (`NavRing`) is too.
static func ready(map: RID) -> bool:
	var ring := NavRing.map_of(map)
	return NavReady.taken_in(map) and (not ring.is_valid() or NavReady.taken_in(ring))


## `p` snapped onto the navmesh (a room's geometric centre is often inside furniture); unchanged
## before the map is baked. The server scans every polygon of the map for it, so a point asked again
## is answered from what was learned while the map's iteration stands (the same answer the server
## gives; a re-bake starts the answers afresh).
static func snap(map: RID, p: Vector2) -> Vector2:
	if not ready(map):
		return p
	return NavSnaps.closest(NavRing.map_for(map, [p]), p)


## `p` snapped onto the navmesh inside `rect` (a room's rectangle) where a route from `from` (a
## point of that room's floor, a doorway's) reaches it: the closest point to `p` when it is, else
## the closest to a point stepped from `p` toward `rect`'s centre, then toward `from`, every
## `SNAP_WITHIN_STEP` px, the first that is, else `from`'s. The plain `snap` of a point by a thin
## wall can land on the wall's far side (the street, the next room) when the floor nearest to it
## there is closer than the room's own; and floor in `rect` that furniture walls off from `from`
## routes round the outside. Unchanged before the map is baked.
static func snap_within(map: RID, p: Vector2, rect: Rect2, from: Vector2) -> Vector2:
	if not ready(map):
		return p
	var asked := NavRing.map_for(map, [p, rect.get_center(), from])
	for toward in [rect.get_center(), from]:
		var steps := maxi(1, ceili(p.distance_to(toward) / SNAP_WITHIN_STEP))
		for i in steps + 1:
			var q := NavigationServer2D.map_get_closest_point(
				asked,
				p.lerp(toward, float(i) / steps),
			)
			if rect.has_point(q) and route(map, from, q)[-1].distance_to(q) <= SNAP_REACHED:
				return q
	return snap(map, from)


## Whether door `door`'s leaf stands in the nav maps as a hole (at its open stop, standing:
## `NavLeaves.hole`), so that a path goes round it where it stands; false for a door shut, ajar or
## down, whose doorway a path goes through as if open. Read through the door contract (interface
## 24). What the AI's walker reads to tell a door it has no need to open (`docs/doors.md` DR14).
static func leaf_in_map(door: Node) -> bool:
	return not NavLeaves.hole(door).is_empty()


## The iterations of the planning map `map` and of its ring (-1 without one), as `[district, ring]`:
## equal to an earlier read while neither map has taken a re-bake in, so an answer made from either
## stands (`route`'s memo, the AI's lead-walk memo).
static func iterations(map: RID) -> Array:
	return NavRoutes.iterations(map)


## The navigated route `from` → `to` as its waypoints; a straight segment before the map is baked or
## when no path exists.
static func route(map: RID, from: Vector2, to: Vector2) -> PackedVector2Array:
	if not ready(map):
		return PackedVector2Array([from, to])
	return NavRoutes.route(map, from, to)


## The length (px) of a path.
static func path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total
