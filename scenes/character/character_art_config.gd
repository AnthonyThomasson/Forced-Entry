class_name CharacterArtConfig
## How the body is drawn (scenes/character/): head and shoulder proportions, the limbs' drawn
## widths, the fallen trunk's sections, the dead body's draw layer, and the wound colours. A
## `class_name` holder of `static var`s, read as `CharacterArtConfig.<name>`; there is no instance
## and no autoload.

## Color of the cracks radiating from each bullet wound — a dark red, so hits read as
## bloody gashes rather than bright scratches.
static var flesh_crack_color: Color = Color(0.42, 0.05, 0.05)
## Color of the central bullet hole in each wound (the darkest part of the wound).
static var flesh_hole_color: Color = Color(0.25, 0.02, 0.03)
## Color of the faint scorch halo around each wound; dark red so it reads as bruising.
static var flesh_scorch_color: Color = Color(0.35, 0.02, 0.02)
## Head radius as a fraction of the body's width.
static var head_size: float = 0.19
## Shoulder span depth (front to back) as a fraction of the body's width.
static var shoulder_depth: float = 0.54
## Drawn thickness of the body's limbs (body radii), at each joint down the chain: the neck;
## the arm at the shoulder, elbow and wrist; the leg at the hip, knee, calf and ankle; the shoe at
## the heel and toe. Neighbouring segments share a joint's width, so limbs taper smoothly.
static var body_neck_width: float = 0.42
static var body_arm_widths: Array = [0.48, 0.36, 0.3]
static var body_leg_widths: Array = [0.66, 0.46, 0.52, 0.32]
static var body_shoe_widths: Array = [0.38, 0.34]
## The fallen trunk's shape: cross-sections along the spine, each Vector3(where along it — 0 at the
## hip joints, 1 at the shoulder joints —, half-width, half-depth in body radii), bottom to top. Its
## outline is the hull of each neighbouring pair, so it is waisted and rounded at both ends.
static var ragdoll_trunk_sections: Array = [
	Vector3(-0.15, 0.62, 0.42), Vector3(0.0, 0.74, 0.5), Vector3(0.45, 0.64, 0.45),
	Vector3(0.8, 0.9, 0.55), Vector3(1.0, 1.0, 0.54), Vector3(1.1, 0.78, 0.4),
]
## Draw layer of a dead body: `DrawLayers.LYING`, beneath the living and a vehicle's chassis, above
## blood pools.
static var ragdoll_z_index: int = DrawLayers.LYING
