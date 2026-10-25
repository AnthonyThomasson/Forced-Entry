class_name CharacterConfig
## Tuning for a Character's body still held together here (scenes/character/): its skeleton, stride,
## melee, pose springs, ragdoll and art. A `class_name` holder of `static var`s — read as
## `CharacterConfig.<name>`; there is no instance and no autoload. Its other topics have their own
## holders: `CharacterPostureConfig`, `CharacterPaceConfig`, `CharacterPushConfig`,
## `CharacterStunConfig`, `CharacterHitConfig`, `CharacterShadowConfig`, `CharacterStyleConfig` and
## `CharacterStanceConfig`.

## Base central impulse a full-extension punch imparts to a pushable object, scaled by the
## swing's range of motion (0 point-blank .. 1 full reach). A shoved RigidBody slides
## ≈ impulse / (mass × PhysicsImpactConfig.body_linear_damp) before settling.
static var punch_impulse: float = 900.0
## Base damage a full-extension punch reports, scaled by the same range of motion. Surfaced
## through hit_landed for the HUD; a punch does not deform what it hits.
static var punch_damage: float = 8.0
## Central impulse a kick imparts to a pushable object, and the damage it reports (both at full
## strength: a kick lands only while the foot is being thrown out).
static var kick_impulse: float = 2200.0
static var kick_damage: float = 14.0
## How far (px) from the body centre the foot is thrown along the facing, and the radius of the
## circle that strikes.
static var kick_reach: float = 44.0
static var kick_radius: float = 6.0
## Seconds the foot takes to be thrown out (the strike) and to be drawn back (no other kick starts
## meanwhile).
static var kick_strike_time: float = 0.09
static var kick_recover_time: float = 0.22
## How high (body radii) the thrown foot is held off the floor: it must stay within the leg's length
## of the hip.
static var kick_foot_height: float = 2.1
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
## Hip joints above the floor (legs stand a touch bent).
static var body_hip_height: float = 3.8
## Shoulder joints above the floor.
static var body_shoulder_height: float = 6.3
## Head center above the floor.
static var body_head_height: float = 7.2
## Each shoulder joint off the spine.
static var body_shoulder_width: float = 0.8
## Each hip joint off the spine.
static var body_hip_width: float = 0.4
## Shoulder to elbow.
static var body_upper_arm: float = 1.35
## Elbow to the center of the fist.
static var body_forearm: float = 1.4
## Hip to knee.
static var body_thigh: float = 1.95
## Knee to ankle.
static var body_shin: float = 1.85
## Shoe length.
static var body_foot: float = 1.0
## How far an arm may stretch before its shoulder follows the hand (fraction of its length), and the
## furthest the shoulder joint follows a hand out of reach (body radii) — a punch's lean-in.
static var body_arm_extension: float = 0.98
static var body_shoulder_reach: float = 1.0
## How far each foot swings fore and aft mid-stride at full walking speed, and how high the
## swinging foot lifts (body radii).
static var body_stride: float = 0.85
static var body_foot_lift: float = 0.35
## The same at a full run: a longer, higher stride.
static var body_run_stride: float = 1.5
static var body_run_foot_lift: float = 0.6
## How far the hips sink at a full run (body radii): knees stay bent through the stride.
static var body_run_hip_drop: float = 0.35
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
## How fast a part past its `max_lag` is reeled back toward it (1/s): high = tight, low = loose.
static var pose_lag_catch: float = 14.0
## Head: turns to the aim first.
static var pose_head_freq: float = 12.0
## Head: barely overshoots.
static var pose_head_damping: float = 0.9
## Head: furthest behind the aim.
static var pose_head_max_lag: float = 0.8
## Steady hands (aiming, supporting): follow the aim closely.
static var pose_aim_freq: float = 11.0
## Steady hands: settle without wobble.
static var pose_aim_damping: float = 0.95
## Steady hands: furthest behind the aim.
static var pose_aim_max_lag: float = 0.6
## Weapon: heavier than the hand holding it.
static var pose_weapon_freq: float = 7.0
## Weapon: swings a hair past and settles.
static var pose_weapon_damping: float = 0.8
## Weapon: furthest behind the aim.
static var pose_weapon_max_lag: float = 0.7
## Free hands: follow the aim loosely.
static var pose_hand_freq: float = 8.0
## Free hands: a little give.
static var pose_hand_damping: float = 0.85
## Free hands: furthest behind the aim.
static var pose_hand_max_lag: float = 0.9
## How far apart the two free hands' paces are (fraction of `pose_hand_freq`; left slower).
static var pose_hand_pace_spread: float = 0.3
## Shoulders: follow last.
static var pose_torso_freq: float = 5.5
## Shoulders: ease past and settle.
static var pose_torso_damping: float = 0.75
## Shoulders: furthest behind the aim.
static var pose_torso_max_lag: float = 1.2
## Hips (and feet): turn to the walking direction.
static var pose_hip_freq: float = 9.0
## Hips: barely overshoot.
static var pose_hip_damping: float = 0.9
## How far the shoulders may twist off the planted hips before the feet re-plant toward the aim
## (rad).
static var pose_hip_twist: float = 0.9
## Distance walked per full stride (two steps), in px.
static var pose_stride_length: float = 48.0
## The same at a full run. A planted foot stays put on the ground when this is 2π × the foot's swing
## (`body_run_stride` × radius ≈ 21 px → ~130 px); shorter and the feet scurry and skate.
static var pose_run_stride_length: float = 130.0
## Shoulder sway either way at full walking speed (rad).
static var pose_walk_sway: float = 0.07
## A full run's shoulders counter-rotate against the hips by this much either way (rad).
static var pose_run_sway: float = 0.18
## ...and the upper body shifts this far (px) sideways over the planted foot, once per step.
static var pose_run_shoulder_shift: float = 1.2
## A full run's forward lean: the shoulders (and head) lead the hips this far (px) along the way it
## travels.
static var pose_run_lean: float = 2.5
## How far the forward-swinging hand rises above, and the back one drops below, its grip height
## (body radii).
static var pose_run_hand_rise: float = 0.7
## How far a running elbow's pole swings up and down with the arm (see `elbow_pole`): down under a
## forward hand, up behind a back one.
static var pose_run_elbow_lift: float = 0.5
## A steady hand's sideways drift at full walking speed (px).
static var pose_aim_drift: float = 0.5
## A punch's body: the shoulders twist toward the punching side by this much (rad) and the upper
## body lunges this far ahead (px) at full extension.
static var pose_punch_twist: float = 0.5
static var pose_punch_lunge: float = 4.0
## Head bob along the walk at full speed (px), twice per stride.
static var pose_head_bob: float = 0.4
## Head lean into the movement at full speed (px), on a soft spring so it settles on a stop.
static var pose_lean: float = 1.2
## Lean spring speed (rad/s).
static var pose_lean_freq: float = 7.0
## Lean spring damping.
static var pose_lean_damping: float = 0.65
## Breathing: the head's slow drift fore and aft (px).
static var pose_breath: float = 0.35
## Breath period (s).
static var pose_breath_period: float = 3.8
## Idle glance: how far the head wanders off the aim while standing (rad), faded out when walking.
static var pose_glance: float = 0.1
