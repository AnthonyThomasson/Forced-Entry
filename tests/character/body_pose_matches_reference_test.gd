extends GameTest
## The 3D body's pose and the rig's stride are worked out with each number read once (#194 perf:
## `BodyMesh`'s sample and `Read`, the rig's `Stride`); what they answer is what the plain forms
## here answer, exactly, standing, walking, running and walking crouched: each joint lifted to the
## body's height with the knees and elbows bent in proportion, each ankle where the stride puts it,
## a steep limb's top turned toward the way the face looks, and a cap and a helmet each in its own
## shape after the head's covering changed.

const Rig := preload("res://scenes/character/body/character_rig.gd")
const IDS: Array[StringName] = [&"stander", &"walker", &"runner", &"ducker"]
## Facing away from the picture's "back", so a limb frame turned to a fixed way shows.
const FACING := Vector2.RIGHT


func describe() -> Dictionary:
	return {
		"name": "The body's pose and stride match their plain forms",
		"description": "BodyMesh's sampled joints, limb frames and headwear and the rig's ankles "
			+ "equal a plain working of the same numbers.",
		"tags": ["pose", "rig", "mirror", "3d", "perf"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 900))
	s.switch(&"nav.rebake", false)
	for i in IDS.size():
		s.actor(IDS[i], &"puppet", Vector2(200, 150 + 180 * i), { "facing": FACING })


func run(t: TestContext) -> void:
	var bodies := {}
	for id in IDS:
		var mesh: BodyMesh = BodyMesh.build(t.actor(id))
		t.world.add_child(mesh)
		bodies[id] = mesh
	t.puppet(&"ducker").set_posture(&"crouch")
	await t.seconds(0.4)
	t.puppet(&"walker").walk_to(Vector2(1300, 330))
	t.puppet(&"runner").set_run(true)
	t.puppet(&"runner").walk_to(Vector2(1300, 510))
	t.puppet(&"ducker").walk_to(Vector2(1300, 690))
	var strode := {}
	for _step in 4:
		await t.frames(9)
		for id in IDS:
			var body: Node2D = t.actor(id)
			var mesh: BodyMesh = bodies[id]
			_pose_now(mesh, body)
			_check_joints(t, id, mesh, body)
			_check_limb_frames(t, id, mesh)
			_check_ankles(t, id, body)
			strode[id] = maxf(strode.get(id, 0.0), body.anatomy.pose.gait.walk_amount())
	t.check(strode[&"walker"] > 0.3 and strode[&"ducker"] > 0.1, "premise: the walkers stride")
	_check_headwear(t, bodies[&"stander"], t.actor(&"stander"))


func _pose_now(mesh: BodyMesh, body: Node2D) -> void:
	mesh.set("_frame", -1)
	mesh.set("_posed", false)
	mesh.mirror_update(body)


## Every sampled joint: the rig's, lifted, with each knee and elbow bent in proportion.
func _check_joints(t: TestContext, id: StringName, mesh: BodyMesh, body: Node2D) -> void:
	var rig: Rig = body.anatomy.rig()
	var squeeze := Rig.squeeze(body.radius)
	var want := PackedVector3Array()
	for i in BodyMesh.JOINTS:
		want.append(_lift(rig.point(i), squeeze))
	for i in 2:
		want[Rig.KNEE[i]] = _bent(rig, [Rig.HIP[i], Rig.KNEE[i], Rig.ANKLE[i]], squeeze)
		want[Rig.ELBOW[i]] = _bent(rig, [Rig.SHOULDER[i], Rig.ELBOW[i], Rig.HAND[i]], squeeze)
	var got: PackedVector3Array = mesh.get("_sample")
	for i in BodyMesh.JOINTS:
		t.check(got[i] == want[i], "%s: joint %d sampled %s (plain %s)" % [id, i, got[i], want[i]])


## The middle joint of `chain` (from, middle, to), lifted with its ends and bent in proportion.
func _bent(rig: Rig, chain: Array, squeeze: float) -> Vector3:
	var a := rig.point(chain[0])
	var low := _lift(a, squeeze)
	var squeezed := _lift(rig.point(chain[2]), squeeze) - low
	var chord := rig.point(chain[2]) - a
	var offset := rig.point(chain[1]) - a
	var along := offset.dot(chord) / chord.length_squared()
	var off := offset - chord * along
	var turned := Vector3(off.x, off.z, off.y)
	var unit := squeezed.normalized()
	var bend := (turned - unit * turned.dot(unit)) * (squeezed.length() / chord.length())
	return low + squeezed * along + bend


func _lift(point: Vector3, squeeze: float) -> Vector3:
	return Vector3(point.x, maxf(point.z * squeeze, 0.0), point.y)


## Each upper arm and thigh: its top turned up, or toward the face as it grows steep.
func _check_limb_frames(t: TestContext, id: StringName, mesh: BodyMesh) -> void:
	var last: PackedVector3Array = mesh.get("_last")
	var face := last[BodyMesh.JOINTS + 2]
	var toward := Vector3(face.x, 0.0, face.z).normalized()
	var turned := 0
	for i in 2:
		for limb: Array in [
			[BodyMesh.UPPER + i, Rig.SHOULDER[i], Rig.ELBOW[i]],
			[BodyMesh.THIGH + i, Rig.HIP[i], Rig.KNEE[i]],
		]:
			var z := (last[limb[2]] - last[limb[1]]).normalized()
			var steep := smoothstep(BodyMesh.STEEP.x, BodyMesh.STEEP.y, absf(z.y))
			var hint := Vector3.UP.lerp(toward, steep)
			var want := (hint - z * hint.dot(z)).normalized()
			var got := mesh.part(limb[0]).transform.basis.y.normalized()
			turned += int(steep > 0.5)
			t.check(got.distance_to(want) < 0.001, "%s: part %d's top %s" % [id, limb[0], got])
	t.check(turned > 0, "%s: premise: a limb hangs steeply" % id)


## Each ankle where the stride puts it, from the gait and the tuning.
func _check_ankles(t: TestContext, id: StringName, body: Node2D) -> void:
	var rig: Rig = body.anatomy.rig()
	var gait: PoseGait = body.anatomy.pose.gait
	var r: float = body.radius
	var hips := Vector2.from_angle(body.anatomy.pose.hip_angle)
	var lengths := _stride_lengths(body)
	for i in 2:
		var phase := gait.stride_phase() + (0.0 if i == 0 else PI)
		var step := -sin(phase) * gait.walk_amount() * lengths.x * r
		var lift := maxf(-cos(phase), 0.0) * gait.walk_amount() * lengths.y * r
		var ankle := rig.point(Rig.ANKLE[i])
		# the ankle along the hips' forward, less where the foot stands, is the step; its height
		# the resting foot's plus the lift
		var ahead := ankle.dot(Vector3(hips.x, hips.y, 0.0)) - _foot_ahead(body, i)
		t.check(body.anatomy.legs.ankle(i) == null, "%s: premise: foot %d is free" % [id, i])
		t.check(
			absf(ahead - step) < 0.01,
			"%s: ankle %d strides %.3f (%.3f)" % [id, i, ahead, step],
		)
		_check_lift(
			t,
			"%s: ankle %d" % [id, i],
			ankle.z - CharacterRagdollConfig.limb_radius * r,
			lift,
		)


func _check_lift(t: TestContext, foot: String, up: float, lift: float) -> void:
	t.check(absf(up - lift) < 0.001, "%s lifts %.3f (%.3f)" % [foot, up, lift])


## The stride's length (x) and the foot's lift (y) of `body` now, in body radii.
func _stride_lengths(body: Node2D) -> Vector2:
	var gait: PoseGait = body.anatomy.pose.gait
	var folded: float = body.movement.posture_folded()
	var amount := gait.run_amount()
	var stride := lerpf(
		CharacterStrideConfig.body_stride, CharacterStrideConfig.body_run_stride, amount
	) \
		* lerpf(1.0, CharacterPostureConfig.body_crouch_stride, folded) \
		* lerpf(1.0, CharacterStunConfig.stagger_stride, gait.stun_amount())
	return Vector2(stride, lerpf(
		CharacterStrideConfig.body_foot_lift, CharacterStrideConfig.body_run_foot_lift, amount
	))


## How far ahead (px) of the body's origin foot `i` stands at rest: nothing standing; crouched,
## ahead of the pelvis and staggered, the weapon hand's side back.
func _foot_ahead(body: Node2D, i: int) -> float:
	var r: float = body.radius
	var folded: float = body.movement.posture_folded()
	var spine := (CharacterBodyConfig.shoulder_height - CharacterBodyConfig.hip_height) * r
	var pitch: float = (deg_to_rad(CharacterPostureConfig.body_crouch_pitch) * folded
			+ body.anatomy.pose.gait.hunch())
	var item: Item = body.inventory.current_item()
	var back := -0.5 if i == (item.weapon_hand() if item != null else 0) else 0.5
	return (
		CharacterPostureConfig.body_crouch_foot_ahead * r * folded - spine * sin(pitch) * 0.5
		+ back * CharacterPostureConfig.body_crouch_stagger * r * folded
	)


## A cap and then a helmet: each in its own shape, the head's sprite over its own dome.
func _check_headwear(t: TestContext, mesh: BodyMesh, body: Node2D) -> void:
	for worn: String in ["cap", "helmet", "cap"]:
		body.wardrobe.outfit.set_ids({ "head": &"hat" if worn == "cap" else &"helmet" })
		_pose_now(mesh, body)
		var shape: Vector3 = BodyMesh.CAP_SHAPE if worn == "cap" else BodyMesh.HELMET_SHAPE
		var head := mesh.part(BodyMesh.HEAD).transform
		var cover := mesh.part(BodyMesh.HEADWEAR).transform
		var wide := cover.basis.x.length() / head.basis.x.length()
		t.check(
			absf(wide - shape.x) < 0.001,
			"a %s is %.2f heads wide (%.2f)" % [worn, shape.x, wide],
		)
		var crown := mesh.part(BodyMesh.CROWN).transform.origin
		var over := (crown.y - head.origin.y - BodyMesh.CROWN_LIFT * RenderConfig.unit) \
			/ head.basis.y.length()
		t.check(over >= shape.y + shape.x * 0.85 - 0.001, "the %s's crown sprite is over it" % worn)
