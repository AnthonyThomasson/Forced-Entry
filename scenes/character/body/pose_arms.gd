class_name PoseArms extends RefCounted
## The arms of a character's pose (`character_pose.gd`'s `arms`): each hand eases between the
## stances its item asks for (CharacterStanceConfig.stances: where it rests, how high it is gripped,
## how its elbow bends), swings with the walk or, held steady, drifts and wanders by its stance's
## `waver`, and is thrown back by a recoil (`kick`) on its own spring. Read by the hands (the rest
## pose) and the rig (the grip and the elbow). Tuning: CharacterStanceConfig (stances, stance_ease,
## pose_recoil*), CharacterPoseHandConfig.aim_drift and CharacterStrideConfig's run hand rise and
## elbow lift.

## A wavering hand (a stance's `waver`) also rises and falls, this many body radii per px of its
## wander across, this many seconds out of step with it.
const WAVER_RISE := 0.05
const WAVER_LAG := 0.2

## Per hand: held steady (aiming or supporting), quick to the aim.
var steady := [false, false]
## Per hand: its stance, eased: the numbers of `CharacterStanceConfig.stances` it is on its way to,
## each its own, and the elbow's pole.
var _forward := [0.0, 0.0]
var _lateral := [0.0, 0.0]
var _height := [0.0, 0.0]
var _swing := [0.0, 0.0]
var _recoil_share := [0.0, 0.0]
var _wavering := [0.0, 0.0]
var _pole: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## Per-hand recoil (px back from the rest pose), on a spring.
var _recoil := [0.0, 0.0]
## Per-hand recoil spring velocity (px/s).
var _recoil_vel := [0.0, 0.0]
## The pose's gait, which the walk swing, the run's pumping arms and the wander follow.
var _gait: PoseGait
## The pose's springs, whose shoulders a recoil twists back.
var _springs: PoseSprings


## Arms that follow `gait` and twist `springs`' shoulders on a recoil.
func _init(gait: PoseGait, springs: PoseSprings) -> void:
	_gait = gait
	_springs = springs
	prime([&"relaxed", &"relaxed"])


## Snap each hand to the stance `stances` names, on the pose's first update.
func prime(stances: Array) -> void:
	for i in 2:
		var to := _stance_data(stances[i])
		_forward[i] = to["forward"]
		_lateral[i] = to["lateral"]
		_height[i] = to["height"]
		_swing[i] = to["swing"]
		_recoil_share[i] = to["recoil_share"]
		_wavering[i] = to.get("waver", 0.0)
		_pole[i] = to["elbow_pole"]
		steady[i] = to["steady"]


## Ease each hand by `delta` toward the stance `stances` names (the held item's hand_stance()), and
## step each hand's recoil spring.
func update(delta: float, stances: Array) -> void:
	var k := 1.0 - exp(-CharacterStanceConfig.stance_ease * delta)
	for i in 2:
		_ease(i, _stance_data(stances[i]), k)
	for i in 2:
		_recoil_vel[i] = PoseSprings.accel(
			_recoil_vel[i],
			-_recoil[i],
			CharacterStanceConfig.pose_recoil_freq,
			CharacterStanceConfig.pose_recoil_damping,
			delta,
		)
		_recoil[i] += _recoil_vel[i] * delta


## A hand's shift off its rest pose (local px), in its own frame (`along`, the unit way it faces):
## a free hand swings fore and aft with the walk (opposite to the other) as far as its stance
## allows, a steady hand only drifts a little sideways and wanders by its stance's `waver`; both
## minus any recoil.
func hand_offset(hand: int, along: Vector2) -> Vector2:
	var step := sin(_gait.stride_phase() + (0.0 if hand == 0 else PI)) * _gait.walk_amount()
	if steady[hand]:
		return (along.orthogonal() * (step * CharacterPoseHandConfig.aim_drift + _waver(hand, 0.0))
				- along * _recoil[hand])
	return along * (step * float(_swing[hand]) - _recoil[hand])


## A steady hand's slow wander (px; across its frame, and at `offset` out of step, up and down): its
## stance's `waver`, two out-of-step sines.
func _waver(hand: int, offset: float) -> float:
	var w: float = _wavering[hand]
	if w <= 0.0:
		return 0.0
	var t := _gait.time + hand * 1.7 + offset
	return w * (0.6 * sin(t * 7.3 + _gait.phase) + 0.4 * sin(t * 11.9 + _gait.phase * 1.7))


## How far ahead of the body center a hand rests (px), along its frame.
func rest_forward(hand: int) -> float:
	return _forward[hand]


## How far out to its own side a hand rests (px).
func rest_lateral(hand: int) -> float:
	return _lateral[hand]


## How high a hand is gripped (body radii off the floor): the arm bends to reach it.
func grip_height(hand: int) -> float:
	# Running pumps the arms: the hand swinging forward rises toward the chest, the back one drops
	# to the hip.
	var step := sin(_gait.stride_phase() + (0.0 if hand == 0 else PI))
	return (_height[hand]
			+ step * CharacterStrideConfig.pose_run_hand_rise * _gait.run_amount()
			+ _waver(hand, WAVER_LAG) * WAVER_RISE)


## Where a hand's elbow bends toward (out, forward, up).
func elbow_pole(hand: int) -> Vector3:
	# Running keeps the elbow tucked in by the body: it drops under the line to a hand swung forward
	# and rides up behind a hand swung back (the bend only ever sits in the plane through the
	# shoulder, the hand and this pole, so a fixed pole would throw the elbow out sideways at one
	# end of the swing).
	var pole: Vector3 = _pole[hand]
	pole.z -= (sin(_gait.stride_phase() + (0.0 if hand == 0 else PI))
			* CharacterStrideConfig.pose_run_elbow_lift * _gait.run_amount())
	return pole


## Recoil: throw `hand` (0 = right as drawn, 1 = left) back and twist the shoulders back on its
## side, `strength` times a pistol's kick. The other hand feels its share if it is steadying the
## weapon.
func kick(hand: int, strength := 1.0) -> void:
	_recoil_vel[hand] += (
		CharacterStanceConfig.pose_recoil * CharacterStanceConfig.pose_recoil_freq * strength
	)
	var other := 1 - hand
	_recoil_vel[other] += (
		CharacterStanceConfig.pose_recoil * CharacterStanceConfig.pose_recoil_freq * strength
		* float(_recoil_share[other])
	)
	var side := -1.0 if hand == 0 else 1.0
	_springs.torso_vel -= (side * CharacterStanceConfig.pose_recoil_twist
			* CharacterPoseTurnConfig.torso_freq * strength)


## A stance's configured values by name (an unknown name is a relaxed hand).
static func _stance_data(name: StringName) -> Dictionary:
	return CharacterStanceConfig.stances.get(name, CharacterStanceConfig.stances[&"relaxed"])


## Hand `i`'s numbers eased `k` (the share of the way) toward the stance `to` (its elbow pole too;
## `steady` switches at once).
func _ease(i: int, to: Dictionary, k: float) -> void:
	_forward[i] = lerpf(_forward[i], to["forward"], k)
	_lateral[i] = lerpf(_lateral[i], to["lateral"], k)
	_height[i] = lerpf(_height[i], to["height"], k)
	_swing[i] = lerpf(_swing[i], to["swing"], k)
	_recoil_share[i] = lerpf(_recoil_share[i], to["recoil_share"], k)
	_wavering[i] = lerpf(_wavering[i], to.get("waver", 0.0), k)
	_pole[i] = _pole[i].lerp(to["elbow_pole"], k)
	steady[i] = to["steady"]
