class_name CharacterMeshes
extends RefCounted
## Character domain, the 3D mesh of its bodies (#193 phase 2; `domain-art/meshes.md`): the one call
## that plugs the character's mesh into the 3D mirror. The mesh itself is `BodyMesh`
## (`body/art/body_mesh.gd`, built from Art's mesh kit beside the painters); a character with no
## `Visuals` dress, or the builder returning null, stays a proxy capsule. Main's 3D view registers
## it (`register`) before it mirrors the match.


## Add the character's builder to `builders` (`WorldMirror.builders`) under the `CHARACTER` kind.
static func register(builders: Dictionary) -> void:
	builders[MirrorProxy.CHARACTER] = Callable(BodyMesh, &"build")
