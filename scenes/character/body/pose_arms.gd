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
## Per hand: its stance, eased.
var _stance := [_stance_data(&"relaxed"), _stance_data(&"relaxed")]
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


## Snap each hand to the stance `stances` names, on the pose's first update.
func prime(stances: Array) -> void:
	_stance = [_stance_data(stances[0]), _stance_data(stances[1])]


## Ease each hand by `delta` toward the stance `stances` names (the held item's hand_stance()), and
## step each hand's recoil spring.
func update(delta: float, stances: Array) -> void:
	for i in 2:
		_stance[i] = _eased(_stance[i], _stance_data(stances[i]), delta)
	steady = [_stance[0]["steady"], _stance[1]["steady"]]
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
	return along * (step * float(_stance[hand]["swing"]) - _recoil[hand])


## A steady hand's slow wander (px; across its frame, and at `offset` out of step, up and down): its
## stance's `waver`, two out-of-step sines.
func _waver(hand: int, offset: float) -> float:
	var w: float = _stance[hand].get("waver", 0.0)
	if w <= 0.0:
		return 0.0
	var t := _gait.time + hand * 1.7 + offset
	return w * (0.6 * sin(t * 7.3 + _gait.phase) + 0.4 * sin(t * 11.9 + _gait.phase * 1.7))


## How far ahead of the body center a hand rests (px), along its frame.
func rest_forward(hand: int) -> float:
	return _stance[hand]["forward"]


## How far out to its own side a hand rests (px).
func rest_lateral(hand: int) -> float:
	return _stance[hand]["lateral"]


## How high a hand is gripped (body radii off the floor): the arm bends to reach it.
func grip_height(hand: int) -> float:
	# Running pumps the arms: the hand swinging forward rises toward the chest, the back one drops
	# to the hip.
	var step := sin(_gait.stride_phase() + (0.0 if hand == 0 else PI))
	return (_stance[hand]["height"]
			+ step * CharacterStrideConfig.pose_run_hand_rise * _gait.run_amount()
			+ _waver(hand, WAVER_LAG) * WAVER_RISE)


## Where a hand's elbow bends toward (out, forward, up).
func elbow_pole(hand: int) -> Vector3:
	# Running keeps the elbow tucked in by the body: it drops under the line to a hand swung forward
	# and rides up behind a hand swung back (the bend only ever sits in the plane through the
	# shoulder, the hand and this pole, so a fixed pole would throw the elbow out sideways at one
	# end of the swing).
	var pole: Vector3 = _stance[hand]["elbow_pole"]
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
		* float(_stance[other]["recoil_share"])
	)
	var side := -1.0 if hand == 0 else 1.0
	_springs.torso_vel -= (side * CharacterStanceConfig.pose_recoil_twist
			* CharacterPoseTurnConfig.torso_freq * strength)


## A stance's configured values by name (an unknown name is a relaxed hand).
static func _stance_data(name: StringName) -> Dictionary:
	return CharacterStanceConfig.stances.get(name, CharacterStanceConfig.stances[&"relaxed"])


## `now` eased toward the stance `to` (its numbers and elbow pole; `steady` switches at once).
static func _eased(now: Dictionary, to: Dictionary, delta: float) -> Dictionary:
	var k := 1.0 - exp(-CharacterStanceConfig.stance_ease * delta)
	var out := to.duplicate()
	for key in ["forward", "lateral", "height", "swing", "recoil_share"]:
		out[key] = lerpf(now[key], to[key], k)
	out["waver"] = lerpf(now.get("waver", 0.0), to.get("waver", 0.0), k)
	out["elbow_pole"] = (now["elbow_pole"] as Vector3).lerp(to["elbow_pole"], k)
	return out
