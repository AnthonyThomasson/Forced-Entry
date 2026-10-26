extends GameTest
## G17 as amended (issue #51, R7), the case behind cover inside: a householder crouched behind a
## sofa inside the kitchen, which an invader in the garden sees over the sofa through the back
## doorway but cannot hit (the sofa stops a bullet at a crouched body's height). The invader with a
## frag takes GRENADE and lobs it through the doorway onto the householder's spot. G17 already
## offers GRENADE against a hostile hidden from the line of fire; this proves it holds for a hostile
## barricaded in a room the NPC is outside of, and whatever stops the throw there is to be fixed at
## its cause. The whole pipeline runs with real Von; a `require` that the invader is fighting the
## householder from outside the kitchen comes first.
##
## Premises: the householder is a puppet that cannot be killed and never shoots, crouched behind the
## sofa from the start of `run`; the invader is armed with one frag at the start of `run`, the way
## Main arms a spawn.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const INVADER_AT := Vector2(980, 140)
const HOSTILE_AT := Vector2(700, 190)
## The sofa stood on end (`rotated`) across the line from the back doorway to the householder.
const SOFA_AT := Vector2(752, 190)


func describe() -> Dictionary:
	return {
		"name": "An invader frags a defender crouched behind cover inside a room",
		"description": "A householder crouches behind a sofa in the kitchen; an invader in the "
			+ "garden sees it through the back doorway but has no shot: it takes GRENADE and lobs "
			+ "its frag through the doorway onto it.",
		"tags": ["ai", "grenade", "combat", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.object(&"sofa", "sofa", SOFA_AT, { "rotated": true })
	s.actor(&"i", &"invader", INVADER_AT, { "facing": (HOSTILE_AT - INVADER_AT).normalized() })
	GrenadeAi.hostile(s, &"h", HOSTILE_AT, Maps.DOOR_BACK)


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	var hostile := t.actor(&"h")
	t.puppet(&"h").set_posture(&"crouch")
	Probe.arm(inv, 0, 1)
	if not await _set_up(t, inv, hostile):
		return
	var target := "t_%d" % hostile.get_instance_id()
	var w := await GrenadeAi.watch_until_thrown(t, inv, target)
	var seen: Array = w["seen"]
	if not t.require(
			w["fighting_outside"],
			"the invader fought the householder from outside the kitchen (acts %s)" % str(seen),
	):
		return
	t.check(
		w["offered"],
		"GRENADE was offered against the householder behind the sofa (acts %s)" % str(seen),
	)
	if not _check_thrown_from_outside(t, inv, seen):
		return
	await _check_frag_caught_householder(t, inv, hostile)


func _set_up(t: TestContext, inv: Node, hostile: Node) -> bool:
	if not t.require(
			Probe.count(inv, Probe.FRAG) == 1,
			"the invader carries a frag grenade (Character.inventory.item_count(8) = %d)"
				% Probe.count(inv, Probe.FRAG),
	):
		return false
	if not t.require(
			await t.until(func(): return hostile.movement.posture() == &"crouch", 2.0),
			"set-up: the householder crouches behind the sofa",
	):
		return false
	return t.require(
		not GrenadeAi.line_clear(t, INVADER_AT, HOSTILE_AT),
		"set-up: the sofa stands on the line from the invader to the householder",
	)


func _check_thrown_from_outside(t: TestContext, inv: Node, seen: Array) -> bool:
	var throws := Probe.raw(t, &"throw", func(d): return d.get("attacker") == inv)
	if not t.check(
			not throws.is_empty() and throws[0]["data"].get("kind") == &"frag",
			"the invader threw its frag (acts %s)" % str(seen),
	):
		return false
	t.check(
		not Maps.HOUSE_KITCHEN.has_point(throws[0]["data"]["position"]),
		"from outside the kitchen (thrown at %s)"
			% str((throws[0]["data"]["position"] as Vector2).round()),
	)
	return true


func _check_frag_caught_householder(t: TestContext, inv: Node, hostile: Node) -> void:
	if t.check(await Probe.wait_boom(t, &"frag", 6.0), "the frag went off"):
		var at: Vector2 = Probe.booms(t, &"frag")[0]["data"]["position"]
		t.check(
			Maps.HOUSE_KITCHEN.has_point(at) and at.distance_to(HOSTILE_AT) < 110.0,
			"in the kitchen, onto the householder's spot (%s, %.0f px from it)"
				% [str(at.round()), at.distance_to(HOSTILE_AT)],
		)
		t.check(
			not Probe.blast_hits(t, hostile).is_empty(),
			"and its blast caught the householder (%d blast hits on it)"
				% Probe.blast_hits(t, hostile).size(),
		)
		t.check(Probe.blast_hits(t, inv).is_empty(), "without catching the thrower in it")
