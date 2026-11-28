extends GameTest
## Small items rest on a flat top and on each other (#194, D20, `docs/stacked-items.md`):
## each is its own free 3D body, set down on a table (a plate and a cup) or on a crate (a box on a
## crate on the floor, a stack), it falls the last hair and settles asleep with its underside on
## the top it stands on and stays where it was put on the plan.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const TABLE_AT := Vector2(300, 250)
const CRATE_AT := Vector2(500, 250)
## Real tops (px: 42.3 a metre) the spec states: a table is 0.73 m, a crate 16 px, a box 12 px.
const TABLE_TOP := 31.0
const CRATE_TOP := 16.0
const SLACK := 0.8


func describe() -> Dictionary:
	return {
		"name": "Items rest on a flat top and on each other, asleep",
		"description": "A plate and a cup set on a table, and a box on a crate on a crate, each "
			+ "end asleep with its underside on the top below it (the table's 31 px, the first "
			+ "crate's 16, the second's 32) and where it was put on the plan.",
		"tags": ["furniture", "3d", "items", "stacking", "twins"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"table", "table", TABLE_AT)
	s.object(&"plate", "plate", Vector2(-10, 0), { "on": &"table" })
	s.object(&"cup", "cup", Vector2(12, 4), { "on": &"table" })
	s.object(&"low", "crate", CRATE_AT)
	s.object(&"mid", "crate", Vector2.ZERO, { "on": &"low" })
	s.object(&"high", "box", Vector2.ZERO, { "on": &"mid" })
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	for id in [&"plate", &"cup", &"low", &"mid", &"high"]:
		if not t.require(
				await Probe.settle(t, t.object(id), 4.0), "%s settles asleep" % id
		):
			return
	var table_top := Probe.top(t.object(&"table"))
	t.require(absf(table_top - TABLE_TOP) < 1.0, "premise: the table's top is %.1f px" % table_top)
	_rests(t, &"plate", TABLE_TOP)
	_rests(t, &"cup", TABLE_TOP)
	_rests(t, &"low", 0.0)
	_rests(t, &"mid", CRATE_TOP)
	_rests(t, &"high", CRATE_TOP * 2.0)
	t.check(
		(t.object(&"plate").global_position - (TABLE_AT + Vector2(-10, 0))).length() < 1.0,
		"the plate stayed where it was set on the plan",
	)
	t.check(
		(t.object(&"high").global_position - CRATE_AT).length() < 1.5,
		"the box on the stack stayed over the crates",
	)


## `id`'s underside is `top` px above the floor.
func _rests(t: TestContext, id: StringName, top: float) -> void:
	var low := Probe.body(t.object(id)).global_position.y / RenderConfig.unit
	t.check(
		absf(low - top) < SLACK, "%s stands %.2f px up, on a top of %.1f px" % [id, low, top]
	)
