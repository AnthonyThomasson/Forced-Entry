class_name ObjectMeshClinicConfig
## Objects domain, the 3D mesh of the surgical chair (`recliner_mesh.gd`; `domain-art/meshes.md`):
## the shape that tells it from the netrunner's rig. A `class_name` holder of `static var`s, read as
## `ObjectMeshClinicConfig.<name>` (ADR 0003). Lengths are 2D pixels, the art's units: the mesh kit
## converts them to 3D units in one place.

## The headrest's top, how high the reclined back rises at the head end (it slopes down to the seat)
## and how low the leg rest ends at the feet (it slopes down from the seat).
static var head_height: float = 32.0
static var back_height: float = 30.0
static var foot_height: float = 10.0
