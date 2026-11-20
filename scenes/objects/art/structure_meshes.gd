class_name StructureMeshes
extends RefCounted
## Objects domain, the 3D meshes of the building's structure (`domain-art/meshes.md`):
## which kinds the mirror shows by a mesh of their own and the one call that plugs them in
## (`ObjectMeshes.register` makes it). Walls, house doors and floors are hooked by their kind
## (`MeshKinds.WALL`, `DOOR`, `FLOOR`), the street's floor by its own key. Each script beside the
## painters has `static func build(body) -> Node3D` built from Art's mesh kit, in 3D units in the
## body's frame (a floor's: at its corner); a body with no builder keeps its proxy.

const FloorMesh = preload("res://scenes/objects/art/floor_mesh.gd")
const StreetMesh = preload("res://scenes/objects/art/street_mesh.gd")


## Add every builder to `builders` (`MeshCarrier.builders`) under its key.
static func register(builders: Dictionary) -> void:
	builders[MeshKinds.WALL] = WallMesh.build
	builders[MeshKinds.DOOR] = DoorMesh.build
	builders[MeshKinds.FLOOR] = FloorMesh.build
	builders[MeshKinds.floor_key("street")] = StreetMesh.build
