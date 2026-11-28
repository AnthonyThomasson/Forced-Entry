extends GameTest
## An item set on a base later reads where its top really is (#194, D20,
## `docs/stacked-items.md` SI2): once the twin space has the base and the box on it, a plate set on
## the table a few frames later goes on the box's top (the ray down at that spot sees the box, 43
## px), not the table's own (31 px), where the box would have it inside; set at the table's bare
## end it rests on the table.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const TABLE_AT := Vector2(400, 250)
const TABLE_TOP := 31.0
const BOX_TOP := 43.0
const SLACK := 0.8


func describe() -> Dictionary:
	return {
		"name": "An item set on a stack later rests on the box's top",
		"description": "A box on a table has settled; a plate set on the table over the box ends "
			+ "up on the box's top (43 px) and a plate at the table's bare end on the "
			+ "table's (31 px), the twin space's ray telling the first.",
		"tags": ["furniture", "3d", "items", "stacking", "twins"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"table", "table", TABLE_AT)
	s.object(&"box", "box", Vector2(-15, 0), { "on": &"table" })
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	for id in [&"table", &"box"]:
		if not t.require(await Probe.settle(t, t.object(id), 4.0), "%s settles asleep" % id):
			return
	var table: Node2D = t.object(&"table")
	t.check(
		absf(ObjectFactory.top_at(table, TABLE_AT + Vector2(-15, 0)) - BOX_TOP) < SLACK,
		"the top over the box is %.1f px (the box's)" % ObjectFactory.top_at(table, TABLE_AT),
	)
	t.check(
		absf(ObjectFactory.top_at(table, TABLE_AT + Vector2(18, 0)) - TABLE_TOP) < SLACK,
		"the top at the table's bare end is the table's",
	)
	var definition := WorldGen.object_definition("plate")
	var over := ObjectFactory.spawn_on(definition, table, Vector2(-15, 0), table.get_parent())
	var bare := ObjectFactory.spawn_on(definition, table, Vector2(18, 0), table.get_parent())
	t.check(
		absf(over.rest.lift - BOX_TOP) < SLACK,
		"the plate over the box is set down at %.1f px" % over.rest.lift,
	)
	t.check(
		absf(bare.rest.lift - TABLE_TOP) < SLACK,
		"the plate at the bare end is set down at %.1f px" % bare.rest.lift,
	)
	await t.frames(3)
	for plate: Node2D in [over, bare]:
		if not t.require(await Probe.settle(t, plate, 4.0), "%s settles asleep" % plate.name):
			return
	_rests(t, over, BOX_TOP)
	_rests(t, bare, TABLE_TOP)


## `plate`'s underside is `top` px above the floor.
func _rests(t: TestContext, plate: Node2D, top: float) -> void:
	var low := Probe.body(plate).global_position.y / RenderConfig.unit
	t.check(
		absf(low - top) < SLACK, "%s lies %.2f px up, on a top of %.1f px" % [plate.name, low, top]
	)
