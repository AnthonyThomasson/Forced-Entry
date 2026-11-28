extends RefCounted
## Objects domain (private): a door's footprint, what its plan handle is once the leaf is a free
## body (`DoorSlab`, D18): the outline the leaf's projection leaves, as polygon data (`hull`, the
## door's frame; empty while the leaf stands upright: the leaf's own rectangle), whether the leaf
## lies flat (no obstacle: `DoorFallConfig.step_over`), and how wide a doorway it leaves clear. The
## door's `footprint` part; the slab writes it.

## The hull the tipped leaf's projection leaves (the door's frame), empty while it is upright.
var hull := PackedVector2Array()
## Whether the leaf lies flat on the floor (walked and driven over).
var flat := false


## The leaf's top is `top` px over the floor now: it lies flat while that is no higher than a step
## over.
func lie_at(top: float) -> void:
	flat = top <= DoorFallConfig.step_over


## The footprint as a ring in the world, `leaf` px for the upright leaf's rectangle when there is no
## hull, placed by `placed`; empty when the leaf lies flat.
func ring(leaf: Vector2, placed: Transform2D) -> PackedVector2Array:
	var outline := PackedVector2Array()
	if flat:
		return outline
	var points := hull
	if points.is_empty():
		var half := leaf * 0.5
		points = PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y),
		])
	for point in points:
		outline.append(placed * point)
	return outline


## How wide (px) the doorway between `from` and `to` (its jambs, world points) stays clear of the
## footprint `outline` (a ring in the world) within `DoorFallConfig.mouth` of the wall line: the
## footprint's shadow along the doorway is taken off it and the wider side left is the answer. The
## whole doorway when the footprint is empty (a leaf lying flat) or stands elsewhere.
static func clear_width(outline: PackedVector2Array, from: Vector2, to: Vector2) -> float:
	var width := from.distance_to(to)
	if outline.size() < 3:
		return width
	var along := (to - from) / width
	var across := along.orthogonal() * DoorFallConfig.mouth
	var mouth := PackedVector2Array([from - across, to - across, to + across, from + across])
	var low := INF
	var high := -INF
	for part in Geometry2D.intersect_polygons(outline, mouth):
		for point in part:
			var t := (point - from).dot(along)
			low = minf(low, t)
			high = maxf(high, t)
	if low > high:
		return width
	return maxf(maxf(low, 0.0), maxf(width - high, 0.0))
