extends GameTest
## D21 unbake (#194 17g, `docs/stacked-items.md` SI13): a desk lost its monitor prop but not its
## neon trim. About half the desks (`ObjectArtLightConfig.neon_share["desk"]`, asked by the desk's
## own `neon_as` option, so no other table takes one) get a cyan or magenta strip round the edge,
## and the strip gives its light (the `trim` row). The monitor item on it takes no neon of its own:
## its screen is the plain green one, so a desk's trim and its monitor never disagree.

const ObjectArt := preload("res://scenes/objects/art/object_art.gd")
const AT := Vector2(400, 250)
const SEEDS := 200


func describe() -> Dictionary:
	return {
		"name": "A desk keeps its share of neon trim, a monitor item none",
		"description": "neon_for gives about half of 200 desks a neon (a plain table none, a "
			+ "monitor item none); a desk with neon draws and lights it as a trim.",
		"tags": ["objects", "neon", "items", "unbake"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"desk", "desk", AT, { "neon": "cyan" })
	s.object(&"plain", "table", AT + Vector2(0.0, 150.0), { "neon": "" })
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var desk_opts: Dictionary = ObjectDefinitions.get_definition("desk").get("art_opts", {})
	var desks := 0
	var tables := 0
	var monitors := 0
	for n in SEEDS:
		if ObjectArt.neon_for("table", desk_opts, n * 7919) != "":
			desks += 1
		if ObjectArt.neon_for("table", {}, n * 7919) != "":
			tables += 1
		if ObjectArt.neon_for("item", { "kind": "monitor" }, n * 7919) != "":
			monitors += 1
	t.check(
		desks >= 70 and desks <= 130,
		"about half the desks take a neon trim (%d of %d)" % [desks, SEEDS],
	)
	t.expect_eq(tables, 0, "a table that is no desk takes none")
	t.expect_eq(monitors, 0, "a monitor item takes none of its own")
	t.expect_eq(
		ObjectArt.neon_variants("table", desk_opts), ["", "cyan", "magenta"],
		"a desk's art can come in each neon",
	)
	var desk: Node2D = t.object(&"desk")
	var lights: Array = desk.call(&"get_lights")
	if t.require(
		lights.size() == 1,
		"a desk with a neon trim gives one light (%d)" % lights.size(),
	):
		t.expect_eq(
			lights[0]["colour"], ObjectArtLightConfig.neon_cyan, "the desk's light is its trim's"
		)
	t.expect_eq(
		(t.object(&"plain").call(&"get_lights") as Array).size(), 0, "a plain table gives none"
	)
