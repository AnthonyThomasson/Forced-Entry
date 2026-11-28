class_name PhysicsMeshes
extends RefCounted
## Physics domain, the one call that plugs the 3D look of its effects into the 3D view
## (`domain-art/meshes.md`). Debris, hit particles, blood and explosions are too many and
## too short-lived for a node and a mesh each, so a layer owns
## their batches and meshes and the 2D code tells it as it makes each thing (`PhysicsFxHook`).
## Main's 3D view installs it once, before the match makes anything.


## Add the effects' layer to `parent` (the 3D view's viewport: it draws in the world that holds the
## twins, no mirror needed) and have the 2D Physics code tell it what it makes. `ground` is a
## `Callable(Vector2) -> float`, the height of the ground (px, 0 on the pavement) at a world point,
## which Main builds from the street (a road lies a kerb lower); none is a flat ground. Returns the
## layer; it stops being told when it leaves the tree. The hook is process-wide: one 3D view at a
## time.
static func install(parent: Node, ground := Callable()) -> FxLayer:
	BlastRig.warm()
	var layer := FxLayer.new()
	layer.build(Despawner.max_scene_objects, FxWorld.new(ground))
	parent.add_child(layer)
	PhysicsFxHook.sink = layer
	layer.tree_exiting.connect(func() -> void:
		if PhysicsFxHook.sink == layer:
			PhysicsFxHook.sink = null
	)
	return layer
