extends RefCounted
## Character RIG (Character domain, animate layer): the standing skeleton as 3D joints (local x/y
## over the floor plus height z), solved fresh from the live pose and the hands. Both the standing
## body's limbs (character_visuals.gd) and the ragdoll's starting pose (character_ragdoll.gd) are
## drawn from it, so a body falls from exactly the pose it was standing in.
## - The upper body (chest, head, shoulders) sits at the pose's torso frame and lunge; the hips and
##   feet at its hip frame, which stays planted while the shoulders twist over it.
## - Each arm is two-bone IK from its shoulder to where the hands layer holds the fist, at the
##   grip height of its stance, the elbow bent toward the stance's pole. A hand out of reach pulls
##   its shoulder after it (a punch's lean-in), up to CharacterConfig.body_shoulder_reach.
## - Each foot strides fore and aft, opposite to the arm on its side, lifting as it swings through;
##   the knee is IK bent forward.
## - A crouch lowers the hips to the character's eased posture height and pitches the spine forward
##   about the pelvis (the neck pitching on, so the head sits ahead of and above the shoulders); the
##   hips and feet come together, the feet standing a little ahead of the pelvis so the knees lead.
## - A stunned body hunches: the spine and the neck pitch forward by the pose's `hunch()` on top of
##   any crouch, its stride is shorter (`stun_stagger_stride`) and its pelvis sways with the pose's
##   `hip_sway`.
## - Each ankle rests where the legs layer (character_legs.gd) stopped it against a wall or piece of
##   furniture.
## Joints are read by index (the constants below, shared with the ragdoll) through `point(i)`, and
## each foot's direction through `toes(i)`. Index pairs are per hand side (0 = the character's right
## as drawn, 1 = the left). A rig also answers `torso()` and `face()`, so a crouched body is drawn
## like a fallen one. Tuning: CharacterConfig.body_*, CharacterConfig.stances,
## CharacterConfig.postures.

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

## How many rigs have been solved in all (a test reads it to check a frame's callers share one
## solve).
static var solves := 0

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
	var m := RigMeasures.new(character)
	_thigh = m.thigh
	_shin = m.shin
	_points.resize(17)
	_face = Vector3(cos(m.pose.head_angle), sin(m.pose.head_angle), 0.0)
	_trunk(m)
	for i in 2:
		_arm(character, m, i)
		_leg(character, m, i)
	if with_legs:
		_rest_feet(character)


## The chest, head and pelvis, and the belly and back between them: the chest at the lunge, half
## the lean ahead; the neck pitching on from the shoulders, so the head sits ahead of and above
## them; the pelvis half the lean back, swayed by a stagger.
func _trunk(m: RigMeasures) -> void:
	var pose := m.pose
	var lunge := Vector3(pose.torso_offset.x, pose.torso_offset.y, 0.0)
	var neck_pitch := m.pitch + deg_to_rad(CharacterConfig.body_crouch_neck_pitch) * m.folded
	var neck := (CharacterConfig.body_head_height - CharacterConfig.body_shoulder_height) * m.r
	_points[CHEST] = lunge + m.fwd * m.lean * 0.5 + UP * m.chest_z
	_points[HEAD] = (Vector3(pose.head_offset.x, pose.head_offset.y, 0.0)
			+ m.fwd * (m.lean * 0.5 + neck * sin(neck_pitch))
			+ UP * (m.chest_z + neck * cos(neck_pitch)))
	_points[PELVIS] = (-m.fwd * m.lean * 0.5 + UP * m.hip_z
			+ Vector3(pose.hip_sway.x, pose.hip_sway.y, 0.0))
	var mid: Vector3 = (_points[CHEST] + _points[PELVIS]) * 0.5
	# Out of the chest, square to the leaning spine.
	var belly := m.fwd * cos(m.pitch) - UP * sin(m.pitch)
	_points[BELLY] = mid + belly * CharacterConfig.ragdoll_belly * m.r
	_points[SPINE] = mid - belly * CharacterConfig.ragdoll_belly * m.r


## Side `i`'s arm: the shoulder reaches for the fist the hands layer holds, at its stance's grip
## height, following it when it is out of reach; the elbow bends toward the stance's pole.
func _arm(character: CharacterBody2D, m: RigMeasures, i: int) -> void:
	var out := -1.0 if i == 0 else 1.0
	var shoulder: Vector3 = (_points[CHEST]
			+ m.right * out * CharacterConfig.body_shoulder_width * m.r)
	var grip: Vector2 = character.hand_position(i)
	var hand := Vector3(grip.x, grip.y, m.pose.grip_height(i) * m.r * m.height)
	hand.z = clampf(hand.z, shoulder.z - m.arm_reach * 0.98, shoulder.z + m.arm_reach * 0.98)
	var flat := Vector2(hand.x - shoulder.x, hand.y - shoulder.y)
	var rise := hand.z - shoulder.z
	var flat_reach := sqrt(maxf(m.arm_reach * m.arm_reach - rise * rise, 0.0))
	if flat.length() > flat_reach:
		var follow := minf(flat.length() - flat_reach, CharacterConfig.body_shoulder_reach * m.r)
		shoulder += Vector3(flat.x, flat.y, 0.0).normalized() * follow
	var pole: Vector3 = m.pose.elbow_pole(i)
	_points[SHOULDER[i]] = shoulder
	_points[HAND[i]] = hand
	_points[ELBOW[i]] = _bend(
		shoulder,
		hand,
		m.upper,
		m.fore,
		m.right * out * pole.x + m.fwd * pole.y + UP * pole.z,
	)


## Side `i`'s leg: the hip, the striding (or kicking) ankle, the knee bent toward the way the leg
## leads, and the toes.
func _leg(character: CharacterBody2D, m: RigMeasures, i: int) -> void:
	var out := -1.0 if i == 0 else 1.0
	_points[HIP[i]] = _points[PELVIS] + m.hip_right * out * m.hip_half
	_points[ANKLE[i]] = _stride_ankle(m, i)
	_knee_poles[i] = m.hip_fwd
	_toes[i] = m.hip_fwd
	var kick: float = character.leg_kick_amount(i)
	if kick > 0.0:
		_kick_leg(character, m, i, kick)
	_points[KNEE[i]] = _bend(_points[HIP[i]], _points[ANKLE[i]], m.thigh, m.shin, _knee_poles[i])


## Where side `i`'s ankle strides: along the hips' forward, back when the arm on its side swings
## forward, lifting as it swings through. A crouch stands the feet closer together, a little ahead
## of the pelvis and staggered (the weapon hand's side back), and takes a shorter step.
func _stride_ankle(m: RigMeasures, i: int) -> Vector3:
	var out := -1.0 if i == 0 else 1.0
	var phase: float = m.pose.stride_phase() + (0.0 if i == 0 else PI)
	var walk: float = m.pose.walk_amount()
	var run: float = m.pose.run_amount()  # A run strides wider and lifts higher.
	var stride := lerpf(CharacterConfig.body_stride, CharacterConfig.body_run_stride, run) \
		* lerpf(1.0, CharacterConfig.body_crouch_stride, m.folded) * m.staggered
	var foot_lift := lerpf(
		CharacterConfig.body_foot_lift,
		CharacterConfig.body_run_foot_lift,
		run,
	)
	var step := -sin(phase) * walk * stride * m.r
	var lift := maxf(-cos(phase), 0.0) * walk * foot_lift * m.r  # Off the floor mid-swing.
	var stagger := ((-0.5 if i == m.weapon_hand else 0.5) * CharacterConfig.body_crouch_stagger
			* m.r * m.folded)
	var base := m.hip_right * out * m.foot_half + m.hip_fwd * (m.foot_fwd + stagger)
	return Vector3(base.x, base.y, m.foot_z + lift) + m.hip_fwd * step


## A kick `kick` of the way out on side `i`: the foot rises first, then is thrown out along the
## aim, as far as the leg reaches at that height; the knee leads along the aim and the toes turn to
## it.
func _kick_leg(character: CharacterBody2D, m: RigMeasures, i: int, kick: float) -> void:
	var hip: Vector3 = _points[HIP[i]]
	var ankle: Vector3 = _points[ANKLE[i]]
	var aim := Vector3(character.facing.x, character.facing.y, 0.0)
	var kick_z := CharacterConfig.kick_foot_height * m.r * m.height
	var leg_rise := hip.z - kick_z
	var reach := minf(
		CharacterConfig.kick_reach,
		sqrt(maxf((m.thigh + m.shin) * (m.thigh + m.shin) - leg_rise * leg_rise, 0.0)) * 0.98,
	)
	var thrown := hip + aim * reach
	ankle.x = lerpf(ankle.x, thrown.x, kick * kick)
	ankle.y = lerpf(ankle.y, thrown.y, kick * kick)
	ankle.z = lerpf(ankle.z, kick_z, minf(kick * 2.0, 1.0))
	_points[ANKLE[i]] = ankle
	_knee_poles[i] = aim
	_toes[i] = m.hip_fwd.lerp(aim, kick).normalized()


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
	return _bend(_points[HIP[i]], ankle, _thigh, _shin, _knee_poles[i])


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


## Where the middle joint of a two-bone chain from `a` to `b` (bone lengths `l1`, `l2`) sits, bent
## toward `pole`.
static func _bend(a: Vector3, b: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var ab := b - a
	var d := clampf(ab.length(), 0.001, l1 + l2 - 0.001)
	var along := ab.normalized()
	var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var side := (pole - along * pole.dot(along)).normalized()
	return a + along * x + side * h
