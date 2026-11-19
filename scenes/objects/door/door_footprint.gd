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
## higher than a step over (`DoorFallConfig.step_over`), none when the leaf lies flat, which is
## walked over.
static func lie_at(door: CollisionObject2D, top: float) -> void:
	door.collision_layer = PhysicsLayers.SOLID if top > DoorFallConfig.step_over else 0


## The footprint as a ring in the world (the collider's corners), or empty when the door is no
## obstacle (`lie_at`).
static func ring(door: CollisionObject2D) -> PackedVector2Array:
	var outline := PackedVector2Array()
	if door.collision_layer == 0:
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


## The door's collision shape.
static func _collider(door: Node2D) -> CollisionShape2D:
	return door.get_node(NodePath(COLLIDER)) as CollisionShape2D
