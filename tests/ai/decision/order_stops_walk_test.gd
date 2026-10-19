extends GameTest
## LD6 (`docs/leadership.md`): an order stops a walk. From the frame an order arrives until the
## decision made knowing it lands, a member on a walk the order replaces stands, as an arrived move
## does: it never walks on with what it chose before the order. A defender walking off to search the
## den is ordered to stack on the den's doorway, and shots land beside it on the same frame (gunfire
## from nobody it knows): it is under fire, so the decision made with the order is a combat one, and
## Von is asked (a stack order confines no fight, so the fight's options are several). Von answers
## late (the scripted answers are held back `LATENCY_FRAMES`), and through that wait the defender
## stands where the order found it.
##
## Scripted Von (SEARCH first, then the first option offered). Premises: the defender cannot be
## killed, and it is walking (a move) when the order comes; the order is given through the squad, as
## Main wires the leader's command menu to it.

const Order := preload("res://tests/_ai/order_probe.gd")
const HALL := Rect2(0, 0, 900, 450)
const DEN := Rect2(0, 450, 300, 200)
const DEN_DOOR := Vector2(150, 450)
const D_AT := Vector2(760, 120)
## How long (physics frames) each scripted answer is held back once the walk is under way: the wait
## for the decision made with the order.
const LATENCY_FRAMES := 90
## How long (s) a walking body takes to come to rest once it stops steering; the stand is measured
## from then on.
const SETTLE := 0.25
## How far (px) the defender may drift while it stands.
const STILL_PX := 3.0


func describe() -> Dictionary:
	return {
		"name": "An order stops a walk",
		"description": "A defender walking off to search is ordered to stack on a door with shots "
			+ "landing by it: while the decision made with the order waits on Von, it stands "
			+ "(LD6).",
		"tags": ["ai", "decision", "leadership", "order", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "hall", "type": "living_room", "rect": HALL },
		{ "key": "den", "type": "bedroom", "rect": DEN },
	], [
		{ "pos": DEN_DOOR, "width": 80.0 },
	])
	s.von_script([{ "pick": "search" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"nav.rebake", false)
	s.actor(&"d", &"defender", D_AT, { "max_health": 1_000_000.0 })
	s.actor(
		&"lead",
		&"puppet",
		Vector2(60, 600),
		{ "faction": &"household", "max_health": 1_000_000.0 },
	)


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	var b := Order.brain(t, &"d")
	var squad := Order.squad(t, &"household", [t.actor(&"lead"), d], t.actor(&"lead"))
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	if not t.require(
			await t.until(func(): return Order.primitive(b) == "move", 5.0),
			"the defender sets off on a walk (premise; %s)" % Order.primitive(b),
	):
		return
	await t.seconds(0.5)
	var was: Vector2 = d.global_position
	await t.seconds(0.25)
	var pace: float = d.global_position.distance_to(was) / 0.25
	if not t.require(
			pace >= 40.0 and Order.primitive(b) == "move",
			"premise: it is walking when the order comes (%.0f px/s, %s)" % [pace, b.current_act()],
	):
		return
	# restored after the test (von_script registered it)
	DecisionStub.latency_frames = LATENCY_FRAMES

	var before := Order.decisions(b)
	Order.gunfire_near(d)
	Order.stack_order(squad, [d], DEN_DOOR + Vector2(0, 30), "quiet", false)
	if not t.require(
			await t.until(func(): return Order.decisions(b) > before, 1.0),
			"the order starts a decision at once (LD6)",
	):
		return
	var from := t.time
	await t.seconds(SETTLE)
	var stood: Vector2 = d.global_position
	var drift := 0.0
	while bool(b.debug_state().get("decision", {}).get("pending", false)) and t.time < from + 10.0:
		drift = maxf(drift, d.global_position.distance_to(stood))
		await t.frames(1)
	var wait := t.time - from
	if not t.require(
			wait >= 1.0,
			"premise: the decision made with the order waits on Von (%.2f s; %s)"
				% [wait, b.current_act()],
	):
		return
	t.check(
		drift <= STILL_PX,
		"through that wait it stands where the order found it (drifted %.1f px in %.2f s)"
			% [drift, wait - SETTLE],
	)
