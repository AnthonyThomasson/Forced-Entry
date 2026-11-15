class_name StructureSkin
extends RefCounted
## Objects domain, the 2D art on the structure's 3D meshes (#193 phase 2b,
## `domain-objects/structure-meshes.md`):
## the floor's, the street's and the wall's tile and the door's leaf, painted flat
## (`ObjectArt.flat`: no baked light, canonical, one texture per piece kind and look, cached by
## `PixelArt`) and laid on a mesh by `MeshNodes.textured`, which projects it straight down in the
## mesh's own frame. The texture is made once per kind and look, never per frame; a mesh with no art
## keeps the toon's plain material (and the colour it was built in).

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")

## A wall tile turned a quarter, for a wall that runs along z, by the tile it was turned from.
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


## The tile of `wall`'s cap (a `Wall` with an art): x along the wall, y across it, painted flat, or
## the same turned a quarter (`vertical`) for a wall along z. Null when the wall has no art.
static func wall_tile(wall: Node2D, vertical := false) -> Texture2D:
	var art := String(wall.get("art"))
	if art == "":
		return null
	var size := Vector2(ObjectArtWallConfig.tile_px, float(wall.get("wall_thickness")))
	var texture := ObjectArt.flat(art, size, wall.get("art_color"), wall.get("art_opts"))
	if texture == null or not vertical:
		return texture
	if not _turned.has(texture):
		# A copy: the cached texture's own image is shared with every other user of the tile.
		var image := texture.get_image().duplicate() as Image
		image.rotate_90(CLOCKWISE)
		_turned[texture] = ImageTexture.create_from_image(image)
	return _turned[texture]


## The size in px a flat `texture` covers (one art pixel `ArtCanvasConfig.pixel_size` px).
static func extent(texture: Texture2D) -> Vector2:
	return texture.get_size() * ArtCanvasConfig.pixel_size
