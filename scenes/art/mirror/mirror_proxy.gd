class_name MirrorProxy
extends RefCounted
## Art domain, the 3D mirror (`world_mirror.gd`'s helper; its kind names are the keys of the mesh
## hook): builds the proxy of one collision shape of a 2D body, a box or cylinder (a character: a
## capsule) sized from the shape and coloured from the body, one shared mesh per shape kind and one
## shared toon material (`ToonMaterial`, a colour per instance). Reads the bodies duck-typed (groups
## `characters`, `vehicles`, `doors`, the properties `wall_thickness`, `art_color`, `color`,
## `faction`), so Art imports nothing from the domains that own them.

## The kinds a body is sorted into (`kind_of`): the hook of `WorldMirror.builders` is keyed by them.
const WALL := &"wall"
const DOOR := &"door"
const CHARACTER := &"character"
const VEHICLE := &"vehicle"
const FURNITURE := &"furniture"
const FLOOR := &"floor"

## The one material every proxy shares (a colour per instance), the one a domain's own meshes
## share too, pushed the holders' tuning anew with each mirror.
var _material := ToonMaterial.shared()
## The unit box and unit cylinder every box and cylinder proxy shares, scaled by its node.
var _box := BoxMesh.new()
var _cylinder := CylinderMesh.new()
## The capsules by radius and height (a character's, shared by every one of that size).
var _capsules: Dictionary = {}


func _init() -> void:
	ToonMaterial.refresh_all()
	_box.size = Vector3.ONE
	_cylinder.top_radius = 1.0
	_cylinder.bottom_radius = 1.0
	_cylinder.height = 1.0
	_cylinder.radial_segments = 12
	_cylinder.rings = 1


## The kind of `body`: a character, vehicle, door or wall by what it says it is (the group or the
## property the owning domain gives it), else a piece of furniture.
static func kind_of(body: Node) -> StringName:
	if body.is_in_group(&"characters"):
		return CHARACTER
	if body.is_in_group(&"vehicles"):
		return VEHICLE
	if body.is_in_group(&"doors"):
		return DOOR
	if body.get("wall_thickness") != null:
		return WALL
	return FURNITURE


## The hook key of the furniture painted by `art` (an `ObjectArt` id): a builder under it wins over
## the `FURNITURE` kind's, for a piece of that art alone.
static func furniture_key(art: String) -> StringName:
	return StringName("%s:%s" % [FURNITURE, art])


## The hook key of the floor painted by `art`: a builder under it wins over `FLOOR`'s.
static func floor_key(art: String) -> StringName:
	return StringName("%s:%s" % [FLOOR, art])


## The art id of `node`, read duck-typed: a piece's `look.art`, a floor's `art`; "" for a node that
## names none.
static func art_of(node: Node) -> String:
	var look: Variant = node.get("look")
	if look is Object and (look as Object).get("art") is String:
		return (look as Object).get("art")
	var own: Variant = node.get("art")
	return own if own is String else ""


## The proxy of `shape_node` (a CollisionShape2D of `body`, of `kind`) as a row, or {} for a shape
## the mirror does not show. A row is `{ node, shape, body, last, size3, half_height, offset, rigid,
## asleep }`: `shape` the 2D node whose transform the proxy follows, `offset` where its centre sits
## in that node's frame, `size3` the scale the shared unit mesh is given, `rigid` the body when it
## is a `RigidBody2D` (it sleeps), `asleep` whether the mirror last found it so and `shown` whether
## the proxy shows (a disabled shape or a hidden body hides it).
func make(body: PhysicsBody2D, kind: StringName, shape_node: CollisionShape2D) -> Dictionary:
	var shape := shape_node.shape
	var rect := rect_of(shape)
	if rect.size == Vector2.ZERO:
		return {}
	var unit := RenderConfig.unit
	var height := height_of(body, kind, rect) * unit
	var colour := colour_of(body, kind)
	var node: MeshInstance3D
	var size3 := Vector3.ONE
	if kind == CHARACTER and shape is CircleShape2D:
		node = _instance(_capsule((shape as CircleShape2D).radius * unit, height), colour)
	elif shape is CircleShape2D:
		var radius := (shape as CircleShape2D).radius * unit
		node = _instance(_cylinder, colour)
		size3 = Vector3(radius, height, radius)
	else:
		node = _instance(_box, colour)
		size3 = Vector3(rect.size.x * unit, height, rect.size.y * unit)
	return {
		"node": node, "shape": shape_node, "body": body, "last": Transform2D(), "size3": size3,
		"half_height": height * 0.5, "offset": rect.get_center(),
		"rigid": body if body is RigidBody2D else null, "asleep": false, "shown": true,
		"update": Callable(),
	}


## The row of a mesh a domain's builder made for `body` (`WorldMirror.builders`): the node follows
## the whole body, so its origin and turn are the body's. `shapes` are the body's own collision
## shapes (while all are disabled the mesh hides: `shapes_all_off`); `update` the mesh's
## `mirror_update(body)` when it has one (else an invalid `Callable`).
func own_row(body: Node2D, node: Node3D) -> Dictionary:
	var shapes: Array[Node] = []
	for child in body.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			shapes.append(child)
	return {
		"node": node, "shape": body, "body": body, "last": Transform2D(), "size3": Vector3.ONE,
		"half_height": 0.0, "offset": Vector2.ZERO, "rigid": body if body is RigidBody2D else null,
		"asleep": false, "shown": true, "shapes": shapes,
		"update": Callable(
			node,
			&"mirror_update",
		) if node.has_method(&"mirror_update") else Callable(),
	}


## Whether `row` is the mesh of a body that has collision shapes and every one is disabled (a
## character seated in a vehicle): such a mesh has no shape of its own to be disabled. A body with
## no shape, and a row of a shape's own proxy, is not.
static func shapes_all_off(row: Dictionary) -> bool:
	var any := false
	for shape: Variant in row.get("shapes", []):
		if not is_instance_valid(shape) or (shape as Node).is_queued_for_deletion():
			continue
		any = true
		if (shape as Node).get("disabled") != true:
			return false
	return any


## The slab of a floor (`floor_node`, a Node2D with a `size` and a `color`): a row like `make`'s,
## placed once, never followed.
func make_floor(floor_node: Node2D) -> Dictionary:
	var size: Vector2 = floor_node.get("size")
	var unit := RenderConfig.unit
	var colour: Variant = floor_node.get("color")
	var node := _instance(_box, colour if colour is Color else MirrorConfig.floor_color)
	var thick := MirrorConfig.floor_thickness * unit
	node.transform = Transform3D(
		Basis.from_scale(Vector3(size.x * unit, thick, size.y * unit)),
		PlanSpace.lift(floor_node.global_position + size * 0.5) + Vector3(0.0, -thick * 0.5, 0.0),
	)
	return { "node": node, "body": floor_node, "shape": null }


## A 2D body's transform as its proxy's: the shape's centre on the ground plane (x, 0, y) times the
## scale, lifted by half the height, turned about the up axis by the 2D turn (a 2D turn clockwise on
## a y-down screen is a turn of -angle about +y), scaled to the shape.
static func lift(xf: Transform2D, row: Dictionary) -> Transform3D:
	var centre := xf * (row["offset"] as Vector2)
	var turned := Basis(Vector3.UP, -xf.get_rotation()) * Basis.from_scale(row["size3"])
	return Transform3D(turned, PlanSpace.lift(centre) + Vector3(0.0, row["half_height"], 0.0))


## The rectangle a shape covers in its own frame (centred rectangles and circles, the bounding box
## of a convex polygon or a capsule); empty for a shape the mirror does not know.
static func rect_of(shape: Shape2D) -> Rect2:
	if shape is RectangleShape2D:
		return Rect2(-(shape as RectangleShape2D).size * 0.5, (shape as RectangleShape2D).size)
	if shape is CircleShape2D:
		var r := (shape as CircleShape2D).radius
		return Rect2(Vector2(-r, -r), Vector2(r, r) * 2.0)
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


## How tall a body of `kind` over `rect` (its shape's footprint) stands, in 2D pixels.
static func height_of(_body: Node, kind: StringName, rect: Rect2) -> float:
	match kind:
		CHARACTER:
			return MirrorConfig.character_height
		DOOR:
			return MirrorConfig.door_height
		WALL:
			return MirrorConfig.wall_height
		VEHICLE:
			return MirrorConfig.vehicle_height
	var narrow := minf(rect.size.x, rect.size.y)
	return clampf(
		narrow * MirrorConfig.furniture_ratio,
		minf(narrow, MirrorConfig.furniture_min),
		MirrorConfig.furniture_max,
	)


## The colour of `body`: its `art_color` or `color`, else by kind (a door's, a character's by its
## `faction` name's hash, so a side reads as one colour) or the hue its node name hashes to.
static func colour_of(body: Node, kind: StringName) -> Color:
	for key in ["art_color", "color"]:
		var value: Variant = body.get(key)
		if value is Color:
			return value
	if kind == DOOR:
		return MirrorConfig.door_color
	if kind == CHARACTER:
		var faction := str(body.get("faction"))
		if faction.is_empty() or faction == "<null>":
			return MirrorConfig.character_color
		return _hashed(faction)
	return _hashed(String(body.name).rstrip("0123456789_"))


## The colour a name hashes to, a hue at the config's saturation and value.
static func _hashed(text: String) -> Color:
	var hue := float(absi(hash(text)) % 100) / 100.0
	return Color.from_hsv(hue, MirrorConfig.hashed_saturation, MirrorConfig.hashed_value)


## The shared capsule of `radius` and `height`, made once.
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


## A mesh node of `mesh` in the shared material, `colour` its own, casting a shadow.
func _instance(mesh: Mesh, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material
	node.set_instance_shader_parameter(&"base_color", colour)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return node
