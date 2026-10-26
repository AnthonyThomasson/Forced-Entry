extends GameTest
## LD6 (`docs/leadership.md`): an order stops a walk, not a fight, and a move chosen under COMBAT (a
## retreat, an advance, a locate) is part of the fight. A defender falls back under fire (COMBAT ->
## RETREAT, to the den) from gunfire it cannot place, and on its way across the hall it is ordered
## to defend the hall, with shots landing beside it on the same frame: it is under fire, so the
## decision made with the order is a combat one, and with the fight's options inside the hall (LD8
## keeps it to those: a spot behind the table, finding the shooter) Von has two to choose from and
## is asked. Von answers late (the scripted answers are held back `LATENCY_FRAMES`), and through
## that wait the defender keeps falling back: it never stands in the line of fire while that
## decision waits on Von.
##
## Scripted Von (RETREAT, then the den). Premises: the defender cannot be killed, and it is on its
## retreat when the order comes; the gunfire is from nobody it knows (`Order.gunfire_near`); the
## squad is built and bound as a match's (`s.squads`, a puppet standing in for the human leader,
## still in the hall's west end, so the den and the spot behind the table are within its leash,
## LD23), and the order is given through it, as Main wires the leader's command menu to it.

const Order := preload("res://tests/_ai/order_probe.gd")
const HALL := Rect2(0, 0, 900, 450)
const DEN := Rect2(0, 450, 300, 200)
const DEN_DOOR := Vector2(150, 450)
const D_AT := Vector2(760, 220)
## Where the human leader stands: in the hall's west end, off the defender's way to the den's
## doorway, within a leash of the den and of the spot behind the table.
const LEAD_AT := Vector2(120, 300)
## How long (physics frames) each scripted answer is held back once the retreat is under way: the
## wait for the decision made with the order.
const LATENCY_FRAMES := 90
## How long (s) after the order the movement is measured from (a stopped body comes to rest in that
## time), and for how long at most.
const SETTLE := 0.25
const MEASURE := 1.0
## The least the defender moves (px) in that span: a retreat that goes on (a walk covers 150 px/s, a
## stopped one under 3 px).
const MOVES_PX := 60.0


func describe() -> Dictionary:
	return {
		"name": "An order does not freeze a retreat",
		"description": "A defender falling back under fire is ordered to defend the room it is "
			+ "crossing: while the decision made with the order waits on Von, it keeps moving "
			+ "(LD6).",
		"tags": ["ai", "decision", "leadership", "order", "combat", "retreat", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "hall", "type": "living_room", "rect": HALL },
		{ "key": "den", "type": "bedroom", "rect": DEN },
	], [
		{ "pos": DEN_DOOR, "width": 80.0 },
	])
	s.von_script([{ "pick": "retreat" }, { "pick": "fall_bedroom" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"nav.rebake", false)
	s.actor(&"d", &"defender", D_AT, { "max_health": 1_000_000.0 })
	s.actor(
		&"lead",
		&"puppet",
		LEAD_AT,
		{ "faction": &"household", "max_health": 1_000_000.0 },
	)
	s.object(
		&"table",
		{
			"name": "Table", "shape": "rect", "size": Vector2(24, 120),
			"color": Color(0.5, 0.4, 0.3), "material": "wood", "coverage": 45.0,
			"penetration": 60.0, "weight": 5000.0,
		},
		Vector2(430, 200),
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	var b := Order.brain(t, &"d")
	var squad: Node = t.world.squad(&"household")
	await t.seconds(0.5)
	if not await _on_retreat(t, d, b):
		return
	# restored after the test (von_script registered it)
	DecisionStub.latency_frames = LATENCY_FRAMES

	var before := Order.decisions(b)
	Order.gunfire_near(d)
	Order.issue(squad, { "kind": Order.DEFEND, "to": [d], "room": "hall" })
	if not t.require(
			await t.until(func(): return Order.decisions(b) > before, 1.0),
			"the order starts a decision at once (LD6)",
	):
		return
	await _check_keeps_moving(t, d, b)


func _on_retreat(t: TestContext, d: Node, b: Node) -> bool:
	Order.gunfire_near(d)
	var retreating := func():
		return (Order.primitive(b) == "move"
				and String(b.current_act()).begins_with("combat")
				and String(b.current_act()).contains("retreat"))
	if not t.require(
			await t.until(retreating, 5.0),
			"the defender falls back under fire (premise; %s)" % b.current_act(),
	):
		return false
	await t.seconds(0.5)
	var was: Vector2 = d.global_position
	await t.seconds(0.25)
	var pace: float = d.global_position.distance_to(was) / 0.25
	if not t.require(
			pace >= 40.0 and retreating.call(),
			"premise: it is on its retreat when the order comes (%.0f px/s, %s)"
				% [pace, b.current_act()],
	):
		return false
	return true


func _check_keeps_moving(t: TestContext, d: Node, b: Node) -> void:
	var from := t.time
	await t.seconds(SETTLE)
	var last: Vector2 = d.global_position
	var moved := 0.0
	while (bool(b.debug_state().get("decision", {}).get("pending", false))
			and t.time < from + SETTLE + MEASURE):
		await t.frames(1)
		moved += d.global_position.distance_to(last)
		last = d.global_position
	var wait := t.time - from
	var levels := Order.levels(b).map(
		func(l): return [l.get("node"), l.get("offered"), l.get("auto")],
	)
	if not t.require(
			wait >= SETTLE + MEASURE,
			("premise: the decision made with the order waits on Von for the whole span (%.2f s; a "
					+ "combat one, %s; levels %s)")
				% [wait, b.current_act(), levels],
	):
		return
	t.check(
		moved >= MOVES_PX,
		"through that wait it keeps falling back (%.0f px in %.2f s, %s)"
			% [moved, MEASURE, b.current_act()],
	)
