extends GameTest
## A door at rest runs neither a physics callback nor a drawing callback. Starting a swing wakes the
## physics step, which sleeps again at the open stop; the art follows transforms by notification.

const SWING := 0.4


func describe() -> Dictionary:
	return {
		"name": "A door at rest runs no per-frame callback",
		"description": "A shut door and its visuals sleep; opening wakes the door, and the open "
			+ "stop puts it back to sleep without changing the swing.",
		"tags": ["door", "perf"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.layout(
		[{ "key": "room", "type": "living_room", "rect": Rect2(0, 0, 400, 400) }],
		[{
			"pos": Vector2(200, 0),
			"width": 52.0,
			"door": {
				"name": "resting",
				"material": "hollow",
				"style": "flush",
				"hinge": Vector2(180, 0),
				"swing_into": Vector2.DOWN,
			},
		}],
	)


func run(t: TestContext) -> void:
	var door := t.object(&"resting")
	await t.frames(20)
	_check_asleep(t, door, "shut")
	door.open_fully(null)
	await t.frames(1)
	t.check(door.is_physics_processing(), "starting a swing wakes the door's physics callback")
	await t.seconds(SWING + 0.2)
	t.check(door.angle() == door.open_angle, "the woken door still swings fully open")
	_check_asleep(t, door, "open")
	door.toggle(null)
	await t.seconds(SWING + 0.2)
	t.check(door.angle() == 0.0, "a second swing still closes the door")
	_check_asleep(t, door, "shut again")


func _check_asleep(t: TestContext, door: Node, where: String) -> void:
	t.check(not door.is_physics_processing(), "%s: the door runs no physics callback" % where)
	t.check(not door.is_processing(), "%s: the door runs no process callback" % where)
	t.check(
		not door.visuals.is_processing(),
		"%s: the door's visuals run no process callback" % where,
	)
