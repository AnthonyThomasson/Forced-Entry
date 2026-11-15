class_name ProjectileMeshes
extends RefCounted
## Projectile domain, the 3D look of the shots (#193 phase 2; `domain-art/meshes.md`): the one call
## that plugs them into the 3D mirror. Tracers (and, with them, casings) are pooled batches the
## `ShotLayer` owns and follows the 2D bullets and casings of the match's world into, rather than
## a node each through the mirror's `track_group`: a sustained fight makes hundreds of them a
## second. Main's 3D view installs it (`install`) once it has built the match.


## Add the shots' layer to `mirror` (it follows the mirror's frame) and have it follow the
## bullets of `world`, the 2D world root the match's shots are made in. Returns the layer.
static func install(mirror: WorldMirror, world: Node) -> ShotLayer:
	var layer := ShotLayer.new()
	mirror.add_child(layer)
	layer.watch(world)
	return layer
