extends GameTest
## A district's steering map is never `NavBuilder.ready` before every tile the build put on it has
## taken its mesh in, and a tile whose re-bake is in flight on its worker thread (`NavTileBurst`)
## still answers routes from its last mesh until the burst lands (#194): no gap in the map and no
## unready between the change and its landing, the mesh the tile had being swapped, not removed.

const MainProbe := preload("res://tests/_main/main_probe.gd")
## A walkable rect the steering tiles (512 px each) cover with several tiles.
const BOUNDS := Rect2(-300, -300, 1800, 1400)
## How long (sim s) the maps may take to answer: they are made on the server's worker thread in
## real time, and a headless run's frames are far shorter than that.
const WAIT := 12.0
## How near (px) a path's end must come to the point asked: the mesh's own cell is 4 px.
const REACH := 6.0
const PIECE := {
	"name": "Crate", "shape": "rect", "size": Vector2(80, 80), "color": Color(0.5, 0.4, 0.3),
	"weight": 40,
}


func describe() -> Dictionary:
	return {
		"name": "A district's steering map is ready only with its tiles in, and answers mid-burst",
		"description": "Every frame from the build, NavBuilder.ready true means every steering "
			+ "tile answers at its probe; a tile whose re-bake is on its thread keeps its "
			+ "mesh and a route through it is found each frame until the burst lands.",
		"tags": ["navigation", "district", "steering", "rebake"],
		"timeout": 40.0,
	}


func run(t: TestContext) -> void:
	var viewport := MainProbe.viewport(t)
	var root := Node2D.new()
	viewport.add_child(root)
	var house := Node2D.new()
	root.add_child(house)
	var twins := TwinSpace.new()
	ObjectTwins.register(twins)
	root.add_child(twins)
	twins.watch(root)
	var piece := ObjectFactory.spawn(PIECE, Vector2(400, 400), house) as Node2D
	await t.frames(2)  # a twin joins the frame after its body
	var rooms: Array = [{ "key": "room", "type": "room", "rect": Rect2(200, 200, 400, 400) }]
	var region := NavBuilder.build(house, rooms, root, NavBuilder.AGENT_RADIUS, BOUNDS)
	var tiles := NavBuilder.steering_regions(region)
	if not t.require(tiles.size() >= 4, "premise: the steering map is many tiles"):
		return
	var steering := NavBuilder.steering_map(region.get_navigation_map())
	await _ready_means_tiles_in(t, steering, tiles)
	await _route_through_a_tile_in_flight(t, region, house, rooms, piece)


## From the build until the map is ready, every frame: ready is false until all tiles answer, and
## once it is true every tile does (the probe of a tile is a point of its own mesh).
func _ready_means_tiles_in(
	t: TestContext,
	steering: RID,
	tiles: Array[NavigationRegion3D],
) -> void:
	var not_ready_first := not NavBuilder.ready(steering)
	t.check(not_ready_first, "the steering map is not ready in the frame the build returns")
	var too_early: Array[int] = []
	var frame := 0
	var landed := false
	while frame < int(WAIT * 60.0):
		if NavBuilder.ready(steering):
			landed = true
			var missing := _missing(steering, tiles)
			if not missing.is_empty():
				too_early.append(frame)
			break
		await t.frames(1)
		frame += 1
	t.check(landed, "the steering map becomes ready")
	t.check(too_early.is_empty(), "ready only with every tile in (frames: %s)" % str(too_early))
	t.check(_missing(steering, tiles).is_empty(), "every tile answers at its probe once ready")


## The tiles of `tiles` with a mesh whose probe the map does not answer from them.
func _missing(steering: RID, tiles: Array[NavigationRegion3D]) -> Array[String]:
	var out: Array[String] = []
	if NavPlan.iteration(steering) == 0:
		for tile in tiles:
			out.append(String(tile.name))
		return out
	for tile in tiles:
		var at := NavTiles.probe_of(tile, Vector2.INF)
		if at == Vector2.INF:
			continue
		if NavPlan.owner_at(steering, at) != tile.get_rid():
			out.append(String(tile.name))
	return out


## The piece is moved, so the tile holding it is due; the burst bakes it on a worker thread and
## lands it `tile_frames` later. Each frame between, a path from a point of that tile to a point
## of its neighbour is found on the steering map, the map stays ready and the tile keeps the
## mesh it had; after the landing the route is found on the new mesh.
func _route_through_a_tile_in_flight(
	t: TestContext,
	region: NavigationRegion3D,
	house: Node2D,
	rooms: Array,
	piece: Node2D,
) -> void:
	var steering := NavBuilder.steering_map(region.get_navigation_map())
	var site := NavBuilder.site_of(region, house, rooms)
	var probes := {}
	for tile in NavBuilder.steering_regions(region):
		probes[tile] = NavTiles.probe_of(tile, Vector2.INF)
	piece.position += Vector2(40, 0)
	await t.frames(2)  # its twin follows
	var due := NavTiles.due_tiles(
		region, site, NavBuilder.furniture_holes(house), NavBuilder.character_holes(root_of(house)),
	)
	if not t.require(not due.is_empty(), "premise: moving the piece made a tile due"):
		return
	var from_tile := due[0]["tile"] as NavigationRegion3D
	var to_tile := _neighbour(NavBuilder.steering_regions(region), from_tile, probes)
	if not t.require(to_tile != null, "premise: the due tile has a neighbour with a mesh"):
		return
	var route := {
		"map": steering, "from": probes[from_tile], "to": probes[to_tile],
		"region": region, "site": site,
	}
	var meshes := {}
	for entry: Dictionary in due:
		meshes[entry["tile"]] = NavPlan.polygon_of((entry["tile"] as NavigationRegion3D))
	var burst := NavTileBurst.new()
	burst.begin(due)
	await _in_flight(t, burst, meshes, route)
	t.check(not burst.pending(), "the burst landed")
	t.check(
		meshes.keys().any(func(tile: NavigationRegion3D) -> bool:
			return NavPlan.polygon_of(tile) != meshes[tile]),
		"the due tile took its new mesh when the burst landed",
	)
	await t.frames(2)
	t.check(NavBuilder.ready(steering), "the steering map is ready after the landing")
	t.check(_found(route), "the route is found on the landed mesh")


## Step `burst` a frame at a time until it lands: every frame it is still in flight the map is
## ready, no due tile has another mesh than it had (`meshes`) and `route` is found (`route` also
## names the `region` and `site` the burst bakes).
func _in_flight(
	t: TestContext,
	burst: NavTileBurst,
	meshes: Dictionary,
	route: Dictionary,
) -> void:
	var in_flight := 0
	var gaps: Array[String] = []
	for _i in 60:
		burst.step(route["region"], route["site"])
		await t.frames(1)
		if not burst.pending():
			break
		in_flight += 1
		if not NavBuilder.ready(route["map"]):
			gaps.append("unready")
		for tile: NavigationRegion3D in meshes:
			if NavPlan.polygon_of(tile) != meshes[tile]:
				gaps.append("%s changed before it landed" % tile.name)
		if not _found(route):
			gaps.append("no route")
	t.check(
		in_flight >= NavBakeConfig.tile_frames - 1,
		"premise: the bake was in flight over several frames (%d)" % in_flight,
	)
	t.check(gaps.is_empty(), "every in-flight frame kept its mesh and a route: %s" % str(gaps))


## Whether the steering map answers a path from `route`'s `from` to its `to`.
func _found(route: Dictionary) -> bool:
	var path := NavPlan.path(route["map"], route["from"], route["to"])
	return not path.is_empty() and path[path.size() - 1].distance_to(route["to"]) <= REACH


## `house`'s parent: the node the characters are read under.
func root_of(house: Node2D) -> Node:
	return house.get_parent()


## A tile beside `tile` (its rect shares an edge) that has a mesh point, null when none.
func _neighbour(
	tiles: Array[NavigationRegion3D],
	tile: NavigationRegion3D,
	probes: Dictionary,
) -> NavigationRegion3D:
	var rect: Rect2 = tile.get_meta(NavTiles.RECT_META)
	for other in tiles:
		if other == tile or probes[other] == Vector2.INF:
			continue
		var other_rect: Rect2 = other.get_meta(NavTiles.RECT_META)
		if rect.grow(1.0).intersects(other_rect) and not rect.intersects(other_rect.grow(-1.0)):
			return other
	return null
