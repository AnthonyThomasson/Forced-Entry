extends GameTest
## The shop's drinks fridge and snack machine hold their stock behind glass (#194 unbake-c, D21,
## rule 9, `docs/stacked-items.md` SI16): the piece is a hollow body with a glass front, the
## bottles and snack packs are free items on its shelves. Shoved along, the stock stays inside (the
## glass holds it in when the piece lurches back from it); laid on its side, the piece spills it.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const PIECES := [["fridge", "drinks_fridge"], ["snack", "snack_machine"]]
const FIRST := 200.0
const COLUMN := 300.0
## A push back from the front, at the middle of a piece (px/s of impulse), and a tipping one.
const LURCH := 20_000.0
const TIP := 30_000.0
## How far past the footprint a thing standing in the piece may lie.
const SLACK := 2.0
const MIN_STOCK := 2
## How far (px) a lurched piece must have slid for the shove to count.
const SLID := 15.0
## How far (px) a thing must have been carried to count as spilled.
const MOVED := 6.0
## How far (px) an item of a shoved piece may lie from where it stood against the piece's glass:
## the lit front's windows are cut where the stock was built (`ShopStock.windows`, 3 px a window,
## a pack 5), so an item further out than this no longer stands behind its own window.
const REGISTERED := 1.5


func describe() -> Dictionary:
	return {
		"name": "A fridge and a snack machine keep their stock behind glass",
		"description": "The drinks fridge and the snack machine carry bottles and packs as free "
			+ "items on shelves inside a hollow body with a glass front: asleep inside at the "
			+ "start, still inside after a shove from the front, spilled when the piece is "
			+ "laid on its side.",
		"tags": ["furniture", "3d", "items", "stacking", "tipping", "unbake"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	for i in PIECES.size():
		for row in 2:
			s.object(
				StringName("%s_%d" % [PIECES[i][0], row]), PIECES[i][1],
				Vector2(FIRST + COLUMN * i, 150.0 + 300.0 * row),
			)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var stock := {}
	for i in PIECES.size():
		for row in 2:
			var piece: Node2D = t.object(StringName("%s_%d" % [PIECES[i][0], row]))
			var definition := ObjectDefinitions.get_definition(PIECES[i][1])
			t.require(
				PieceHeights.hollow(FurnitureSpec.of(piece)),
				"premise: %s is hollow" % piece.name,
			)
			var placed := RoomItems.carry(piece, definition, piece.get_parent(), "test")
			t.require(placed.size() >= MIN_STOCK, "premise: %s carries stock" % piece.name)
			stock[piece] = placed
	await t.seconds(1.5)
	for piece: Node2D in stock:
		for entry: Dictionary in stock[piece]:
			var item: Node2D = entry["node"]
			t.check(_inside(piece, item), "%s stands in %s at the start" % [item.name, piece.name])
			t.check(Probe.asleep(item), "%s is asleep on its shelf" % item.name)
	for i in PIECES.size():
		await _lurch(t, t.object(StringName("%s_0" % PIECES[i][0])), stock)
	for i in PIECES.size():
		await _tip(t, t.object(StringName("%s_1" % PIECES[i][0])), stock)


## `piece` shoved back from its front, at a height that does not tip it: it slides and its stock,
## carried on toward the front, is held in by the glass.
func _lurch(t: TestContext, piece: Node2D, stock: Dictionary) -> void:
	var from := Probe.middle(piece)
	var stood := {}
	for entry: Dictionary in stock[piece]:
		stood[entry["node"]] = Probe.middle(entry["node"]) - from
	Knockback.push(piece, Vector2(0.0, -LURCH), Vector2.ZERO, 20.0)
	await t.seconds(0.6)
	await Probe.settle(t, piece, 6.0)
	var slid := Probe.middle(piece).distance_to(from)
	t.check(Probe.lean(piece) < 30.0, "premise: %s was not tipped" % piece.name)
	t.check(slid > SLID, "premise: %s slid (%.0f px)" % [piece.name, slid])
	for entry: Dictionary in stock[piece]:
		t.check(
			_inside(piece, entry["node"]),
			"%s is still in %s after the shove" % [entry["node"].name, piece.name],
		)
		var drift: float = (
			(Probe.middle(entry["node"]) - Probe.middle(piece)) - stood[entry["node"]]
		).length()
		t.check(
			drift <= REGISTERED,
			"%s is still behind its window in %s (%.2f px from it, at most %.1f)"
			% [entry["node"].name, piece.name, drift, REGISTERED],
		)


## `piece` laid on its side: most of its stock is carried off from where it stood.
func _tip(t: TestContext, piece: Node2D, stock: Dictionary) -> void:
	var start := {}
	for entry: Dictionary in stock[piece]:
		start[entry["node"]] = Probe.middle(entry["node"])
	Knockback.push(piece, Vector2(TIP, 0.0), Vector2.ZERO, Probe.top(piece) - 6.0)
	await t.seconds(0.5)
	await Probe.settle(t, piece, 8.0)
	if not t.require(Probe.lean(piece) > 60.0, "premise: %s lies on its side" % piece.name):
		return
	var out := 0
	for entry: Dictionary in stock[piece]:
		await Probe.settle(t, entry["node"], 8.0)
		if Probe.middle(entry["node"]).distance_to(start[entry["node"]]) > MOVED:
			out += 1
	t.check(
		out * 2 >= stock[piece].size(),
		"%s spilled most of its stock (%d of %d)" % [piece.name, out, stock[piece].size()],
	)


## Whether `item` lies over `piece`'s footprint now (the piece's own 2D handle follows its body).
func _inside(piece: Node2D, item: Node2D) -> bool:
	var at := Probe.middle(item)
	var centre := Probe.middle(piece)
	var half: Vector2 = piece.size * 0.5
	var turned := half if (piece.look.facing as Vector2).y != 0.0 else Vector2(half.y, half.x)
	return Rect2(centre - turned, turned * 2.0).grow(SLACK).has_point(at)
