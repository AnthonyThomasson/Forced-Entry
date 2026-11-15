class_name MeshCache
extends RefCounted
## Art domain, the 3D mesh kit's cache (interface 12): the same inputs give the same `Mesh`
## resource, shared by every piece asking for it, as `PixelArt` shares a texture. Static, so it
## survives scene reloads. A key names what the mesh is made from the way `PixelArt`'s does
## (`key`): the builder's id, the footprint, the colour and the options, with the scale
## (`RenderConfig.unit`), since a mesh is built in 3D units. A builder puts every tuning value its
## shape reads in the options, so a retuned holder is another mesh.
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
	return "%s|%v|%s|%s|%s" % [
		id, size, color.to_html(), JSON.stringify(opts, "", true), RenderConfig.unit,
	]


## The mesh stored under `key`, built by `make` the first time it is asked for.
static func fetch(key_text: String, make: Callable) -> Mesh:
	var cached: Variant = _meshes.get(key_text)
	if cached is Mesh:
		return cached
	var mesh: Mesh = make.call()
	_meshes[key_text] = mesh
	builds += 1
	return mesh


## How many meshes are cached.
static func count() -> int:
	return _meshes.size()


## Forget every mesh (a test, or a tuning change that alters what builders make).
static func clear() -> void:
	_meshes.clear()
