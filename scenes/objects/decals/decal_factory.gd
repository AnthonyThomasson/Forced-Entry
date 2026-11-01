class_name DecalFactory
## Objects-domain factory (interface 2): turns where a decal goes and what it says (World-Gen's
## placement) into a draw-only node on the floor: no collider, no nav change, registers nothing.
## World-Gen never draws, and never touches the node's fields.
##
## `stencil` is a floor stencil: words painted in pixel stencil letters inside a hazard-stripe
## border over an area of floor (stencil_painter.gd). It is painted upright on a canvas the size of
## the area, so it reads the same whichever way the building it lies in is turned.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")


## Lay a floor stencil of `spec` over `rect` (in `parent`'s space) under `parent`, named
## `decal_name`, and return it (a `Sprite2D`). `spec`: `text` the words (one to a line) and `style`
## (`hazard`, the only one). It draws on the floor's rung, after the floors already laid, so over
## them.
static func stencil(rect: Rect2, spec: Dictionary, decal_name: String, parent: Node) -> Node2D:
	var sprite := Sprite2D.new()
	sprite.name = decal_name
	sprite.centered = false
	sprite.position = rect.position
	sprite.z_index = ObjectArtLayerConfig.floor_z_index
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = ObjectArt.texture(
		"stencil",
		rect.size,
		Color.WHITE,
		Vector2.DOWN,
		{ "text": spec.get("text", ""), "style": spec.get("style", "hazard") },
	)
	parent.add_child(sprite)
	return sprite
