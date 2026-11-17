class_name VehicleTwins
extends RefCounted
## Vehicles domain, the 3D twin of a vehicle for the twin space (`TwinSpace`, interface 29, #194
## D3): a kinematic body (`AnimatableBody3D`) over the vehicle's own 2D outline, standing from the
## ground to the top of its body (`VehicleMeshConfig.heights`' `belt`, the mesh's own number: the
## roof and the glass above it are not a twin yet), following the vehicle's transform. On
## `PhysicsLayers.TWIN_VEHICLE`. A dent that reshapes the 2D collider does not reshape the twin.


## Add the hook to `space` (a `TwinSpace`).
static func register(space: TwinSpace) -> void:
	space.builders.append(Callable(VehicleTwins, &"build"))


## The twin of `node` if it is a vehicle, else null.
static func build(node: Node2D) -> Node3D:
	if not node is RigidBody2D or not node.is_in_group(&"vehicles"):
		return null
	var heights: Dictionary = VehicleMeshConfig.heights.get(node.get("kind"), {})
	var twin := AnimatableBody3D.new()
	twin.sync_to_physics = false
	twin.collision_layer = PhysicsLayers.TWIN_VEHICLE
	twin.collision_mask = 0
	TwinShapes.lift_body(node, twin, 0.0, float(heights.get("belt", 0.0)))
	return twin
