class_name PhysicsMeshes
extends RefCounted
## Physics domain, the one call that plugs the 3D look of its effects into the 3D mirror (#193
## phase 2; `domain-art/meshes.md`). Debris, hit particles, blood and explosions are too many and
## too short-lived for a node and a mesh each through the mirror's `track_group`, so a layer owns
## their batches and meshes and the 2D code tells it as it makes each thing (`PhysicsFxHook`).
## Main's 3D view installs it once, before the match makes anything.


## Add the effects' layer to `mirror` (it follows the mirror's frame) and have the 2D Physics code
## tell it what it makes. Returns the layer; it stops being told when it leaves the tree.
static func install(mirror: WorldMirror) -> FxLayer:
	var layer := FxLayer.new()
	layer.build(Despawner.max_scene_objects)
	mirror.add_child(layer)
	PhysicsFxHook.sink = layer
	layer.tree_exiting.connect(func() -> void:
		if PhysicsFxHook.sink == layer:
			PhysicsFxHook.sink = null
	)
	return layer
