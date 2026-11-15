class_name FadeBox
extends RefCounted
## Art domain, the ground footprint and height of one piece the wall fade looks at (`wall_fade.gd`):
## a box turned about the up axis, in 3D units, and the one question asked of it: where does a
## line along the ground from a focus toward the camera first meet it. The line is the camera's
## ray seen from above; whether it is still under the piece's top there is the caller's (the ray
## rises with the camera's tangent).

## The footprint's centre `(x, z)`, its local x axis on the ground (the local z axis is that turned
## a quarter), its half sizes along them, the circle that holds it, and the height of its top.
var centre := Vector2.ZERO
var axis := Vector2.RIGHT
var half := Vector2.ZERO
var bound := 0.0
var top := 0.0


## Set from `aabb` (in the frame of `xf`) placed by `xf`, a transform that turns about up only (the
## mirror's lift of a 2D body, and what a mesh is built under).
func set_box(xf: Transform3D, aabb: AABB) -> void:
	var middle := xf * aabb.get_center()
	centre = Vector2(middle.x, middle.z)
	axis = Vector2(xf.basis.x.x, xf.basis.x.z)
	var along := axis.length()
	axis = axis / along if along > 0.0001 else Vector2.RIGHT
	half = Vector2(
		aabb.size.x * 0.5 * xf.basis.x.length(), aabb.size.z * 0.5 * xf.basis.z.length()
	)
	bound = half.length()
	top = xf.origin.y + aabb.end.y * xf.basis.y.length()


## The box's extent along the ground, as its two corners (x, z), for the grid it is filed in.
func lowest() -> Vector2:
	return centre - _spread()


## The high corner of the same.
func highest() -> Vector2:
	return centre + _spread()


## How far along the unit line `dir` from `from` (all on the ground, `(x, z)`) the box, grown by
## `pad` all round, is first met: 0 when `from` is inside it, -1 when the line misses it.
func entry(from: Vector2, dir: Vector2, pad: float) -> float:
	var offset := from - centre
	var across := Vector2(-axis.y, axis.x)
	var start := Vector2(offset.dot(axis), offset.dot(across))
	var heading := Vector2(dir.dot(axis), dir.dot(across))
	var reach := half + Vector2(pad, pad)
	var near := 0.0
	var far := INF
	for i in 2:
		if absf(heading[i]) < 0.000001:
			if absf(start[i]) > reach[i]:
				return -1.0
			continue
		var a := (-reach[i] - start[i]) / heading[i]
		var b := (reach[i] - start[i]) / heading[i]
		near = maxf(near, minf(a, b))
		far = minf(far, maxf(a, b))
	return near if far >= near else -1.0


## How far along the unit line `dir` from `from` the box is first met by a strip of half width
## `width` laid along the line (the line grown across it only, not ahead): 0 when the strip already
## overlaps the box at `from`, -1 when the box lies behind `from` or off to the side. The strip is
## the character's width seen from the camera, so a wall beside the character, not across the
## line to the camera, is missed however near.
func strip_entry(from: Vector2, dir: Vector2, width: float) -> float:
	var across := Vector2(-axis.y, axis.x)
	var corners := [
		centre + axis * half.x + across * half.y, centre - axis * half.x + across * half.y,
		centre - axis * half.x - across * half.y, centre + axis * half.x - across * half.y,
	]
	var first := INF
	var last := -INF
	for i in 4:
		var a: Vector2 = corners[i] - from
		var b: Vector2 = corners[(i + 1) % 4] - from
		var span := _clip_to_strip(
			Vector2(a.dot(dir), a.cross(dir)),
			Vector2(b.dot(dir), b.cross(dir)),
			width,
		)
		first = minf(first, span.x)
		last = maxf(last, span.y)
	if last < 0.0 or first == INF:
		return -1.0
	return maxf(first, 0.0)


## The lowest and highest along-line coordinate (x) of the part of the segment `a`-`b`, both given
## as (along, across), that lies within `width` across the line; (INF, -INF) when none does.
static func _clip_to_strip(a: Vector2, b: Vector2, width: float) -> Vector2:
	var none := Vector2(INF, -INF)
	var lo := 0.0
	var hi := 1.0
	var step := b.y - a.y
	if absf(step) >= 0.000001:
		var t1 := (-width - a.y) / step
		var t2 := (width - a.y) / step
		lo = maxf(lo, minf(t1, t2))
		hi = minf(hi, maxf(t1, t2))
	elif absf(a.y) > width:
		return none
	if lo > hi:
		return none
	var p := a.lerp(b, lo).x
	var q := a.lerp(b, hi).x
	return Vector2(minf(p, q), maxf(p, q))


## The extent along each ground axis of the turned box: its half sizes projected onto them.
func _spread() -> Vector2:
	var across := Vector2(-axis.y, axis.x)
	return Vector2(
		absf(axis.x) * half.x + absf(across.x) * half.y,
		absf(axis.y) * half.x + absf(across.y) * half.y,
	)
