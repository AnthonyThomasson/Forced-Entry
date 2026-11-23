extends RefCounted
## Test helper (not a test): how near a route runs to the walls, for the tests that hold a route to
## the agent's radius off them (`navigation/bake_matches_recorded_colliders`,
## `navigation/doorways_admit_a_route`): a route that cuts a corner passes nearer than the radius.

## The spacing (px) a route is sampled at.
const SAMPLE := 4.0
## How far (px) beyond the radius the walls looked at reach.
const REACH_PAD := 12.0


## The least distance (px) from `path` (world space), sampled every `SAMPLE` px, to the edges of
## `walls` (outlines in the house's frame, which lies at `frame`); INF for no wall near it.
static func least_off_walls(path: PackedVector2Array, walls: Array, frame: Vector2) -> float:
	var edges := _edges_near(path, walls, frame)
	var least := INF
	for i in range(1, path.size()):
		var leg := path[i - 1].distance_to(path[i])
		for step in int(ceil(leg / SAMPLE)) + 1:
			var at := path[i - 1].lerp(path[i], minf(1.0, step * SAMPLE / maxf(leg, 0.001)))
			for edge in edges:
				var near := Geometry2D.get_closest_point_to_segment(at, edge[0], edge[1])
				least = minf(least, near.distance_to(at))
	return least


## The edges (world space) of the outlines of `walls` that reach within the agent's radius and
## `REACH_PAD` of `path`.
static func _edges_near(
	path: PackedVector2Array,
	walls: Array,
	frame: Vector2,
) -> Array[PackedVector2Array]:
	var edges: Array[PackedVector2Array] = []
	if path.size() < 2:
		return edges
	var box := Rect2(path[0] - frame, Vector2.ZERO)
	for p in path:
		box = box.expand(p - frame)
	box = box.grow(NavBuilder.AGENT_RADIUS + REACH_PAD)
	for outline: PackedVector2Array in walls:
		if not NavSource.outline_bounds(outline).intersects(box):
			continue
		for k in outline.size():
			var b := outline[(k + 1) % outline.size()]
			edges.append(PackedVector2Array([outline[k] + frame, b + frame]))
	return edges
