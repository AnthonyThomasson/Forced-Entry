extends RefCounted
## Vision domain: the exact polygon of what an eye sees (`docs/player-vision.md` V1). A point is
## seen when it is within the view distance, either inside the near bubble or inside the cone round
## the facing, and the line to it is clear by General's `SightRay`: walls and tall pieces break it,
## low ones are looked over.
##
## The polygon is a fan from the eye over ray ends sorted by angle. The rays are an even fan
## (`VisionConfig.cone_rays` across the cone, `bubble_rays` round the bubble) plus, exactly at
## corners, three rays for each corner of each blocking shape the eye can see (at the corner's own
## angle and `corner_offset` either side), so the fan's chords never cut across the shadow behind a
## corner. The shapes and their corners come from `ViewShapes`.
##
## Every ray is cast leaving out the low pieces in reach (the eye looks over them whatever their
## place), so it meets its first blocker in one cast, and a fixed coverage is read once, not on each
## ray (`ViewShapes`): the polygon is the one the plain rule draws, vertex for vertex.
##
## A ray that ends on a blocker runs on to where it leaves that one shape (at most `far_depth`), so
## a wall or a wardrobe that is seen shows its top and is not left as a black hole.

const Shapes := preload("res://scenes/vision/view_shapes.gd")

## The cone: the eye, then one corner per ray from the left edge to the right (empty with no
## facing). A triangle fan from the first point.
var cone := PackedVector2Array()
## The near bubble: one corner per ray round the eye, a closed fan from the eye.
var bubble := PackedVector2Array()
## The eye the polygons were built from.
var eye := Vector2.ZERO
var _shapes := Shapes.new()
## The sight rule (`SightRay`), asked with the coverage the shapes already know and with the low
## pieces in reach left out.
var _ray := SightRay.new()
## What the eye sees by (`Character.sight()`), set by each `rebuild`.
var _fov := 0.0
var _reach := 0.0
var _near := 0.0
var _see_over := 0.0


func _init() -> void:
	_ray.rated = _shapes.rated()


## Rebuild both polygons for an eye at `from` facing `facing`, casting in `space`, leaving `exclude`
## (rids) out and seeing by `sight` (`Character.sight()`).
func rebuild(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	facing: Vector2,
	exclude: Array,
	sight: Dictionary,
) -> void:
	eye = from
	_fov = deg_to_rad(float(sight["fov_degrees"]))
	_reach = float(sight["view_distance"])
	_near = float(sight["awareness_radius"])
	_see_over = float(sight["see_over_coverage"])
	_shapes.see_over = _see_over
	_ray.looks_over = _see_over
	_shapes.reset()
	var found := _shapes.corners(space, from, _reach, exclude)
	# Every low collider in reach is left out of the rays from here on: each meets the first blocker
	# in one cast, where it would otherwise cast again past each low piece on its way.
	_ray.leave_out(exclude + _shapes.lows())
	var corners := _visible_corners(space, from, facing, found)
	bubble = _sweep(space, from, _bubble_angles(from, corners), _near)
	cone.clear()
	if facing == Vector2.ZERO:
		return
	cone = PackedVector2Array([from])
	cone.append_array(_sweep(space, from, _cone_angles(from, facing, corners), _reach))


## Whether `point` is inside the cone or the bubble polygon.
func contains(point: Vector2) -> bool:
	return (
		(cone.size() >= 3 and Geometry2D.is_point_in_polygon(point, cone))
		or (bubble.size() >= 3 and Geometry2D.is_point_in_polygon(point, bubble))
	)


## Where sight along `dir` from `from` ends within `dist`: the full distance when the way is clear
## or only low furniture is in it, else where the ray leaves the first blocker's hit shape.
func _sight_end(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	dir: Vector2,
	dist: float,
) -> Vector2:
	var to := from + dir * dist
	var hit := _ray.cast(space, from, to)
	return to if hit.is_empty() else _far_face(hit, dir)


## The ray ends for `angles` (each `[key, direction]`, in order), the direction's `dist` out.
func _sweep(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	angles: Array,
	dist: float,
) -> PackedVector2Array:
	var ends := PackedVector2Array()
	for entry in angles:
		ends.append(_sight_end(space, from, entry[1], dist))
	return ends


## The corners the eye sees: within the view range, inside the cone or the bubble, and with no
## blocker in the way (a corner behind a wall needs no rays: the wall's own ray decides there).
func _visible_corners(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	facing: Vector2,
	found: Array,
) -> Array:
	var visible: Array = []
	for corner in found:
		var to: Vector2 = corner - from
		var dist := to.length()
		if dist < 1.0:
			continue
		var in_cone := facing != Vector2.ZERO and absf(facing.angle_to(to)) <= _fov * 0.5
		if not (in_cone or dist <= _near):
			continue
		# A point 1 px short of the corner: the corner's own shape is not in the way of itself.
		var short := from + to * ((dist - 1.0) / dist)
		if _ray.cast(space, from, short).is_empty():
			visible.append(corner)
	return visible


## The cone's rays as `[angle from the facing, direction]`, sorted: the even fan, which holds the
## two edge rays, and three rays at each visible corner inside the cone.
func _cone_angles(from: Vector2, facing: Vector2, corners: Array) -> Array:
	var half := _fov * 0.5
	var rays := VisionConfig.cone_rays
	var offset := VisionConfig.corner_offset
	var angles: Array = []
	for i in rays + 1:
		angles.append(-half + float(i) / float(rays) * _fov)
	for corner in corners:
		var angle := facing.angle_to(corner - from)
		if absf(angle) > half:
			continue
		for shift in [-offset, 0.0, offset]:
			angles.append(clampf(angle + shift, -half, half))
	angles.sort()
	return angles.map(func(angle: float) -> Array: return [angle, facing.rotated(angle)])


## The bubble's rays as `[angle, direction]`, sorted: the even fan and three rays at each visible
## corner inside the bubble.
func _bubble_angles(from: Vector2, corners: Array) -> Array:
	var rays := VisionConfig.bubble_rays
	var offset := VisionConfig.corner_offset
	var angles: Array = []
	for i in rays:
		angles.append(float(i) / float(rays) * TAU)
	for corner in corners:
		var to: Vector2 = corner - from
		if to.length() > _near:
			continue
		for shift in [-offset, 0.0, offset]:
			angles.append(fposmod(to.angle() + shift, TAU))
	angles.sort()
	return angles.map(func(angle: float) -> Array: return [angle, Vector2.from_angle(angle)])


## The far end of the blocker `hit` along `dir`: where the ray leaves the one shape it hit, at most
## `far_depth` in, else `far_bleed` px in.
func _far_face(hit: Dictionary, dir: Vector2) -> Vector2:
	var near: Vector2 = hit["position"]
	var polygon := _shapes.polygon_of(hit["collider"], hit["shape"])
	if polygon.size() < 3:
		return near + dir * VisionConfig.far_bleed
	var depth := _shapes.exit_distance(polygon, near, dir)
	if depth < 0.0:
		return near + dir * VisionConfig.far_bleed
	return near + dir * minf(depth, VisionConfig.far_depth)
