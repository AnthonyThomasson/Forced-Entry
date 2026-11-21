extends GameTest
## D21 unbake (#194 17g, `docs/stacked-items.md` SI13): the desk no longer paints its monitor,
## keyboard, mug and papers; its catalogue row `carries` them and `RoomItems.carry` sets each one
## on it where it was drawn, as a free body of its own. The desk's art holds no props; each item
## rests on the desk's top asleep; a shove on the monitor moves only the monitor.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const AT := Vector2(400, 250)
const WANT := ["monitor", "keyboard", "cup", "papers"]


func describe() -> Dictionary:
	return {
		"name": "An emptied desk carries its monitor, keyboard, mug and papers as items",
		"description": "The desk paints no props; carry() sets four separate items on it where "
			+ "they were drawn, each asleep on its top; a shove moves the monitor alone.",
		"tags": ["furniture", "3d", "items", "stacking", "unbake"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"desk", "desk", AT)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var desk: Node2D = t.object(&"desk")
	t.check(
		not (desk.look.art_opts as Dictionary).has("props"),
		"the desk paints no props (they are items now)",
	)
	var carried := RoomItems.carry(
		desk, ObjectDefinitions.get_definition("desk"), t.world, "test"
	)
	var keys: Array = carried.map(func(c: Dictionary) -> String: return c["key"])
	keys.sort()
	var want := WANT.duplicate()
	want.sort()
	t.expect_eq(keys, want, "the desk carries a monitor, a keyboard, a mug and papers")
	await t.seconds(2.5)
	var top := PieceHeights.top_of_spec(FurnitureSpec.of(desk))
	var at := {}
	for c: Dictionary in carried:
		var node: Node2D = c["node"]
		t.check(Probe.asleep(node), "%s rests asleep" % c["key"])
		t.check(
			absf(Probe.centre(node) - top) < 12.0 and Probe.centre(node) > top - 0.5,
			"%s rests on the desk's top (%.1f over %.1f)" % [c["key"], Probe.centre(node), top],
		)
		at[c["key"]] = node.global_position
		var foot := Rect2(desk.global_position - desk.size * 0.5, desk.size)
		t.check(
			foot.has_point(node.global_position),
			"%s is within the desk's footprint" % c["key"],
		)
	var monitor: Node2D = _node(carried, "monitor")
	Knockback.push(monitor, Vector2(0.0, -900.0), Vector2.ZERO, 20.0)
	await t.seconds(0.6)
	t.check(
		monitor.global_position.distance_to(at["monitor"]) > 3.0,
		"the shoved monitor moved (%.1f px)" % monitor.global_position.distance_to(at["monitor"]),
	)
	for c: Dictionary in carried:
		if c["key"] == "monitor":
			continue
		t.check(
			(c["node"] as Node2D).global_position.distance_to(at[c["key"]]) < 0.5,
			"%s did not move with it" % c["key"],
		)


func _node(carried: Array, key: String) -> Node2D:
	for c: Dictionary in carried:
		if c["key"] == key:
			return c["node"]
	return null
