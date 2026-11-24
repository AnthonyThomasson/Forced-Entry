extends GameTest
## A district's planning, ring and avoid maps answer the same routes with the server's
## edge-connection pass off as on, so they are built without it (it rebuilds the whole map's links
## on every change: a bake landing synchronised a district's mesh in 4.4 ms with it, 1.1 ms
## without; `steering-edge-connections.md`). Each of these maps holds one region baked in one go
## (the planning and the ring's; an avoid map's is the planning source and some holes), so every
## edge two polygons share is one edge to the server already: the pass has no other region to join.
## Asked the middle of every few polygons, every ordered pair, with the pass off and then on, the
## paths are the same points, on this seed and (`planning_routes_match_edge_connections_other_*`)
## on others.

const Seams := preload("res://tests/_navigation/seam_probe.gd")
const SEED := 2
## How far (px) a point of a path may lie from the same point of the other.
const SAME := 0.01
## How many points a map is asked between (every ordered pair is a route).
const POINTS := 40
## The hole an avoid map is baked with: a body's footprint at the middle of a polygon.
const HOLE_RADIUS := 30.0


func describe() -> Dictionary:
	return {
		"name": "A district's planning, ring and avoid maps route the same with their edge "
			+ "connections off as on",
		"description": "Every route between the middles of the planning region's polygons is "
			+ "the same path with the server's edge-connection pass turned on, on the planning "
			+ "map, the ring's and an avoid map.",
		"tags": ["navigation", "district", "planning"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.district(_seed())


## The district's seed.
func _seed() -> int:
	return SEED


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var region := t.world.find_children("NavRegion", "NavigationRegion3D", true, false)[0]
	var planning := region as NavigationRegion3D
	var map := NavWorld.map_of(planning)
	var ring := NavRing.region_of(planning)
	if not t.require(map.is_valid() and NavBuilder.ready(map), "premise: a planning map"):
		return
	t.check(
		not NavigationServer3D.map_get_use_edge_connections(map),
		"the planning map is built without its edge-connection pass",
	)
	_expect_same(t, map, [planning], "the planning map")
	if ring != null:
		var ring_map := NavRing.map_of(map)
		t.check(
			not NavigationServer3D.map_get_use_edge_connections(ring_map),
			"the planning ring is built without its edge-connection pass",
		)
		_expect_same(t, ring_map, [ring], "the planning ring")
	var middle := Seams.points(
		[planning],
		maxi(1, int(NavPlan.polygon_of(planning).get_polygon_count() / 3.0)),
	)
	var hole := PackedVector2Array()
	for i in 8:
		hole.append(middle[1] + Vector2.from_angle(TAU * i / 8.0) * HOLE_RADIUS)
	var avoid := NavBuilder.avoid_map(planning, "edge_connections_probe", [hole])
	var waited := 0
	while not NavBuilder.ready(avoid) and waited < 300:
		await t.frames(1)
		waited += 1
	t.check(
		not NavigationServer3D.map_get_use_edge_connections(avoid),
		"an avoid map is built without its edge-connection pass",
	)
	if t.require(NavBuilder.ready(avoid), "premise: the avoid map answers"):
		_expect_same(t, avoid, [planning], "an avoid map")


## `map` answers the same routes between the middles of `regions`' polygons with the pass off as on.
func _expect_same(t: TestContext, map: RID, regions: Array, what: String) -> void:
	var stride := maxi(1, int(NavPlan.polygon_of(regions[0]).get_polygon_count() / float(POINTS)))
	var points := Seams.points(regions, stride)
	_set_edge_connections(map, false)
	var off := Seams.all_pairs(map, points)
	_set_edge_connections(map, true)
	var on := Seams.all_pairs(map, points)
	_set_edge_connections(map, false)
	var difference := Seams.compare(on, off)
	t.check(
		difference["pairs"] == 0 or difference["worst"] <= SAME,
		"%d routes on %s the same with the pass off as on; %d differ, the worst by %.2f px, %d "
			% [on.size(), what, difference["pairs"], difference["worst"], difference["longer"]]
		+ "longer, %d shorter, %d reached by one only"
			% [difference["shorter"], difference["reach"]],
	)


## `map` with its edge-connection pass `on` or off, synchronised now.
func _set_edge_connections(map: RID, on: bool) -> void:
	NavigationServer3D.map_set_use_edge_connections(map, on)
	NavigationServer3D.map_force_update(map)
