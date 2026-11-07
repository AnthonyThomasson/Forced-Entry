extends GameTest
## One conservative near-solid query after the pose is shared by the hands and legs. In the open it
## skips every hand and leg sweep; at a wall and in a crowd the ordinary sweeps still run. Hand and
## ankle positions, and the muzzle they place, are exactly the ungated path's. The legs' own rig
## solve leaves the arms out and gives the legs' joints the full solve's.

const Rig := preload("res://scenes/character/body/character_rig.gd")
const IDS := [&"open", &"wall", &"crowd"]


func describe() -> Dictionary:
	return {
		"name": "The shared body gate matches the ungated sweeps",
		"description": "Open, wall and crowd bodies keep the same hands, ankles and muzzle with "
			+ "the shared near-solid gate; only the open body skips its sweeps.",
		"tags": ["contact", "hands", "legs", "perf"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.actor(&"open", &"puppet", Vector2(400, 500), { "start_slot": 6 })
	s.actor(&"wall", &"puppet", Vector2(30, 200), { "start_slot": 6 })
	s.actor(&"crowd", &"puppet", Vector2(600, 300), { "start_slot": 6 })
	s.actor(&"crowd_east", &"puppet", Vector2(640, 300), { "start_slot": 1 })
	s.actor(&"crowd_south", &"puppet", Vector2(600, 340), { "start_slot": 1 })


func run(t: TestContext) -> void:
	t.puppet(&"wall").aim_at(Vector2(-1000, 200))
	t.puppet(&"crowd").aim_at(Vector2(1000, 300))
	await t.seconds(2.0)
	var open: RefCounted = t.actor(&"open").anatomy.get("sweep")
	if not t.require(open != null, "the body owns a shared sweep gate"):
		return

	var before_casts: int = open.get("casts")
	var before_near: int = open.get("near_queries")
	await t.frames(3)
	t.check(
		open.get("casts") == before_casts,
		"the open body runs no hand or leg sweep while its shared gate is clear",
	)
	t.check(
		open.get("near_queries") > before_near,
		"the shared gate still polls each physics frame",
	)
	var fast := _capture(t)

	for id in IDS:
		t.actor(id).anatomy.sweep.set("gate_enabled", false)
	await t.frames(2)
	var plain := _capture(t)
	t.check(open.get("casts") > before_casts, "the ungated reference really sweeps in the open")

	for id in IDS:
		t.actor(id).anatomy.sweep.set("gate_enabled", true)
	await t.frames(2)
	var gated := _capture(t)
	for id in IDS:
		t.check(fast[id] == plain[id], "%s: the gate matches the plain path" % id)
		t.check(gated[id] == plain[id], "%s: restoring the gate restores the plain result" % id)
	await _check_legs_only_solve(t)


## The legs layer solves the rig only for the legs: the arms' joints, which it never reads, are not
## solved, and each ankle and knee it reads is the full solve's.
func _check_legs_only_solve(t: TestContext) -> void:
	var solves_before: int = Rig.solves
	var with_arms_before: int = Rig.arm_solves
	await t.frames(3)
	t.check(
		Rig.solves - solves_before > Rig.arm_solves - with_arms_before,
		"the legs layer's per-frame solve leaves the arms out",
	)
	for id in IDS:
		var body: Node = t.actor(id)
		var full := Rig.new(body, false)
		var legs_only := Rig.new(body, false, false)
		for joint in [Rig.PELVIS, Rig.HIP[0], Rig.HIP[1], Rig.KNEE[0], Rig.KNEE[1], Rig.ANKLE[0],
				Rig.ANKLE[1]]:
			t.check(
				legs_only.point(joint) == full.point(joint),
				"%s: the legs-only solve places joint %d as the full solve does" % [id, joint],
			)
		for side in 2:
			t.check(legs_only.toes(side) == full.toes(side), "%s: toes %d match" % [id, side])


func _capture(t: TestContext) -> Dictionary:
	var out := {}
	for id in IDS:
		var c = t.actor(id)
		var item: Item = c.inventory.current_item()
		out[id] = {
			"hands": [c.anatomy.hands.hand_position(0), c.anatomy.hands.hand_position(1)],
			"ankles": [c.anatomy.legs.ankle(0), c.anatomy.legs.ankle(1)],
			"muzzle": c.weapon.muzzle_origin(item.weapon_hand()),
		}
	return out
