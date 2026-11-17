class_name StructureSkin
extends RefCounted
## Objects domain, the 2D art on the structure's 3D meshes
## (`domain-objects/structure-meshes.md`):
## the floor's, the street's and the wall's tile and the door's leaf, painted flat
## (`ObjectArt.flat`: no baked light, canonical, one texture per piece kind and look, cached by
## `PixelArt`) and laid on a mesh by `MeshNodes.textured`, which projects it straight down in the
## mesh's own frame. The texture is made once per kind and look, never per frame; a mesh with no art
## keeps the toon's plain material (and the colour it was built in).

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")

## The turned copies of a tile, `{ texture: { turn: Texture2D } }`.
static var _turned := {}


## Lay the floor `floor_node`'s tile (its art, colour, material and options, a `Floor`) on `node`,
## repeated over the whole slab from the floor's `tile_offset`, so a neighbour sharing a `tile_from`
## shares the grid. `node`'s frame has the floor's corner as its origin.
static func tile(node: GeometryInstance3D, floor_node: Node2D) -> void:
	var colour: Color = floor_node.get("color")
	var texture := ObjectArt.tile_flat(
		String(floor_node.get("art")),
		colour,
		String(floor_node.get("floor_material")),
		floor_node.get("art_opts"),
	)
	if texture == null:
		MeshNodes.textured(node, null, Rect2(), { "tint": ObjectArt.drawn_color(colour) })
		return
	var offset: Vector2 = floor_node.get("tile_offset")
	var rect := Rect2(-offset, texture.get_size() * ArtCanvasConfig.pixel_size)
	MeshNodes.textured(node, texture, rect, { "tiled": true })


## How a wall segment `seg` (`[a, b]` in the wall's frame) wears the cap tile: `{ texture, rect }`
## for `MeshNodes.textured` (`tiled`), `rect` in px in the wall's frame; empty for a wall with no
## art. The tile runs along a to b and across the thickness by `dir.orthogonal()`, so it is
## oriented to match: a wall running +x wears it flipped
## across, -x flipped along, +z transposed, -z transposed and turned half round. The texture is
## made once per tile and direction.
static func wall_skin(wall: Node2D, seg: PackedVector2Array) -> Dictionary:
	var art := String(wall.get("art"))
	if art == "":
		return {}
	var size := Vector2(ObjectArtWallConfig.tile_px, float(wall.get("wall_thickness")))
	var cap := ObjectArt.flat(art, size, wall.get("art_color"), wall.get("art_opts"))
	if cap == null:
		return {}
	var along := cap.get_size() * ArtCanvasConfig.pixel_size
	var half := along.y * 0.5
	var dir := seg[1] - seg[0]
	var a := seg[0]
	if absf(dir.x) >= absf(dir.y):
		var across := &"flip_y" if dir.x >= 0.0 else &"flip_x"
		return {
			"texture": _variant(cap, across),
			"rect": Rect2(a.x, a.y - half, along.x, along.y),
		}
	var down := &"transpose" if dir.y >= 0.0 else &"transpose_flip"
	return { "texture": _variant(cap, down), "rect": Rect2(a.x - half, a.y, along.y, along.x) }


## `texture` turned across (`&"flip_y"`), along (`&"flip_x"`), transposed (`&"transpose"`) or
## transposed and turned half round (`&"transpose_flip"`): a copy, made once per texture and turn
## (the cached texture's own image is shared with every other user of the tile).
static func _variant(texture: Texture2D, turn: StringName) -> Texture2D:
	if not _turned.has(texture):
		_turned[texture] = {}
	var made: Dictionary = _turned[texture]
	if not made.has(turn):
		made[turn] = ImageTexture.create_from_image(_turn(texture.get_image().duplicate(), turn))
	return made[turn]


## `image` turned as `_variant` says (in place).
static func _turn(image: Image, turn: StringName) -> Image:
	match turn:
		&"flip_y":
			image.flip_y()
		&"flip_x":
			image.flip_x()
		_:
			image.rotate_90(CLOCKWISE)
			image.flip_x()
			if turn == &"transpose_flip":
				image.flip_x()
				image.flip_y()
	return image


## `texture` mirrored across its length (the 2D leaf lying flipped), a copy made once.
static func flipped(texture: Texture2D) -> Texture2D:
	return _variant(texture, &"flip_y")


## The size in px a flat `texture` covers (one art pixel `ArtCanvasConfig.pixel_size` px).
static func extent(texture: Texture2D) -> Vector2:
	return texture.get_size() * ArtCanvasConfig.pixel_size
