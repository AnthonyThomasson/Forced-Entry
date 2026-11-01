extends RefCounted
## TEST-ONLY REFERENCE (not the game's): the blocking shapes as `scenes/vision/view_shapes.gd` read
## them at the start of #168 slice 11 (commit f69b6f80), before any saving: everything is read anew
## each build. See `reference_view_cone.gd`.
##
## Vision domain: the blocking shapes round an eye, read from the physics space (a shape query on
## `PhysicsLayers.SOLID`, never a walk of the scene tree). A shape blocks sight when its piece's
## `coverage` is above the viewer's `see_over` (walls, tall furniture); lower furniture is seen
## over. Each shape a ray hits is turned into its world-space convex polygon, which gives the
## corners where the cone's boundary can jump and the point a ray through that one shape leaves it
## (a `Wall` is one body of many segment shapes: only the shape the ray hit counts). What it read is
## kept for one build (`reset`): the world moves between frames.

## The sides a circle shape is cut into.
const CIRCLE_SIDES := 16
## The shapes a query first asks for; a query that comes back full asks again for `GROWTH` times as
## many, until one comes back with room to spare, so no shape in reach is ever dropped.
const FIRST_RESULTS := 512
const GROWTH := 4

## The coverage a shape must be above to block sight, set by the cone for each build.
var see_over := 60.0
var _circle := CircleShape2D.new()
var _query := PhysicsShapeQueryParameters2D.new()
## Coverage by collider instance id.
var _coverage := {}
## The world polygon of a shape (empty for one that is no rectangle, circle or convex polygon) by
## `collider id * 4096 + shape index`.
var _polygons := {}


func _init() -> void:
	_query.collision_mask = PhysicsLayers.SOLID
	_query.shape = _circle


## Forget what the last build read.
func reset() -> void:
	_coverage.clear()
	_polygons.clear()


## The distinct corners, in world space, of every blocking shape within `reach` of `from`.
func corners(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	reach: float,
	exclude: Array,
) -> Array:
	_circle.radius = reach
	_query.transform = Transform2D(0.0, from)
	_query.exclude = exclude
	var seen := {}
	var found: Array = []
	for hit in _shapes_in_reach(space):
		if _coverage_of(hit["collider"]) <= see_over:
			continue
		for point in polygon_of(hit["collider"], hit["shape"]):
			var key := Vector2i((point * 2.0).round())
			if not seen.has(key):
				seen[key] = true
				found.append(point)
	return found


## Every solid shape the query circle touches. The physics query returns at most as many as it is
## asked for, so a result that comes back full is asked again with a larger cap.
func _shapes_in_reach(space: PhysicsDirectSpaceState2D) -> Array[Dictionary]:
	var cap := FIRST_RESULTS
	var hits := space.intersect_shape(_query, cap)
	while hits.size() >= cap:
		cap *= GROWTH
		hits = space.intersect_shape(_query, cap)
	return hits


## The world-space convex polygon of shape `index` of `collider` (empty when it is not a rectangle,
## circle or convex polygon).
func polygon_of(collider: Object, index: int) -> PackedVector2Array:
	var key: int = collider.get_instance_id() * 4096 + index
	if not _polygons.has(key):
		_polygons[key] = _make_polygon(collider, index)
	return _polygons[key]


## How far a ray from `origin` (on or in the shape) along `dir` runs before it leaves the convex
## `polygon`, or -1 when it does not.
func exit_distance(polygon: PackedVector2Array, origin: Vector2, dir: Vector2) -> float:
	var turn := signf(_signed_area(polygon))
	var exit := INF
	for i in polygon.size():
		var edge := polygon[(i + 1) % polygon.size()] - polygon[i]
		# The edge's outward normal; the ray leaves through the nearest edge it heads out of.
		var normal := Vector2(edge.y, -edge.x) * turn
		var along := normal.dot(dir)
		if along > 0.000001:
			exit = minf(exit, normal.dot(polygon[i] - origin) / along)
	return exit if exit < INF else -1.0


## Twice the signed area of `polygon`; its sign says which way it winds.
func _signed_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size():
		area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return area


## The coverage of a collider (`SightRay.coverage_of`), read once per build.
func _coverage_of(collider: Object) -> float:
	var id := collider.get_instance_id()
	if not _coverage.has(id):
		_coverage[id] = SightRay.coverage_of(collider)
	return _coverage[id]


## The world polygon of shape `index` of `collider`.
func _make_polygon(collider: Object, index: int) -> PackedVector2Array:
	if not collider is CollisionObject2D:
		return PackedVector2Array()
	var body := collider as CollisionObject2D
	var owner_id := body.shape_find_owner(index)
	if owner_id < 0:
		return PackedVector2Array()
	var shape: Shape2D = null
	for k in body.shape_owner_get_shape_count(owner_id):
		if body.shape_owner_get_shape_index(owner_id, k) == index:
			shape = body.shape_owner_get_shape(owner_id, k)
	var to_world := body.global_transform * body.shape_owner_get_transform(owner_id)
	return to_world * _local_points(shape)


## The shape's corners in its own frame.
func _local_points(shape: Shape2D) -> PackedVector2Array:
	if shape is RectangleShape2D:
		var half := (shape as RectangleShape2D).size * 0.5
		return PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y),
		])
	if shape is ConvexPolygonShape2D:
		return (shape as ConvexPolygonShape2D).points
	if shape is CircleShape2D:
		var points := PackedVector2Array()
		for i in CIRCLE_SIDES:
			var radius := (shape as CircleShape2D).radius
			points.append(Vector2.from_angle(float(i) / CIRCLE_SIDES * TAU) * radius)
		return points
	return PackedVector2Array()
