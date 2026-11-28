extends GameTest
## A free item that lands on a plate on the floor rests on it (#194, D20,
## `docs/stacked-items.md`): a plate lying on the floor is walk-over (on `TWIN_WALKOVER`, no walker
## meets it), and still what falls onto it lands on it: a book set on it stands on its top, and a
## book let fall onto a second plate from higher up comes to rest there, asleep, not on the floor
## under it.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const PLATE_AT := Vector2(300, 250)
const OTHER_AT := Vector2(500, 250)
const DROP_FROM := 50.0
const SLACK := 0.8


func describe() -> Dictionary:
	return {
		"name": "A book set or dropped on a plate rests on it",
		"description": "A plate on the floor is a walk-over body, and a book set on it and a "
			+ "book let fall onto another from 50 px up both settle asleep on a plate's top, "
			+ "not through it onto the floor.",
		"tags": ["furniture", "3d", "items", "stacking", "twins"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"plate", "plate", PLATE_AT)
	s.object(&"other", "plate", OTHER_AT)
	s.object(&"set", "book", Vector2.ZERO, { "on": &"plate" })
	s.object(&"drop", "book", Vector2(500, 120))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	for id in [&"plate", &"other", &"set", &"drop"]:
		if not t.require(await Probe.settle(t, t.object(id), 4.0), "%s settles asleep" % id):
			return
	var top := PieceHeights.top_of_spec(FurnitureSpec.of(t.object(&"plate")))
	t.require(
		top > 0.5 and top <= DoorFallConfig.step_over,
		"premise: the plate lies flat, its top %.2f px" % top,
	)
	t.check(
		TwinSpace.twin_for(t.object(&"plate")).collision_layer == PhysicsLayers.TWIN_WALKOVER,
		"the plate lies on the walk-over layer",
	)
	_rests(t, &"set", top)
	# the second book is carried over the other plate and let go
	var body := Probe.body(t.object(&"drop"))
	body.global_position = PlanSpace.lift(OTHER_AT, DROP_FROM)
	body.sleeping = false
	if not t.require(await Probe.settle(t, t.object(&"drop"), 6.0), "the dropped book settles"):
		return
	_rests(t, &"drop", top)
	t.check(
		(PlanSpace.plan_of(body.global_position) - OTHER_AT).length() < 8.0,
		"and it lies on the plate it fell on",
	)


## `id`'s underside is `top` px above the floor.
func _rests(t: TestContext, id: StringName, top: float) -> void:
	var low := Probe.body(t.object(id)).global_position.y / RenderConfig.unit
	t.check(
		absf(low - top) < SLACK, "%s stands %.2f px up, on a top of %.2f px" % [id, low, top]
	)
