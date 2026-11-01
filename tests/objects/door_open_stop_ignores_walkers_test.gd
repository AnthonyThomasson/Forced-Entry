extends GameTest
## DR10: a door at its fully open stop (`open_angle`, 90°) stays there for a body
## walking past it toward shut: a puppet brushing the leaf and walking through from the pull side
## leaves it at 90°, while the same walk turns a door open to 70° toward shut (and, the door
## shutting in its way, is stopped by it). Use and a kick behave as before: Use swings the open door
## shut, a kick on its pull side turns it toward shut. The doors swing east, hinged on their upper
## jamb, so the pull side (where the leaf lies) is the east.

const JAMB := 20.0
const ROWS := { &"open": 100.0, &"seventy": 250.0, &"used": 400.0, &"kicked": 550.0 }
## The walker's line through the doorway, this far above the doorway's middle: 7 px below the line
## of the leaf lying open along the north wall (20 px above the middle), so it meets the free end
## of that leaf nearly head on and brushes past, and meets a leaf open to 70° across its way.
const LINE := -13.0
## A kick's shove (this test's own copy of the kick's figure), landing on the open leaf's free end
## from the pull side, a hair below its axis.
const KICK_IMPULSE := 2200.0
const KICK_AT := Vector2(19.5, 3.0)


func describe() -> Dictionary:
	return {
		"name": "A fully open door stays open for a walker",
		"description": "A puppet brushing past and walking through a door open to its stop from "
			+ "its pull side leaves it at 90 degrees; the same walk turns a door open to 70 "
			+ "degrees toward shut; Use and a kick still shut the open door.",
		"tags": ["door", "objects", "push"],
		"timeout": 20.0,
	}


func _doorway(id: StringName, angle: float) -> Dictionary:
	var y: float = ROWS[id]
	return {
		"pos": Vector2(400, y), "width": 52.0,
		"door": {
			"name": String(id), "material": "hollow", "style": "flush",
			"hinge": Vector2(400, y - JAMB), "swing_into": Vector2.RIGHT, "angle": angle,
		},
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 700) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 700) },
	], [
		_doorway(&"open", 90.0), _doorway(&"seventy", 70.0),
		_doorway(&"used", 90.0), _doorway(&"kicked", 90.0),
	])
	s.von_down()
	for id: StringName in [&"open", &"seventy"]:
		s.actor(StringName("%s_walker" % id), &"puppet", Vector2(480, ROWS[id] + LINE))
	s.actor(&"user", &"puppet", Vector2(440, ROWS[&"used"] + 10.0))


func run(t: TestContext) -> void:
	await t.seconds(0.4)
	for id: StringName in [&"open", &"seventy", &"used", &"kicked"]:
		var want := 70.0 if id == &"seventy" else 90.0
		t.require(
			is_equal_approx(t.object(id).angle(), want),
			"premise: the %s door starts at %.0f° (%.1f°)" % [id, want, t.object(id).angle()],
		)
	for id: StringName in [&"open", &"seventy"]:
		t.puppet(StringName("%s_walker" % id)).walk_to(Vector2(330, ROWS[id] + LINE))
	var walker := t.puppet(&"open_walker")
	var line_y: float = ROWS[&"open"] + LINE
	var pushed_off := { "by": 0.0 }
	var through := func() -> bool:
		var y: float = t.actor(&"open_walker").global_position.y
		pushed_off["by"] = maxf(pushed_off["by"], y - line_y)
		return walker.has_arrived()
	t.check(
		await t.until(through, 8.0),
		"the walker brushes past the fully open leaf and walks through",
	)
	t.check(
		pushed_off["by"] >= 3.0,
		"premise: the leaf's end pushed the walker off its line, so they touched (%.1f px)"
			% pushed_off["by"],
	)
	await t.seconds(2.0)
	var open = t.object(&"open")
	var seventy = t.object(&"seventy")
	t.check(
		seventy.angle() < 60.0,
		"the same walk turns the door open to 70° toward shut (%.1f°)" % seventy.angle(),
	)
	t.check(
		is_equal_approx(open.angle(), 90.0),
		"and leaves the fully open door at 90° (%.1f°)" % open.angle(),
	)
	await _use_and_kick(t)


## Use swings the open door shut; a kick on its pull side turns it toward shut as before.
func _use_and_kick(t: TestContext) -> void:
	var used = t.object(&"used")
	t.puppet(&"user").use()
	t.check(
		await t.until(func(): return used.angle() == 0.0, 2.0),
		"Use swings a fully open door shut (%.1f°)" % used.angle(),
	)
	var kicked = t.object(&"kicked")
	var spot: Vector2 = kicked.global_position
	kicked.apply_impulse(Vector2.LEFT * KICK_IMPULSE, KICK_AT)
	kicked.take_blow(&"kick", 14.0, Vector2.LEFT * KICK_IMPULSE)
	await t.seconds(0.6)
	t.check(
		kicked.angle() < 89.9,
		"a kick on the pull side of a fully open door turns it toward shut (%.1f° at %s)"
			% [kicked.angle(), spot],
	)
