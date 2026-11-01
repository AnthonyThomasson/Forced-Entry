extends Node2D
## Objects domain: draws an EnvironmentObject's OVERHANG, the overhead part of a piece that reaches
## out beyond its footprint (a streetlight's arm and lamp head over the road), as the child
## `Overhang`. It hangs above whoever walks under it: drawn at
## `ObjectArtLayerConfig.overhang_z_index` (`DrawLayers.OVERHEAD`, absolute), over the living and a
## vehicle's roof, and it has no collider (only the piece's footprint is solid). Its art is the
## piece's own painter with `part: "overhang"` in the options, at the overhang's `size` (across x
## out, in the canonical frame), centred `reach` px from the piece's centre along its facing. What
## in it gives light (a lens, a sign's tube) is drawn again over it by a child `Emissive` layer
## (emissive_layer.gd), as on the piece. Draw-only: it reads its parent's look fields and the
## definition's `overhang` (`{ size, reach }`). With `fade_under: true` in it the overhang fades to
## `ObjectFadeConfig.alpha` over `ObjectFadeConfig.seconds` while any node of the group `characters`
## stands inside the area it draws, and back to opaque over the same time when none does: its own
## `modulate`, so its glowing `Emissive` child fades with it.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
const EmissiveLayer = preload("res://scenes/objects/emissive_layer.gd")

## The overhang's pixel art (null for a piece without an art painter: nothing is drawn).
var _art: Texture2D
## Its light-giving pixels, or null when nothing in it gives light.
var _emissive: Texture2D
## The child drawing `_emissive` over the art (null without one).
var _emissive_layer: Node2D
## The area it draws, in its own frame (the piece's).
var _rect := Rect2()
## Whether it fades while a character stands under it (the definition's `fade_under`).
var _fades := false


func _ready() -> void:
	# A node with a `_process` starts processing as it enters the tree: only a fading one keeps it.
	set_process(_fades)


func _draw() -> void:
	if _art:
		draw_texture_rect(_art, _rect, false)


func _process(delta: float) -> void:
	var goal := ObjectFadeConfig.alpha if _character_under() else 1.0
	var speed := (1.0 - ObjectFadeConfig.alpha) / ObjectFadeConfig.seconds
	modulate.a = move_toward(modulate.a, goal, speed * delta)


## Make this the `Overhang` child of `piece` (an EnvironmentObject not yet in the tree, its look
## fields set) for the definition's `overhang` (`{ size: Vector2, reach: float }`), and return it.
func setup(piece: Node2D, overhang: Dictionary) -> Node2D:
	name = "Overhang"
	z_as_relative = false
	z_index = ObjectArtLayerConfig.overhang_z_index
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var facing: Vector2 = piece.look.facing
	var canonical: Vector2 = overhang.get("size", Vector2.ZERO)
	var size := Vector2(canonical.y, canonical.x) if absf(facing.x) > absf(facing.y) else canonical
	_rect = Rect2(facing * float(overhang.get("reach", 0.0)) - size * 0.5, size)
	if piece.look.art != "" and size.x > 0.0 and size.y > 0.0:
		var opts: Dictionary = piece.look.art_opts.merged(
			{ "part": "overhang", "material": piece.object_material },
			true,
		)
		_art = ObjectArt.texture(piece.look.art, size, piece.color, facing, opts)
		_emissive = ObjectArt.emissive(piece.look.art, size, piece.color, facing, opts)
		if _emissive:
			_emissive_layer = EmissiveLayer.new().setup(self)
	_fades = overhang.get("fade_under", false)
	piece.add_child(self)
	return self


## Whether any node of the group `characters` stands inside the area the overhang draws.
func _character_under() -> bool:
	var area := get_global_transform() * _rect
	for body: Node in get_tree().get_nodes_in_group(&"characters"):
		if body is Node2D and area.has_point((body as Node2D).global_position):
			return true
	return false


## The area the overhang draws, in its own frame (the piece's): what reaches out beyond the
## footprint.
func get_rect() -> Rect2:
	return _rect


## The `Emissive` child layer drawing `_emissive` (null when the overhang has nothing that gives
## light).
func emissive_layer() -> Node2D:
	return _emissive_layer


## Draw the light-giving pixels onto `layer` (the `Emissive` child) over the art.
func draw_emissive(layer: CanvasItem) -> void:
	layer.draw_texture_rect(_emissive, _rect, false)
