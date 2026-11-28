extends GameTest
## Interface 9, #194: a `NavigationAgent3D` on a `Node3D` anchor at a plan point (x, 0, y)
## (what Locomotion's `NavAnchor` is), its target another plan point, walks the route
## `NavPlan.path` answers on the same map: its path is that route, the waypoints
## `get_next_path_position` hands out are that route's in turn as the anchor stands on each, and
## `is_target_reachable` / `is_navigation_finished` agree with the route's end.

## How near the walk's last waypoint must be to the asked point to count as reaching it (px).
const REACHED := 1.0


func describe() -> Dictionary:
	return {
		"name": "A NavigationAgent3D on an anchor follows NavPlan.path's waypoints",
		"description": "An agent from one room to another hands out the waypoints NavPlan.path "
			+ "gives and finishes at the route's end; a target off the mesh is not reachable.",
		"tags": ["navigation", "character"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.house(1)


func run(t: TestContext) -> void:
	var map := NavWorld.map_of(t.world)
	if not t.require(
			await t.until(func(): return NavBuilder.ready(map), 3.0), "the house's map is ready",
	):
		return
	var rooms := t.rooms
	var from := NavBuilder.snap(map, (rooms[0]["rect"] as Rect2).get_center())
	var to := NavBuilder.snap(map, (rooms[rooms.size() - 1]["rect"] as Rect2).get_center())
	var expected := NavPlan.path(map, from, to)
	if not t.require(expected.size() > 2, "premise: the route between two rooms bends"):
		return
	var anchor := Node3D.new()
	anchor.position = NavPlan.lift(from)
	var agent := NavigationAgent3D.new()
	agent.path_desired_distance = 1.0
	agent.target_desired_distance = REACHED
	agent.path_max_distance = 100.0
	anchor.add_child(agent)
	t.world.add_child(anchor)
	agent.set_navigation_map(map)
	_walk(t, agent, to, expected)
	t.check(
		_on_the_polygon(NavBuilder.planning_region(map), expected),
		"the route's waypoints lie on the plan polygon the mesh was made from",
	)
	# A target off the mesh: the route ends short of it, and the agent says it cannot reach it.
	var off := (rooms[0]["rect"] as Rect2).position - Vector2(500, 500)
	anchor.position = NavPlan.lift(from)
	agent.target_position = NavPlan.lift(off)
	agent.get_next_path_position()
	var short := NavPlan.path(map, from, off)
	t.check(
		short[short.size() - 1].distance_to(off) > REACHED,
		"premise: the route to a point off the mesh ends short of it",
	)
	t.check(not agent.is_target_reachable(), "a target off the mesh is not reachable")
	t.check(
		NavPlan.plan_path(agent.get_current_navigation_path()) == short,
		"and the agent's path is still NavPlan.path's",
	)


## `agent` (on its anchor at the route's start) walks to `to`, the anchor stepped onto each waypoint
## it hands out: checked against `expected`, `NavPlan.path`'s route.
func _walk(
	t: TestContext, agent: NavigationAgent3D, to: Vector2, expected: PackedVector2Array,
) -> void:
	var anchor := agent.get_parent() as Node3D
	agent.target_position = NavPlan.lift(to)
	var next := NavPlan.plan_of(agent.get_next_path_position())
	t.check(
		NavPlan.plan_path(agent.get_current_navigation_path()) == expected,
		"the agent's path is NavPlan.path's (%d points)" % expected.size(),
	)
	t.check(agent.is_target_reachable(), "the target is reachable")
	t.check(not agent.is_navigation_finished(), "the walk is not finished at the start")
	var heading: Array[Vector2] = []
	while not agent.is_navigation_finished() and heading.size() <= expected.size():
		heading.append(next)
		anchor.position = NavPlan.lift(next)  # stands on the waypoint
		next = NavPlan.plan_of(agent.get_next_path_position())
	t.expect_eq(
		heading, Array(Array(expected).slice(1)), "the waypoints handed out are the route's",
	)
	t.check(agent.is_navigation_finished(), "the walk finishes on the route's end")
	t.check(
		NavPlan.plan_of(anchor.position).distance_to(to) <= REACHED
		and expected[expected.size() - 1].distance_to(to) <= REACHED,
		"which is the asked point",
	)


## Whether every point of `path` (world plan points) lies on a polygon of `region`'s plan polygon
## (its own geometry: what the mesh was made from, whatever `NavPlan.mesh_of` made of it).
func _on_the_polygon(region: NavigationRegion3D, path: PackedVector2Array) -> bool:
	var poly := NavPlan.polygon_of(region)
	for p in path:
		var local := NavPlan.local_of(region, p)
		var found := false
		for i in poly.get_polygon_count():
			var ring := PackedVector2Array()
			for index in poly.get_polygon(i):
				ring.append(poly.vertices[index])
			found = found or Geometry2D.is_point_in_polygon(local, ring) or _near(local, ring)
		if not found:
			return false
	return true


## Whether `p` is on the boundary of `ring` (within a hundredth of a px).
func _near(p: Vector2, ring: PackedVector2Array) -> bool:
	for i in ring.size():
		var on := Geometry2D.get_closest_point_to_segment(p, ring[i], ring[(i + 1) % ring.size()])
		if on.distance_to(p) <= 0.01:
			return true
	return false
