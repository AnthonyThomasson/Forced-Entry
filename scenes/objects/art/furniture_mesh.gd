class_name FurnitureMesh
extends RefCounted
## Objects domain, the plumbing every furniture mesh shares (#193 phase 2; the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): the cache key of a piece's mesh and the node that shows
## it. A kind's script (`sofa_mesh.gd`) reads a `FurnitureSpec`, names every value its shape reads
## in a tuning dictionary and builds its solids once per distinct key; every piece of one look
## shares that `Mesh`.


## The mesh `make` builds for the kind `id` with `spec`, cached: the key is the id, the canonical
## footprint, the drawn colour, the facing and `tuning` (every option and every holder value the
## shape reads, so a retuned holder or another option is another mesh).
static func fetch(id: String, spec: FurnitureSpec, tuning: Dictionary, make: Callable) -> Mesh:
	var key := MeshCache.key(
		id,
		spec.size,
		spec.color,
		{ "turns": spec.turns, "overhang": spec.overhang, "tuning": tuning },
	)
	return MeshCache.fetch(key, make)


## The mesh the glowing parts of kind `id` make, cached like `fetch`: the same key under the id's
## glow name.
static func fetch_glow(id: String, spec: FurnitureSpec, tuning: Dictionary, make: Callable) -> Mesh:
	return fetch("%s_glow" % id, spec, tuning, make)


## The node that shows `mesh` for `piece`: a rig with the mesh as its body, tinted by the damage the
## piece has taken and following its dents.
static func show(piece: Node2D, mesh: Mesh) -> FurnitureRig:
	return FurnitureRig.new().with_body(piece, mesh)
