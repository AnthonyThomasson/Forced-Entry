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
## A ray that ends on a blocker runs on to where it leaves it (at most `far_depth`): the farthest
## exit over the blocking shapes that hold a point 0.1 px along the ray, so a wall or a wardrobe
## that is seen shows its top and is not left as a black hole.

const Shapes := preload("res://scenes/vision/view_shapes.gd")
## The region of a rebuild (`_region`): the sides of the polygon round the bubble, the chords the
## cone's arc is cut into, and the margin (px) it is grown by.
const REGION_SIDES := 16
const REGION_ARC := 16
const REGION_MARGIN := 2.0

## The cone: the eye, then one corner per ray from the left edge to the right (empty with no
## facing). A triangle fan from the first point.
var cone := PackedVector2Array()
## The near bubble: one corner per ray round the eye, a closed fan from the eye.
var bubble := PackedVector2Array()
## The eye the polygons were built from.
var eye := Vector2.ZERO
## How many rays the last `rebuild` cast to ask whether a corner is seen (a test's read of the
## cost).
var corner_rays := 0
## How many corners the last `rebuild` read from the shapes about the eye (a test's read of the
## cost).
var corners_read := 0
var _shapes := Shapes.new()
## The even fan's rays of the last `rebuild` (`_cast_fan`): the hit of ray `i` (an empty dictionary
## for a clear one) and where it ends. A corner between two neighbouring rays that met one convex
## shape nearer than the corner is hidden by it.
var _fan_hits: Array[Dictionary] = []
var _fan_ends := PackedVector2Array()
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
	var found := _shapes.corners(space, from, _reach, exclude, _region(from, facing))
	corners_read = found.size()
	# Every low collider in reach is left out of the rays from here on: each meets the first blocker
	# in one cast, where it would otherwise cast again past each low piece on its way.
	_ray.leave_out(exclude + _shapes.lows())
	corner_rays = 0
	_cast_fan(space, from, facing)
	var corners := _visible_corners(space, from, facing, found)
	bubble = _sweep(space, from, _bubble_angles(from, corners), _near)
	cone.clear()
	if facing == Vector2.ZERO:
		return
	cone = PackedVector2Array([from])
	cone.append_array(_sweep(space, from, _cone_angles(from, facing, corners), _reach, _fan_ends))


## The hull of everything a ray of this rebuild passes through, grown by `REGION_MARGIN`: the
## sector of the cone (its arc cut into chords that lie outside it) and the bubble round the eye.
## A shape that does not touch it is in no ray, and has no corner within half a pixel of one that
## is (`ViewShapes.corners` joins those), so it need not be read.
func _region(from: Vector2, facing: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var round_bubble := _near / cos(PI / float(REGION_SIDES))
	for i in REGION_SIDES:
		points.append(from + Vector2.from_angle(float(i) / REGION_SIDES * TAU) * round_bubble)
	if facing != Vector2.ZERO:
		var half := _fov * 0.5
		var round_arc := _reach / cos(_fov / float(REGION_ARC) * 0.5)
		for i in REGION_ARC + 1:
			var angle := -half + float(i) / float(REGION_ARC) * _fov
			points.append(from + facing.rotated(angle) * round_arc)
	var grown := Geometry2D.offset_polygon(Geometry2D.convex_hull(points), REGION_MARGIN)
	return PackedVector2Array() if grown.is_empty() else grown[0]


## Whether `point` is inside the cone or the bubble polygon.
func contains(point: Vector2) -> bool:
	return SeenArea.contains(cone, point) or SeenArea.contains(bubble, point)


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
	return to if hit.is_empty() else _far_face(space, hit, dir)


## The ray ends for `rays` (each `[angle, direction, fan index]`, in order), the direction's `dist`
## out. A ray with a fan index in `known` (the even fan's ends, `_fan_ends`) takes its end from it.
func _sweep(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	rays: Array,
	dist: float,
	known := PackedVector2Array(),
) -> PackedVector2Array:
	var ends := PackedVector2Array()
	for ray in rays:
		var fan_index: int = ray[2]
		if fan_index >= 0 and fan_index < known.size():
			ends.append(known[fan_index])
		else:
			ends.append(_sight_end(space, from, ray[1], dist))
	return ends


## Cast the even fan (`VisionConfig.cone_rays` + 1 rays across the cone) and keep each ray's hit and
## end: the polygon needs these rays whatever the corners, and the corners are tested against them.
func _cast_fan(space: PhysicsDirectSpaceState2D, from: Vector2, facing: Vector2) -> void:
	_fan_hits.clear()
	_fan_ends.clear()
	if facing == Vector2.ZERO:
		return
	for i in VisionConfig.cone_rays + 1:
		var dir := facing.rotated(_fan_angle(i))
		var to := from + dir * _reach
		var hit := _ray.cast(space, from, to)
		_fan_hits.append(hit)
		_fan_ends.append(to if hit.is_empty() else _far_face(space, hit, dir))


## The angle from the facing of ray `i` of the even fan across the cone, `i` from 0 (the left edge)
## to `VisionConfig.cone_rays` (the right).
func _fan_angle(i: int) -> float:
	return -_fov * 0.5 + float(i) / float(VisionConfig.cone_rays) * _fov


## Whether the line from `from` to the point `reach` px along `angle` (from the facing, inside the
## cone) is blocked before it is, by what the fan found: the two rays either side of it met the
## same convex shape, both nearer than `reach`. The shape holds the chord between its two hits, the
## line crosses that chord, so it meets the shape there.
func _fan_hides(from: Vector2, angle: float, reach: float) -> bool:
	var rays := VisionConfig.cone_rays
	var half := _fov * 0.5
	var i := clampi(int((angle + half) / _fov * float(rays)), 0, rays - 1)
	if angle <= _fan_angle(i) or angle >= _fan_angle(i + 1):
		return false
	var a := _fan_hits[i]
	var b := _fan_hits[i + 1]
	if a.is_empty() or b.is_empty():
		return false
	if a["collider_id"] != b["collider_id"] or a["shape"] != b["shape"]:
		return false
	if from.distance_to(a["position"]) >= reach or from.distance_to(b["position"]) >= reach:
		return false
	return not _shapes.polygon_of(a["collider"], a["shape"]).is_empty()


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
		if dist < 1.0 or dist > _reach:  # a corner beyond the view distance adds no ray
			continue
		var in_cone := facing != Vector2.ZERO and absf(facing.angle_to(to)) <= _fov * 0.5
		if not (in_cone or dist <= _near):
			continue
		# A point 1 px short of the corner: the corner's own shape is not in the way of itself.
		if in_cone and _fan_hides(from, facing.angle_to(to), dist - 1.0):
			continue
		var short := from + to * ((dist - 1.0) / dist)
		corner_rays += 1
		if _ray.cast(space, from, short).is_empty():
			visible.append(corner)
	return visible


## The cone's rays as `[angle from the facing, direction, fan index]`, sorted by angle: the even
## fan, which holds the two edge rays (its index `i` is the ray's place in `_fan_ends`), and three
## rays at each visible corner inside the cone (index -1: cast on their own; one clamped onto an
## edge of the cone takes that edge ray's index).
func _cone_angles(from: Vector2, facing: Vector2, corners: Array) -> Array:
	var half := _fov * 0.5
	var offset := VisionConfig.corner_offset
	var rays: Array = []
	for i in VisionConfig.cone_rays + 1:
		rays.append([_fan_angle(i), i])
	for corner in corners:
		var angle := facing.angle_to(corner - from)
		if absf(angle) > half:
			continue
		for shift in [-offset, 0.0, offset]:
			var shifted := clampf(angle + shift, -half, half)
			# A ray clamped onto an edge of the cone is the fan's edge ray: its end is known.
			var edge := 0 if shifted <= -half else VisionConfig.cone_rays if shifted >= half else -1
			rays.append([shifted, edge])
	rays.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return rays.map(func(ray: Array) -> Array: return [ray[0], facing.rotated(ray[0]), ray[1]])


## The bubble's rays as `[angle, direction, -1]`, sorted: the even fan and three rays at each
## visible corner inside the bubble.
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
	return angles.map(func(angle: float) -> Array: return [angle, Vector2.from_angle(angle), -1])


## The far end of the blocker `hit` along `dir`: where the ray leaves the solid it met (the
## farthest face of the blocking shapes it runs into at the hit, so the engine's pick among
## overlapping shapes does not matter), at most `far_depth` in, else `far_bleed` px in.
func _far_face(space: PhysicsDirectSpaceState2D, hit: Dictionary, dir: Vector2) -> Vector2:
	var near: Vector2 = hit["position"]
	var depth := _shapes.far_exit(space, near, dir)
	if depth < 0.0:
		return near + dir * VisionConfig.far_bleed
	return near + dir * minf(depth, VisionConfig.far_depth)
