extends GameTest
## The real bookshelf of a built house, hollow since D21, lies down and is carved like the solid one
## (#194, `docs/stacked-items.md` SI13): two bookshelves, one hollow (the catalogue's) and
## one built solid as before the unbake, stand on clear floor of two rooms of a house and take the
## same shove. Both lie on their sides and the nav holes of each (the footprint hull of what lies)
## cover the same area. A room's middle is not clear floor (a bed may stand there: a shelf set on
## it is settled clear and leans on it); the spot is picked by `Piece.clear_spot`.

const Piece := preload("res://tests/_objects/piece_probe.gd")
const SEED := 1
const PLAN := "garage_home"
const PUSH := 5000.0
const AREA_SHARE := 0.1


func describe() -> Dictionary:
	return {
		"name": "A tipped hollow bookshelf in a house is carved like the solid one",
		"description": "In a built house a hollow and a solid bookshelf on clear floor take the "
			+ "same shove: both lie on their sides, and the nav holes of the pair cover the same "
			+ "area to 10%.",
		"tags": ["navigation", "furniture", "tipping", "house", "unbake"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED, PLAN)
	var solid: Dictionary = ObjectDefinitions.get_definition("bookshelf").duplicate(true)
	var opts: Dictionary = solid.get("art_opts", {})
	opts["loose"] = false
	solid["art_opts"] = opts
	s.object(&"solid", solid, Vector2.ZERO)
	s.object(&"hollow", "bookshelf", Vector2.ZERO)
	s.switch(&"nav.rebake", false)
	s.switch(&"worldgen.items", false)


func run(t: TestContext) -> void:
	var house: Node2D = t.world.get("house")
	var rooms := WorldGen.get_rooms(house)
	await t.frames(30)
	var areas := {}
	var both: Array = [t.object(&"solid"), t.object(&"hollow")]
	for kind: StringName in [&"solid", &"hollow"]:
		var shelf: Node2D = t.object(kind)
		for other: Node2D in both:
			if other != shelf:
				other.global_position = Vector2(-9000.0, -9000.0)
		shelf.global_position = Piece.clear_spot(t, rooms[1]["rect"], both)
		await t.frames(TwinSpace.PARK_SPREAD + 40)
		Knockback.push(shelf, Vector2(PUSH, 0.0), Vector2.ZERO, Piece.top(shelf) - 4.0)
		await t.seconds(0.3)
		await Piece.settle(t, shelf, 10.0)
		t.check(Piece.lean(shelf) > 60.0, "the %s bookshelf lies on its side" % kind)
		await t.frames(2)
		areas[kind] = _area(NavHoles.cut(shelf))
	t.require(areas[&"solid"] > 0.0, "premise: the solid shelf's lying footprint is carved")
	t.check(
		absf(areas[&"hollow"] - areas[&"solid"]) <= areas[&"solid"] * AREA_SHARE,
		"the lying hollow shelf is carved as the solid one (%.0f px², solid %.0f)" % [
			areas[&"hollow"],
			areas[&"solid"],
		],
	)


## The area of the polygon `poly`.
func _area(poly: PackedVector2Array) -> float:
	var sum := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5
