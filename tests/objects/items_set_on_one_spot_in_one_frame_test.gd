extends GameTest
## Items set on one spot in one frame stack on each other (#194 stack-a, D20,
## `docs/stacked-items.md` SI2): a house is built before the twin space takes any piece over, so
## `ObjectFactory.spawn_on` cannot ask the twin space what an item set a moment ago is: it keeps the
## chain itself. Three plates on one spot of a table start one above the other (not inside each
## other) and end asleep
## on each other; a cup set on a plate in the same frame rests on it; two on different spots of the
## table each rest on the table.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const TABLE_AT := Vector2(300, 250)
const TABLE_TOP := 31.0
const PLATE := 1.5
const CUP := 5.0
const SLACK := 0.8


func describe() -> Dictionary:
	return {
		"name": "Items set on one spot in one frame stack on each other",
		"description": "Three plates and a cup set on one spot of a table in one frame start "
			+ "one above the other (31, 32.5, 34 px, the cup at 35.5) and settle asleep there; a "
			+ "plate set on another spot of the table rests on the table.",
		"tags": ["furniture", "3d", "items", "stacking", "twins"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"table", "table", TABLE_AT)
	s.object(&"first", "plate", Vector2(-10, 0), { "on": &"table" })
	s.object(&"second", "plate", Vector2(-10, 0), { "on": &"table" })
	s.object(&"third", "plate", Vector2(-10, 0), { "on": &"table" })
	s.object(&"cup", "cup", Vector2(-10, 0), { "on": &"table" })
	s.object(&"apart", "plate", Vector2(20, 0), { "on": &"table" })
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	# as built, before the first physics step: each starts above the one under it
	var starts := {
		&"first": TABLE_TOP, &"second": TABLE_TOP + PLATE,
		&"third": TABLE_TOP + PLATE * 2.0, &"cup": TABLE_TOP + PLATE * 3.0,
		&"apart": TABLE_TOP,
	}
	for id: StringName in starts:
		t.check(
			absf(t.object(id).rest.lift - starts[id]) < 0.01,
			"%s is set down at %.2f px (%.2f)" % [id, starts[id], t.object(id).rest.lift],
		)
	await t.frames(3)
	for id: StringName in starts:
		if not t.require(await Probe.settle(t, t.object(id), 4.0), "%s settles asleep" % id):
			return
	for id: StringName in starts:
		var low := Probe.body(t.object(id)).global_position.y / RenderConfig.unit
		t.check(
			absf(low - starts[id]) < SLACK,
			"%s lies %.2f px up, on a top of %.2f px" % [id, low, starts[id]],
		)
