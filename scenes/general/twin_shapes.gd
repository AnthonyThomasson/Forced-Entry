class_name TwinShapes
extends RefCounted
## General domain, the lifting of a 2D collision shape into the 3D twin space (#194, D3/D4,
## `docs/adr/0014-twin-staging-and-plan-space.md`): the same footprint, from a base height to a top,
## on the one scale and mapping of `PlanSpace`. A domain building the twin of one of its bodies
## (`TwinSpace.builders`) lifts one footprint shape with `lift`, or a rectangle with `box`, from
## the outline data it holds (no body has a 2D shape), so no domain writes the `(x, y)` ->
## `(x, 0, y)` mapping by hand. Rectangles become boxes, circles upright cylinders, convex polygons
## extruded hulls; a shape of another kind is lifted as the box of its bounds (a capsule); a shape
## with none (a segment, a world boundary) is left out, with a warning.
## Heights are px above the floor (`BodyHeights`, `PieceHeights`).

## The sides a round shape's footprint is cut into (as the 2D circle was).
const ROUND_SIDES := 16

## The cosines and sines of the `ROUND_SIDES` angles of a ring, made on first use.
static var _ring_cos := PackedFloat64Array()
static var _ring_sin := PackedFloat64Array()


## The floor-plan polygon (px, plan space, convex, no repeated point) that `shape`, placed at `at`
## in the twin space, casts on the floor: the hull of its extreme points moved to plan. A box is its
## rectangle, an upright cylinder a `ROUND_SIDES`-sided disc, a convex hull its points' hull, and a
## tilted one the hull of what it reaches. Empty for a shape with no extent (a plane, a concave
## mesh). What the navigation bake and the player's view read of a twin.
static func footprint_of(shape: Shape3D, at: Transform3D) -> PackedVector2Array:
	# the whole set moved in one step (the same product a point at a time), then to plan
	var moved := at * _extremes(shape)
	var unit := RenderConfig.unit
	var points := PackedVector2Array()
	points.resize(moved.size())
	for i in moved.size():
		var point := moved[i]
		points[i] = Vector2(point.x, point.z) / unit
	if points.size() < 3:
		return PackedVector2Array()
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)  # the engine closes the ring
	return hull if hull.size() >= 3 else PackedVector2Array()


## The points of `shape` (its own frame, 3D units) whose hull is the shape's extent.
static func _extremes(shape: Shape3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if shape is BoxShape3D:
		var half := (shape as BoxShape3D).size * 0.5
		out = PackedVector3Array(
			[
				Vector3(-half.x, -half.y, -half.z), Vector3(-half.x, -half.y, half.z),
				Vector3(-half.x, half.y, -half.z), Vector3(-half.x, half.y, half.z),
				Vector3(half.x, -half.y, -half.z), Vector3(half.x, -half.y, half.z),
				Vector3(half.x, half.y, -half.z), Vector3(half.x, half.y, half.z),
			]
		)
	elif shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		_ring(out, cylinder.radius, cylinder.height * 0.5)
		_ring(out, cylinder.radius, -cylinder.height * 0.5)
	elif shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var straight := capsule.height * 0.5 - capsule.radius
		_ring(out, capsule.radius, straight)
		_ring(out, capsule.radius, -straight)
		out.append(Vector3(0.0, capsule.height * 0.5, 0.0))
		out.append(Vector3(0.0, -capsule.height * 0.5, 0.0))
	elif shape is SphereShape3D:
		_ring(out, (shape as SphereShape3D).radius, 0.0)
	elif shape is ConvexPolygonShape3D:
		out = (shape as ConvexPolygonShape3D).points
	return out


## Add to `out` the `ROUND_SIDES` points of the circle of `radius` round the up axis, `y` up.
static func _ring(out: PackedVector3Array, radius: float, y: float) -> void:
	if _ring_cos.is_empty():
		for i in ROUND_SIDES:
			var angle := float(i) / ROUND_SIDES * TAU
			_ring_cos.append(cos(angle))
			_ring_sin.append(sin(angle))
	for i in ROUND_SIDES:
		out.append(Vector3(_ring_cos[i] * radius, y, _ring_sin[i] * radius))


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


## The convex `outline` (px, in the body's frame), placed by `local` there, lifted from `base` to
## `top` px: a box for an upright rectangle (four corners on its bounds), else the extruded hull.
## Null for an outline of fewer than three points.
static func lift_outline(
	outline: PackedVector2Array,
	local: Transform2D,
	base: float,
	top: float,
) -> CollisionShape3D:
	var rect := rect_of(outline)
	if rect.has_area():
		return box(rect, local, base, top)
	return _hull(outline, local, base, top)


## The rectangle `outline` is when it is four corners on its own bounds (upright, axis aligned);
## an empty `Rect2` for any other outline.
static func rect_of(outline: PackedVector2Array) -> Rect2:
	if outline.size() != 4:
		return Rect2()
	var bounds := Rect2(outline[0], Vector2.ZERO)
	for point in outline:
		bounds = bounds.expand(point)
	for point in outline:
		var on_x := is_equal_approx(
			point.x,
			bounds.position.x,
		) or is_equal_approx(point.x, bounds.end.x)
		var on_y := is_equal_approx(
			point.y,
			bounds.position.y,
		) or is_equal_approx(point.y, bounds.end.y)
		if not (on_x and on_y):
			return Rect2()
	return bounds


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
