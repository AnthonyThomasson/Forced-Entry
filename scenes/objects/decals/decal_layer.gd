extends Node2D
## A batch of pixel-art marks drawn where they lie (Objects domain): a room's wear, the street's
## marks and litter. One node draws them all, once, on its own draw-order rung (`setup`); draw-only:
## no collider, no nav change, registers nothing.

## `[texture, rect, kind]` per mark, in the layer's frame.
var _decals: Array = []


func _draw() -> void:
	for d: Array in _decals:
		draw_texture_rect(d[0], d[1], false)


## Name the layer `layer_name` and put it on draw-order rung `z` (relative to its parent); returns
## it.
func setup(layer_name: String, z: int) -> Node2D:
	name = layer_name
	z_index = z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return self


## Draw `texture` stretched over `rect` (the layer's frame; at ArtCanvasConfig.pixel_size one texel
## per art pixel). `kind` says what the mark is (`crack`, `slab`, `crossing`: the 3D render lays
## each by its kind, `wear_mesh.gd`).
func add(texture: Texture2D, rect: Rect2, kind := &"") -> void:
	if texture:
		_decals.append([texture, rect, kind])
		queue_redraw()


## The marks, `[texture, rect, kind]` each, in the order they are drawn (a copy of the list, the
## marks themselves shared).
func decals() -> Array:
	return _decals.duplicate()


## How many marks the layer holds.
func count() -> int:
	return _decals.size()
