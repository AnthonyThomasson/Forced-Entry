extends RefCounted
## Objects domain, the 3D mesh of a room's walls (`structure_meshes.gd`, `domain-art/meshes.md`):
## every wall segment a full-height solid at its collider's own footprint (its real thickness, the
## doorways and gaps left open), the cap's colour on its sides and a lighter tone on top. Each
## segment is its own `MeshInstance3D` (`Segment<i>`, the segment's index in `wall_segments()`), so
## the wall-fade job fades them one by one. A whole segment is the one cached box every segment of
## that size and colour shares; a dented one is built from the convex pieces of its collider, so a
## wall hit and rebuilt (the mirror builds it again when its colliders change) shows its dents.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")


## The node a `wall` (a `Wall`: `segment_shapes()`, `art`, `art_color`) is shown by, in 3D units in
## the wall's own frame; null for a body that is no wall.
static func build(wall: Node2D) -> Node3D:
	if not wall.has_method(&"segment_shapes"):
		return null
	var colour := colour_of(wall)
	var shapes: Dictionary = wall.call(&"segment_shapes")
	var indices: Array = shapes.keys()
	indices.sort()
	var root := Node3D.new()
	root.name = "WallMesh"
	for i: int in indices:
		var part := _segment(shapes[i], colour)
		if part != null:
			part.name = "Segment%d" % i
			root.add_child(part)
	return root


## The cap colour as drawn: the painter's run-down grade of `art_color`, or the flat line's own
## when the wall has no art (as `Wall.get_surface` gives its debris).
static func colour_of(wall: Node) -> Color:
	var colour: Color = wall.get("art_color")
	return ObjectArt.drawn_color(colour) if String(wall.get("art")) != "" else colour


## Every value the shape reads, so a change of any is a different mesh.
static func _tuning() -> Dictionary:
	return {
		"height": ObjectStructureMeshConfig.wall_height,
		"top": ObjectStructureMeshConfig.wall_top_tone,
		"side": ObjectStructureMeshConfig.wall_side_tone,
	}


## The solid of one segment's collider shapes, or null when it has none now (a collider on its way
## out is not counted).
static func _segment(shapes: Array, colour: Color) -> MeshInstance3D:
	var live: Array[CollisionShape2D] = []
	for shape: Variant in shapes:
		if is_instance_valid(shape):
			var node := shape as CollisionShape2D
			if node.shape != null and not node.is_queued_for_deletion():
				live.append(node)
	if live.is_empty():
		return null
	if live.size() == 1 and _is_whole(live[0]):
		var size := (live[0].shape as RectangleShape2D).size
		var key := MeshCache.key("wall", size, colour, _tuning())
		var instance := MeshNodes.instance(
			MeshCache.fetch(key, func() -> Mesh: return _box(size, colour))
		)
		var centre := live[0].position
		MeshNodes.place(instance, Vector3(centre.x, 0.0, centre.y))
		return instance
	var kit := MeshKit.new()
	var side := _side(colour)
	var top := _top(colour)
	for shape in live:
		kit.extrude(_outline(shape), 0.0, ObjectStructureMeshConfig.wall_height, side, top)
	return MeshNodes.instance(kit.build())


## Whether `shape_node` is an upright rectangle with nothing but a position (a whole segment).
static func _is_whole(shape_node: CollisionShape2D) -> bool:
	return (
		shape_node.shape is RectangleShape2D
		and is_zero_approx(shape_node.rotation)
		and shape_node.scale.is_equal_approx(Vector2.ONE)
	)


## `size` px wide and deep, centred on the origin: the whole segment.
static func _box(size: Vector2, colour: Color) -> Mesh:
	var kit := MeshKit.new()
	kit.box(
		MeshKit.volume(Rect2(-size * 0.5, size), 0.0, ObjectStructureMeshConfig.wall_height),
		_side(colour),
		_top(colour),
	)
	return kit.build()


## The outline of `shape_node`'s shape in the wall's frame.
static func _outline(shape_node: CollisionShape2D) -> PackedVector2Array:
	var local := PackedVector2Array()
	if shape_node.shape is ConvexPolygonShape2D:
		local = (shape_node.shape as ConvexPolygonShape2D).points
	elif shape_node.shape is RectangleShape2D:
		var half := (shape_node.shape as RectangleShape2D).size * 0.5
		local = PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y),
		])
	return shape_node.transform * local


## The tone of the cap colour a wall's sides take.
static func _side(colour: Color) -> Color:
	return MeshKit.tone(colour, StringName(ObjectStructureMeshConfig.wall_side_tone))


## The tone of the cap colour a wall's top takes.
static func _top(colour: Color) -> Color:
	return MeshKit.tone(colour, StringName(ObjectStructureMeshConfig.wall_top_tone))
