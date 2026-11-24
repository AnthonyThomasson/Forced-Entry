extends GameTest
## What the body's sweep, hands and legs keep from one frame to the next (`body_sweep.gd`'s twin
## space and exclusion lists, the hands' once-a-frame reads, the legs' reused rig) answers what a
## fresh one asks of the engine and the body that frame would: a sweep kept across the body's twin
## being replaced (and the old one freed) and across physics frames; a hand through an item swap and
## a butt-first long gun; the legs' rig (the toes and the knees too) through a kick and a stagger.
## A body in no twin space keeps no space and builds its empty exclusion once.

const Rig := preload("res://scenes/character/body/character_rig.gd")
const Sweep := preload("res://scenes/character/body/body_sweep.gd")
const Legs := preload("res://scenes/character/body/character_legs.gd")


func describe() -> Dictionary:
	return {
		"name": "The body's kept caches answer what fresh ones do",
		"description": "A kept sweep across a retwin and a frame change, hands through an item "
			+ "swap and a butt-first grip, and the legs' rig through a kick and a stagger equal "
			+ "fresh ones; a viewport fallback space is not kept.",
		"tags": ["contact", "hands", "legs", "perf", "twin"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.actor(&"wall", &"puppet", Vector2(30, 200), { "start_slot": 6 })
	s.actor(&"open", &"puppet", Vector2(600, 300), { "start_slot": 1 })
	s.actor(&"kicker", &"puppet", Vector2(30, 400), { "start_slot": 1 })
	s.actor(&"reeler", &"puppet", Vector2(30, 560), { "start_slot": 1 })


func run(t: TestContext) -> void:
	await t.frames(3)
	await _check_retwin(t)
	await _check_retwin_gate(t)
	await _check_frames(t)
	await _check_hands(t)
	await _check_legs(t)
	await _check_no_twin_space(t)


## The kept sweep across a retwin (the old twin freed) answers a fresh one's.
func _check_retwin(t: TestContext) -> void:
	var body: Node2D = t.actor(&"wall")
	var kept: Sweep = body.anatomy.sweep
	var before := _answers(kept, body)
	t.check(before == _answers(Sweep.new(body), body), "premise: kept equals fresh before")
	t.check(
		before[0] != Vector2(-60.0, 0.0) and before[1] == Vector2(40.0, 0.0) and before[4] == INF,
		"premise: the wall stops a foot, and the body's own twin stops nothing (%s)" % [before],
	)
	var old := TwinSpace.twin_for(body)
	TwinSpace.retwin(body)
	t.check(TwinSpace.twin_for(body) != old, "premise: the body has a new twin")
	t.check(
		_answers(kept, body) == _answers(Sweep.new(body), body),
		"a sweep kept across a retwin answers a fresh one's the frame the twin is made",
	)
	await t.frames(3)
	t.check(not is_instance_valid(old), "premise: the old twin is freed")
	t.check(
		_answers(kept, body) == _answers(Sweep.new(body), body),
		"and once the old twin is freed",
	)
	t.check(_answers(kept, body) == before, "and as before the retwin")


## The near-solid gate of a body in the open, kept across a retwin: the body's own new twin is not
## a solid in its reach (the exclusion follows the twin), as for a fresh sweep.
func _check_retwin_gate(t: TestContext) -> void:
	var body: Node2D = t.actor(&"open")
	var kept: Sweep = body.anatomy.sweep
	var radius := maxf(Legs.NEAR, body.anatomy.hands.near_radius())
	kept.refresh(radius)
	t.require(not kept.near_solid, "premise: nothing is near a body in the open")
	TwinSpace.retwin(body)
	kept.refresh(radius)
	var fresh := Sweep.new(body)
	fresh.refresh(radius)
	t.check(
		kept.near_solid == fresh.near_solid and not kept.near_solid,
		"a sweep kept across a retwin finds no solid by the body's own new twin",
	)
	await t.frames(2)
	kept.refresh(radius)
	t.check(not kept.near_solid, "nor once the old twin is freed")


## A sweep kept across physics frames equals a fresh one each frame.
func _check_frames(t: TestContext) -> void:
	var body: Node2D = t.actor(&"wall")
	var kept: Sweep = body.anatomy.sweep
	for _frame in 4:
		await t.frames(1)
		t.check(
			_answers(kept, body) == _answers(Sweep.new(body), body),
			"a sweep kept across a physics frame equals a fresh one",
		)
	t.check(
		kept.get("_space_cache") == TwinSpace.space_of(body),
		"the twin space it keeps is the one the body is in",
	)


## The answers a sweep gives for the body's feet: a foot into the wall, a foot into the open, a
## knee along it, and a barrel's ray into the wall and into the open.
func _answers(sweep: Sweep, body: Node2D) -> Array:
	var at: Vector2 = body.global_position
	var ankle := BodyHeights.contact(&"ankle", &"stand")
	var knee := BodyHeights.contact(&"knee", &"stand")
	var muzzle := BodyHeights.muzzle(&"stand")
	var radius: float = CharacterPushConfig.leg_radius
	return [
		sweep.circle(at, Vector2(-60.0, 0.0), radius, ankle),
		sweep.circle(at, Vector2(40.0, 0.0), radius, ankle),
		sweep.circle(at, Vector2(-30.0, 30.0), radius, knee),
		sweep.solid_distance(at, Vector2.LEFT, 200.0, muzzle),
		sweep.solid_distance(at, Vector2.RIGHT, 100.0, muzzle),
	]


## Each hand, through an item swap and a long gun swung butt first, is where a fresh read of the
## held item, the hand-ahead, the gate and the fist's height puts it.
func _check_hands(t: TestContext) -> void:
	var body: Node2D = t.actor(&"wall")
	var puppet := t.puppet(&"wall")
	var gripped := false
	for slot in [6, 3, 5, 6, 1, 6]:
		puppet.select_slot(slot)
		await t.frames(2)
		await body.get_tree().process_frame  # After this frame's nodes, before the next's tweens.
		_check_hands_now(t, body, "slot %d" % slot)
		if slot == 6:
			puppet.punch()
			for _frame in 14:
				await t.frames(1)
				await body.get_tree().process_frame
				_check_hands_now(t, body, "the butt swung from slot 6")
				var item: Item = body.inventory.current_item()
				gripped = gripped or (
					item.strike.support_gap != 0.0
					and body.anatomy.hands.punch_amount(item.weapon_hand()) > 0.3
				)
	t.check(gripped, "premise: a long gun was swung butt first with the other hand gripping on")


func _check_hands_now(t: TestContext, body: Node2D, when: String) -> void:
	var hands = body.anatomy.hands
	var item: Item = body.inventory.current_item()
	var ahead: float = body.movement.posture_hand_ahead()
	var fresh := Sweep.new(body)
	# The swing's tween has stepped since the hands were placed: their frame's extension is the
	# one they kept for the speed.
	var thrown: Array = hands.get("_punch")
	hands.set("_punch", (hands.get("_prev_punch") as Array).duplicate())
	var fist := BodyHeights.contact(&"fist", body.movement.body_posture())
	for hand in 2:
		var raw: Vector2 = hands.call("_raw_hand_position", hand, item, ahead)
		var want := raw
		if not body.anatomy.sweep.is_clear():
			want = fresh.circle(body.global_position, raw, hands.hand_radius, fist)
		t.check(
			hands.hand_position(hand) == want,
			"hand %d is where a fresh read puts it (%s)" % [hand, when],
		)
	hands.set("_punch", thrown)


## The legs' kept rig places the toes and the knees as a fresh solve does, kicking and staggering.
func _check_legs(t: TestContext) -> void:
	var kicker := t.puppet(&"kicker")
	kicker.aim_at(Vector2(700, 400))
	await t.frames(5)
	kicker.kick()
	for _frame in 24:
		await t.frames(1)
		_check_legs_rig(t, &"kicker")
	var reeler: Node = t.actor(&"reeler")
	reeler.stun.take(3.0, 3.0)
	t.puppet(&"reeler").walk(Vector2(0.0, -1.0))
	var swayed := false
	for _frame in 20:
		await t.frames(1)
		_check_legs_rig(t, &"reeler")
		swayed = swayed or reeler.anatomy.pose.hip_sway != Vector2.ZERO
	t.check(swayed, "premise: the stunned walker's hips swayed")


func _check_legs_rig(t: TestContext, id: StringName) -> void:
	var body: Node = t.actor(id)
	var kept: Rig = body.anatomy.legs.get("_rig")
	if not t.require(kept != null, "%s: the legs layer keeps its own rig" % id):
		return
	var fresh := Rig.new(body, false, false)
	var same := true
	for joint in [Rig.PELVIS, Rig.HIP[0], Rig.HIP[1], Rig.KNEE[0], Rig.KNEE[1], Rig.ANKLE[0],
			Rig.ANKLE[1]]:
		same = same and kept.point(joint) == fresh.point(joint)
	for side in 2:
		same = same and kept.toes(side) == fresh.toes(side)
		var ankle: Vector3 = fresh.point(Rig.ANKLE[side])
		same = same and kept.knee_at(side, ankle) == fresh.knee_at(side, ankle)
	t.check(same, "%s: the kept rig's joints, toes and knees are a fresh solve's" % id)


## A body outside any twin space: the viewport's own space it falls back to is not kept, and its
## empty exclusion is built once.
func _check_no_twin_space(t: TestContext) -> void:
	var port := SubViewport.new()
	var lone := Node2D.new()
	port.add_child(lone)
	t.actor(&"wall").get_parent().add_child(port)
	var sweep := Sweep.new(lone)
	t.check(
		TwinSpace.space_in(lone.get_viewport().find_world_2d()) == null,
		"premise: no twin space",
	)
	sweep.circle(Vector2.ZERO, Vector2(50.0, 0.0), 6.0, 4.0)
	await t.frames(1)
	sweep.circle(Vector2.ZERO, Vector2(50.0, 0.0), 6.0, 4.0)
	t.check(sweep.get("_space_cache") == null, "the viewport fallback space is not kept")
	var built: Array = sweep.get("_excluded")
	sweep.circle(Vector2.ZERO, Vector2(50.0, 0.0), 6.0, 4.0)
	t.check(
		is_same(sweep.get("_excluded"), built),
		"a twinless body's empty exclusion is built once",
	)
	port.queue_free()
