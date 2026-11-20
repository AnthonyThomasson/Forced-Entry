class_name DoorMesh
extends Node3D
## Objects domain, the 3D mesh of a house door (`structure_meshes.gd`, `domain-art/meshes.md`): a
## frame-less leaf as thick as the 2D leaf and as long as its collider, `door_height` tall, wearing
## the door painter's flat art over its footprint (`StructureSkin`: planks, panels, rivets, panes on
## top, the art's edge down the face), with a handle at the latch end (its own plain child). A
## glass-panel door has a solid sill, a frame and a lighter pane (no pane once shattered). The
## door's body turns about its hinge, so the leaf's swing is the mirror following the body's
## transform: the leaf is built at the body's origin (the middle of the leaf, its x axis hinge to
## latch, its foot on the floor). A knocked-down door is the same leaf, lying as its free body does:
## the mesh then stands on that body, tilt and all (`MeshCarrier`, `TwinSpace.leader_of`).
## `mirror_update` shows a pane shattering.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")

## The leaf.
var _leaf: MeshInstance3D
## Whether the panes show as shattered.
var _broken := false


## The node a `door` (a `Door`) is shown by.
static func build(door: Node2D) -> Node3D:
	if not (door.get("look") is Object and door.has_method(&"is_down")):
		return null
	var node := DoorMesh.new()
	node.name = "DoorMesh"
	node._leaf = MeshNodes.instance(_standing(door))
	node._skin(door)
	node._leaf.add_child(_handle(door))
	node._broken = _broken_of(door)
	node.add_child(node._leaf)
	return node


## Follow the door's state: lose the glass when the panes shatter.
func mirror_update(door: Node2D) -> void:
	var broken := _broken_of(door)
	if broken == _broken:
		return
	_broken = broken
	_leaf.mesh = _standing(door)
	_skin(door)


## Lay the leaf's flat art on the standing leaf (again when its panes shatter).
func _skin(door: Node2D) -> void:
	var texture := _art(door)
	if texture != null:
		MeshNodes.textured(_leaf, texture, Rect2(-_leaf_size(door) * 0.5, _leaf_size(door)))


## The door painter's flat art of the leaf: its `leaf_size`, in the look's colour, finish and style;
## null for a body with no look.
static func _art(door: Node2D) -> Texture2D:
	var look: Object = door.get("look")
	return ObjectArt.flat("door", _leaf_size(door), look.get("color"), look.call(&"art_opts"))


## The 2D leaf's size (its length from hinge to latch, its thickness).
static func _leaf_size(door: Node2D) -> Vector2:
	return door.call(&"leaf_size")


## Whether `door`'s panes have shattered.
static func _broken_of(door: Node2D) -> bool:
	var look: Variant = door.get("look")
	return look is Object and bool((look as Object).get("broken"))


## The colour `door`'s leaf is drawn in.
static func _colour(door: Node2D) -> Color:
	return ObjectArt.drawn_color((door.get("look") as Object).get("color"))


## The standing leaf's mesh: shared by every door of its size, material and state.
static func _standing(door: Node2D) -> Mesh:
	var size := _leaf_size(door)
	var look: Object = door.get("look")
	var glass := String(look.get("material")) == "glass"
	var broken := _broken_of(door)
	var opts := _tuning()
	opts["glass"] = glass
	opts["broken"] = broken
	var key := MeshCache.key("door", size, Color.WHITE, opts)
	return MeshCache.fetch(key, func() -> Mesh: return _leaf_mesh(size, glass, broken))


## Every value the leaf's shape reads, so a change of any is another mesh.
static func _tuning() -> Dictionary:
	return {
		"height": ObjectStructureMeshConfig.door_height,
		"thick": DoorConfig.leaf_thickness,
		"handle_at": ObjectStructureMeshConfig.door_handle_height,
		"handle": [
			ObjectStructureMeshConfig.door_handle_length,
			ObjectStructureMeshConfig.door_handle_thick,
			ObjectStructureMeshConfig.door_handle_proud,
		],
		"sill": ObjectStructureMeshConfig.door_sill,
		"frame": ObjectStructureMeshConfig.door_frame,
		"glass_thick": ObjectStructureMeshConfig.door_glass_thickness,
	}


## The leaf centred on the origin, hinge at `-x`, latch at `+x`, white: the flat art colours it.
static func _leaf_mesh(size: Vector2, glass: bool, broken: bool) -> Mesh:
	var kit := MeshKit.new()
	if glass:
		_glass_leaf(kit, size, broken)
	else:
		kit.box(
			MeshKit.volume(Rect2(-size * 0.5, size), 0.0, ObjectStructureMeshConfig.door_height),
			Color.WHITE,
		)
	return kit.build()


## The handle at the latch end, a lighter tone of the leaf's colour standing off each face, a plain
## (untextured) child of the leaf: shared by every door of its size and colour.
static func _handle(door: Node2D) -> MeshInstance3D:
	var size := _leaf_size(door)
	var colour := _colour(door)
	var key := MeshCache.key("door_handle", size, colour, _tuning())
	return MeshNodes.instance(
		MeshCache.fetch(key, func() -> Mesh: return _handle_mesh(size, colour))
	)


## The handle's solid: it spans the leaf's thickness and a little over.
static func _handle_mesh(size: Vector2, colour: Color) -> Mesh:
	var half := size * 0.5
	var length := ObjectStructureMeshConfig.door_handle_length
	var proud := ObjectStructureMeshConfig.door_handle_proud
	var handle := Rect2(
		Vector2(half.x - ObjectStructureMeshConfig.door_frame - length, -half.y - proud),
		Vector2(length, size.y + proud * 2.0),
	)
	var kit := MeshKit.new()
	kit.box(
		MeshKit.volume(
			handle,
			ObjectStructureMeshConfig.door_handle_height,
			ObjectStructureMeshConfig.door_handle_thick,
		),
		MeshKit.tone(colour, &"highlight"),
	)
	return kit.build()


## A glass-panel door's leaf: a solid sill, the frame (two stiles and a top rail) over it and,
## unless `broken`, the glass in the frame (the art draws the panes on top). Shattered, it is the
## two stiles alone (no sill, no rail over the empty panes), so the floor shows through as in 2D.
static func _glass_leaf(kit: MeshKit, size: Vector2, broken: bool) -> void:
	var cfg := ObjectStructureMeshConfig
	var half := size * 0.5
	var above := cfg.door_height - cfg.door_sill
	var stile := Vector2(cfg.door_frame, size.y)
	var base := 0.0 if broken else cfg.door_sill
	for x in [-half.x, half.x - cfg.door_frame]:
		var rect := Rect2(Vector2(x, -half.y), stile)
		kit.box(MeshKit.volume(rect, base, cfg.door_height - base), Color.WHITE)
	if broken:
		return
	kit.box(MeshKit.volume(Rect2(-half, size), 0.0, cfg.door_sill), Color.WHITE)
	var inner := size.x - cfg.door_frame * 2.0
	var rail := Rect2(Vector2(-half.x + cfg.door_frame, -half.y), Vector2(inner, size.y))
	kit.box(MeshKit.volume(rail, cfg.door_height - cfg.door_frame, cfg.door_frame), Color.WHITE)
	var pane := Rect2(
		Vector2(-half.x + cfg.door_frame, -cfg.door_glass_thickness * 0.5),
		Vector2(inner, cfg.door_glass_thickness),
	)
	kit.box(MeshKit.volume(pane, cfg.door_sill, above - cfg.door_frame), Color.WHITE)
