class_name FurnitureArt
extends RefCounted
## Objects domain, the 2D art of a furniture piece worn by its 3D mesh (#193 phase 2b): the flat
## (unlit, albedo) render of the piece's painter, projected straight down on the mesh by Art's
## `MeshNodes.textured` (`domain-art/textured-toon.md`), so the 3D piece reads as the 2D art.
##
## A piece's mesh is built already turned to its facing (`FurnitureSpec.kit`), so the art, painted
## canonical (`ObjectArt.flat`: front +y, one texture whatever the facing), is turned the same
## quarter turns here and its rect turned with it; the texture stays small and is cached per
## piece look (`of`), never made per frame. A piece with an overhang (a streetlight's arm and head,
## an awning) gets the footprint's art and the overhang's art on one canvas covering both.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")

## The dressed art by look (`_key`): `{ texture, rect }`.
static var _dressed: Dictionary = {}


## The art `spec`'s mesh wears: `{ texture: Texture2D, rect: Rect2 }` (`rect` in px, the footprint
## and overhang in the mesh's own frame, turned to the facing), or `{}` for a piece with no art.
static func of(spec: FurnitureSpec) -> Dictionary:
	if spec.art == "" or not ObjectArt.PAINTERS.has(spec.art):
		return {}
	var key := _key(spec)
	var found: Variant = _dressed.get(key)
	if found != null:
		return found
	var made := _make(spec)
	_dressed[key] = made
	return made


## The textures wearing furniture now, one per piece look (a test reads it).
static func count() -> int:
	return _dressed.size()


## Every `PixelArt.warm` request the art of a piece of definition `art` needs for the canonical
## footprints `sizes` and `colors` (and, for a piece with an overhang, that part's `overhang` size
## in either orientation): what `of` will paint, so a district's pre-warm has painted it by the time
## it is built.
static func requests(art: String, sizes: Array, colors: Array, opts: Dictionary,
		overhang := Vector2.ZERO) -> Array:
	var out: Array = []
	if not ObjectArt.PAINTERS.has(art):
		return out
	var parts: Array = []
	for size: Vector2 in sizes:
		parts.append([size, opts])
	if overhang != Vector2.ZERO:
		var part := opts.merged({ "part": "overhang" }, true)
		parts.append([overhang, part])
		parts.append([Vector2(overhang.y, overhang.x), part])
	for part: Array in parts:
		for color: Color in colors:
			out.append(ObjectArt.flat_request(art, part[0], color, part[1]))
	return out


## The cache key of `spec`'s look: everything its art is painted from.
static func _key(spec: FurnitureSpec) -> String:
	return var_to_str([
		spec.art, spec.size, spec.paint, spec.opts, spec.material, spec.overhang, spec.turns,
		ArtCanvasConfig.pixel_size,
	])


## The art of `spec`: the flat render, turned with the piece, one canvas when it has an overhang.
static func _make(spec: FurnitureSpec) -> Dictionary:
	var opts := spec.opts.merged({ "material": spec.material }, true)
	var foot := Rect2(-spec.size * 0.5, spec.size)
	var texture := ObjectArt.flat(spec.art, spec.size, spec.paint, opts)
	if texture == null:
		return {}
	if not spec.overhang.has_area() and spec.turns == 0:
		return { "texture": texture, "rect": foot }
	var rect := foot
	# A copy: the headless renderer hands back the cached texture's own image, and it is turned.
	var image: Image = texture.get_image().duplicate()
	if spec.overhang.has_area():
		var over := ObjectArt.flat(
			spec.art, spec.overhang.size, spec.paint, opts.merged({ "part": "overhang" }, true)
		)
		rect = foot.merge(spec.overhang)
		image = _joined(rect, [[foot, image], [spec.overhang, over.get_image().duplicate()]])
	var turned := _turned(image, rect, spec.turns)
	return { "texture": ImageTexture.create_from_image(turned["image"]), "rect": turned["rect"] }


## One canvas over `rect` (px) with each `[area, image]` of `parts` drawn on its `area`, in order.
static func _joined(rect: Rect2, parts: Array) -> Image:
	var step := maxf(ArtCanvasConfig.pixel_size, 0.01)
	var out := Image.create(
		roundi(rect.size.x / step), roundi(rect.size.y / step), false, Image.FORMAT_RGBA8
	)
	for part: Array in parts:
		var image: Image = part[1]
		image.convert(Image.FORMAT_RGBA8)
		var at := Vector2i(((part[0] as Rect2).position - rect.position) / step)
		out.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
	return out


## `image` (covering `rect`) and `rect` turned `turns` clockwise quarter turns about the origin,
## as `PixelArt.render` turns a facing piece's art.
static func _turned(image: Image, rect: Rect2, turns: int) -> Dictionary:
	var out := rect
	for _i in turns:
		image.rotate_90(CLOCKWISE)
		out = Rect2(Vector2(-out.end.y, out.position.x), Vector2(out.size.y, out.size.x))
	return { "image": image, "rect": out }
