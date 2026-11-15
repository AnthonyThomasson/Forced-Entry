class_name DoorMesh
extends Node3D
## Objects domain, the 3D mesh of a house door (`structure_meshes.gd`, `domain-art/meshes.md`): a
## frame-less leaf as thick as the 2D leaf and as long as its collider, `door_height` tall, in the
## colour its painter draws, with a handle at the latch end. A glass-panel door has a solid sill, a
## frame and a lighter pane (no pane once shattered). The door's body turns about its hinge in 2D,
## so the leaf's swing is the mirror following the body's transform: the leaf is built at the body's
## origin (the middle of the leaf, its x axis hinge to latch). A knocked-down door lies flat: the
## node swaps the standing leaf for a slab the size of the 2D one (`mirror_update`, which also
## shows a pane shattering).

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")

## The standing leaf and the flat slab of a door knocked down (one is shown at a time).
var _leaf: MeshInstance3D
var _lying: MeshInstance3D
## What the leaf shows now: knocked down, panes shattered.
var _down := false
var _broken := false


## The node a `door` (a `Door`) is shown by.
static func build(door: Node2D) -> Node3D:
	if not (door.get("look") is Object and door.has_method(&"is_down")):
		return null
	var node := DoorMesh.new()
	node.name = "DoorMesh"
	node._leaf = MeshNodes.instance(_standing(door))
	node._down = bool(door.call(&"is_down"))
	node._broken = _broken_of(door)
	node._show()
	node.add_child(node._leaf)
	if node._down:
		node._lie(door)
	return node


## Follow the door's state: lie flat when it is knocked down, lose the glass when it shatters.
func mirror_update(door: Node2D) -> void:
	var down := bool(door.call(&"is_down"))
	var broken := _broken_of(door)
	if down == _down and broken == _broken:
		return
	_down = down
	_broken = broken
	_leaf.mesh = _standing(door)
	if down and _lying == null:
		_lie(door)
	_show()


## Add the slab of the door knocked down (made when it first falls: few doors ever do).
func _lie(door: Node2D) -> void:
	_lying = _flat(door)
	add_child(_lying)


## The leaf as the door is now (the standing one is shown unless it lies knocked down).
func _show() -> void:
	_leaf.visible = not _down
	if _lying != null:
		_lying.visible = _down


## Whether `door`'s panes have shattered.
static func _broken_of(door: Node2D) -> bool:
	var look: Variant = door.get("look")
	return look is Object and bool((look as Object).get("broken"))


## The colour `door`'s leaf is drawn in.
static func _colour(door: Node2D) -> Color:
	return ObjectArt.drawn_color((door.get("look") as Object).get("color"))


## The standing leaf's mesh: shared by every door of its size, colour, material and state.
static func _standing(door: Node2D) -> Mesh:
	var size: Vector2 = door.call(&"leaf_size")
	var colour := _colour(door)
	var look: Object = door.get("look")
	var glass := String(look.get("material")) == "glass"
	var broken := _broken_of(door)
	var opts := _tuning()
	opts["glass"] = glass
	opts["broken"] = broken
	var key := MeshCache.key("door", size, colour, opts)
	return MeshCache.fetch(key, func() -> Mesh: return _leaf_mesh(size, colour, glass, broken))


## The slab of a door knocked down: the 2D door's fallen footprint, flat, no shadow.
static func _flat(door: Node2D) -> MeshInstance3D:
	var size := Vector2(DoorConfig.fallen_length, float(door.get("width")))
	var colour := _colour(door)
	var key := MeshCache.key("door_lying", size, colour, { "thick": DoorConfig.leaf_thickness })
	return MeshNodes.instance(
		MeshCache.fetch(key, func() -> Mesh: return _lying_mesh(size, colour)),
		Color.WHITE,
		false,
	)


## A slab `size` px centred on the origin, a leaf thick, its face `colour`.
static func _lying_mesh(size: Vector2, colour: Color) -> Mesh:
	var kit := MeshKit.new()
	kit.box(
		MeshKit.volume(Rect2(-size * 0.5, size), 0.0, DoorConfig.leaf_thickness),
		MeshKit.tone(colour, &"dark"),
		colour,
	)
	return kit.build()


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
		"glass_tone": ObjectStructureMeshConfig.door_glass_tone,
	}


## The leaf centred on the origin, hinge at `-x`, latch at `+x`.
static func _leaf_mesh(size: Vector2, colour: Color, glass: bool, broken: bool) -> Mesh:
	var kit := MeshKit.new()
	var edge := MeshKit.tone(colour, &"dark")
	var half := size * 0.5
	if glass:
		_glass_leaf(kit, size, colour, broken)
	else:
		kit.box(
			MeshKit.volume(Rect2(-half, size), 0.0, ObjectStructureMeshConfig.door_height),
			edge,
			colour,
		)
	var length := ObjectStructureMeshConfig.door_handle_length
	var proud := ObjectStructureMeshConfig.door_handle_proud
	var handle := Rect2(
		Vector2(half.x - ObjectStructureMeshConfig.door_frame - length, -half.y - proud),
		Vector2(length, size.y + proud * 2.0),
	)
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
## unless `broken`, the glass in the frame.
static func _glass_leaf(kit: MeshKit, size: Vector2, colour: Color, broken: bool) -> void:
	var cfg := ObjectStructureMeshConfig
	var half := size * 0.5
	var edge := MeshKit.tone(colour, &"dark")
	var above := cfg.door_height - cfg.door_sill
	kit.box(MeshKit.volume(Rect2(-half, size), 0.0, cfg.door_sill), edge, colour)
	var stile := Vector2(cfg.door_frame, size.y)
	for x in [-half.x, half.x - cfg.door_frame]:
		kit.box(
			MeshKit.volume(Rect2(Vector2(x, -half.y), stile), cfg.door_sill, above), edge, colour
		)
	var inner := size.x - cfg.door_frame * 2.0
	var rail := Rect2(Vector2(-half.x + cfg.door_frame, -half.y), Vector2(inner, size.y))
	kit.box(MeshKit.volume(rail, cfg.door_height - cfg.door_frame, cfg.door_frame), edge, colour)
	if not broken:
		var pane := Rect2(
			Vector2(-half.x + cfg.door_frame, -cfg.door_glass_thickness * 0.5),
			Vector2(inner, cfg.door_glass_thickness),
		)
		kit.box(
			MeshKit.volume(pane, cfg.door_sill, above - cfg.door_frame),
			MeshKit.tone(colour, StringName(cfg.door_glass_tone)),
		)
