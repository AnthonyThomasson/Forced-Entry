class_name VehicleMeshes
extends RefCounted
## Vehicles domain, the 3D meshes of its vehicles (`domain-art/meshes.md`): the one
## call that plugs them into the 3D mirror. A car or a van is a `vehicle.gd` body, so one builder
## under the `MirrorProxy.VEHICLE` kind covers both (`vehicle_mesh.gd` reads the kind's rows).
## Main's 3D view registers them (`register`) before it mirrors the match.

const VehicleMesh = preload("res://scenes/vehicle/art/vehicle_mesh.gd")


## Add the vehicle builder to `builders` (`WorldMirror.builders`) under the vehicle kind.
static func register(builders: Dictionary) -> void:
	builders[MirrorProxy.VEHICLE] = Callable(VehicleMesh, &"build")
