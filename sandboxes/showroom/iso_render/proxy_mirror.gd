extends Node3D
## Spike of #193: a 3D mirror of the 2D world as proxies. Every collision shape of every physics
## body under a root becomes one box or cylinder (a character: a capsule) sized from the shape,
## (x, y) -> (x, 0, y) * `IsoConfig.UNIT`; the floors (group `floors`) become slabs. A body that
## moves (a character, a door's leaf, a furniture piece awake) has its proxy's transform written
## when its 2D transform changed; a wall or a sleeping piece is written once. This is the cost of
## the mirror the real build would pay, measured by the windowed probe.

const IsoConfig := preload("res://sandboxes/showroom/iso_render/iso_config.gd")
const TOON := preload("res://sandboxes/showroom/iso_render/iso_toon.gdshader")

## Furniture heights by the body's node name (a prefix), else the footprint decides.
var heights: Dictionary = {}
## How many proxies exist, how many of them follow a moving body, and how many were written last
## frame.
var count := 0
var dynamic_count := 0
var written := 0
var _material: ShaderMaterial
var _box := BoxMesh.new()
var _cylinder := CylinderMesh.new()
var _capsules: Dictionary = {}
## Each moving proxy: `{ node, shape, body, last, size3, half_height }`.
var _moving: Array[Dictionary] = []


func _init() -> void:
	_material = ShaderMaterial.new()
	_material.shader = TOON
	_box.size = Vector3.ONE
	_cylinder.top_radius = 1.0
	_cylinder.bottom_radius = 1.0
	_cylinder.height = 1.0
	_cylinder.radial_segments = 12
	_cylinder.rings = 1


## The shared toon material (its ramp and bands are set by the view).
func material() -> ShaderMaterial:
	return _material


## Build proxies for everything under `root` now (floors, then every physics body's shapes).
func mirror(root: Node) -> void:
	for floor_node: Node in root.get_tree().get_nodes_in_group(&"floors"):
		if root.is_ancestor_of(floor_node):
			_add_floor(floor_node as Node2D)
	for body: Node in root.find_children("*", "PhysicsBody2D", true, false):
		_add_body(body as PhysicsBody2D)
	count = get_child_count()
	dynamic_count = _moving.size()


## Follow the moving bodies: write the proxies whose 2D transform changed.
func update() -> void:
	written = 0
	var i := 0
	while i < _moving.size():
		var row: Dictionary = _moving[i]
		var shape: Variant = row["shape"]  # untyped: a freed node may not be assigned to a Node2D
		if not is_instance_valid(shape):
			(row["node"] as Node).queue_free()
			_moving.remove_at(i)
			continue
		var body: Node2D = row["body"]
		if body is RigidBody2D and (body as RigidBody2D).sleeping:
			i += 1
			continue
		var xf: Transform2D = (shape as Node2D).global_transform
		if xf != row["last"]:
			row["last"] = xf
			(row["node"] as Node3D).transform = _lift(xf, row["size3"], row["half_height"])
			written += 1
		i += 1


func _add_floor(floor_node: Node2D) -> void:
	var size: Vector2 = floor_node.get("size")
	var slab := _instance(_box, _tint(floor_node.get("color"), Color(0.5, 0.45, 0.4)))
	slab.scale = Vector3(size.x, 2.0, size.y) * IsoConfig.UNIT
	var centre := floor_node.global_position + size * 0.5
	slab.position = Vector3(centre.x, -1.0, centre.y) * IsoConfig.UNIT
	add_child(slab)


func _add_body(body: PhysicsBody2D) -> void:
	var moving := body is CharacterBody2D or body is AnimatableBody2D or body is RigidBody2D
	var colour := _colour_of(body)
	for child in body.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.disabled or shape_node.shape == null:
			continue
		var proxy := _proxy(body, shape_node, colour)
		if proxy.is_empty():
			continue
		add_child(proxy["node"])
		if moving:
			_moving.append(proxy)
		else:
			(proxy["node"] as Node3D).transform = _lift(
				(proxy["shape"] as Node2D).global_transform, proxy["size3"], proxy["half_height"]
			)


## `{ node, shape, body, last, size3, half_height }` for one collision shape, or {} for a shape
## the spike does not mirror.
func _proxy(body: PhysicsBody2D, shape_node: CollisionShape2D, colour: Color) -> Dictionary:
	var shape := shape_node.shape
	var height := _height_of(body, shape) * IsoConfig.UNIT
	var node: MeshInstance3D
	var size3 := Vector3.ONE
	var anchor: Node2D = shape_node
	if body.is_in_group(&"characters") and shape is CircleShape2D:
		var radius := (shape as CircleShape2D).radius * IsoConfig.UNIT
		node = _instance(_capsule(radius, height), colour)
	elif shape is CircleShape2D:
		var radius := (shape as CircleShape2D).radius * IsoConfig.UNIT
		node = _instance(_cylinder, colour)
		size3 = Vector3(radius, height, radius)
	else:
		var rect := _rect_of(shape)
		if rect.size == Vector2.ZERO:
			return {}
		node = _instance(_box, colour)
		size3 = Vector3(
			rect.size.x,
			height,
			rect.size.y,
		) * Vector3(IsoConfig.UNIT, 1.0, IsoConfig.UNIT)
		# A shape off its node's origin (a convex piece's points) is centred by the rect.
		anchor = _centred(shape_node, rect.get_center())
	return {
		"node": node, "shape": anchor, "body": body, "last": Transform2D(), "size3": size3,
		"half_height": height * 0.5,
	}


func _lift(xf: Transform2D, size3: Vector3, half_height: float) -> Transform3D:
	var turned := Basis(Vector3.UP, -xf.get_rotation()) * Basis.from_scale(size3)
	return Transform3D(
		turned,
		Vector3(xf.origin.x, 0.0, xf.origin.y) * IsoConfig.UNIT + Vector3(0, half_height, 0),
	)


func _rect_of(shape: Shape2D) -> Rect2:
	if shape is RectangleShape2D:
		return Rect2(-(shape as RectangleShape2D).size * 0.5, (shape as RectangleShape2D).size)
	if shape is ConvexPolygonShape2D:
		var points := (shape as ConvexPolygonShape2D).points
		if points.size() < 3:
			return Rect2()
		var rect := Rect2(points[0], Vector2.ZERO)
		for p in points:
			rect = rect.expand(p)
		return rect
	if shape is CapsuleShape2D:
		var cap := shape as CapsuleShape2D
		return Rect2(Vector2(-cap.radius, -cap.height * 0.5), Vector2(cap.radius * 2.0, cap.height))
	return Rect2()


## A node-like stand-in for a shape whose points are off its origin: a Node2D under the shape
## node carrying the offset, so `global_transform` lands on the shape's centre.
func _centred(shape_node: CollisionShape2D, offset: Vector2) -> Node2D:
	if offset.is_zero_approx():
		return shape_node
	var marker := shape_node.get_node_or_null(^"IsoCentre") as Node2D
	if marker == null:
		marker = Node2D.new()
		marker.name = "IsoCentre"
		marker.position = offset
		shape_node.add_child(marker)
	return marker


func _height_of(body: Node, shape: Shape2D) -> float:
	if body.is_in_group(&"characters"):
		return IsoConfig.CHARACTER_HEIGHT
	if body is Door:
		return IsoConfig.DOOR_HEIGHT
	if body.get("wall_thickness") != null:
		return IsoConfig.WALL_HEIGHT
	for prefix: String in heights:
		if String(body.name).begins_with(prefix):
			return heights[prefix]
	var rect := _rect_of(shape)
	var narrow := minf(rect.size.x, rect.size.y) if rect.size != Vector2.ZERO else 40.0
	return clampf(narrow * 0.7, IsoConfig.FURNITURE_MIN, IsoConfig.FURNITURE_MAX)


func _colour_of(body: Node) -> Color:
	if body.is_in_group(&"characters"):
		var faction := String(body.get("faction"))
		if faction == "invader":
			return Color(0.24, 0.3, 0.55)
		if faction == "defender":
			return Color(0.75, 0.62, 0.4)
		return Color(0.85, 0.45, 0.2)
	for key in ["art_color", "color"]:
		var value: Variant = body.get(key)
		if value is Color:
			return value
	if body is Door:
		return Color(0.55, 0.38, 0.24)
	return Color.from_hsv(
		float(hash(String(body.name).rstrip("0123456789_")) % 100) / 100.0,
		0.35,
		0.7,
	)


func _tint(value: Variant, fallback: Color) -> Color:
	return value if value is Color else fallback


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var key := "%.2f/%.2f" % [radius, height]
	if not _capsules.has(key):
		var capsule := CapsuleMesh.new()
		capsule.radius = radius
		capsule.height = maxf(height, radius * 2.0 + 0.1)
		capsule.radial_segments = 12
		capsule.rings = 4
		_capsules[key] = capsule
	return _capsules[key]


func _instance(mesh: Mesh, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material
	node.set_instance_shader_parameter(&"base_color", colour)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return node
