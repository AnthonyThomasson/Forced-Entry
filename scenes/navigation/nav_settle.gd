class_name NavSettle extends RefCounted
## Navigation domain: whether two lists of hole outlines are the same holes. After a district is
## built its pieces come to rest: they settle by up to about 0.15 px (measured over a seed's pieces)
## and a plain rectangle may be outlined with 6 vertices. That is no change to a steering tile's
## holes: outlines are compared as shapes, within `TOLERANCE`, not exactly.

## How far (px) a hole's boundary may lie from the one it is compared with and still be the same
## hole: 0.1 px, above the 0.15 px settling's bulk (a hole is compared by its distance to the
## other's boundary, which reads a settle a little under its corner shift) and a fifth of the 0.5 px
## at which a shoved piece is a move (a tipped piece's footprint differs by tens of px). The bake's
## cells are 4 px, so a drift this small rarely changes a polygon the baker draws (a cell centre
## within it of a hole edge can flip, and the tile stays baked from slightly stale holes).
const TOLERANCE := 0.1


## Whether `now` (outlines, `PackedVector2Array`s) are `before`'s holes within `TOLERANCE`: the same
## number of outlines, each matching its own in order. The order is that of the pieces, so a
## list that was only re-ordered reads as changed (a re-bake, never a missed one).
static func same_holes(before: Array, now: Array) -> bool:
	if before == now:
		return true
	if before.size() != now.size():
		return false
	for i in before.size():
		if not same_outline(before[i], now[i]):
			return false
	return true


## Whether the closed outlines `a` and `b` have the same boundary within `TOLERANCE`: every vertex
## and every edge midpoint of each lies that near the other's boundary, so a re-outline of the same
## shape with more vertices is the same, and a chord across a notch is not.
static func same_outline(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a == b:
		return true
	if a.size() < 3 or b.size() < 3:
		return false
	return _near(a, b) and _near(b, a)


## Whether each vertex and edge midpoint of `from` lies within `TOLERANCE` of the boundary of `to`.
static func _near(from: PackedVector2Array, to: PackedVector2Array) -> bool:
	var count := from.size()
	for i in count:
		var corner := from[i]
		if _gap(corner, to) > TOLERANCE:
			return false
		if _gap(corner.lerp(from[(i + 1) % count], 0.5), to) > TOLERANCE:
			return false
	return true


## The distance from `point` to the closed boundary of `outline`.
static func _gap(point: Vector2, outline: PackedVector2Array) -> float:
	var best := INF
	var count := outline.size()
	for i in count:
		var near := Geometry2D.get_closest_point_to_segment(
			point, outline[i], outline[(i + 1) % count])
		best = minf(best, point.distance_to(near))
	return best
