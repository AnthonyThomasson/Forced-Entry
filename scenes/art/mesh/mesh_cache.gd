class_name MeshCache
extends RefCounted
## Art domain, the 3D mesh kit's cache (interface 12): the same inputs give the same `Mesh`
## resource, shared by every piece asking for it, as `PixelArt` shares a texture. Static, so it
## survives scene reloads. A key names what the mesh is made from the way `PixelArt`'s does
## (`key`): the builder's id, the footprint, the colour and the options, with the scale
## (`RenderConfig.unit`) and the kit's own tunables (the tone ramp, the round solids' side count),
## since a mesh is built in 3D units. A builder puts every tuning value its shape reads in the
## options, so a retuned holder is another mesh.
##
## The cache is bounded (`MeshKitConfig.cache_limit`: the mesh asked for longest ago goes first). It
## is for meshes many pieces share; a mesh unique to one node (a dented panel, a posed limb) is
## `MeshKit.build()` straight into `MeshNodes.instance`, freed with its node.
##
## `fetch(key, make)` builds a missing mesh with `make` (a `Callable` returning the `Mesh`, usually
## a `MeshKit` chain's `build()`); a hit never calls it.

## The meshes by key.
static var _meshes: Dictionary = {}
## How many times `fetch` had to build (a test reads it).
static var builds := 0


## The key of the mesh `id` makes for a `size` px footprint in `color` with `opts` (the piece's
## options, in any key order).
static func key(id: String, size: Vector2, color: Color, opts: Dictionary = {}) -> String:
	return "%s|%v|%s|%s|%s|%s" % [
		id, size, color.to_html(), JSON.stringify(opts, "", true), RenderConfig.unit, _kit_tuning(),
	]


## The mesh stored under `key`, built by `make` the first time it is asked for. A hit moves the mesh
## to the newest end, so past the limit it is the one asked for longest ago that is dropped.
static func fetch(key_text: String, make: Callable) -> Mesh:
	var cached: Variant = _meshes.get(key_text)
	if cached is Mesh:
		_meshes.erase(key_text)
		_meshes[key_text] = cached
		return cached
	var mesh: Mesh = make.call()
	_meshes[key_text] = mesh
	builds += 1
	while _meshes.size() > maxi(MeshKitConfig.cache_limit, 1):
		for oldest: String in _meshes:
			_meshes.erase(oldest)
			break
	return mesh


## How many meshes are cached.
static func count() -> int:
	return _meshes.size()


## Forget every mesh (a test, or a tuning change that alters what builders make).
static func clear() -> void:
	_meshes.clear()


## What the kit itself reads and a builder cannot put in its options: the tone ramp and the side
## count of a round solid.
static func _kit_tuning() -> String:
	return "%s,%s,%s,%s,%s,%s" % [
		ArtSurfaceConfig.tone_outline, ArtSurfaceConfig.tone_shadow, ArtSurfaceConfig.tone_dark,
		ArtSurfaceConfig.tone_light, ArtSurfaceConfig.tone_highlight, MeshKitConfig.cylinder_sides,
	]
