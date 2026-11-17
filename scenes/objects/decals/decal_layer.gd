extends Node
## A batch of pixel-art marks placed where they lie (Objects domain): a room's wear, the street's
## marks and litter. It draws nothing: the 3D render lays each as a decal (`wear_mesh.gd`) from the
## list `decals()` holds, in the frame of the node that owns the layer. No collider, no nav change,
## registers nothing.

## `[texture, rect, kind]` per mark, in the layer's frame.
var _decals: Array = []


## Name the layer `layer_name`; returns it.
func setup(layer_name: String) -> Node:
	name = layer_name
	return self


## Keep `texture` (the flat albedo the decal shows) for `rect` (the layer's frame; at
## ArtCanvasConfig.pixel_size one texel per art pixel). `kind` says what the mark is (`crack`,
## `slab`, `crossing`: the 3D render lays each by its kind, `wear_mesh.gd`).
func add(texture: Texture2D, rect: Rect2, kind := &"") -> void:
	if texture:
		_decals.append([texture, rect, kind])


## The marks, `[texture, rect, kind]` each, in the order they are laid (a copy of the list, the
## marks themselves shared).
func decals() -> Array:
	return _decals.duplicate()


## How many marks the layer holds.
func count() -> int:
	return _decals.size()
