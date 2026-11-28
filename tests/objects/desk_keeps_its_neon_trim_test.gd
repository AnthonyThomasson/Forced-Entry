extends GameTest
## D21 unbake (#194, `docs/stacked-items.md` SI13): a desk lost its monitor prop but not its
## neon trim. About half the desks (`ObjectArtLightConfig.neon_share["desk"]`, asked by the desk's
## own `neon_as` option, so no other table takes one) get a cyan or magenta strip round the edge,
## and the strip gives its light (the `trim` row). The monitor item draws no neon of its own, but
## a neon desk's monitor takes the desk's (its lit edge and its light), and one on a plain desk is
## the plain green screen, so a desk's trim and its monitor never disagree (SI14).

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
	s.object(&"bare", "desk", AT + Vector2(0.0, -150.0), { "neon": "" })
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

	_monitors(t, desk)


## The monitor a neon desk carries has the desk's neon (art option and light), a plain desk's none.
func _monitors(t: TestContext, desk: Node2D) -> void:
	var definition := ObjectDefinitions.get_definition("desk")
	var neon := _monitor_of(RoomItems.carry(desk, definition, t.world, "test"))
	if not t.require(neon != null, "the neon desk carries a monitor"):
		return
	t.expect_eq(neon.look.art_opts.get("neon"), "cyan", "its monitor takes the desk's neon")
	var lights: Array = neon.call(&"get_lights")
	if t.require(lights.size() == 1, "the monitor gives one light (%d)" % lights.size()):
		t.expect_eq(lights[0]["colour"], ObjectArtLightConfig.neon_cyan, "in the desk's neon")
	var bare := t.object(&"bare")
	var plain := _monitor_of(RoomItems.carry(bare, definition, t.world, "test"))
	if t.require(plain != null, "the plain desk carries a monitor"):
		t.check(not plain.look.art_opts.has("neon"), "a plain desk's monitor has no neon")


func _monitor_of(carried: Array) -> Node2D:
	for c: Dictionary in carried:
		if c["key"] == "monitor":
			return c["node"]
	return null
