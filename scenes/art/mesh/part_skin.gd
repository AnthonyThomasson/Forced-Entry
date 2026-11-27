class_name PartSkin
extends RefCounted
## Art domain, many posed solids drawn as ONE mesh instance (interface 12): a body of parts that
## move against each other costs one draw, not one a part. `dress()` joins the shown parts' solids
## into one surface (each vertex tagged with its part) and their art into one atlas; `pose()` hands
## the parts' transforms to the material, and the vertex shader (`toon_parts.gdshader`) puts each
## vertex there, so a pose writes one material and no node. The picture is the textured toon's, part
## for part (the art is projected in each part's own frame). A dressed look (mesh and atlas) is
## shared by the skins whose parts are the same; the pose is each skin's own, so each has its own
## material. The mesh's vertices are the unposed solids: the caller gives `pose` the box they are
## in.

## The most parts a skin holds (the shader's arrays).
const MOST := 32
const SHADER := preload("res://scenes/art/post/toon_parts.gdshader")
## The narrowest atlas (texels).
const ATLAS_WIDTH := 128

## The looks alive, by what their parts are (`_key`), held weakly: a skin holds the look it wears.
static var _looks: Dictionary = {}
## Each solid's surface arrays, read back once, by the solid.
static var _arrays: Dictionary = {}
## The table's size at which the next new look drops the freed ones.
static var _prune_at := 64

## The one node that draws the parts, in the frame the parts' transforms are given in.
var node: MeshInstance3D
## The parts, as many as the skin was made with.
var parts: Array[MeshPart] = []
var _material: ShaderMaterial
## Each part's transform as the shader reads it: three basis columns and the origin.
var _pose := PackedVector3Array()
var _look: Look


## A skin of `count` parts (at most `MOST`), its node casting no shadow.
func _init(count: int) -> void:
	assert(count <= MOST, "PartSkin: more parts than the shader holds")
	for i in count:
		parts.append(MeshPart.new())
	_pose.resize(MOST * 4)
	ToonMaterial.shared()  # installs the globals the shader names
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	ToonMaterial.refresh_textured(_material)
	node = MeshNodes.instance(null, Color.WHITE, false)
	node.material_override = _material


## Take up the parts' solids, art, tints and visibility: call after any of them changed.
func dress() -> void:
	var key := _key()
	var held: Variant = _looks[key].get_ref() if _looks.has(key) else null
	if held == null:
		_prune()
		held = Look.new(parts)
		_looks[key] = weakref(held)
	_look = held
	node.mesh = _look.mesh
	_material.set_shader_parameter(&"atlas", _look.atlas)
	_material.set_shader_parameter(&"part_atlas", _look.regions)
	_material.set_shader_parameter(&"part_uv", _look.footprints)


## Put the parts where their transforms say; `bounds` is a box (the node's frame) every posed
## vertex is in, what the node is culled by.
func pose(bounds: AABB) -> void:
	var at := 0
	for part: MeshPart in parts:
		var t := part.transform
		_pose[at] = t.basis.x
		_pose[at + 1] = t.basis.y
		_pose[at + 2] = t.basis.z
		_pose[at + 3] = t.origin
		at += 4
	_material.set_shader_parameter(&"part_pose", _pose)
	node.custom_aabb = bounds


## What makes a look: each part's solid, visibility, tint and art.
func _key() -> Array:
	var key := []
	for part: MeshPart in parts:
		if not part.visible:
			key.append(0)
			continue
		var art := part.texture.get_instance_id() if part.texture != null else 0
		key.append_array(
			[part.mesh.get_instance_id(), part.tint, art, part.rect, part.cutout]
		)
	return key


## Before a new look: past `_prune_at` entries, drop the freed ones.
static func _prune() -> void:
	if _looks.size() < _prune_at:
		return
	for key: Variant in _looks.keys():
		if (_looks[key] as WeakRef).get_ref() == null:
			_looks.erase(key)
	_prune_at = maxi(64, _looks.size() * 2)


## The surface arrays of `solid`.
static func _surface(solid: Mesh) -> Array:
	if not _arrays.has(solid):
		_arrays[solid] = (solid as ArrayMesh).surface_get_arrays(0)
	return _arrays[solid]


## One dressed look: the joined mesh, the atlas of its art and where each part's art is in it.
class Look:
	var mesh := ArrayMesh.new()
	var atlas: Texture2D
	## Per part: where its art is in the atlas (x, y, width, height in texels; width 0: no art;
	## a negative height: a cut-out).
	var regions := PackedVector4Array()
	## Per part: the footprint its art covers in the part's frame (x, z, width, depth).
	var footprints := PackedVector4Array()
	## What the key names by instance id, held so no id is reused while the look lives.
	var _held: Array = []


	func _init(parts: Array[MeshPart]) -> void:
		regions.resize(PartSkin.MOST)
		footprints.resize(PartSkin.MOST)
		_join(parts)
		_pack(parts)


	## The shown parts' vertices in one surface: position and normal in the part's own frame, the
	## colour (the solid's times the tint, linear) and the part's index in the first custom channel.
	func _join(parts: Array[MeshPart]) -> void:
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = PackedVector3Array()
		out[Mesh.ARRAY_NORMAL] = PackedVector3Array()
		out[Mesh.ARRAY_CUSTOM0] = PackedFloat32Array()
		for index in parts.size():
			if parts[index].visible:
				_add(out, parts[index], index)
		var format := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, format)


	## `part`'s vertices put on the end of `out` (a surface's arrays), tagged `index`.
	func _add(out: Array, part: MeshPart, index: int) -> void:
		_held.append(part.mesh)
		var arrays := PartSkin._surface(part.mesh)
		assert(arrays[Mesh.ARRAY_INDEX] == null, "PartSkin: an indexed solid")
		out[Mesh.ARRAY_VERTEX].append_array(arrays[Mesh.ARRAY_VERTEX])
		out[Mesh.ARRAY_NORMAL].append_array(arrays[Mesh.ARRAY_NORMAL])
		var painted: Variant = arrays[Mesh.ARRAY_COLOR]
		var tint := part.tint.srgb_to_linear()
		for i in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			var colour := tint if painted == null else tint * (painted[i] as Color)
			out[Mesh.ARRAY_CUSTOM0].append_array([colour.r, colour.g, colour.b, float(index)])


	## The parts' art in one atlas, and where each part's art is in it.
	func _pack(parts: Array[MeshPart]) -> void:
		var images: Dictionary = {}
		for part: MeshPart in parts:
			if part.visible and part.texture != null and not images.has(part.texture):
				var image := part.texture.get_image()
				if image.get_format() != Image.FORMAT_RGBA8:
					image.convert(Image.FORMAT_RGBA8)
				images[part.texture] = image
				_held.append(part.texture)
		var places := _sheet(images)
		for index in parts.size():
			var part := parts[index]
			if not part.visible or part.texture == null:
				continue
			var place: Rect2i = places[part.texture]
			var tall := -place.size.y if part.cutout else place.size.y
			var rect := part.rect
			regions[index] = Vector4(place.position.x, place.position.y, place.size.x, tall)
			footprints[index] = Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)


	## The atlas made of `images` (by texture), a texture once however many parts wear it, in rows
	## (the tallest first); returns each one's place in it.
	func _sheet(images: Dictionary) -> Dictionary:
		var order := images.keys()
		order.sort_custom(func(a: Texture2D, b: Texture2D) -> bool:
			return images[a].get_height() > images[b].get_height())
		var width := PartSkin.ATLAS_WIDTH
		for texture: Texture2D in order:
			width = maxi(width, images[texture].get_width())
		var places: Dictionary = {}
		var at := Vector2i.ZERO
		var row := 0
		for texture: Texture2D in order:
			var size: Vector2i = images[texture].get_size()
			if at.x + size.x > width:
				at = Vector2i(0, at.y + row)
				row = 0
			places[texture] = Rect2i(at, size)
			at.x += size.x
			row = maxi(row, size.y)
		var sheet := Image.create(width, maxi(at.y + row, 1), false, Image.FORMAT_RGBA8)
		for texture: Texture2D in order:
			var place: Rect2i = places[texture]
			sheet.blit_rect(images[texture], Rect2i(Vector2i.ZERO, place.size), place.position)
		atlas = ImageTexture.create_from_image(sheet)
		return places
