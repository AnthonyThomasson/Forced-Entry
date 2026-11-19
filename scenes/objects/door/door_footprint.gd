extends RefCounted
## Objects domain (private): a door's footprint, what its 2D body is once the leaf is a free body
## (`DoorSlab`, D18): the collider the leaf's projection leaves, and whether the leaf is an obstacle
## at all. Plain functions over the door's own collider, found by name.

## The name of the door's collision shape.
const COLLIDER := &"Leaf"


## The footprint's collider is the hull `hull` (the door's frame): the leaf has tipped.
static func cut(door: Node2D, hull: PackedVector2Array) -> void:
	var hulled := ConvexPolygonShape2D.new()
	hulled.points = hull
	var collider := _collider(door)
	collider.shape = hulled


## The leaf stands upright again: its footprint is the leaf's.
static func restore(door: Node2D) -> void:
	var leaf := RectangleShape2D.new()
	leaf.size = door.call(&"leaf_size")
	var collider := _collider(door)
	collider.shape = leaf


## The leaf's top is `top` px over the floor now: the footprint is a solid collider while that is
## higher than a step over (`DoorFallConfig.step_over`), and on `PhysicsLayers.LYING` when the leaf
## lies flat: walked and driven over, but still found by a blast.
static func lie_at(door: CollisionObject2D, top: float) -> void:
	var flat := top <= DoorFallConfig.step_over
	door.collision_layer = PhysicsLayers.LYING if flat else PhysicsLayers.SOLID


## The footprint as a ring in the world (the collider's corners), or empty when the door is no
## obstacle (`lie_at`).
static func ring(door: CollisionObject2D) -> PackedVector2Array:
	var outline := PackedVector2Array()
	if door.collision_layer & PhysicsLayers.SOLID == 0:
		return outline
	var shape := _collider(door).shape
	var points := PackedVector2Array()
	if shape is ConvexPolygonShape2D:
		points = (shape as ConvexPolygonShape2D).points
	elif shape is RectangleShape2D:
		var half := (shape as RectangleShape2D).size * 0.5
		points = PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y),
		])
	for point in points:
		outline.append(door.global_transform * point)
	return outline


## How wide (px) the doorway between `from` and `to` (its jambs, world points) stays clear of the
## footprint of door `door` within `DoorFallConfig.mouth` of the wall line: the footprint's
## shadow along the doorway is taken off it and the wider side left is the answer. The whole
## doorway when the door's footprint is no obstacle (a leaf lying flat) or stands elsewhere.
static func clear_width(door: CollisionObject2D, from: Vector2, to: Vector2) -> float:
	var width := from.distance_to(to)
	var outline := ring(door)
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


## The door's collision shape.
static func _collider(door: Node2D) -> CollisionShape2D:
	return door.get_node(NodePath(COLLIDER)) as CollisionShape2D
