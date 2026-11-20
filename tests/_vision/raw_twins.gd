extends RefCounted
## Test helper (not a test): the bare solids a test adds and their twins. A `Solid` is a plan handle
## (a `Node2D` of `TwinSpace.BODIES`, no engine body) that holds `Shape` children (a `Node2D` with
## a `Shape2D` resource: plain data, no physics), and the twin the twin space builds for it
## (`register`) is a wall `HEIGHT` tall on the world layer that follows its handle each physics
## frame: where it stands, which shapes it holds and how they lie, so a test may move a handle or
## give it a shape and the twin keeps up as a game object's twin does. A shape that comes or goes
## makes the solid say `segment_rebuilt`, as a re-cut wall does, so the player's view watches it.

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
		if not node is Solid:
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
	## put at the body's place and turn, never stretched: a plan handle has no scale of its own (a
	## test that scales a solid tests the view's bookkeeping of it, as the view reads the extent at
	## scale 1).
	func _sync() -> void:
		if _body == null or not is_instance_valid(_body):
			return
		var at := _body.global_transform
		transform = PlanSpace.lift_transform(Transform2D(at.get_rotation(), at.origin))
		if is_inside_tree():
			force_update_transform()  # pushed to Jolt now, as the twin space does: a query sees it
		var at_scale := at.get_scale()
		var stretch := Transform2D(Vector2(at_scale.x, 0.0), Vector2(0.0, at_scale.y), Vector2.ZERO)
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


	## The shape a child of the body stands for: a `Shape`'s; {} for any other child or an empty
	## holder.
	func _shape_of(child: Node) -> Dictionary:
		if child is Shape:
			var holder := child as Shape
			if holder.disabled or holder.shape == null:
				return {}
			return { "shape": holder.shape }
		return {}


	## Follow the body now, as a shape comes or goes.
	func sync_now() -> void:
		_sync()


	## What a shape's extent is made of, so a resized shape reads as a change.
	func _size_of(shape: Shape2D) -> Variant:
		if shape is RectangleShape2D:
			return (shape as RectangleShape2D).size
		if shape is CircleShape2D:
			return (shape as CircleShape2D).radius
		if shape is ConvexPolygonShape2D:
			return (shape as ConvexPolygonShape2D).points
		return null


## A bare solid: a plan handle of `TwinSpace.BODIES` with no engine body. Its `Shape` children are
## its footprint; it says `segment_rebuilt` (and `changed`, for a test to emit) as a wall and a door
## do.
class Solid:
	extends Node2D

	@warning_ignore("unused_signal")  # emitted by a test, or by a shape that comes or goes
	signal changed
	signal segment_rebuilt(index: int)


	func _init() -> void:
		add_to_group(TwinSpace.BODIES)
		child_entered_tree.connect(_shape_changed.bind(false))
		child_exiting_tree.connect(_shape_changed.bind(true))


	## A shape came (at once) or is going: a going one is still among the children when the signal
	## comes, and so is every shape of a solid that leaves the tree (no re-cut), so it is looked at
	## once it is gone, if the solid is still in the tree.
	func _shape_changed(child: Node, leaving: bool) -> void:
		if not child is Shape:
			return
		if leaving:
			_after_leaving.call_deferred()
		else:
			reshape()


	func _after_leaving() -> void:
		if is_inside_tree():
			reshape()


	## The shapes changed (one came or went, or was set): the twin follows at once and the watch of
	## the view is told.
	func reshape() -> void:
		var twin := TwinSpace.twin_for(self) as RawTwin
		if twin != null:
			twin.sync_now()
		segment_rebuilt.emit(0)


## A shape of a bare solid: where it lies (`position`, `rotation`, `scale`) and its `Shape2D`.
class Shape:
	extends Node2D

	var shape: Shape2D
	var disabled := false
