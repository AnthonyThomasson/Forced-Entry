extends RefCounted
## Test helper (not a test): the twins of the bare solids a vision test adds (a `StaticBody2D` or
## `AnimatableBody2D` on `PhysicsLayers.SOLID` that no game object builds), so the player's cone,
## which reads the twin space, meets them. A twin is a wall `HEIGHT` tall on the world layer that
## follows its body each physics frame: where it stands, which shapes it holds and how they lie, so
## a test may move a body or give it a shape and the twin keeps up as a game object's twin does.

## The height (px) of a twin: a wall's, so the cone cannot see over it.
const HEIGHT := 96.0


## Have `world`'s twin space twin the bare solids added from now on.
static func register(world: Node) -> void:
	var twins: TwinSpace = world.twin_space()
	if twins != null:
		twins.builders.append(Callable(RawTwin, &"build"))


## The twin of `node` when it is a bare solid, else null.
class RawTwin:
	extends StaticBody3D

	var _body: Node2D
	var _signature: Array = []


	func _physics_process(_delta: float) -> void:
		_sync()


	static func build(node: Node2D) -> Node3D:
		if not (node is StaticBody2D or node is AnimatableBody2D):
			return null
		if (node as CollisionObject2D).collision_layer & PhysicsLayers.SOLID == 0:
			return null
		var twin := RawTwin.new()
		twin._body = node
		twin.collision_layer = PhysicsLayers.TWIN_WORLD
		twin.collision_mask = 0
		twin.set_meta(&"top", HEIGHT)
		twin.process_physics_priority = -200
		twin._sync()
		return twin


	## Follow the body: its place, and its shapes when they or their places changed. The twin is
	## put at the body's place and turn; the body's stretch goes into each shape's own frame.
	func _sync() -> void:
		if _body == null or not is_instance_valid(_body):
			return
		var at := _body.global_transform
		transform = PlanSpace.lift_transform(Transform2D(at.get_rotation(), at.origin))
		var stretch := Transform2D(
			Vector2(at.get_scale().x, 0.0),
			Vector2(0.0, at.get_scale().y),
			Vector2.ZERO,
		)
		var now: Array = [stretch]
		var shapes: Array = []
		for child in _body.get_children():
			var holder := _shape_of(child)
			if holder.is_empty():
				continue
			var placed: Transform2D = stretch * (child as Node2D).transform
			now.append([placed, holder["shape"].get_class(), _size_of(holder["shape"])])
			shapes.append([holder["shape"], placed])
		if now == _signature:
			return
		_signature = now
		for child in get_children():
			remove_child(child)
			child.queue_free()
		for entry in shapes:
			var lifted := TwinShapes.lift(entry[0], entry[1], 0.0, HEIGHT)
			if lifted != null:
				add_child(lifted)


	## The shape a child of the body stands for: a `CollisionShape2D`'s, or the hull of a
	## `CollisionPolygon2D`'s points; {} for any other child or an empty holder.
	func _shape_of(child: Node) -> Dictionary:
		if child is CollisionShape2D:
			var holder := child as CollisionShape2D
			if holder.disabled or holder.shape == null:
				return {}
			return { "shape": holder.shape }
		if child is CollisionPolygon2D:
			var hull := Geometry2D.convex_hull((child as CollisionPolygon2D).polygon)
			if hull.size() < 4 or (child as CollisionPolygon2D).disabled:
				return {}
			hull.remove_at(hull.size() - 1)
			var shape := ConvexPolygonShape2D.new()
			shape.points = hull
			return { "shape": shape }
		return {}


	## What a shape's extent is made of, so a resized shape reads as a change.
	func _size_of(shape: Shape2D) -> Variant:
		if shape is RectangleShape2D:
			return (shape as RectangleShape2D).size
		if shape is CircleShape2D:
			return (shape as CircleShape2D).radius
		if shape is ConvexPolygonShape2D:
			return (shape as ConvexPolygonShape2D).points
		return null
