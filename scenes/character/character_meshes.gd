class_name CharacterMeshes
extends RefCounted
## Character domain, the 3D mesh of its bodies (`domain-art/meshes.md`): the one call
## that plugs the character's mesh into the 3D mirror. The mesh itself is `BodyMesh`
## (`body/art/body_mesh.gd`, built from Art's mesh kit beside the painters); a node with no
## anatomy or wardrobe, or the builder returning null, stays a proxy capsule. Main's 3D view
## registers it (`register`) before it mirrors the match.


## Add the character's builder to `builders` (`MeshCarrier.builders`) under the `CHARACTER` kind.
static func register(builders: Dictionary) -> void:
	builders[MeshKinds.CHARACTER] = Callable(BodyMesh, &"build")
