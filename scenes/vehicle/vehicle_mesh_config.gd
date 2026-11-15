class_name VehicleMeshConfig
## Vehicles domain, the 3D meshes of cars and vans (`art/vehicle_mesh.gd`; #193 phase 2,
## `domain-art/meshes.md`): how tall each kind stands and how its parts are proportioned. The
## footprint, the doors, the axles, the wheels and the lamps come from the kind's `VehicleConfig`
## `kinds` and `looks` rows, the colours from `VehicleArtConfig`, so the 3D matches the painters;
## what the painters leave out (a height) lives here. A `class_name` holder of `static var`s, read
## as `VehicleMeshConfig.<name>` (ADR 0003). Lengths are 2D pixels, the art's units: the mesh kit
## converts them to 3D units in one place, so nothing here is multiplied by `RenderConfig.unit`.

## Per kind, heights above the ground (a standing character is 74): `sill` the underside of the
## body (the wheels stand in the gap), `belt` the top of the body and of the doors, `roof` the top
## of the cabin, `lamp` the [low, high] of the head and tail lamps.
static var heights := {
	&"car": { "sill": 9.0, "belt": 36.0, "roof": 52.0, "lamp": Vector2(19.0, 28.0) },
	&"van": { "sill": 11.0, "belt": 46.0, "roof": 78.0, "lamp": Vector2(24.0, 34.0) },
}
## How thick the roof slab is (the glass band runs under it).
static var roof_thickness: float = 3.0
## A door leaf stops this short of the notch it shuts in at each end, so a seam shows.
static var door_gap: float = 0.4
## How far a lamp, a bumper, a hub and a dent stand proud of the surface they sit on, so a face
## never fights the one under it.
static var proud: float = 0.6
## A bumper's height (from the sill up).
static var bumper_height: float = 11.0
## A tyre's hub is this share of its radius; its spoke (what shows the wheel turn) is this thick.
static var hub_ratio: float = 0.55
static var spoke: float = 2.5
## Whether the wheels turn as the vehicle rolls.
static var wheel_spin: bool = true
## A wing mirror's (out from the door, along it, up) size, how far from the hinge it starts and how
## far above the belt its underside is.
static var mirror_size: Vector3 = Vector3(5.0, 8.0, 5.0)
static var mirror_from: float = 1.0
static var mirror_lift: float = -2.0
## A dent shows as a dark patch this wide plus this much a unit of its depth, at this share of the
## way up the body's side, in this colour.
static var dent_size: float = 4.0
static var dent_growth: float = 1.5
static var dent_height: float = 0.5
static var dent_color: Color = Color(0.1, 0.1, 0.11)
