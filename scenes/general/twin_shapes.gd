class_name TwinShapes
extends RefCounted
## General domain, the lifting of a 2D collision shape into the 3D twin space (#194, D3/D4,
## `docs/adr/0014-twin-staging-and-plan-space.md`): the same footprint, from a base height to a top,
## on the one scale and mapping of `PlanSpace`. A domain building the twin of one of its bodies
## (`TwinSpace.builders`) lifts the body's own 2D shapes with `lift_body`, or one footprint
## rectangle with `box`, so no domain writes the `(x, y)` -> `(x, 0, y)` mapping by hand.
## Rectangles become boxes, circles upright cylinders, convex polygons extruded hulls; a shape of
## another kind is lifted as the box of its bounds (a capsule); a shape with none (a segment, a
## world boundary) is left out, with a warning.
## Heights are px above the floor (`BodyHeights`, `PieceHeights`).


## Add to `twin` a `CollisionShape3D` for each enabled `CollisionShape2D` child of `body`, lifted
## from `base` to `top`, in `body`'s own frame (the twin is placed by the body's transform). Returns
## how many were added.
static func lift_body(body: Node2D, twin: CollisionObject3D, base: float, top: float) -> int:
	var added := 0
	for child in body.get_children():
		if not child is CollisionShape2D:
			continue
		var holder := child as CollisionShape2D
		if holder.disabled or holder.shape == null:
			continue
		var lifted := lift(holder.shape, holder.transform, base, top)
		if lifted != null:
			twin.add_child(lifted)
			added += 1
	return added


## The height (px above the floor) of the highest point of `twin`'s shapes: its top, read once and
## kept on the twin (a twin's shapes are built once). 0 for a twin with none.
static func top_of(twin: Node3D) -> float:
	if twin.has_meta(&"top"):
		return twin.get_meta(&"top")
	var top := 0.0
	var shaped := false
	for child in twin.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			var holder := child as CollisionShape3D
			top = maxf(top, _top_of_shape(holder.shape, holder.position.y))
			shaped = true
	top /= RenderConfig.unit
	if shaped:
		twin.set_meta(&"top", top)  # a twin with no shapes yet is asked again
	return top


## The height (px above the floor) of the top of the shape of `twin` that a ray result's `shape`
## index names: the part the ray struck (a sofa's seat and its back differ), the twin's own top for
## a result that names none.
static func top_of_shape(twin: CollisionObject3D, shape_index: int) -> float:
	var owner_id := twin.shape_find_owner(shape_index)
	var holder: CollisionShape3D = null
	if owner_id >= 0:
		holder = twin.shape_owner_get_owner(owner_id) as CollisionShape3D
	if holder == null or holder.shape == null:
		return top_of(twin)
	return _top_of_shape(holder.shape, holder.position.y) / RenderConfig.unit


## The height of the highest point of `shape` whose centre stands `centre` up.
static func _top_of_shape(shape: Shape3D, centre: float) -> float:
	if shape is BoxShape3D:
		return centre + (shape as BoxShape3D).size.y * 0.5
	if shape is CylinderShape3D:
		return centre + (shape as CylinderShape3D).height * 0.5
	if shape is CapsuleShape3D:
		return centre + (shape as CapsuleShape3D).height * 0.5
	var top := centre
	if shape is ConvexPolygonShape3D:
		top = -INF
		for point in (shape as ConvexPolygonShape3D).points:
			top = maxf(top, centre + point.y)
	return top


## `shape`, placed by `local` in its body's frame, lifted from `base` to `top` px: a
## `CollisionShape3D` in the body's frame, or null for a shape with no footprint.
static func lift(shape: Shape2D, local: Transform2D, base: float, top: float) -> CollisionShape3D:
	if shape is ConvexPolygonShape2D:
		return _hull((shape as ConvexPolygonShape2D).points, local, base, top)
	if shape is CircleShape2D:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = (shape as CircleShape2D).radius * local.get_scale().x * RenderConfig.unit
		cylinder.height = (top - base) * RenderConfig.unit
		return _holder(cylinder, local, 0.5 * (base + top), Vector2.ZERO)
	var rect := _bounds(shape)
	if rect.size == Vector2.ZERO:
		if not (shape is RectangleShape2D or shape is CapsuleShape2D):
			push_warning("TwinShapes: no twin for a %s, it has no footprint" % shape.get_class())
		return null
	return box(rect, local, base, top)


## A box over `rect` (px, in the body's frame), from `base` to `top`, placed by `local` (the
## body's frame itself when omitted).
static func box(
	rect: Rect2,
	local: Transform2D = Transform2D.IDENTITY,
	base: float = 0.0,
	top: float = 0.0,
) -> CollisionShape3D:
	var made := BoxShape3D.new()
	var across := rect.size * local.get_scale().abs()
	made.size = Vector3(across.x, top - base, across.y) * RenderConfig.unit
	return _holder(made, local, 0.5 * (base + top), rect.get_center())


## The convex hull of `points` (px, in the body's frame, moved by `local`), from `base` to `top`.
static func _hull(
	points: PackedVector2Array,
	local: Transform2D,
	base: float,
	top: float,
) -> CollisionShape3D:
	if points.size() < 3:
		return null
	var cloud := PackedVector3Array()
	for point in points:
		var moved := local * point
		cloud.append(PlanSpace.lift(moved, base))
		cloud.append(PlanSpace.lift(moved, top))
	var made := ConvexPolygonShape3D.new()
	made.points = cloud
	var holder := CollisionShape3D.new()
	holder.shape = made
	return holder


## A holder of `shape` at `local`'s turn, its centre the point `across` of the shape's own frame
## (so it follows `local`'s offset and scale), `height` px up.
static func _holder(
	shape: Shape3D,
	local: Transform2D,
	height: float,
	across: Vector2,
) -> CollisionShape3D:
	var holder := CollisionShape3D.new()
	holder.shape = shape
	holder.transform = PlanSpace.lift_transform(
		Transform2D(local.get_rotation(), local * across), height
	)
	return holder


## The rectangle `shape` covers in its own frame; empty for a shape with no extent.
static func _bounds(shape: Shape2D) -> Rect2:
	if shape is RectangleShape2D:
		return Rect2(-(shape as RectangleShape2D).size * 0.5, (shape as RectangleShape2D).size)
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		return Rect2(
			Vector2(-capsule.radius, -capsule.height * 0.5),
			Vector2(capsule.radius * 2.0, capsule.height),
		)
	return Rect2()
