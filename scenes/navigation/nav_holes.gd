class_name NavHoles extends RefCounted
## Navigation domain: the footprints a bake carves as holes, measured from the twins (`NavTwins`;
## no 2D collider is read). A body's footprint is the convex hull of the plan polygons
## its twin's shapes stand on, grown by the obstacle margin (`cut`); `NavBuilder.furniture_holes`
## and `character_holes` hand them out. `walks` and `cuts` count the work done, for the tests.

## Hulls kept per body (`hull_of`) before the freed bodies' are dropped.
const HULLS_KEPT := 512
## Segment count approximating a circular footprint as an obstruction polygon.
const CIRCLE_SEGMENTS := 10

## Tree walks made to find the furniture, and footprints cut from a body's shapes, since the start.
static var walks := 0
static var cuts := 0
## Body instance id -> [inputs, hull] as `hull_of` last made it.
static var _hulls := {}


## The footprints of every solid piece under `house`, in the order a walk of its descendants finds
## them, then the doors' leaves standing clear of their doorways (`NavLeaves.hole`).
static func furniture(house: Node2D) -> Array:
	if not house.is_inside_tree():
		return plain(house)
	return NavPieces.of(house).holes()


## `furniture` with nothing kept: every piece's footprint cut afresh, the reference the cached one
## equals.
static func plain(house: Node2D) -> Array:
	var out: Array = []
	for node in house.find_children("*", "RigidBody2D", true, false):
		var hull := cut(node as RigidBody2D)
		if not hull.is_empty():
			out.append(hull)
	NavLeaves.append_holes(out, house)
	return out


## The world-space footprint of `body`, kept with what it was made from (its twin and the twin's
## pose, `NavTwins.stamp_of`) and cut again only when that changes: a character at rest is measured
## every tick.
static func hull_of(body: Node2D) -> PackedVector2Array:
	var inputs: Variant = NavTwins.stamp_of(body)
	var kept: Array = _hulls.get(body.get_instance_id(), [])
	if not kept.is_empty() and kept[0] == inputs:
		return (kept[1] as PackedVector2Array).duplicate()
	var hull := cut(body)
	if _hulls.size() >= HULLS_KEPT:
		for id in _hulls.keys():
			if not is_instance_id_valid(id):
				_hulls.erase(id)
	_hulls[body.get_instance_id()] = [inputs, hull.duplicate()]
	return hull


## The world-space footprint of `body` cut afresh: the convex hull of the plan footprints of its
## twin's shapes (`NavTwins.parts`), each grown by `NavBuilder.OBSTACLE_MARGIN`, as an
## open ring; empty when `body` has no twin or fewer than three points come out of it. An upright
## cylinder (a round piece, a character) is a `CIRCLE_SEGMENTS`-sided polygon, the bake's own
## approximation of a circle.
static func cut(body: Node2D) -> PackedVector2Array:
	cuts += 1
	var points := PackedVector2Array()
	for part: Array in NavTwins.parts(body):
		points.append_array(_footprint(part[0], part[1]))
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1:
		hull.remove_at(hull.size() - 1)  # convex_hull closes the ring by repeating the first point
	return hull if hull.size() >= 3 else PackedVector2Array()


## The footprint of `shape` at `pose`, grown by the margin: `CIRCLE_SEGMENTS` points round an
## upright cylinder (vertex 0 on the shape's own x axis), else the shape's plan polygon offset
## (corners mitred, a rectangle stays a rectangle).
static func _footprint(shape: Shape3D, pose: Transform3D) -> PackedVector2Array:
	var margin := NavBuilder.OBSTACLE_MARGIN
	if shape is CylinderShape3D and pose.basis.y.is_equal_approx(Vector3.UP):
		var plan := PlanSpace.plan_transform(pose)
		var radius := (shape as CylinderShape3D).radius / RenderConfig.unit + margin
		var ring := PackedVector2Array()
		for i in CIRCLE_SEGMENTS:
			var angle := TAU * float(i) / float(CIRCLE_SEGMENTS)
			ring.append(plan * (Vector2(cos(angle), sin(angle)) * radius))
		return ring
	var outline := NavTwins.footprint(shape, pose)
	if outline.is_empty():
		return outline
	var best := PackedVector2Array()
	for poly: PackedVector2Array in Geometry2D.offset_polygon(
		outline, margin, Geometry2D.JOIN_MITER,
	):
		if poly.size() > best.size():
			best = poly
	return best if best.size() >= 3 else outline
