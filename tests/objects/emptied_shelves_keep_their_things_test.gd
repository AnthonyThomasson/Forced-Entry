extends GameTest
## An emptied shelf keeps what it carries (#194 unbake-b, D21, rule 9, `docs/stacked-items.md`
## SI13): the emptied pieces of `SHELVES` set side by side, every
## carried thing is asleep over its own piece a second after the start: none is thrown out of a
## compartment where it overlaps a side or a board, so nothing lies on the floor between pieces.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const SHELVES := [
	["bookshelf", "bookshelf"], ["shelving", "shelving"], ["linen", "linen_shelf"],
	["shoes", "shoe_rack"], ["stack", "crate_stack"], ["pallet", "wrapped_pallet"],
	["hotplate", "hotplate"], ["aisle", "shelf_aisle"], ["fridge", "drinks_fridge"],
	["snack", "snack_machine"], ["cyber", "cyberware_shelf"],
]
const FIRST := 120.0
const COLUMN := 150.0
const ROW := 200.0
## How far past its piece's footprint a thing may lie (a leaning book, a box on a lip).
const SLACK := 3.0


func describe() -> Dictionary:
	return {
		"name": "Emptied shelves and stock keep their things",
		"description": "The four shelves, a crate stack, a pallet, a hotplate, a shop aisle, a "
			+ "fridge, a snack machine and a cyberware shelf, each carrying its things, in two "
			+ "turns: every carried thing is asleep over its piece, none thrown to the floor.",
		"tags": ["furniture", "3d", "items", "stacking", "unbake"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1900, 500))
	for i in SHELVES.size():
		for turn in 2:
			s.object(
				StringName("%s_%d" % [SHELVES[i][0], turn]),
				SHELVES[i][1],
				Vector2(FIRST + COLUMN * i, 120.0 + ROW * turn),
				{ "rotated": turn == 1, "facing": Vector2.RIGHT if turn == 1 else Vector2.DOWN },
			)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var placed: Array = []
	for i in SHELVES.size():
		for turn in 2:
			var piece: Node2D = t.object(StringName("%s_%d" % [SHELVES[i][0], turn]))
			var definition := ObjectDefinitions.get_definition(SHELVES[i][1])
			placed.append_array(RoomItems.carry(piece, definition, piece.get_parent(), "test"))
	t.require(placed.size() >= 30, "premise: the pieces carry things (%d)" % placed.size())
	await t.seconds(1.5)
	for entry: Dictionary in placed:
		var item: Node2D = entry["node"]
		var piece: Node2D = entry["on"]
		var size: Vector2 = piece.size
		var reach := Rect2(piece.global_position - size * 0.5, size).grow(SLACK)
		t.check(
			reach.has_point(item.global_position),
			"%s of %s stays over its piece (at %s)" % [item.name, piece.name, item.global_position],
		)
		t.check(Probe.body(item).sleeping, "%s is asleep" % item.name)
