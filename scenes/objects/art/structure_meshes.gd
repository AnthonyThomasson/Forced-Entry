class_name StructureMeshes
extends RefCounted
## Objects domain, the 3D meshes of the building's structure (#193 phase 2; `domain-art/meshes.md`):
## which kinds the mirror shows by a mesh of their own and the one call that plugs them in
## (`ObjectMeshes.register` makes it). Walls, house doors and floors are hooked by their kind
## (`MirrorProxy.WALL`, `DOOR`, `FLOOR`), the street's floor by its own key. Each script beside the
## painters has `static func build(body) -> Node3D` built from Art's mesh kit, in 3D units in the
## body's frame (a floor's: at its corner); a body with no builder keeps its proxy.

const DoorMeshScript = preload("res://scenes/objects/art/door_mesh.gd")
const WallMesh = preload("res://scenes/objects/art/wall_mesh.gd")
const FloorMesh = preload("res://scenes/objects/art/floor_mesh.gd")
const StreetMesh = preload("res://scenes/objects/art/street_mesh.gd")
## The builder script per hook key: the kinds, then the floor of an art of its own.
const BUILDERS := {
	MirrorProxy.WALL: WallMesh,
	MirrorProxy.DOOR: DoorMeshScript,
	MirrorProxy.FLOOR: FloorMesh,
}
const FLOORS := {
	"street": StreetMesh,
}


## Add every builder to `builders` (`WorldMirror.builders`) under its key.
static func register(builders: Dictionary) -> void:
	for key: StringName in BUILDERS:
		_put(builders, key, BUILDERS[key])
	for art: String in FLOORS:
		_put(builders, MirrorProxy.floor_key(art), FLOORS[art])


## Put the builder of `script` (its static `build`) under `key`.
static func _put(builders: Dictionary, key: StringName, script: GDScript) -> void:
	var builder := Callable(script, &"build")
	if builder.is_valid():
		builders[key] = builder
	else:
		push_error("StructureMeshes: the mesh script of '%s' has no static build(body)" % key)
