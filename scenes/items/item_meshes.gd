class_name ItemMeshes
extends RefCounted
## Items domain, the 3D mesh of the items loose in the world (`domain-art/meshes.md`):
## the one call that plugs them into the 3D mirror. A `DroppedItem` (a dead hand's gun, a grenade's
## spoon) and a `ThrownGrenade` (in the air and lying before it bursts) are shown by a
## `LyingItemMesh` of the mesh their item's art gives; an item with none is not shown. Main's 3D
## view registers it (`register`) before it mirrors the match; the held item is Character's
## `BodyHeld`, from the same art.

## The groups the 2D nodes join (`DroppedItem`, `ThrownGrenade`): every one is shown by its mesh.
const GROUPS: Array[StringName] = [&"dropped_items", &"live_grenades"]


## Have `mirror` show every loose item by its mesh, those already in the match and each as it joins.
static func register(mirror: WorldMirror) -> void:
	for group in GROUPS:
		mirror.track_group(group, Callable(LyingItemMesh, &"build"))
