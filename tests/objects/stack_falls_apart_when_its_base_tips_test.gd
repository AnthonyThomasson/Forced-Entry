extends GameTest
## A stack is only as steady as its base (#194, D20, `docs/stacked-items.md`): a table
## struck high enough to tip drops the plates and the cup on it, each its own body that falls to
## the floor and comes to rest there, lower than a step.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const AT := Vector2(400, 250)


func describe() -> Dictionary:
	return {
		"name": "A tipping table drops its plates",
		"description": "Two plates and a cup on a side table; the table is knocked over: it lies "
			+ "on its side and every item ends on the floor, lying lower than a 10 px step.",
		"tags": ["furniture", "3d", "items", "stacking", "tipping"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"table", "side_table", AT)
	s.object(&"plate", "plate", Vector2(-4, -3), { "on": &"table" })
	s.object(&"second", "plate", Vector2(4, 3), { "on": &"table" })
	s.object(&"cup", "cup", Vector2(5, -5), { "on": &"table" })
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var ids := [&"plate", &"second", &"cup"]
	for id in ids:
		if not t.require(await Probe.settle(t, t.object(id), 4.0), "premise: %s asleep" % id):
			return
	var standing := Probe.top(t.object(&"table"))
	t.require(
		Probe.body(t.object(&"plate")).global_position.y / RenderConfig.unit > standing - 2.0,
		"premise: the plate is up on the table's top",
	)
	Knockback.push(t.object(&"table"), Vector2(9000.0, 0.0), Vector2.ZERO, standing - 2.0)
	await t.seconds(0.3)
	await Probe.settle(t, t.object(&"table"), 6.0)
	if not t.require(
			Probe.lean(t.object(&"table")) > 60.0,
			"premise: the table lies on its side (%.0f degrees)" % Probe.lean(t.object(&"table")),
	):
		return
	for id in ids:
		await Probe.settle(t, t.object(id), 6.0)
		var height := Probe.body(t.object(id)).global_position.y / RenderConfig.unit
		t.check(height < standing - 10.0, "%s fell off the table (%.1f px up)" % [id, height])
	t.check(
		t.object(&"plate").global_position.distance_to(AT) > 3.0,
		"the plate is not where it stood on the table",
	)
