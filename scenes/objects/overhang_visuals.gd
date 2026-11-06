extends Node2D
## Objects domain: draws an EnvironmentObject's OVERHANG, the overhead part of a piece that reaches
## out beyond its footprint (a streetlight's arm and lamp head over the road), as the child
## `Overhang`. It hangs above whoever walks under it: drawn at
## `ObjectArtLayerConfig.overhang_z_index` (`DrawLayers.OVERHEAD`, absolute), over the living and a
## vehicle's roof, and it has no collider (only the piece's footprint is solid). Its art is the
## piece's own painter with `part: "overhang"` in the options, at the overhang's `size` (across x
## out, in the canonical frame), centred `reach` px from the piece's centre along its facing. What
## in it gives light (a lens, a sign's tube) is drawn again over it by a child `Emissive` layer
## (emissive_layer.gd), as on the piece. With `fade_under: true` one shared watcher reads the
## character group and steps every fading overhang; the overhang itself has no frame callback.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
const EmissiveLayer = preload("res://scenes/objects/emissive_layer.gd")

## One watcher per scene tree; weak references keep a closed tree or a torn-down world alive
## nowhere.
static var _watchers := {}

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
## Actual alpha writes made by the shared watcher (a test read; zero at rest).
var fade_writes := 0


func _ready() -> void:
	set_process(false)
	if _fades:
		_watch(self)


func _draw() -> void:
	if _art:
		draw_texture_rect(_art, _rect, false)


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


## Step the fade from the watcher's already-fetched character list, writing only a changed alpha.
func _fade_step(characters: Array, delta: float) -> void:
	var goal := ObjectFadeConfig.alpha if _character_under(characters) else 1.0
	var speed := (1.0 - ObjectFadeConfig.alpha) / ObjectFadeConfig.seconds
	var next := move_toward(modulate.a, goal, speed * delta)
	if next == modulate.a:
		return
	modulate.a = next
	fade_writes += 1


## Whether any of `characters` stands inside the area the overhang draws.
func _character_under(characters: Array) -> bool:
	var area := get_global_transform() * _rect
	for body: Node in characters:
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


## Register `overhang` with the tree's one fade watcher, creating it on demand.
static func _watch(overhang: Node2D) -> void:
	var tree := overhang.get_tree()
	var key := tree.get_instance_id()
	var watcher: FadeWatcher
	if _watchers.has(key):
		watcher = (_watchers[key] as WeakRef).get_ref()
	if watcher == null:
		watcher = FadeWatcher.new()
		watcher.name = "OverhangFadeWatcher"
		_watchers[key] = weakref(watcher)
		tree.root.add_child.call_deferred(watcher)
	watcher.watch(overhang)


## The only per-frame callback for fading overhangs: one character-group read for all of them.
class FadeWatcher extends Node:
	## Live overhangs, held weakly so world teardown needs no unregister pass.
	var _overhangs: Array[WeakRef] = []


	## Step every live overhang; sleep while no world has one.
	func _process(delta: float) -> void:
		var characters := get_tree().get_nodes_in_group(&"characters")
		for i in range(_overhangs.size() - 1, -1, -1):
			var overhang = _overhangs[i].get_ref()
			if overhang == null:
				_overhangs.remove_at(i)
				continue
			overhang._fade_step(characters, delta)
		if _overhangs.is_empty():
			set_process(false)


	## Add an overhang and wake the watcher.
	func watch(overhang: Node2D) -> void:
		_overhangs.append(weakref(overhang))
		set_process(true)
