class_name DecalFactory
## Objects-domain factory (interface 2): turns where a decal goes and what it says (World-Gen's
## placement) into a draw-only node on the floor: no collider, no nav change, registers nothing.
## World-Gen never draws, and never touches the node's fields.
##
## `stencil` is a floor stencil: words painted in pixel stencil letters inside a hazard-stripe
## border over an area of floor (stencil_painter.gd). It is painted upright on a canvas the size of
## the area, so it reads the same whichever way the building it lies in is turned.
##
## `shadow` is the long hard shadow a tall tower throws across the street: its footprint dragged
## away from the art light (shadow_painter.gd), on the street's light layer, beneath characters.

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


## Lay the shadow of a tower whose footprint is `foot` (in `parent`'s space) under `parent`, named
## `decal_name`, and return it (a `Sprite2D`). `spec`: `length` how far the footprint is dragged
## away from the art light (px; `PixelArt.away_from_light` in `parent`'s frame). The footprint
## itself is left clear. It draws over the street's floors and under whatever lies or stands on them
## (`DrawLayers.RUG`), lit only by the street's lights (`LightMasks.STREET`).
static func shadow(foot: Rect2, spec: Dictionary, decal_name: String, parent: Node2D) -> Node2D:
	var length := int(spec.get("length", 0))
	var drag := (PixelArt.away_from_light(parent) * float(length)).round()
	var area := foot.merge(Rect2(foot.position + drag, foot.size))
	var sprite := Sprite2D.new()
	sprite.name = decal_name
	sprite.centered = false
	sprite.position = area.position
	sprite.z_index = DrawLayers.RUG
	sprite.light_mask = LightMasks.STREET
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = ObjectArt.texture(
		"shadow",
		area.size,
		Color.WHITE,
		Vector2.DOWN,
		{
			"foot": Rect2i(Rect2(foot.position - area.position, foot.size)),
			"length": length,
		},
	)
	parent.add_child(sprite)
	return sprite
