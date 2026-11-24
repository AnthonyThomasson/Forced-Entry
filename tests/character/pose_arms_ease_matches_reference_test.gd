extends GameTest
## The arms' stance easing (`pose_arms.gd`) keeps each hand's numbers as plain floats and makes no
## dictionary a frame; what it answers is what the dictionary version (a copy of the target stance
## with each number eased toward it) answered, bit for bit, through every stance change a fight
## makes, and the legs' own rig (`Rig.solve_legs`, solved again into one object) places the legs'
## joints as a fresh legs-only solve does, standing, walking and crouched.

const Arms := preload("res://scenes/character/body/pose_arms.gd")
const Rig := preload("res://scenes/character/body/character_rig.gd")
const KEYS := ["forward", "lateral", "height", "swing", "recoil_share"]
## Stances run through, in turn, for hand 0 and (a step later) hand 1: steady ones, free ones, the
## wavering one and a repeat.
const SEQUENCE := [&"relaxed", &"aim", &"aim", &"support", &"run", &"one_hand", &"one_hand",
		&"throw", &"relaxed", &"smg_grip", &"eyes", &"guard", &"relaxed"]


func describe() -> Dictionary:
	return {
		"name": "The pose's stance easing and the legs' rig match their plain forms",
		"description": "PoseArms eased on floats equals the dictionary easing it replaced, bit for "
			+ "bit; the legs layer's reused rig places the legs as a fresh legs-only solve does.",
		"tags": ["pose", "legs", "perf", "rig"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 500))
	s.switch(&"nav.rebake", false)
	s.actor(&"walker", &"puppet", Vector2(300, 250), { "start_slot": 6 })
	s.actor(&"ducker", &"puppet", Vector2(400, 250), { "start_slot": 6 })


func run(t: TestContext) -> void:
	_check_stance_easing(t)
	t.puppet(&"ducker").set_posture(&"crouch")
	t.puppet(&"walker").walk_to(Vector2(600, 250))
	for _step in 4:
		await t.frames(7)
		_check_legs_rig(t, &"walker")
		_check_legs_rig(t, &"ducker")


## The float easing against a reference that eases a copy of the target stance's dictionary.
func _check_stance_easing(t: TestContext) -> void:
	var gait := PoseGait.new()
	gait.set("_walk", 1.0)
	gait.set("_stride", 0.9)
	var arms := Arms.new(gait, PoseSprings.new())
	var now: Array[Dictionary] = [_data(&"relaxed").duplicate(), _data(&"relaxed").duplicate()]
	var delta := 1.0 / 60.0
	var same := true
	for n in SEQUENCE.size():
		var stances := [SEQUENCE[n], SEQUENCE[maxi(n - 1, 0)]]
		for _frame in 20:
			arms.update(delta, stances)
			for hand in 2:
				now[hand] = _eased(now[hand], _data(stances[hand]), delta)
				same = same and _same_hand(arms, hand, now[hand])
	t.check(same, "every hand's eased numbers, elbow pole and steadiness match the reference")


## The reference: the target's dictionary copied, each number eased toward it from `from`.
func _eased(from: Dictionary, to: Dictionary, delta: float) -> Dictionary:
	var k := 1.0 - exp(-CharacterStanceConfig.stance_ease * delta)
	var out := to.duplicate()
	for key in KEYS:
		out[key] = lerpf(from[key], to[key], k)
	out["waver"] = lerpf(from.get("waver", 0.0), to.get("waver", 0.0), k)
	out["elbow_pole"] = (from["elbow_pole"] as Vector3).lerp(to["elbow_pole"], k)
	return out


func _data(name: StringName) -> Dictionary:
	return CharacterStanceConfig.stances.get(name, CharacterStanceConfig.stances[&"relaxed"])


## Whether `arms`'s hand `hand` reads what the reference stance `ref` holds: its rest, its elbow
## pole, whether it is steady, its grip height and its offset (the gait is set mid-stride, walking,
## so the swing and the drift count).
func _same_hand(arms: RefCounted, hand: int, ref: Dictionary) -> bool:
	var along := Vector2.from_angle(0.7)
	var step := sin(0.9 + (0.0 if hand == 0 else PI))
	var wander := _wander(ref, float(hand) * 1.7)
	var offset: Vector2
	if ref["steady"]:
		offset = along.orthogonal() * (step * CharacterPoseHandConfig.aim_drift + wander)
	else:
		offset = along * (step * float(ref["swing"]))
	var grip := float(ref["height"]) + _wander(ref, float(hand) * 1.7 + 0.2) * 0.05
	return (
		arms.rest_forward(hand) == ref["forward"]
		and arms.rest_lateral(hand) == ref["lateral"]
		and arms.elbow_pole(hand) == ref["elbow_pole"]
		and arms.steady[hand] == ref["steady"]
		and arms.hand_offset(hand, along) == offset
		and arms.grip_height(hand) == grip
	)


## A wavering hand's wander in the reference (the gait's clock and phase at 0).
func _wander(ref: Dictionary, t: float) -> float:
	var w: float = ref.get("waver", 0.0)
	if w <= 0.0:
		return 0.0
	return w * (0.6 * sin(t * 7.3) + 0.4 * sin(t * 11.9))


## The legs' reused rig places every joint the legs read as a fresh legs-only solve does.
func _check_legs_rig(t: TestContext, id: StringName) -> void:
	var body: Node = t.actor(id)
	var fresh := Rig.new(body, false, false)
	var kept: Rig = body.anatomy.legs.get("_rig")
	if not t.require(kept != null, "%s: the legs layer keeps its own rig" % id):
		return
	for joint in [Rig.PELVIS, Rig.HIP[0], Rig.HIP[1], Rig.KNEE[0], Rig.KNEE[1], Rig.ANKLE[0],
			Rig.ANKLE[1]]:
		t.check(
			kept.point(joint) == fresh.point(joint),
			"%s: the reused rig places joint %d as a fresh solve does" % [id, joint],
		)
	for side in 2:
		t.check(kept.toes(side) == fresh.toes(side), "%s: toes %d match" % [id, side])
