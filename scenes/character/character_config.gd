class_name CharacterConfig
## Tuning for a Character's fall and art still held together here (scenes/character/): its ragdoll's
## build, joints and launch and how the body is drawn. A `class_name` holder of `static var`s — read
## as `CharacterConfig.<name>`; there is no instance and no autoload. Its other topics have their
## own holders (`CharacterPostureConfig`, `CharacterBodyConfig`, `CharacterPoseTurnConfig` ...).

## Color of the cracks radiating from each bullet wound — a dark red, so hits read as
## bloody gashes rather than bright scratches.
static var flesh_crack_color: Color = Color(0.42, 0.05, 0.05)
## Color of the central bullet hole in each wound (the darkest part of the wound).
static var flesh_hole_color: Color = Color(0.25, 0.02, 0.03)
## Color of the faint scorch halo around each wound; dark red so it reads as bruising.
static var flesh_scorch_color: Color = Color(0.35, 0.02, 0.02)
## Head radius as a fraction of the body's width.
static var art_head_size: float = 0.19
## Shoulder span depth (front to back) as a fraction of the body's width.
static var art_shoulder_depth: float = 0.54
## Belly and back points off the spine (keep the trunk rigid).
static var ragdoll_belly: float = 0.4
## Collision radii: the trunk's is half its depth, so it lies on its back or front with thickness.
static var ragdoll_torso_radius: float = 0.5
static var ragdoll_head_radius: float = 0.38
static var ragdoll_limb_radius: float = 0.24
## Point masses (relative): a heavy trunk (seven points), lighter limbs toward their ends.
static var ragdoll_torso_mass: float = 1.0
static var ragdoll_head_mass: float = 0.8
static var ragdoll_elbow_mass: float = 0.25
static var ragdoll_hand_mass: float = 0.15
static var ragdoll_knee_mass: float = 0.6
static var ragdoll_ankle_mass: float = 0.35
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
## Joint limits: how far each bone may swing off its rest (neck up; arms and legs down) toward the
## front / back / the body's outside / across it, and each hinge's bend range plus the twist out of
## its plane it allows (the elbow's stands in for the upper arm's roll; the knee barely twists).
static var ragdoll_neck_limits: Dictionary = {
	"front": 50.0, "back": 45.0, "out": 40.0, "in": 40.0,
}
static var ragdoll_shoulder_limits: Dictionary = {
	"front": 170.0, "back": 60.0, "out": 160.0, "in": 40.0,
}
static var ragdoll_hip_limits: Dictionary = {
	"front": 120.0, "back": 25.0, "out": 35.0, "in": 30.0,
}
static var ragdoll_elbow_bend: Vector2 = Vector2(0.0, 145.0)
static var ragdoll_elbow_slack: float = 70.0
static var ragdoll_knee_bend: Vector2 = Vector2(0.0, 150.0)
static var ragdoll_knee_slack: float = 20.0
## The fall's launch: the upper body's push along the killing blow (px/s at the shoulders, fading
## to none at the hips), the knees' forward buckle (px/s) and a random jolt on every point (px/s).
static var ragdoll_hit_topple: float = 60.0
static var ragdoll_knee_buckle: float = 70.0
static var ragdoll_jitter: float = 15.0
## How much of an explosion's shove on a fallen body goes up (a hop off the floor), as a share of
## its speed along it.
static var ragdoll_blast_lift: float = 0.35
## Speed (px/s) a held item is tossed off at as the hand lets go, on top of the body's momentum.
static var ragdoll_drop_toss: float = 70.0
## Draw layer of a dead body: `DrawLayers.LYING`, beneath the living and a vehicle's chassis, above
## blood pools.
static var ragdoll_z_index: int = DrawLayers.LYING
