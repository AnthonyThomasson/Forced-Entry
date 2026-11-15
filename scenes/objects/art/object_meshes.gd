class_name ObjectMeshes
extends RefCounted
## Objects domain, the 3D meshes of its pieces (#193 phase 2; `domain-art/meshes.md`): which art ids
## have a mesh of their own and the one call that plugs them into the 3D mirror. Each id has a
## script beside the painters (`table_mesh.gd`) with `static func build(piece) -> Node3D`, built
## from Art's mesh kit, in 3D units and centred on the piece's origin; an art id with none stays a
## proxy box. Main's 3D view registers them (`register`) before it mirrors the match.

const TableMesh = preload("res://scenes/objects/art/table_mesh.gd")
## The builder script per `ObjectArt` id.
const BUILDERS := {
	"table": TableMesh,
}


## Add every builder to `builders` (`WorldMirror.builders`) under the finer key of its art id, and
## the building's structure (walls, doors, floors: `StructureMeshes`).
static func register(builders: Dictionary) -> void:
	StructureMeshes.register(builders)
	for art: String in BUILDERS:
		var builder := Callable(BUILDERS[art], &"build")
		if builder.is_valid():
			builders[MirrorProxy.furniture_key(art)] = builder
		else:
			push_error("ObjectMeshes: the mesh script of '%s' has no static build(piece)" % art)
