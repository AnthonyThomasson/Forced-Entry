class_name ObjectMeshCarConfig
## Objects domain, the 3D mesh of the garage's parked car (`car_mesh.gd`; `domain-art/meshes.md`):
## the prop's own proportions of tyre and underside, but the height of the Vehicles domain's
## drivable car: one source for how tall a car is, `VehicleMeshConfig.heights`. A `class_name`
## holder of `static var`s, read as `ObjectMeshCarConfig.<name>` (ADR 0003), and the two heights it
## reads from there. Lengths are 2D pixels, the art's units: the mesh kit converts them to 3D units
## in one place.

## A tyre's radius and how far the body's underside rides over the ground.
static var tyre_radius: float = 14.0
static var body_base: float = 6.0
## How far the glass and the lamps stand proud of the body.
static var glass_proud: float = 0.5


## The body's top: the drivable car's belt (`VehicleMeshConfig.heights`).
static func body_top() -> float:
	return float((VehicleMeshConfig.heights[&"car"] as Dictionary)["belt"])


## The roof's top: the drivable car's roof (`VehicleMeshConfig.heights`).
static func roof_top() -> float:
	return float((VehicleMeshConfig.heights[&"car"] as Dictionary)["roof"])
