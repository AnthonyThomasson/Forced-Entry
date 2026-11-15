class_name PhysicsMeshes
extends RefCounted
## Physics domain, the one call that plugs the 3D look of its effects into the 3D mirror (#193
## phase 2; `domain-art/meshes.md`). Debris, hit particles, blood and explosions are too many and
## too short-lived for a node and a mesh each through the mirror's `track_group`, so a layer owns
## their batches and meshes and the 2D code tells it as it makes each thing (`PhysicsFxHook`).
## Main's 3D view installs it once, before the match makes anything.


## Add the effects' layer to `mirror` (it follows the mirror's frame) and have the 2D Physics code
## tell it what it makes. `ground` is a `Callable(Vector2) -> float`, the height of the ground (px,
## 0 on the pavement) at a world point, which Main builds from the street (a road lies a kerb
## lower); none is a flat ground. Returns the layer; it stops being told when it leaves the tree.
## The hook is process-wide: one 3D view at a time.
static func install(mirror: WorldMirror, ground := Callable()) -> FxLayer:
	var layer := FxLayer.new()
	layer.build(Despawner.max_scene_objects, FxWorld.new(ground))
	mirror.add_child(layer)
	PhysicsFxHook.sink = layer
	layer.tree_exiting.connect(func() -> void:
		if PhysicsFxHook.sink == layer:
			PhysicsFxHook.sink = null
	)
	return layer
