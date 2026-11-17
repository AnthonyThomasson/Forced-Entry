class_name DoorMesh
extends Node3D
## Objects domain, the 3D mesh of a house door (`structure_meshes.gd`, `domain-art/meshes.md`): a
## frame-less leaf as thick as the 2D leaf and as long as its collider, `door_height` tall, wearing
## the door painter's flat art over its footprint (`StructureSkin`: planks, panels, rivets, panes on
## top, the art's edge down the face), with a handle at the latch end (its own plain child). A
## glass-panel door has a solid sill, a frame and a lighter pane (no pane once shattered). The
## door's body turns about its hinge in 2D, so the leaf's swing is the mirror following the body's
## transform: the leaf is built at the body's origin (the middle of the leaf, its x axis hinge to
## latch). A knocked-down door lies flat: the node swaps the standing leaf for a slab the size of
## the 2D one (`mirror_update`, which also
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
	node._skin(door)
	node._leaf.add_child(_handle(door))
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
	var shattered := broken != _broken
	_down = down
	_broken = broken
	_leaf.mesh = _standing(door)
	_skin(door)
	if down and _lying == null:
		_lie(door)
	elif shattered and _lying != null:
		_dress_lying(door)
	_show()


## Lay the leaf's flat art on the standing leaf (again when its panes shatter).
func _skin(door: Node2D) -> void:
	var texture := _art(door, false)
	if texture != null:
		MeshNodes.textured(_leaf, texture, Rect2(-_leaf_size(door) * 0.5, _leaf_size(door)))


## The door painter's flat art of the leaf standing or lying `fallen`: its `leaf_size` or the 2D
## fallen slab's size, in the look's colour, finish and style; null for a body with no look.
static func _art(door: Node2D, fallen: bool) -> Texture2D:
	var look: Object = door.get("look")
	var size := _fallen_size(door) if fallen else _leaf_size(door)
	return ObjectArt.flat("door", size, look.get("color"), look.call(&"art_opts", fallen))


## The 2D leaf's size (its length from hinge to latch, its thickness).
static func _leaf_size(door: Node2D) -> Vector2:
	return door.call(&"leaf_size")


## The knocked-down door's footprint: the 2D fallen slab's length and the doorway's width.
static func _fallen_size(door: Node2D) -> Vector2:
	return Vector2(DoorConfig.fallen_length, float(door.get("width")))


## Add the slab of the door knocked down (made when it first falls: few doors ever do).
func _lie(door: Node2D) -> void:
	_lying = MeshNodes.instance(_lying_shape(door), Color.WHITE, false)
	_dress_lying(door)
	add_child(_lying)


## The slab's mesh and art as the door is now: its panes gone when they shattered, the art mirrored
## when the door lies flipped (`DoorLook.flipped`).
func _dress_lying(door: Node2D) -> void:
	_lying.mesh = _lying_shape(door)
	var texture := _art(door, true)
	if texture == null:
		return
	if _flipped(door):
		texture = StructureSkin.flipped(texture)
	var size := _fallen_size(door)
	MeshNodes.textured(_lying, texture, Rect2(-size * 0.5, size))


## Whether the door lies flipped: mirrored across the leaf's length (`DoorLook.flipped`).
static func _flipped(door: Node2D) -> bool:
	var look: Variant = door.get("look")
	return look is Object and bool((look as Object).get("flipped"))


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


## The mesh of the slab of a door knocked down: the 2D door's fallen footprint, a leaf thick, white
## (the art colours it). A glass door whose panes shattered is its frame and bars only, so the
## floor shows through the empty panes as in 2D.
static func _lying_shape(door: Node2D) -> Mesh:
	var size := _fallen_size(door)
	var open := _panes_gone(door)
	var key := MeshCache.key(
		"door_lying",
		size,
		Color.WHITE,
		{ "thick": DoorConfig.leaf_thickness, "open": open, "pane": ObjectArtDoorConfig.pane_px },
	)
	return MeshCache.fetch(key, func() -> Mesh: return _lying_mesh(size, open))


## Whether `door` is a glass door whose panes have shattered.
static func _panes_gone(door: Node2D) -> bool:
	var look: Object = door.get("look")
	return String(look.get("material")) == "glass" and _broken_of(door)


## A slab `size` px centred on the origin, a leaf thick, white. `open`: only the frame round the
## panes and the bars between them (`door_painter._panes`: a frame of 6 art px, the panes
## `pane_px` wide in columns).
static func _lying_mesh(size: Vector2, open: bool) -> Mesh:
	var kit := MeshKit.new()
	var thick := DoorConfig.leaf_thickness
	if not open:
		kit.box(MeshKit.volume(Rect2(-size * 0.5, size), 0.0, thick), Color.WHITE)
		return kit.build()
	var px := ArtCanvasConfig.pixel_size
	var frame := 6.0 * px
	var area := Rect2(Vector2.ONE * frame, size - Vector2.ONE * frame * 2.0)
	var bars: Array[Rect2] = [
		Rect2(0.0, 0.0, size.x, frame),
		Rect2(0.0, size.y - frame, size.x, frame),
		Rect2(0.0, frame, frame, area.size.y),
		Rect2(size.x - frame, frame, frame, area.size.y),
	]
	var columns := maxi(1, int(area.size.x / px / float(ObjectArtDoorConfig.pane_px)))
	var width := int(area.size.x / px / float(columns))
	for k in columns - 1:
		bars.append(Rect2(area.position.x + (k * width + width - 1) * px, frame, px, area.size.y))
	for bar in bars:
		kit.box(MeshKit.volume(Rect2(bar.position - size * 0.5, bar.size), 0.0, thick), Color.WHITE)
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
