extends GameTest
## D16 (#194 nav3d-a): every doorway of the house and district floorplans admits a route on the
## 4 px mesh, as it did on the 2D baker's (checked at 4671b7a9 with this probe: every doorway of the
## district and of houses 1 to 6 routed, an empty one and one with its door open). A route runs from
## `PROBE` px before the doorway's middle to `PROBE` px past it along the wall's normal, on the
## walls alone (an empty doorway) and then with every house door open and its leaf carved
## (`NavLeaves.hole`). It is found, goes through the doorway (within `THROUGH` px of its middle:
## the open leaf may crowd one jamb) and keeps the agent's radius off every wall (a corner cut
## would pass nearer: the radius at the least, as in `bake_matches_recorded_colliders`).

const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const Clearance := preload("res://tests/_navigation/route_clearance.gd")
const WallScript := preload("res://scenes/objects/wall/wall.gd")
const SEED := 7
const HOUSE_SEEDS := [1, 2, 3, 4, 5, 6]
const RADIUS := NavBuilder.AGENT_RADIUS
## How far (px) either side of a doorway's middle a route starts and ends: past the agent's radius
## and the wall's depth.
const PROBE := 40.0
## How far (px) from the doorway's middle the route may pass: half a doorway less the radius, the
## leaf crowding one side.
const THROUGH := 26.0
## A route longer than this times the straight line (and `SLACK`) has gone the long way round.
const DETOUR := 1.35
const SLACK := 12.0
## The walls of a district's shells, whose doorways open on nothing the mesh holds.
const SCENERY_WALLS := "Partition"
## What `_through` says of a doorway it could not probe.
const UNSEEN := "unseen"
## How many doorways a world's probe must have asked for the premise to hold.
const MOST_UNSEEN := 0.25


func describe() -> Dictionary:
	return {
		"name": "Every doorway admits a route on the 4 px mesh",
		"description": "Over the district's floorplan and six houses: a route runs through each "
			+ "doorway, empty and with its door open, through the doorway and off the walls by "
			+ "the agent's radius.",
		"tags": ["navigation", "bake", "doorway", "district"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"worldgen.items", false)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var district := t.world.get("district") as Node2D
	if not t.require(district != null, "the world holds the district"):
		return
	var site := NavSite.new(
		district, WorldGen.district_rooms(district), RADIUS, WorldGen.district_bounds(district),
	)
	_probe(t, district, site, [], "the district, empty doorways")
	for house_seed in HOUSE_SEEDS:
		var holder := Node2D.new()
		t.world.add_child(holder)
		var house := WorldGen.generate(house_seed, "", Vector2.ZERO, holder)
		await t.frames(2)
		var house_site := NavSite.new(house, WorldGen.get_rooms(house), RADIUS)
		_probe(t, house, house_site, [], "house %d, empty doorways" % house_seed)
	var doors := NavLeaves.doors_of(district)
	for door in doors:
		door.open_fully(null)
	await t.seconds(1.5)
	var leaves: Array = []
	for door in doors:
		var leaf := NavLeaves.hole(door)
		if not leaf.is_empty():
			leaves.append(leaf)
	t.check(
		leaves.size() > 0,
		"premise: some doors stand open with a leaf carved (%d)" % leaves.size(),
	)
	_probe(t, district, site, leaves, "the district, doors open (%d leaves)" % leaves.size())


## Route through every doorway of `root` on a map baked from its walls and `holes`.
func _probe(t: TestContext, root: Node2D, site: NavSite, holes: Array, label: String) -> void:
	var walls := NavSource.walls_of(root)
	var poly := NavSource.bake(NavSource.job(site, holes, [], walls), root.position)
	var map := NavSource.new_map()
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_transform(
		region,
		Transform3D(Basis(), NavPlan.lift(root.position)),
	)
	NavigationServer3D.region_set_navigation_mesh(region, NavPlan.mesh_of(poly))
	NavigationServer3D.map_force_update(map)
	var asked := 0
	var failed: Array[String] = []
	var unseen := 0
	for wall in NavTwins.walls_under(root):
		if String(wall.name).begins_with(SCENERY_WALLS):
			continue
		for gap: Dictionary in wall.openings:
			if wall.opening_is_shared(gap):
				continue
			asked += 1
			var problem := _through(map, wall, gap, walls["obstruction"], root.position)
			if problem == UNSEEN:
				unseen += 1
			elif problem != "":
				failed.append("%s at %s: %s" % [wall.name, _middle(wall, gap).round(), problem])
	NavigationServer3D.free_rid(region)
	NavigationServer3D.free_rid(map)
	t.require(asked > 0, "premise: %s has doorways (%d)" % [label, asked])
	t.check(
		unseen <= asked * MOST_UNSEEN,
		"%s: most doorways could be probed (%d of %d)" % [label, asked - unseen, asked],
	)
	t.expect_eq(failed.size(), 0, "%s: every doorway admits a route: %s" % [label, failed])


## What is wrong with the route through the doorway `gap` of `wall` on `map`: "" for nothing,
## `UNSEEN` when an end of the route has no floor near it (a room's corner), else what it is.
func _through(map: RID, wall: Node2D, gap: Dictionary, walls: Array, frame: Vector2) -> String:
	var across := _across(wall, gap)
	var middle := _middle(wall, gap)
	var from := NavPlan.closest(map, middle - across * PROBE)
	var to := NavPlan.closest(map, middle + across * PROBE)
	if from.distance_to(middle - across * PROBE) > 8.0 \
			or to.distance_to(middle + across * PROBE) > 8.0:
		return UNSEEN
	return _problem(NavPlan.path(map, from, to), middle, walls, frame)


## What is wrong with the route `path` through `middle`, "" for nothing: `walls` are the outlines
## it keeps off (in the frame at `frame`).
func _problem(
	path: PackedVector2Array,
	middle: Vector2,
	walls: Array,
	frame: Vector2,
) -> String:
	if path.size() < 2:
		return "no route"
	var length := 0.0
	var nearest := INF
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
		var near := Geometry2D.get_closest_point_to_segment(middle, path[i - 1], path[i])
		nearest = minf(nearest, near.distance_to(middle))
	var straight := path[0].distance_to(path[path.size() - 1])
	if length > straight * DETOUR + SLACK:
		return "detour %.0f px for %.0f" % [length, straight]
	if nearest > THROUGH:
		return "misses the doorway by %.0f px" % nearest
	var least := Clearance.least_off_walls(path, walls, frame)
	if least < RADIUS:
		return "cuts a corner: %.1f px off a wall (radius %.0f)" % [least, RADIUS]
	return ""


## Whether the doorway `gap` lies on a wall running along x (the gap is on its top or bottom).
func _along_x(gap: Dictionary) -> bool:
	return int(gap["side"]) in [WallScript.Side.TOP, WallScript.Side.BOTTOM]


## The unit vector across the wall at its doorway `gap`, in the world.
func _across(wall: Node2D, gap: Dictionary) -> Vector2:
	var local := Vector2.DOWN if _along_x(gap) else Vector2.RIGHT
	return wall.global_transform.basis_xform(local).normalized()


## The world point of the middle of the doorway `gap` of `wall`, across the wall's depth.
func _middle(wall: Node2D, gap: Dictionary) -> Vector2:
	var offset: float = gap["offset"]
	var size: Vector2 = wall.size
	var local := Vector2(offset, size.y * 0.5) if _along_x(gap) else Vector2(size.x * 0.5, offset)
	return wall.to_global(local)
