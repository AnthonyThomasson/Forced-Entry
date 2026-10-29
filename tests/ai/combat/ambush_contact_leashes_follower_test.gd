extends GameTest
## LD15 and LD23 (`docs/leadership.md`): an ambush ends on first contact (D18), and from then the
## member holds no order, so the leash binds it again: the decision that very contact forces is
## made within its leash of its leader. Its confinement is refreshed after the whole order intake,
## the ambush ending on contact included, before that decision freezes the copy it walks over.
##
## The doorway is the Terrace house's hall / living room doorway (`door_150_360`), ambushed from the
## living room, as in `ambush_ends_on_shot_at_test.gd`. A defender in the living room is ordered (by
## its squad's leader, a household puppet in the kitchen standing in for the human leader; the
## squad built and bound as a match's, `s.squads`) to ambush it. Once it holds its post, an invader
## puppet is put down between it and the threshold it watches, in plain sight of it: the order ends
## `done`, and the first decision walk begun after it carries the leash round its leader
## (`debug_state()["decision"]["confinement"]`).
##
## Scripted Von (the first option offered): what it decides is not under test, only where it may
## act while deciding. The intruder is unkillable and never shoots.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const OrderBrain := preload("res://tests/_ai/order_brain_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
## The click that orders the ambush: in the living room, on the doorway's axis.
const CLICK := Vector2(150, 330)
const LEAD_AT := Vector2(700, 120)


func describe() -> Dictionary:
	return {
		"name": "The decision an ambush's contact forces is made on the leash",
		"description": "A defender ambushing the hall doorway sees an intruder: its order ends "
			+ "done and the decision that contact forces keeps it within its leader's leash "
			+ "(LD15, LD23).",
		"tags": ["ai", "combat", "leadership", "order", "ambush", "leash", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	s.actor(&"a", &"defender", Vector2(240, 150), { "max_health": 1_000_000.0 })
	s.actor(&"lead", &"puppet", LEAD_AT, { "faction": &"household" })
	s.actor(
		&"intruder",
		&"puppet",
		Vector2(800, 430),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var a := t.actor(&"a")
	var brain := await _take_post(t, a)
	if brain == null:
		return
	# Halfway from its post to the threshold its gun is kept on (`door_pos`), in the living room.
	var door: Array = OrderBrain.params(brain).get("door_pos", [])
	if not t.require(
		door.size() == 2,
		"the ambush leaf names its threshold (door_pos %s)" % str(door),
	):
		return
	var at: Vector2 = a.global_position.lerp(Vector2(door[0], door[1]), 0.5)
	var before := OrderBrain.decisions(brain)
	GrenadeAi.place(t, &"intruder", at, a.global_position)
	if not t.require(
			GrenadeAi.line_clear(t, a.global_position, at),
			"premise: the intruder stands in plain sight of the ambusher (at %s, it at %s)"
				% [str(at.round()), str(a.global_position.round())],
	):
		return
	# The confinement of the first walk begun after the contact, read on the frame it begins.
	var firsts: Array = []
	var begun := func() -> bool:
		if OrderBrain.decisions(brain) > before:
			firsts.append(brain.debug_state().get("decision", {}).get("confinement", {}))
			return true
		return false
	if not t.require(
			await t.until(begun, 3.0),
			"the contact forces a decision (decisions %d)" % OrderBrain.decisions(brain),
	):
		return
	t.check(
		not Order.progress(t, "done", a).is_empty(),
		"the ambusher radios its order done on first contact",
	)
	var first: Dictionary = firsts[0]
	var center: Vector2 = first.get("leash_center", Vector2.INF)
	t.check(
		center != Vector2.INF and center.distance_to(LEAD_AT) <= 1.0,
		"the decision the contact forced is made within the leash round its leader at %s "
			% str(LEAD_AT) + "(its confinement %s)" % str(first),
	)


func _take_post(t: TestContext, a: Node) -> Node:
	var squad: Node = t.world.squad(&"household")
	await t.seconds(0.5)
	var order := Order.issue(squad, { "kind": Order.AMBUSH, "to": [a], "pos": CLICK })
	if not t.require(
			not order.is_empty(),
			"the squad posts the ambush order (issue of kind ambush returned %s)" % str(order),
	):
		return null
	var brain := OrderBrain.brain(t, &"a")
	if not t.require(
			await t.until(func(): return not Order.progress(t, "in_position", a).is_empty(), 20.0),
			"it reaches its post and radios in_position",
	):
		return null
	return brain
