class_name PoseSprings extends RefCounted
## The springs of a character's pose (`character_pose.gd`'s `_springs`): the head, each hand, a held
## weapon and the shoulders each chase the aim on their own damped angular spring, each reeled back
## in when it trails the aim too far, and the hips plant while standing and turn to the way the body
## walks. `chase` steps them and writes the angles the pose publishes. Tuning:
## CharacterPoseTurnConfig, CharacterPoseHandConfig, CharacterPoseHeadConfig.glance and
## CharacterStrideConfig.pose_walk_sway.

## The pose the springs turn (`character_pose.gd`), for its published angles.
const Pose = preload("res://scenes/character/body/character_pose.gd")

## Shoulders' spring angle, before the punch twist (rad).
var torso_core := 0.0
## Shoulders' spring velocity (rad/s); a recoil kicks it.
var torso_vel := 0.0
## Hips' spring velocity (rad/s).
var _hip_vel := 0.0
## Head's spring velocity (rad/s).
var _head_vel := 0.0
## Per-hand spring velocity (rad/s).
var _hand_vels := [0.0, 0.0]
## Weapon's spring velocity (rad/s).
var _weapon_vel := 0.0


## Set the shoulders' spring on `aim` (rad), on the pose's first update.
func reset(aim: float) -> void:
	torso_core = aim


## Turn `pose`'s head, hands, weapon, shoulders' spring and hips toward `aim` (rad) over `delta`.
func chase(pose: Pose, aim: float, delta: float) -> void:
	_turn_parts(pose, aim, delta)
	_step_hips(pose, aim, delta)


## Turn the head, each hand, the weapon and the shoulders' spring toward `aim`, each on its own
## spring (see `accel`), each reeled back in when it trails the aim too far (see `_reel`): the head
## glances around while standing still and the shoulders sway with the walk.
func _turn_parts(pose: Pose, aim: float, delta: float) -> void:
	var gait: PoseGait = pose.gait
	var walk := gait.walk_amount()
	var glance := (sin(gait.time * 0.5 + gait.phase) * 0.6
		+ sin(gait.time * 0.21 + gait.phase * 2.3) * 0.4) \
		* CharacterPoseHeadConfig.glance * (1.0 - walk)
	var sway := sin(gait.stride_phase()) * CharacterStrideConfig.pose_walk_sway * walk
	_head_vel = accel(_head_vel, angle_difference(pose.head_angle, aim + glance),
		CharacterPoseTurnConfig.head_freq, CharacterPoseTurnConfig.head_damping, delta)
	var head := _reel(pose.head_angle + _head_vel * delta, _head_vel, aim,
		CharacterPoseTurnConfig.head_max_lag, delta)
	pose.head_angle = head.x
	_head_vel = head.y
	for i in 2:
		_turn_hand(pose, i, aim, delta)
	_weapon_vel = accel(_weapon_vel, angle_difference(pose.weapon_angle, aim),
		CharacterPoseHandConfig.weapon_freq, CharacterPoseHandConfig.weapon_damping, delta)
	var weapon := _reel(pose.weapon_angle + _weapon_vel * delta, _weapon_vel, aim,
		CharacterPoseHandConfig.weapon_max_lag, delta)
	pose.weapon_angle = weapon.x
	_weapon_vel = weapon.y
	torso_vel = accel(torso_vel, angle_difference(torso_core, aim + sway),
		CharacterPoseTurnConfig.torso_freq, CharacterPoseTurnConfig.torso_damping, delta)
	var torso := _reel(torso_core + torso_vel * delta, torso_vel, aim,
		CharacterPoseTurnConfig.torso_max_lag, delta)
	torso_core = torso.x
	torso_vel = torso.y


## Turn `pose`'s hand `i` toward `aim`: a steady one on the quick aim spring, a free one on the
## hand spring, each free hand at its own pace, so the pair doesn't turn as one rigid piece.
func _turn_hand(pose: Pose, i: int, aim: float, delta: float) -> void:
	var freq := CharacterPoseHandConfig.aim_freq
	var damping := CharacterPoseHandConfig.aim_damping
	var max_lag := CharacterPoseHandConfig.aim_max_lag
	if not pose.arms.steady[i]:
		var pace := 1.0 + CharacterPoseHandConfig.hand_pace_spread * (-0.5 if i == 0 else 0.5)
		freq = CharacterPoseHandConfig.hand_freq * pace
		damping = CharacterPoseHandConfig.hand_damping
		max_lag = CharacterPoseHandConfig.hand_max_lag
	var hand_angles: Array = pose.hand_angles
	var vel := accel(_hand_vels[i], angle_difference(hand_angles[i], aim), freq, damping, delta)
	var hand := _reel(hand_angles[i] + vel * delta, vel, aim, max_lag, delta)
	hand_angles[i] = hand.x
	_hand_vels[i] = hand.y


## `pose`'s hips plant while standing and turn to the way the character walks (a backward step
## stays facing the aim); the shoulders may twist only so far off them before the feet re-plant.
func _step_hips(pose: Pose, aim: float, delta: float) -> void:
	var gait: PoseGait = pose.gait
	var target := pose.hip_angle
	if gait.walk_amount() > 0.15:
		target = gait.move_dir.angle()
		if absf(angle_difference(aim, target)) > PI * 0.5:
			target += PI  # Walking backward: the feet still face the aim.
	# The hips' own spring never reels them in: their twist off the aim is held below.
	var vel := accel(_hip_vel, angle_difference(pose.hip_angle, target),
		CharacterPoseTurnConfig.hip_freq, CharacterPoseTurnConfig.hip_damping, delta)
	var hips := _reel(pose.hip_angle + vel * delta, vel, target, PI, delta)
	var planted := _reel(hips.x, hips.y, aim, CharacterPoseTurnConfig.hip_twist, delta)
	pose.hip_angle = planted.x
	_hip_vel = planted.y


## A damped spring's velocity after `delta`, pulled to close `error` (target − value): `freq` is
## its natural frequency (rad/s), `damping` its ratio (1 = no overshoot).
static func accel(vel: float, error: float, freq: float, damping: float, delta: float) -> float:
	return vel + (freq * freq * error - 2.0 * damping * freq * vel) * delta


## `angle` past `max_lag` behind `aim` is reeled back in quickly (CharacterPoseTurnConfig.lag_catch)
## rather than snapped, so a sudden flick drags it along smoothly instead of leaving it behind.
## Returns (angle, velocity).
static func _reel(angle: float, vel: float, aim: float, max_lag: float, delta: float) -> Vector2:
	var lag := angle_difference(aim, angle)
	if absf(lag) > max_lag:
		var excess := lag - signf(lag) * max_lag
		angle -= excess * (1.0 - exp(-CharacterPoseTurnConfig.lag_catch * delta))
		if signf(vel) == signf(lag):
			vel = 0.0  # Moving further away from the aim: stop it there.
	return Vector2(wrapf(angle, -PI, PI), vel)
