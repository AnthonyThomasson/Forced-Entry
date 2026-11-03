class_name NavRing extends RefCounted
## Navigation domain: the planning ring of a district. The AI plans (snaps a point, weighs a route)
## on the world's navigation map, and the server scans every polygon of a map for a query's two
## ends, so a district's map (eight hundred polygons: nine towers and their streets) costs ten
## times what a lone house's does for the same question. The match is fought in one building and
## the ring round it, so a second, small map holds just that: the match building's rooms and the
## outdoor ring (`NavBuilder.BOUNDS_PAD`) round them, baked from the same walls and furniture as
## the district map. `NavBuilder` answers a query whose points all lie well inside it from this
## map (`map_for`), else from the district's, which stays the map the AI is handed. Walking,
## steering and the streets stay on the district's maps. `NavBuilder.plan_ring` builds the region,
## `NavBuilder`'s re-bakes hand each tick's footprints to `job`.

## The ring region's name: a child of the planning region, on a map of its own.
const NAME := "NavRing"
## The meta on the planning region that keeps the ring: `{ rooms, rect }`, the match building's
## rooms and the ring's walkable rect (world space), so every re-bake bakes the same map.
const META := "nav_ring"
## How far (px) inside the ring's rect a point must lie to be weighed on the ring map: the bake
## erodes the rect's edge by the agent radius, so a point nearer the edge would snap inward where
## the district map leaves it.
const MARGIN := 32.0

## The ring map made for each world navigation map that has one (planning map RID -> `{ map: RID,
## covered: Rect2 }`).
static var _rings: Dictionary = {}


## Give the planning `region` of a district over `house` its ring round `focus` (the match
## building's rooms, world space), as `NavBuilder.plan_ring`: a region on a map of its own, baked
## from the walls and the furniture that reach the building and its outdoor ring, freed with the
## region. Nothing when the region covers no explicit footprint or `focus` has no area.
static func add(
	region: NavigationRegion2D,
	house: Node2D,
	focus: Array,
	agent_radius: float,
) -> void:
	var bounds: Rect2 = region.get_meta(NavBuilder.BOUNDS_META, Rect2())
	var rect := rect_of(focus, bounds)
	if not rect.has_area():
		return
	region.set_meta(META, { "rooms": focus, "rect": rect })
	var site := NavSite.new(house, [], agent_radius, bounds)
	var baked := job(region, site, NavBuilder.furniture_holes(house), {})
	if baked.is_empty():
		region.remove_meta(META)  # no ring: a re-bake must not look for its region
		return
	var map := NavSource.new_map()
	var ring := NavigationRegion2D.new()
	ring.name = NAME
	ring.navigation_polygon = NavSource.bake(baked, house.position)
	ring.set_navigation_map(map)
	region.add_child(ring)
	var planning_map := region.get_world_2d().navigation_map
	_rings[planning_map] = { "map": map, "covered": covered(rect) }
	ring.tree_exited.connect(_on_exited.bind(planning_map, map), CONNECT_ONE_SHOT)
	NavReady.await_region(map, ring, (focus[0]["rect"] as Rect2).get_center())


## The ring region left the tree: free its map and forget what was learned on it.
static func _on_exited(planning_map: RID, map: RID) -> void:
	if _rings.get(planning_map, {}).get("map", RID()) == map:
		_rings.erase(planning_map)
	NavSnaps.forget(map)
	NavigationServer2D.free_rid(map)


## The ring region of `region` (the planning region `NavBuilder.build` returned): null for a lone
## house, which plans on its one map.
static func region_of(region: NavigationRegion2D) -> NavigationRegion2D:
	return region.get_node_or_null(NAME) as NavigationRegion2D


## The ring map that goes with the world's navigation map `planning_map`: invalid when the world
## has none. Named from the moment `add` has returned, before it answers.
static func map_of(planning_map: RID) -> RID:
	return _rings.get(planning_map, {}).get("map", RID())


## The map a query over `points` is answered from: the ring map when it answers and every point
## lies well inside the ring (`MARGIN`), else `map`, the world's own.
static func map_for(map: RID, points: Array) -> RID:
	var ring: Dictionary = _rings.get(map, {})
	if ring.is_empty() or not NavReady.taken_in(ring["map"]):
		return map
	var inside: Rect2 = ring["covered"]
	for p: Vector2 in points:
		if not inside.has_point(p):
			return map
	return ring["map"]


## Whether `path`, asked of the ring `map` for `to`, is an answer to keep: it ends at `to`, or `to`
## is off the floor (inside a wall or a piece of furniture) and the path ends at the floor the
## server took for it, as the district's would. A path that stops short of a `to` that is on the
## floor means the floor lies where the ring does not reach from the path's start, perhaps round
## the outside of the ring: the district map is asked.
static func keeps(map: RID, path: PackedVector2Array, to: Vector2) -> bool:
	if path.size() < 2:
		return false
	return (
		path[-1].distance_to(to) <= NavBuilder.SNAP_REACHED
		or NavigationServer2D.map_get_closest_point(map, to).distance_to(to)
			> NavBuilder.SNAP_REACHED
	)


## The walkable rect of the ring: `focus` grown by the outdoor ring, kept inside the district's
## `bounds`. An empty Rect2 when there is none.
static func rect_of(focus: Array, bounds: Rect2) -> Rect2:
	if focus.is_empty() or not bounds.has_area():
		return Rect2()
	return NavSource.bounds_of(focus).grow(NavBuilder.BOUNDS_PAD).intersection(bounds)


## The part of the ring's `rect` a query is answered from the ring map in.
static func covered(rect: Rect2) -> Rect2:
	return rect.grow(-MARGIN)


## The bake job (`NavSource.job`) of `region`'s ring from the district's `site`: the
## walls and the furniture footprints of the district that reach it. `walls` is a parse of the
## district (`NavTiles.walls_after`'s shape) when the caller has one this frame, else the towers
## that reach the ring are parsed (`NavTiles.walls_reaching`). `furniture` is
## `NavBuilder.furniture_holes`. {} when the region has no ring.
static func job(
	region: NavigationRegion2D,
	site: NavSite,
	furniture: Array,
	walls: Dictionary,
) -> Dictionary:
	var kept: Dictionary = region.get_meta(META, {})
	if kept.is_empty():
		return {}
	var ring := NavSite.new(site.house, kept["rooms"], site.agent_radius, kept["rect"])
	var reaches: Array[Rect2] = [ring.footprint().grow(NavTiles.BORDER)]
	var outlines: Array = (
		walls["obstruction"] if not walls.is_empty()
		else NavTiles.walls_reaching(region, ring, reaches)
	)
	var reached := NavSource.walls(NavTiles.bin(outlines, reaches, Vector2.ZERO)[0])
	var holes: Array = NavTiles.bin(furniture, reaches, ring.house.position)[0]
	return NavSource.job(ring, holes, [], reached)
