extends GameTest
## DR5 / DR10: a body walking into an ajar or open door's leaf turns it about its
## hinge away from the body, with physics: toward open from the push side, toward shut from the pull
## side, slower the heavier the door, stopped by what it meets, latching when it reaches shut. A
## shut door never moves from a walker. The doors swing east, hinged on their upper jamb, so the
## push side is the west and the pull side the east; ajar is 30° (15 to 35° in a house).

const JAMB := 20.0
## The line a walker takes through a doorway, this far below the doorway's middle: it meets the
## leaf near its free end, and the leaf has swung out of its way at about 60°.
const LINE := 10.0
const ROWS := {
	&"hollow": 100.0, &"steel": 250.0, &"shut": 400.0, &"pull": 550.0, &"stopped": 700.0,
}
## The body standing in the arc of the `stopped` door: 36 px from the hinge, 60° open.
const IN_THE_ARC := Vector2(431.2, 698.0)


func describe() -> Dictionary:
	return {
		"name": "A walker pushes an ajar door about its hinge",
		"description": "A puppet walking into an ajar hollow door from its push side opens it and "
			+ "walks through; a steel door turns less over the same walk; a shut door stays shut "
			+ "and stops the walker; from the pull side the walker turns an ajar door toward shut, "
			+ "it latches and then holds; a leaf stops at a body standing in its arc.",
		"tags": ["door", "objects", "push"],
		"timeout": 25.0,
	}


func _doorway(id: StringName, angle: float, material := "hollow", style := "flush") -> Dictionary:
	var y: float = ROWS[id]
	return {
		"pos": Vector2(400, y), "width": 52.0,
		"door": {
			"name": String(id), "material": material, "style": style,
			"hinge": Vector2(400, y - JAMB), "swing_into": Vector2.RIGHT, "angle": angle,
		},
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 900) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 900) },
	], [
		_doorway(&"hollow", 30.0), _doorway(&"steel", 30.0, "steel", "riveted"),
		_doorway(&"shut", 0.0), _doorway(&"pull", 30.0), _doorway(&"stopped", 25.0),
	])
	s.von_down()
	for id: StringName in [&"hollow", &"steel", &"shut", &"stopped"]:
		s.actor(StringName("%s_walker" % id), &"puppet", Vector2(340, ROWS[id] + LINE))
	s.actor(&"pull_walker", &"puppet", Vector2(470, ROWS[&"pull"] + LINE))
	s.actor(&"in_the_arc", &"puppet", IN_THE_ARC)


func run(t: TestContext) -> void:
	await t.seconds(0.4)
	t.check(
		is_equal_approx(t.object(&"hollow").angle(), 30.0),
		"premise: the hollow door starts ajar at 30° (%.1f)" % t.object(&"hollow").angle(),
	)
	var arc_at: Vector2 = t.actor(&"in_the_arc").global_position
	for id: StringName in [&"hollow", &"steel", &"shut", &"stopped"]:
		t.puppet(StringName("%s_walker" % id)).walk_to(Vector2(480, ROWS[id] + LINE))
	t.puppet(&"pull_walker").walk_to(Vector2(330, ROWS[&"pull"] + LINE))

	# the walk the hollow door's walker makes, through it: the same time the others have to walk
	var through: bool = await t.until(t.puppet(&"hollow_walker").has_arrived, 8.0)
	t.check(through, "a puppet walks through an ajar hollow door from its push side")
	_push_side(t, arc_at)
	await _pull_side(t)


## What the push-side walkers did over the walk the hollow one made.
func _push_side(t: TestContext, arc_at: Vector2) -> void:
	var hollow = t.object(&"hollow")
	var steel = t.object(&"steel")
	var shut = t.object(&"shut")
	var stopped = t.object(&"stopped")
	t.check(
		hollow.angle() >= 70.0,
		"the walker opens the ajar hollow door wide, from 30° (%.0f°)" % hollow.angle(),
	)
	var hollow_turn: float = hollow.angle() - 30.0
	var steel_turn: float = steel.angle() - 30.0
	t.check(steel_turn >= 2.0, "the ajar steel door turns for a walker (%.1f°)" % steel_turn)
	t.check(
		steel_turn < hollow_turn * 0.75,
		"but by less than the hollow door's %.0f° over the same walk (%.1f°)" % [
			hollow_turn, steel_turn],
	)
	t.check(
		shut.angle() == 0.0,
		"a walker leaves a shut door shut (%.1f°)" % shut.angle(),
	)
	var at: float = t.actor(&"shut_walker").global_position.x
	t.check(at < 395.0, "and is stopped by it (x %.0f)" % at)
	t.check(
		stopped.angle() < 40.0 and stopped.angle() >= 25.0,
		"a leaf stops at a body in its arc (%.1f°; the open one went to %.0f°)" % [
			stopped.angle(), hollow.angle()],
	)
	t.check(
		t.actor(&"in_the_arc").global_position.distance_to(arc_at) < 1.0,
		"and does not nudge it",
	)


## Pushed from the pull side the ajar door turns toward shut, latches there and holds as a shut one.
func _pull_side(t: TestContext) -> void:
	var pull = t.object(&"pull")
	var shut_here := func(d: Dictionary) -> bool:
		return d["door"] == pull and d["stage"] == &"shut"
	t.check(
		await t.until(func(): return pull.angle() == 0.0, 6.0),
		"a walker pushing an ajar door from its pull side turns it shut (%.1f°)" % pull.angle(),
	)
	t.check(t.happened(&"door", shut_here), "and it latches with the shut sound")
	await t.seconds(1.5)
	t.check(pull.angle() == 0.0, "then it holds like a shut door (%.1f°)" % pull.angle())
	var at: float = t.actor(&"pull_walker").global_position.x
	t.check(at > 405.0, "and stops the walker (x %.0f)" % at)
