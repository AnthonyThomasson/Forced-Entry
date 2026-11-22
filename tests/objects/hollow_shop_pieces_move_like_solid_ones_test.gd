extends GameTest
## A shop's hollow pieces move as the solid boxes of their extent (#194 unbake-c, D21, rule 9,
## `docs/stacked-items.md` SI16): the drinks fridge, the snack machine, the shelf aisle and the
## cyberware shelf are thin parts round empty compartments, but their body has the centre of mass
## and the yaw inertia of the solid box a block of their footprint and height would be (as the
## emptied bookshelf's does, `objects/hollow_shelf_moves_like_a_solid_one`), so a shove slides,
## turns and tips them as the solid pieces they replaced.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const PIECES := ["drinks_fridge", "snack_machine", "shelf_aisle", "cyberware_shelf"]
## How close a number must be to the box's (a share of it).
const CLOSE := 0.02


func describe() -> Dictionary:
	return {
		"name": "A shop's hollow pieces move like solid ones",
		"description": "The drinks fridge, snack machine, shelf aisle and cyberware shelf have "
			+ "the centre of mass at the middle of their box and the yaw inertia of the solid "
			+ "box of their footprint and height (the numbers a shove moves them by; the shove "
			+ "itself is `objects/stocked_fridge_keeps_its_stock`).",
		"tags": ["furniture", "3d", "tipping", "unbake"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	for i in PIECES.size():
		s.object(StringName(PIECES[i]), PIECES[i], Vector2(120 + 200.0 * i, 200))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(5)
	for key: String in PIECES:
		var piece: Node2D = t.object(StringName(key))
		var body := Probe.body(piece)
		if not t.require(body != null, "%s has a 3D body" % key):
			continue
		var size: Vector2 = WorldGen.object_definition(key)["size"]
		var high := Probe.top(piece)
		t.check(high > 20.0, "premise: %s stands %.1f px tall" % [key, high])
		t.check(
			absf(body.center_of_mass.y - high * 0.5) <= high * CLOSE,
			"%s: its centre of mass is the box's middle (%.2f of %.2f)"
			% [key, body.center_of_mass.y, high * 0.5],
		)
		t.check(
			absf(body.center_of_mass.x) < 0.5 and absf(body.center_of_mass.z) < 0.5,
			"%s: its centre of mass is over the middle of its footprint" % key,
		)
		var box := 12.0 / (body.mass * (size.x * size.x + size.y * size.y))
		t.check(
			absf(body.inverse_yaw_inertia() - box) <= box * CLOSE,
			"%s: the yaw inertia is the box's (%.6f, box %.6f)"
			% [key, body.inverse_yaw_inertia(), box],
		)
