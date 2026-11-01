extends RefCounted
## TEST-ONLY REFERENCE (not the game's): the cone as `scenes/vision/view_cone.gd` built it at the
## start of #168 slice 11 (commit f69b6f80), before any saving, kept as it was so that
## `vision/cone_same_after_savings` can hold the faster cone to its output vertex for vertex. It
## keeps nothing from one rebuild to the next, reads every shape and coverage anew each build and
## casts every ray plainly. Do not "fix" it: it is the yardstick. The game's cone follows
## `docs/player-vision.md` V1; this file is that rule in its plainest form. The sight rule itself
## (`_hit`) is a copy of General's `SightRay.hit` as it was then, so a change to `SightRay` does not
## move the yardstick.
##
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
## A ray that ends on a blocker runs on to where it leaves that one shape (at most `far_depth`), so
## a wall or a wardrobe that is seen shows its top and is not left as a black hole. (One change
## since f69b6f80, #168 slice 14: "that one shape" is the farthest face of the blocking shapes found
## just inside the hit, `far_exit`, because the physics query names any of several overlapping or
## touching shapes for one ray, so the yardstick differed from itself between two builds of the
## same world.)

const Shapes := preload("res://tests/_vision/reference_view_shapes.gd")

## The cone: the eye, then one corner per ray from the left edge to the right (empty with no
## facing). A triangle fan from the first point.
var cone := PackedVector2Array()
## The near bubble: one corner per ray round the eye, a closed fan from the eye.
var bubble := PackedVector2Array()
## The eye the polygons were built from.
var eye := Vector2.ZERO
var _shapes := Shapes.new()
## What the eye sees by (`Character.sight()`), set by each `rebuild`.
var _fov := 0.0
var _reach := 0.0
var _near := 0.0
var _see_over := 0.0
## The ray `_hit` refills on each cast.
var _query := _solid_query()


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
	_shapes.reset()
	var corners := _visible_corners(space, from, facing, exclude)
	bubble = _sweep(space, from, _bubble_angles(from, corners), _near, exclude)
	cone.clear()
	if facing == Vector2.ZERO:
		return
	cone = PackedVector2Array([from])
	cone.append_array(_sweep(space, from, _cone_angles(from, facing, corners), _reach, exclude))


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
	exclude: Array,
) -> Vector2:
	var to := from + dir * dist
	var hit := _hit(space, from, to, exclude)
	return to if hit.is_empty() else _far_face(space, hit, dir)


## The ray ends for `angles` (each `[key, direction]`, in order), the direction's `dist` out.
func _sweep(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	angles: Array,
	dist: float,
	exclude: Array,
) -> PackedVector2Array:
	var ends := PackedVector2Array()
	for entry in angles:
		ends.append(_sight_end(space, from, entry[1], dist, exclude))
	return ends


## The corners the eye sees: within the view range, inside the cone or the bubble, and with no
## blocker in the way (a corner behind a wall needs no rays: the wall's own ray decides there).
func _visible_corners(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	facing: Vector2,
	exclude: Array,
) -> Array:
	var visible: Array = []
	for corner in _shapes.corners(space, from, _reach, exclude):
		var to: Vector2 = corner - from
		var dist := to.length()
		if dist < 1.0:
			continue
		var in_cone := facing != Vector2.ZERO and absf(facing.angle_to(to)) <= _fov * 0.5
		if not (in_cone or dist <= _near):
			continue
		# A point 1 px short of the corner: the corner's own shape is not in the way of itself.
		var short := from + to * ((dist - 1.0) / dist)
		if _hit(space, from, short, exclude).is_empty():
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
func _far_face(space: PhysicsDirectSpaceState2D, hit: Dictionary, dir: Vector2) -> Vector2:
	var near: Vector2 = hit["position"]
	var depth := _shapes.far_exit(space, near, dir)
	if depth < 0.0:
		return near + dir * VisionConfig.far_bleed
	return near + dir * minf(depth, VisionConfig.far_depth)


## `SightRay.hit` as it was at f69b6f80: the first thing on the line from `from` to `to` too tall to
## look over, casting again past each low one, or {} when the line reaches `to`.
func _hit(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	to: Vector2,
	exclude: Array,
) -> Dictionary:
	var skipped := exclude
	var copied := false
	while true:
		_query.from = from
		_query.to = to
		_query.exclude = skipped
		var found := space.intersect_ray(_query)
		if found.is_empty() or SightRay.coverage_of(found.get("collider")) > _see_over:
			return found
		if not copied:
			skipped = exclude.duplicate()
			copied = true
		skipped.append(found.get("rid"))
	return {}  # unreachable; satisfies the parser


## A ray query on the solid layer.
func _solid_query() -> PhysicsRayQueryParameters2D:
	var query := PhysicsRayQueryParameters2D.new()
	query.collision_mask = PhysicsLayers.SOLID
	return query
