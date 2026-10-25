extends RefCounted
## Character RIG (Character domain, animate layer): the standing skeleton as 3D joints (local x/y
## over the floor plus height z), solved fresh from the live pose and the hands. Both the standing
## body's limbs (character_visuals.gd) and the ragdoll's starting pose (character_ragdoll.gd) are
## drawn from it, so a body falls from exactly the pose it was standing in.
## - The upper body (chest, head, shoulders) sits at the pose's torso frame and lunge; the hips and
##   feet at its hip frame, which stays planted while the shoulders twist over it.
## - Each arm is two-bone IK from its shoulder to where the hands layer holds the fist, at the
##   grip height of its stance, the elbow bent toward the stance's pole. A hand out of reach pulls
##   its shoulder after it (a punch's lean-in), up to CharacterBodyConfig.shoulder_reach.
## - Each foot strides fore and aft, opposite to the arm on its side, lifting as it swings through;
##   the knee is IK bent forward.
## - A crouch lowers the hips to the character's eased posture height and pitches the spine forward
##   about the pelvis (the neck pitching on, so the head sits ahead of and above the shoulders); the
##   hips and feet come together, the feet standing a little ahead of the pelvis so the knees lead.
## - A stunned body hunches: the spine and the neck pitch forward by the pose's `hunch()` on top of
## any crouch, its stride is shorter (`CharacterStunConfig.stagger_stride`) and its pelvis sways
## with the pose's
##   `hip_sway`.
## - Each ankle rests where the legs layer (character_legs.gd) stopped it against a wall or piece of
##   furniture.
## Joints are read by index (the constants below, shared with the ragdoll) through `point(i)`, and
## each foot's direction through `toes(i)`. Index pairs are per hand side (0 = the character's right
## as drawn, 1 = the left). A rig also answers `torso()` and `face()`, so a crouched body is drawn
## like a fallen one. Tuning: CharacterBodyConfig, CharacterStrideConfig,
## CharacterStanceConfig.stances, CharacterPostureConfig.postures.

const HEAD := 0
const CHEST := 1
const PELVIS := 2
const BELLY := 3
const SHOULDER := [4, 5]
const HIP := [6, 7]
const ELBOW := [8, 9]
const HAND := [10, 11]
const KNEE := [12, 13]
const ANKLE := [14, 15]
## The back, opposite the belly.
const SPINE := 16
## Straight up, out of the floor.
const UP := Vector3(0.0, 0.0, 1.0)
## The pose the measures read the solve's angles and offsets off.
const Pose = preload("res://scenes/character/body/character_pose.gd")

## How many rigs have been solved in all (a test reads it to check a frame's callers share one
## solve).
static var solves := 0
## The measures every solve takes afresh and places the joints from (solves run one at a time;
## it keeps what the last one read until the next).
static var _measures := Measures.new()

## Vector3 per joint index.
var _points: Array = []
## Per side: the way the foot points (unit, flat).
var _toes := [Vector3.RIGHT, Vector3.RIGHT]
## The way the face looks (unit, flat).
var _face := Vector3.RIGHT
## Per side: the way the knee bends toward.
var _knee_poles := [Vector3.RIGHT, Vector3.RIGHT]
## Bone lengths (px), for re-solving a knee.
var _thigh := 0.0
var _shin := 0.0


## Solve the skeleton of `character` as it stands now. With `with_legs` (the default) each ankle
## takes the place the legs layer rested it at against a wall or piece of furniture
## (`character.foot_clamp(i)`, when it has one); the legs layer itself solves without, to learn
## where the legs would go unobstructed.
func _init(character: CharacterBody2D, with_legs := true) -> void:
	solves += 1
	var m := _measures
	m._measure(character)
	_thigh = m.thigh
	_shin = m.shin
	_points.resize(17)
	_face = Vector3(cos(m.pose.head_angle), sin(m.pose.head_angle), 0.0)
	m._place(character, _points, _knee_poles, _toes)
	if with_legs:
		_rest_feet(character)


## Each ankle the legs layer rested against something (`character.foot_clamp(i)`) moved there, its
## knee re-solved.
func _rest_feet(character: CharacterBody2D) -> void:
	for i in 2:
		var rested: Variant = character.foot_clamp(i)
		if rested != null:
			var ankle: Vector3 = _points[ANKLE[i]]
			ankle.x = (rested as Vector2).x
			ankle.y = (rested as Vector2).y
			_points[ANKLE[i]] = ankle
			_points[KNEE[i]] = knee_at(i, ankle)


## Where side `i`'s knee sits with its ankle at `ankle`: the middle joint of the leg's two bones,
## bent the way this pose bends it.
func knee_at(i: int, ankle: Vector3) -> Vector3:
	return Measures._bend(_points[HIP[i]], ankle, _thigh, _shin, _knee_poles[i])


## Joint `i`'s position (local x/y px, z = height px).
func point(i: int) -> Vector3:
	return _points[i]


## Which way side `i`'s toes point (unit, flat).
func toes(i: int) -> Vector3:
	return _toes[i]


## Which way the face looks (unit, flat).
func face() -> Vector3:
	return _face


## The trunk's orientation: x toward the right shoulder, y up the spine (hips to chest), z out of
## the chest. A body face down has z pointing at the floor.
func torso() -> Basis:
	var y: Vector3 = (_points[CHEST] - _points[PELVIS]).normalized()
	var across: Vector3 = _points[SHOULDER[1]] - _points[SHOULDER[0]]
	var x := (across - y * across.dot(y)).normalized()
	return Basis(x, y, x.cross(y))


## The measures one solve builds the skeleton from, read off the character as it stands (its
## bone lengths in px, the held weapon's hand, a stagger, and the body's frames and fold in `fold`),
## and the steps that place the joints from them into the solving rig's own arrays: the trunk, then
## each arm and leg. The rig keeps one (`_measures`) for every solve, taken afresh by `_measure`
## each time, so a solve allocates no measures and its steps read them as their own.
class Measures:
	## The pose the solve reads (the character's `pose`).
	var pose: Pose
	## The body radius.
	var r := 0.0
	## The body's frames, its heights as the posture folds it and the feet's spacing, built once.
	var fold := Fold.new()
	## The bones: upper arm, forearm, thigh and shin; how far an arm reaches before its shoulder
	## follows.
	var upper := 0.0
	var fore := 0.0
	var thigh := 0.0
	var shin := 0.0
	var arm_reach := 0.0
	## A foot's height at rest.
	var foot_z := 0.0
	## The hand that holds the weapon (its side's foot is staggered back in a crouch), and the share
	## of a stride a stunned walk keeps.
	var weapon_hand := 0
	var staggered := 1.0
	## The solving rig's joints (by index), knee poles and toes (per side), handed in by `_place`.
	var _points: Array = []
	var _knee_poles: Array = []
	var _toes: Array = []


	## Take the measures of `character` as it stands now, every field anew.
	func _measure(character: CharacterBody2D) -> void:
		pose = character.pose
		r = character.radius
		fold.take(character, pose, r)
		upper = CharacterBodyConfig.upper_arm * r
		fore = CharacterBodyConfig.forearm * r
		thigh = CharacterBodyConfig.thigh * r
		shin = CharacterBodyConfig.shin * r
		arm_reach = (upper + fore) * CharacterBodyConfig.arm_extension
		foot_z = CharacterRagdollConfig.limb_radius * r
		var item: Item = character.inventory.current_item()
		weapon_hand = item.weapon_hand() if item != null else 0
		# A stunned walk's shorter steps.
		staggered = lerpf(1.0, CharacterStunConfig.stagger_stride, pose.gait.stun_amount())


	## Place the joints of `character`, as measured, into the rig's `points` (sized for every
	## joint), `knee_poles` and `toes`: the trunk, then each side's arm and leg.
	func _place(character: CharacterBody2D, points: Array, knee_poles: Array, toes: Array) -> void:
		_points = points
		_knee_poles = knee_poles
		_toes = toes
		_trunk()
		for i in 2:
			_arm(character, i)
			_leg(character, i)


	## The chest, head and pelvis, and the belly and back between them: the chest at the lunge, half
	## the lean ahead; the neck pitching on from the shoulders, so the head sits ahead of and above
	## them; the pelvis half the lean back, swayed by a stagger.
	func _trunk() -> void:
		var f := fold
		var lunge := Vector3(pose.torso_offset.x, pose.torso_offset.y, 0.0)
		var neck_pitch := (f.pitch
				+ deg_to_rad(CharacterPostureConfig.body_crouch_neck_pitch) * f.folded)
		var neck := (CharacterBodyConfig.head_height - CharacterBodyConfig.shoulder_height) * r
		_points[CHEST] = lunge + f.fwd * f.lean * 0.5 + UP * f.chest_z
		_points[HEAD] = (Vector3(pose.head_offset.x, pose.head_offset.y, 0.0)
				+ f.fwd * (f.lean * 0.5 + neck * sin(neck_pitch))
				+ UP * (f.chest_z + neck * cos(neck_pitch)))
		_points[PELVIS] = (-f.fwd * f.lean * 0.5 + UP * f.hip_z
				+ Vector3(pose.hip_sway.x, pose.hip_sway.y, 0.0))
		var mid: Vector3 = (_points[CHEST] + _points[PELVIS]) * 0.5
		# Out of the chest, square to the leaning spine.
		var belly := f.fwd * cos(f.pitch) - UP * sin(f.pitch)
		_points[BELLY] = mid + belly * CharacterRagdollConfig.belly * r
		_points[SPINE] = mid - belly * CharacterRagdollConfig.belly * r


	## Side `i`'s arm: the shoulder reaches for the fist the hands layer holds, at its stance's grip
	## height, following it when it is out of reach; the elbow bends toward the stance's pole.
	func _arm(character: CharacterBody2D, i: int) -> void:
		var f := fold
		var out := -1.0 if i == 0 else 1.0
		var shoulder: Vector3 = (_points[CHEST]
				+ f.right * out * CharacterBodyConfig.shoulder_width * r)
		var grip: Vector2 = character.hand_position(i)
		var hand := Vector3(grip.x, grip.y, pose.arms.grip_height(i) * r * f.height)
		hand.z = clampf(hand.z, shoulder.z - arm_reach * 0.98, shoulder.z + arm_reach * 0.98)
		var flat := Vector2(hand.x - shoulder.x, hand.y - shoulder.y)
		var rise := hand.z - shoulder.z
		var flat_reach := sqrt(maxf(arm_reach * arm_reach - rise * rise, 0.0))
		if flat.length() > flat_reach:
			var follow := minf(flat.length() - flat_reach, CharacterBodyConfig.shoulder_reach * r)
			shoulder += Vector3(flat.x, flat.y, 0.0).normalized() * follow
		var pole: Vector3 = pose.arms.elbow_pole(i)
		_points[SHOULDER[i]] = shoulder
		_points[HAND[i]] = hand
		_points[ELBOW[i]] = _bend(
			shoulder,
			hand,
			upper,
			fore,
			f.right * out * pole.x + f.fwd * pole.y + UP * pole.z,
		)


	## Side `i`'s leg: the hip, the striding (or kicking) ankle, the knee bent toward the way the
	## leg leads, and the toes.
	func _leg(character: CharacterBody2D, i: int) -> void:
		var f := fold
		var out := -1.0 if i == 0 else 1.0
		_points[HIP[i]] = _points[PELVIS] + f.hip_right * out * f.hip_half
		_points[ANKLE[i]] = _stride_ankle(i)
		_knee_poles[i] = f.hip_fwd
		_toes[i] = f.hip_fwd
		var kick: float = character.leg_kick_amount(i)
		if kick > 0.0:
			_kick_leg(character, i, kick)
		_points[KNEE[i]] = _bend(_points[HIP[i]], _points[ANKLE[i]], thigh, shin, _knee_poles[i])


	## Where side `i`'s ankle strides: along the hips' forward, back when the arm on its side swings
	## forward, lifting as it swings through. A crouch stands the feet closer together, a little
	## ahead of the pelvis and staggered (the weapon hand's side back), and takes a shorter step.
	func _stride_ankle(i: int) -> Vector3:
		var f := fold
		var phase: float = pose.gait.stride_phase() + (0.0 if i == 0 else PI)
		var walk: float = pose.gait.walk_amount()
		var run: float = pose.gait.run_amount()  # A run strides wider and lifts higher.
		var stride := lerpf(
			CharacterStrideConfig.body_stride,
			CharacterStrideConfig.body_run_stride,
			run,
		) \
			* lerpf(1.0, CharacterPostureConfig.body_crouch_stride, f.folded) * staggered
		var foot_lift := lerpf(
			CharacterStrideConfig.body_foot_lift,
			CharacterStrideConfig.body_run_foot_lift,
			run,
		)
		var step := -sin(phase) * walk * stride * r
		var lift := maxf(-cos(phase), 0.0) * walk * foot_lift * r  # Off the floor mid-swing.
		var stagger := ((-0.5 if i == weapon_hand else 0.5)
				* CharacterPostureConfig.body_crouch_stagger * r * f.folded)
		var base := (f.hip_right * (-1.0 if i == 0 else 1.0) * f.foot_half
				+ f.hip_fwd * (f.foot_fwd + stagger))
		return Vector3(base.x, base.y, foot_z + lift) + f.hip_fwd * step


	## A kick `kick` of the way out on side `i`: the foot rises first, then is thrown out along the
	## aim, as far as the leg reaches at that height; the knee leads along the aim and the toes turn
	## to it.
	func _kick_leg(character: CharacterBody2D, i: int, kick: float) -> void:
		var hip: Vector3 = _points[HIP[i]]
		var ankle: Vector3 = _points[ANKLE[i]]
		var aim := Vector3(character.facing.x, character.facing.y, 0.0)
		var kick_z := CharacterMeleeConfig.kick_foot_height * r * fold.height
		var leg_rise := hip.z - kick_z
		var reach := minf(
			CharacterMeleeConfig.kick_reach,
			sqrt(maxf((thigh + shin) * (thigh + shin) - leg_rise * leg_rise, 0.0)) * 0.98,
		)
		var thrown := hip + aim * reach
		ankle.x = lerpf(ankle.x, thrown.x, kick * kick)
		ankle.y = lerpf(ankle.y, thrown.y, kick * kick)
		ankle.z = lerpf(ankle.z, kick_z, minf(kick * 2.0, 1.0))
		_points[ANKLE[i]] = ankle
		_knee_poles[i] = aim
		_toes[i] = fold.hip_fwd.lerp(aim, kick).normalized()


	## Where the middle joint of a two-bone chain from `a` to `b` (bone lengths `l1`, `l2`) sits,
	## bent toward `pole`.
	static func _bend(a: Vector3, b: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
		var ab := b - a
		var d := clampf(ab.length(), 0.001, l1 + l2 - 0.001)
		var along := ab.normalized()
		var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
		var side := (pole - along * pole.dot(along)).normalized()
		return a + along * x + side * h


## The body's frame and the posture's fold as one solve measures them (`Measures.fold`): the
## shoulders' and the hips' frames, the heights a lower posture scales and folds, and the feet's
## spacing. Built once with the shared measures and taken afresh by `take` each solve.
class Fold:
	## The shoulders' forward and hand 1's side (the character's left as drawn: Godot's orthogonal()
	## turns counter-clockwise), and the hips' (flat, unit).
	var fwd := Vector3.ZERO
	var right := Vector3.ZERO
	var hip_fwd := Vector3.ZERO
	var hip_right := Vector3.ZERO
	## The posture's height (1 standing) and how far it folds the body (0 standing .. 1 crouched).
	var height := 1.0
	var folded := 0.0
	## How far the spine pitches forward (rad), its length, and how far the chest sits ahead of the
	## pelvis.
	var pitch := 0.0
	var spine := 0.0
	var lean := 0.0
	## The heights of the hips and the chest.
	var hip_z := 0.0
	var chest_z := 0.0
	## Half the hips' and the feet's widths, and how far the feet stand ahead of the pelvis.
	var hip_half := 0.0
	var foot_half := 0.0
	var foot_fwd := 0.0


	## Take the frames and the fold of `character` (body radius `r`) as it stands now, its `pose`
	## turning them, every field anew.
	func take(character: CharacterBody2D, pose: Pose, r: float) -> void:
		_frames(pose)
		_heights(character, pose, r)
		hip_half = (CharacterBodyConfig.hip_width * r
				* lerpf(1.0, CharacterPostureConfig.body_crouch_hip_width, folded))
		foot_half = (CharacterBodyConfig.hip_width * r
				* lerpf(1.0, CharacterPostureConfig.body_crouch_foot_gap, folded))
		foot_fwd = CharacterPostureConfig.body_crouch_foot_ahead * r * folded - lean * 0.5


	## The shoulders' frame (turned to the pose's torso angle) and the hips' (its hip angle).
	func _frames(pose: Pose) -> void:
		var torso_dir := Vector2.from_angle(pose.torso_angle)
		fwd = Vector3(torso_dir.x, torso_dir.y, 0.0)
		right = Vector3(torso_dir.orthogonal().x, torso_dir.orthogonal().y, 0.0)
		var hips := Vector2.from_angle(pose.hip_angle)
		hip_fwd = Vector3(hips.x, hips.y, 0.0)
		hip_right = Vector3(hips.orthogonal().x, hips.orthogonal().y, 0.0)


	## A lower posture scales the standing heights down and folds the body: the spine pitches
	## forward about the pelvis (the pelvis sits back and the chest forward by half the lean, so the
	## body stays centred over its feet), the hips and feet come together, and the feet stand ahead
	## of the pelvis so the knees lead over the toes.
	func _heights(character: CharacterBody2D, pose: Pose, r: float) -> void:
		height = character.movement.posture_height()
		var crouch_height: float = CharacterPostureConfig.postures[&"crouch"]["height"]
		folded = clampf((1.0 - height) / maxf(1.0 - crouch_height, 0.01), 0.0, 1.0)
		# A stun hunches it on.
		pitch = deg_to_rad(CharacterPostureConfig.body_crouch_pitch) * folded + pose.gait.hunch()
		spine = (CharacterBodyConfig.shoulder_height - CharacterBodyConfig.hip_height) * r
		lean = spine * sin(pitch)
		# A run sinks.
		hip_z = ((CharacterBodyConfig.hip_height
				- CharacterStrideConfig.body_run_hip_drop * pose.gait.run_amount()) * r * height)
		chest_z = CharacterBodyConfig.hip_height * r * height + spine * cos(pitch)
