extends RefCounted
## Character POSE (Character domain, animate layer): the living motion layered over the aim. The
## head, each hand, a held weapon and the shoulders each chase `facing` on their own damped spring
## — the head first, a steady (aiming or supporting) hand next, the weapon a touch behind it, free
## hands each at a slightly different pace, the shoulders last — so a turn ripples through the body.
## The hips are planted while standing and turn to the walking direction while walking, so the feet
## stay put under a twisting upper body and step the way the body travels. Walking sways the
## shoulders and swings the free hands along a stride; the head leans into the movement and settles
## when it stops; standing still, it breathes and glances around. A kick (recoil) throws a hand back
## and twists the shoulders; a punch twists them toward the punching side and lunges the upper body.
## Each hand eases between the stances its item asks for (CharacterStanceConfig.stances): where it
## rests, how high it is gripped, how its elbow bends. A stunned character (the level handed to
## `update`, eased) hunches (the rig reads `hunch()`) and staggers: shorter, uneven strides, the
## hips swaying over the planted foot and the head lolling (docs/grenades.md G13). Owned and stepped
## by character.gd each physics frame; read by the hands (their rest pose), the rig (the joints) and
## the visuals (each part's angle and offset). Visual only: aim, shots and punches stay on `facing`.
## Its parts, built once with it: the springs (`_springs`, `pose_springs.gd`), the arms (`arms`,
## `pose_arms.gd`: the stances, the swing, the recoil) and the gait (`gait`, `pose_gait.gd`: the
## stride, the walk and run, the stun as shown, the breath's clock).
## Tuning: CharacterPoseTurnConfig, CharacterPoseHandConfig, CharacterPoseHeadConfig, the stride's
## CharacterStrideConfig.pose_*, and CharacterStunConfig's look_ease, hunch_pitch and stagger_*.

## Shoulders' facing angle (rad, as Vector2.angle()), punch twist included.
var torso_angle := 0.0
## Upper body's lunge ahead of the hips (local px).
var torso_offset := Vector2.ZERO
## Hips' and feet's facing angle (rad).
var hip_angle := 0.0
## Head's facing angle (rad).
var head_angle := 0.0
## Per hand: the angle of the frame its rest pose is built in (rad).
var hand_angles := [0.0, 0.0]
## A held weapon's facing angle (rad): trails the aiming hand.
var weapon_angle := 0.0
## Head's shift off the body center (local px), the lunge included.
var head_offset := Vector2.ZERO
## The hips' sideways sway of a stunned walk (local px), for the rig's pelvis.
var hip_sway := Vector2.ZERO
## Head lean (local px), on a spring.
var _lean := Vector2.ZERO
## Head lean spring velocity (px/s).
var _lean_vel := Vector2.ZERO
## False until the first update snaps every part to the aim.
var _primed := false
## The head's, hands', weapon's, shoulders' and hips' springs toward the aim.
var _springs := PoseSprings.new()
## The stride, the walk and the run, the stun as the body shows it, and the breath's clock.
var gait := PoseGait.new()
## Each hand's stance, swing and recoil.
var arms := PoseArms.new(gait, _springs)


## Advance the pose by `delta` as `drive` asks: toward its `facing`, walking at its `velocity`
## (top speed `top_speed`), each hand toward the stance it names (the held item's hand_stance()),
## each `punch` extension 0 (resting) .. 1 (fully punched), at its `stun` level (0..1; 0 while a
## ride poses it).
func update(delta: float, drive: PoseDrive) -> void:
	var aim := drive.facing.angle()
	if not _primed:
		_prime(aim, drive.stances)
	arms.update(delta, drive.stances)
	gait.update(delta, drive)
	_springs.chase(self, aim, delta)
	_twist_torso(drive.facing, drive.punch)
	_step_lean(delta, drive.velocity, drive.top_speed)
	_place_head(drive.facing)


## Snap every part to `aim` and each hand to the stance `stances` names, on the first update.
func _prime(aim: float, stances: Array) -> void:
	torso_angle = aim
	_springs.reset(aim)
	hip_angle = aim
	head_angle = aim
	hand_angles = [aim, aim]
	weapon_angle = aim
	arms.prime(stances)
	_primed = true


## The shoulders' angle and lunge over their spring: a punch (each hand's extension in `punch`)
## drives the shoulder on its side forward and the body in behind it along `facing`, as the fist
## goes; a runner's shoulders rock against the legs and lead the hips.
func _twist_torso(facing: Vector2, punch: Array) -> void:
	var punching := maxf(punch[0], punch[1])
	var run := gait.run_amount()
	# The one on the forward-swinging arm's side comes forward. Added over the spring, which is far
	# too slow to follow a stride.
	var run_twist := -sin(gait.stride_phase()) * CharacterStrideConfig.pose_run_sway * run
	torso_angle = wrapf(
		_springs.torso_core + (punch[1] - punch[0]) * CharacterMeleeConfig.pose_punch_twist
				+ run_twist,
		-PI,
		PI,
	)
	# A runner leans into the run: the shoulders lead the hips along the way it travels.
	torso_offset = facing * (punching * CharacterMeleeConfig.pose_punch_lunge) \
		+ gait.move_dir * (CharacterStrideConfig.pose_run_lean * run)


## The head's lean into the movement (`velocity` over `top_speed`), on a soft spring.
func _step_lean(delta: float, velocity: Vector2, top_speed: float) -> void:
	var lean_target := velocity / maxf(top_speed, 1.0) * CharacterPoseHeadConfig.lean
	_lean_vel = Vector2(
		PoseSprings.accel(
			_lean_vel.x,
			lean_target.x - _lean.x,
			CharacterPoseHeadConfig.lean_freq,
			CharacterPoseHeadConfig.lean_damping,
			delta,
		),
		PoseSprings.accel(
			_lean_vel.y,
			lean_target.y - _lean.y,
			CharacterPoseHeadConfig.lean_freq,
			CharacterPoseHeadConfig.lean_damping,
			delta,
		),
	)
	_lean += _lean_vel * delta


## The head's shift (the lean, a breath along `facing`, a bob per step, the lunge) and a stagger's
## sway of the hips and loll of the head, then the shoulders' shift over the planted foot.
func _place_head(facing: Vector2) -> void:
	var walk := gait.walk_amount()
	var stride := gait.stride_phase()
	var breath := sin(gait.time * TAU / maxf(CharacterPoseHeadConfig.breath_period, 0.1)
		+ gait.phase) * CharacterPoseHeadConfig.breath * (1.0 - walk)
	var bob := cos(stride * 2.0) * CharacterPoseHeadConfig.bob * walk  # A bob per step.
	# A stunned walk sways the hips over the planted foot (foot 0, the right, is planted while cos >
	# 0) and lolls the head a quarter of a stride behind.
	var across := Vector2.from_angle(hip_angle).orthogonal()
	var stagger := gait.stun_amount() * walk
	hip_sway = across * (-cos(stride) * CharacterStunConfig.stagger_sway * stagger)
	head_offset = _lean + facing * breath + gait.move_dir * bob + torso_offset \
		+ across * (sin(stride) * CharacterStunConfig.stagger_bob * stagger)
	# The upper body shifts over the planted foot each step (foot 0 is planted while cos > 0); the
	# head is set before this, so it stays steady over the rocking shoulders.
	torso_offset += Vector2.from_angle(hip_angle).orthogonal() * (-cos(stride) \
		* CharacterStrideConfig.pose_run_shoulder_shift * gait.run_amount())
