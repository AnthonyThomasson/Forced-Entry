extends GameTest
## LD6 (`docs/leadership.md`): an order stops a walk, not a fight. From the frame an order arrives
## until the decision made knowing it lands, a member in a fight fights on: its peek-and-cover keeps
## peeking, firing and ducking to cover, and is never frozen in the open while that decision waits
## on Von. A defender fighting an intruder across a hall (it holds a table near it for cover) is
## ordered to defend the hall: it is engaged, so the decision made with the order is a combat one,
## and with the fight's options inside the hall (LD8 keeps it to those) Von has several to choose
## from and is asked. Von answers late (the scripted answers are held back `LATENCY_FRAMES`), and
## through that wait the defender keeps moving between its firing and cover spots and keeps firing.
##
## Scripted Von (an ENGAGE, then the first spot offered). Premises: neither side can be killed; the
## intruder is an invader puppet that stands still and never fires (the defender's own shots keep it
## engaged); the order is given through the squad, as Main wires the leader's command menu to it.

const Order := preload("res://tests/_ai/order_probe.gd")
const HALL := Rect2(0, 0, 900, 450)
const DEN := Rect2(0, 450, 300, 200)
const DEN_DOOR := Vector2(150, 450)
const D_AT := Vector2(200, 220)
const FOE_AT := Vector2(760, 220)
## How long (physics frames) each scripted answer is held back once the fight is under way: the wait
## for the decision made with the order.
const LATENCY_FRAMES := 150
## The least the defender moves (px, summed frame to frame) through that wait: a peek-and-cover that
## moves between its spots at all.
const MOVES_PX := 24.0


func describe() -> Dictionary:
	return {
		"name": "An order does not freeze a fight",
		"description": "A defender in a peek-and-cover fight is ordered to defend the room it "
			+ "fights in: while the decision made with the order waits on Von, it keeps moving "
			+ "between its spots and firing (LD6).",
		"tags": ["ai", "decision", "leadership", "order", "combat", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "hall", "type": "living_room", "rect": HALL },
		{ "key": "den", "type": "bedroom", "rect": DEN },
	], [
		{ "pos": DEN_DOOR, "width": 80.0 },
	])
	s.von_script([{ "pick": "engage" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_sight", true)
	s.switch(&"nav.rebake", false)
	s.actor(&"d", &"defender", D_AT, { "max_health": 1_000_000.0, "start_slot": 3 })
	s.actor(
		&"lead",
		&"puppet",
		Vector2(60, 600),
		{ "faction": &"household", "max_health": 1_000_000.0 },
	)
	s.actor(
		&"foe",
		&"puppet",
		FOE_AT,
		{ "faction": &"invader", "max_health": 1_000_000.0, "aim_point": D_AT },
	)
	s.object(
		&"table",
		{
			"name": "Table", "shape": "rect", "size": Vector2(24, 100),
			"color": Color(0.5, 0.4, 0.3), "material": "wood", "coverage": 45.0,
			"penetration": 60.0, "weight": 5000.0,
		},
		Vector2(290, 220),
	)


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	var b := Order.brain(t, &"d")
	var squad := Order.squad(t, &"household", [t.actor(&"lead"), d], t.actor(&"lead"))
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	var fighting := func(): return Order.primitive(b) == "engage" and _shots(t, d, 0.0) >= 2
	if not t.require(
			await t.until(fighting, 12.0),
			"the defender fights the intruder from its spots (premise; %s, %d shots)"
				% [Order.primitive(b), _shots(t, d, 0.0)],
	):
		return
	await t.seconds(1.0)
	# restored after the test (von_script registered it)
	DecisionStub.latency_frames = LATENCY_FRAMES

	var before := Order.decisions(b)
	Order.issue(squad, { "kind": Order.DEFEND, "to": [d], "room": "hall" })
	if not t.require(
			await t.until(func(): return Order.decisions(b) > before, 1.0),
			"the order starts a decision at once (LD6)",
	):
		return
	var from := t.time
	var last: Vector2 = d.global_position
	var moved := 0.0
	while bool(b.debug_state().get("decision", {}).get("pending", false)) and t.time < from + 10.0:
		await t.frames(1)
		moved += d.global_position.distance_to(last)
		last = d.global_position
	var wait := t.time - from
	if not t.require(
			wait >= 1.5,
			"premise: the decision made with the order waits on Von (%.2f s; a combat one, %s)"
				% [wait, b.current_act()],
	):
		return
	t.check(
		moved >= MOVES_PX,
		"through that wait it keeps moving between its firing and cover spots (%.0f px in %.2f s)"
			% [moved, wait],
	)
	t.check(
		_shots(t, d, from) >= 1,
		"and keeps firing (%d shots in %.2f s)" % [_shots(t, d, from), wait],
	)


## The rounds `who` fired from sim time `since` on (`&"shot"` events with it as the attacker).
func _shots(t: TestContext, who: Node, since: float) -> int:
	var n := 0
	for e: Dictionary in t.events:
		if e["topic"] == &"shot" and e["data"].get("attacker") == who and float(e["time"]) >= since:
			n += 1
	return n
