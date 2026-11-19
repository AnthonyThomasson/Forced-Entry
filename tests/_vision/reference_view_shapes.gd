extends RefCounted
## TEST-ONLY REFERENCE (not the game's): the blocking shapes as `scenes/vision/view_shapes.gd` reads
## them, plainly: everything is read anew each build. See `reference_view_cone.gd`. Two of its rules
## exist because the physics query lists shapes in an order, and names one of several overlapping
## shapes for a ray, that are not stable from one frame to the next, so a yardstick that followed
## the query would differ from itself between two builds of the same world: `far_exit` (the far
## face is read off the shapes that hold a point, not off the one shape the ray named) and `corners`
## (of two corners in one half-pixel cell, the lesser stands for it, not the first listed).
##
## Vision domain: the blocking shapes round an eye, read from the twin space (a 3D shape query on
## the twin layers of what sight meets, over the column above the viewer's `see_over`, never a walk
## of the scene tree). A shape blocks sight when it stands above the viewer's `see_over`, its eye
## height (walls, tall furniture); lower furniture is seen over. Each shape a ray hits is turned
## into the convex polygon it casts on the floor, which gives the corners where the cone's boundary
## can jump and the point a ray through that one shape leaves it (a `Wall` is one body of many
## segment shapes: only the shape the ray hit counts). What it read is kept for one build
## (`reset`): the world moves between frames.

## The shapes a query first asks for; a query that comes back full asks again for `GROWTH` times as
## many, until one comes back with room to spare, so no shape in reach is ever dropped.
const FIRST_RESULTS := 512
const GROWTH := 4
## The thickness (px) of the slab, at the level the cone's rays run at, a query reads.
const SLAB := 2.0
const LEVEL_OVER := 0.05

## The height a shape must be above to block sight, set by the cone for each build.
var see_over := 69.4
var _column := CylinderShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
## The world polygon of a shape (empty for one with no extent) by
## `collider id * 4096 + shape index`.
var _polygons := {}


func _init() -> void:
	_query.collision_mask = SightRay.MASK
	_query.shape = _column


## Forget what the last build read.
func reset() -> void:
	_polygons.clear()


## Whether `a` comes before `b`: the lesser x, then the lesser y. Two corners less than half a pixel
## apart are one corner (`corners`); which of them stands for it is this one, whatever order the
## physics query listed the shapes in.
static func _before(a: Vector2, b: Vector2) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


## The distinct corners, in world space, of every blocking shape within `reach` of `from`.
func corners(
	space: PhysicsDirectSpaceState3D,
	from: Vector2,
	reach: float,
	exclude: Array,
) -> Array:
	_column.radius = reach
	_column.height = SLAB
	_query.transform = Transform3D(
		Basis.IDENTITY, PlanSpace.lift(from, see_over + LEVEL_OVER + SLAB * 0.5)
	)
	_query.exclude = exclude
	var seen := {}
	var found: Array = []
	for hit in _shapes_in_reach(space):
		if SightRay.looks_through(hit["collider"]):
			continue
		for point in polygon_of(hit["collider"], hit["shape"]):
			var key := Vector2i((point * 2.0).round())
			if not seen.has(key):
				seen[key] = found.size()
				found.append(point)
			elif _before(point, found[seen[key]]):
				found[seen[key]] = point
	return found


## Every blocking shape the query column touches. The physics query returns at most as many as it
## is asked for, so a result that comes back full is asked again with a larger cap.
func _shapes_in_reach(space: PhysicsDirectSpaceState3D) -> Array[Dictionary]:
	var cap := FIRST_RESULTS
	var hits := space.intersect_shape(_query, cap)
	while hits.size() >= cap:
		cap *= GROWTH
		hits = space.intersect_shape(_query, cap)
	return hits


## The floor polygon of shape `index` of the twin `collider` (empty for a shape with no extent).
func polygon_of(collider: Object, index: int) -> PackedVector2Array:
	var key: int = collider.get_instance_id() * 4096 + index
	if not _polygons.has(key):
		_polygons[key] = _make_polygon(collider, index)
	return _polygons[key]


## How far a ray from `origin` along `dir`, which has just hit a blocker there, runs before it
## leaves the solid it entered: the farthest it leaves any blocking shape that holds the point 0.1
## px along it, -1 when it leaves such a shape through no edge, and 0 when no blocking shape holds
## the point (the ray only touches a corner). The physics query may name any of several overlapping
## or touching shapes for one ray, from one frame to the next, and one it names need not even be
## entered, so the far face is read off every shape that holds the point.
func far_exit(space: PhysicsDirectSpaceState3D, origin: Vector2, dir: Vector2) -> float:
	var probe := PhysicsPointQueryParameters3D.new()
	probe.collision_mask = SightRay.MASK
	probe.exclude = _query.exclude
	probe.position = PlanSpace.lift(origin + dir * 0.1, see_over + 0.05)
	var exits: Array[float] = []
	for found in space.intersect_point(probe, 32):
		if not SightRay.looks_through(found["collider"]):
			exits.append(exit_distance(polygon_of(found["collider"], found["shape"]), origin, dir))
	return 0.0 if exits.is_empty() else exits.max()


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


## The floor polygon of shape `index` of the twin `collider`.
func _make_polygon(collider: Object, index: int) -> PackedVector2Array:
	if not collider is CollisionObject3D:
		return PackedVector2Array()
	var body := collider as CollisionObject3D
	var owner_id := body.shape_find_owner(index)
	if owner_id < 0:
		return PackedVector2Array()
	var shape: Shape3D = null
	for k in body.shape_owner_get_shape_count(owner_id):
		if body.shape_owner_get_shape_index(owner_id, k) == index:
			shape = body.shape_owner_get_shape(owner_id, k)
	if shape == null:
		return PackedVector2Array()
	return TwinShapes.footprint_of(
		shape,
		body.global_transform * body.shape_owner_get_transform(owner_id),
	)
