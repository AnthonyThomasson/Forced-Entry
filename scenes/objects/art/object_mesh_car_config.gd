class_name ObjectMeshCarConfig
## Objects domain, the 3D mesh of the garage's parked car (`car_mesh.gd`; `domain-art/meshes.md`):
## the prop's own proportions, not the Vehicles domain's drivable car. A `class_name` holder of
## `static var`s, read as `ObjectMeshCarConfig.<name>` (ADR 0003). Lengths are 2D pixels, the art's
## units: the mesh kit converts them to 3D units in one place. A body is 40 tall, a roof 60 (a 1.42
## m car).

## A tyre's radius, how far the body's underside rides over the ground, the body's top and the
## roof's.
static var tyre_radius: float = 14.0
static var body_base: float = 6.0
static var body_top: float = 40.0
static var roof_top: float = 60.0
## How far the glass and the lamps stand proud of the body.
static var glass_proud: float = 0.5
