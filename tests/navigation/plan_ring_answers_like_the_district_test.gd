extends GameTest
## The AI plans on a small map in a district (#182): the match building and its outdoor ring, on a
## map of their own beside the whole district's. The server scans every polygon of a map for a
## query's two ends, so what the AI asks of the 1000-polygon district map costs ten times what a
## lone house's does; a point and a route inside the ring are answered by the small one.
##
## The ring's answers are the district map's: the same reachability, a path as long to a few px.
## What lies outside the ring (a point out in the street, a route that leaves it) is answered by
## the district map, as before, and a query never goes unanswered. The expected answers are the
## engine's own on the world's navigation map.

const SEED := 7
## How near (px) the length of a ring path is to the district map's, and a path's end to its goal.
const LENGTH_SLACK := 6.0
const REACHED := 3.0
## The ring has less than this share of the district map's polygons (the match building and a
## ring round it, of a 3x3 district and its streets).
const SMALLER_THAN := 0.5
## How far (px) out of the ring's rect, along its width, the street point stands.
const OUTSIDE := 400.0
## The outdoor ring the AI plans on round the match building (px): a street point this far out of
## the building is answered by the ring, one this far (and the margin past it) is not.
const PAD_IN := 250.0
const PAD_OUT := 450.0
## How near (px) a street point must snap to the point asked for to be a premise.
const ON_FLOOR := 20.0


func describe() -> Dictionary:
	return {
		"name": "A district's planning ring answers as the district map does",
		"description": "Room centres of the match building are snapped and routed between; the "
			+ "answers match the district map's, from a smaller map. A point outside the ring "
			+ "is answered by the district map.",
		"tags": ["navigation", "district", "path"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.seconds(0.5)  # the first bake is applied a frame or two after the build
	var region: NavigationRegion2D = t.world.find_children(
		"NavRegion", "NavigationRegion2D", true, false,
	)[0]
	var map := region.get_navigation_map()
	var ring := NavRing.map_of(map)
	if not t.require(ring.is_valid() and ring != map, "premise: the district has a ring map"):
		return
	if not t.require(NavBuilder.ready(map), "premise: the maps answer"):
		return
	_check_smaller(t, region)
	var centres := _centres(t, map)
	if not t.require(
		centres.size() >= 3,
		"premise: the match building has rooms to route between (%d)" % centres.size(),
	):
		return
	for p in centres:
		t.check(
			NavRing.map_for(map, [p]) == ring,
			"a room's centre %s is weighed on the ring map" % str(p.round()),
		)
		t.check(
			NavBuilder.snap(map, p).distance_to(NavigationServer2D.map_get_closest_point(map, p))
				<= REACHED,
			"%s snaps where the district map snaps it" % str(p.round()),
		)
	for i in centres.size():
		for j in range(i + 1, centres.size()):
			_check_route(t, map, centres[i], centres[j])
	_check_outside(t, map, ring, centres[0])
	_check_pad(t, map, ring)
	_check_keeps(t, ring, centres)


## The ring's region has far fewer polygons than the planning region's.
func _check_smaller(t: TestContext, region: NavigationRegion2D) -> void:
	var small := NavRing.region_of(region)
	if not t.require(small != null, "premise: the ring has a region"):
		return
	var ring_polygons := small.navigation_polygon.get_polygon_count()
	var district_polygons := region.navigation_polygon.get_polygon_count()
	t.check(
		ring_polygons > 0 and ring_polygons < district_polygons * SMALLER_THAN,
		"the ring map is the smaller (%d polygons, the district's %d)"
			% [ring_polygons, district_polygons],
	)


## The centres of the match building's rooms, each moved onto the district map (a centre is often
## inside furniture).
func _centres(t: TestContext, map: RID) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for room: Dictionary in WorldGen.get_rooms(t.world.house):
		var centre := (room["rect"] as Rect2).get_center()
		out.append(NavigationServer2D.map_get_closest_point(map, centre))
	return out


## `NavBuilder.route` between two points of the ring ends where the district map's path does and
## is as long as it, to a few px.
func _check_route(t: TestContext, map: RID, from: Vector2, to: Vector2) -> void:
	var expected := NavigationServer2D.map_get_path(map, from, to, true)
	var got := NavBuilder.route(map, from, to)
	var label := "%s -> %s" % [str(from.round()), str(to.round())]
	t.check(
		(got[-1].distance_to(to) <= REACHED) == (expected[-1].distance_to(to) <= REACHED),
		"%s: reachable exactly when the district map says so" % label,
	)
	t.check(
		absf(NavBuilder.path_length(got) - NavBuilder.path_length(expected)) <= LENGTH_SLACK,
		"%s: as long a path as the district map's (%.1f px against %.1f)"
			% [label, NavBuilder.path_length(got), NavBuilder.path_length(expected)],
	)


## A point out in the street is weighed on the district map, alone and with one in the ring, and is
## answered as before.
func _check_outside(t: TestContext, map: RID, ring: RID, inside: Vector2) -> void:
	var far := inside + Vector2(OUTSIDE * 2.0, 0.0)
	var street := NavigationServer2D.map_get_closest_point(map, far)
	t.check(
		NavRing.map_for(map, [street]) == map,
		"a point out in the street %s is weighed on the district map" % str(street.round()),
	)
	t.check(
		NavRing.map_for(map, [inside, street]) == map,
		"a route from the ring to the street is weighed on the district map",
	)
	t.check(
		NavRing.map_for(map, [inside]) == ring,
		"premise: the point in the ring is weighed on the ring",
	)
	t.check(
		NavBuilder.snap(map, street).distance_to(street) <= REACHED,
		"the street point snaps to itself (%s)" % str(street.round()),
	)
	var expected := NavigationServer2D.map_get_path(map, inside, street, true)
	var got := NavBuilder.route(map, inside, street)
	var slack := absf(NavBuilder.path_length(got) - NavBuilder.path_length(expected))
	t.check(
		got[-1].distance_to(street) <= REACHED and slack <= LENGTH_SLACK,
		"a route from the ring out to the street is the district map's",
	)


## The ring's path is kept when it ends at its goal, or at the floor the server took for a goal that
## is off the floor; it is not when it stops short of a goal that is on the floor (the way there
## leads out of the ring, and the district map is asked).
func _check_keeps(t: TestContext, ring: RID, centres: Array[Vector2]) -> void:
	var floor_point := centres[0]
	var short := PackedVector2Array([floor_point, floor_point + Vector2(10, 0)])
	var there := PackedVector2Array([floor_point + Vector2(10, 0), floor_point])
	t.check(NavRing.keeps(ring, there, floor_point), "a path that ends at its goal is kept")
	t.check(
		not NavRing.keeps(ring, short, centres[1]),
		"a path that stops short of a goal on the floor is not kept",
	)
	var wall := WorldGen.get_rooms(t.world.house)[0]["rect"].position as Vector2
	var inside_wall := wall + Vector2(1, 1)
	if NavigationServer2D.map_get_closest_point(
		ring,
		inside_wall,
	).distance_to(inside_wall) > REACHED:
		t.check(NavRing.keeps(ring, short, inside_wall), "a path to a goal off the floor is kept")
	t.check(not NavRing.keeps(ring, PackedVector2Array(), floor_point), "no path is not kept")


## The street round the match building: a point `PAD_IN` px out of its walls is weighed on the ring
## (the AI's hostiles and routes just outside it stay on the small map), one `PAD_OUT` px out on
## the district map.
func _check_pad(t: TestContext, map: RID, ring: RID) -> void:
	var building := Rect2()
	for room: Dictionary in WorldGen.get_rooms(t.world.house):
		building = (room["rect"] as Rect2) if building.size == Vector2.ZERO \
				else building.merge(room["rect"])
	var checked := 0
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var edge := building.get_center() + dir * (building.size * 0.5 * dir.abs()).length()
		var near := edge + dir * PAD_IN
		var far := edge + dir * PAD_OUT
		var near_floor := NavigationServer2D.map_get_closest_point(map, near)
		var far_floor := NavigationServer2D.map_get_closest_point(map, far)
		if near_floor.distance_to(near) > ON_FLOOR or far_floor.distance_to(far) > ON_FLOOR:
			continue
		checked += 1
		t.check(
			NavRing.map_for(map, [near_floor]) == ring,
			"a street point %d px %s of the building is weighed on the ring" % [PAD_IN, str(dir)],
		)
		t.check(
			NavRing.map_for(map, [far_floor]) == map,
			"a street point %d px %s of the building is weighed on the district map"
				% [PAD_OUT, str(dir)],
		)
	t.require(
		checked > 0,
		"premise: a side of the building has street floor out to %d px" % PAD_OUT,
	)
