extends GameTest
## A showroom of the emptied pieces (`docs/stacked-items.md` SI13): you are the
## player, with a pistol (3) and fists (2), in a room of three rows.
## The back row is the built-in look: a bookshelf, garage shelving, a linen shelf and a shoe rack
## with their books, boxes, towels... built into one mesh (`art_opts.loose` off): a solid piece,
## shot or shoved as one. The middle row is the same four pieces EMPTIED (what a house builds):
## hollow boards, with the books (in runs), boxes and shoes loose on them: shoot a book and it alone
## drops; shove a shelf and its things slide with it, tip it and they spill. The front row is the
## stock: two plain crates stacked, a crate stack as a stockroom has it (2 or 3 loose crates), a
## pallet with its four wrapped boxes, and the hotplate (the crate, a hob that glows and a pan).
##
## Nothing is asserted. Temporary showroom.

const ARENA := Rect2(0, 0, 960, 640)
const OLD_ROW := 130.0
const NEW_ROW := 290.0
const STOCK_ROW := 470.0
## The shelves of a row, left to right: `[id, catalogue key]`, `COLUMN` px apart from `FIRST`.
const SHELVES := [
	[&"books", "bookshelf"], [&"shelving", "shelving"], [&"linen", "linen_shelf"],
	[&"shoes", "shoe_rack"],
]
const FIRST := 120.0
const COLUMN := 150.0
## Every emptied piece of the middle and front rows and its catalogue key, to set what it carries
## on in `run`.
const EMPTIED := {
	&"new_books": "bookshelf", &"new_shelving": "shelving", &"new_linen": "linen_shelf",
	&"new_shoes": "shoe_rack", &"stack": "crate_stack", &"pallet": "wrapped_pallet",
	&"hotplate": "hotplate",
}


func describe() -> Dictionary:
	return {
		"name": "Emptied pieces showroom",
		"description": "Player sandbox: WASD, mouse, LMB fire, 2 fists, 3 pistol. Back row: "
			+ "shelves with their books, boxes and shoes built in (the old look); middle row: "
			+ "the same shelves hollow with their things loose; front row: plain crates, a "
			+ "crate stack, a pallet with wrapped boxes, a hotplate with a pan. Shoot or shove "
			+ "anything: a loose thing moves alone.",
		"tags": ["sandbox", "player", "items", "stacking", "furniture", "showroom", "unbake"],
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA)
	s.actor(&"you", &"player", Vector2(60, 580), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(900, 580), { "max_health": 200.0, "faction": &"dummy" })
	for i in SHELVES.size():
		var key: String = SHELVES[i][1]
		var at := FIRST + COLUMN * i
		var old := WorldGen.object_definition(key).duplicate(true)
		var opts: Dictionary = old.get("art_opts", {})
		opts["loose"] = false
		old["art_opts"] = opts
		s.object(StringName("old_%s" % SHELVES[i][0]), old, Vector2(at, OLD_ROW))
		s.object(StringName("new_%s" % SHELVES[i][0]), key, Vector2(at, NEW_ROW))
	s.object(&"plain_low", "crate", Vector2(FIRST, STOCK_ROW))
	s.object(&"plain_top", "crate", Vector2.ZERO, { "on": &"plain_low" })
	s.object(&"stack", "crate_stack", Vector2(FIRST + COLUMN, STOCK_ROW))
	s.object(&"pallet", "wrapped_pallet", Vector2(FIRST + COLUMN * 2.0, STOCK_ROW))
	s.object(&"hotplate", "hotplate", Vector2(FIRST + COLUMN * 3.4, STOCK_ROW))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	for id: StringName in EMPTIED:
		var piece: Node2D = t.object(id)
		var definition := ObjectDefinitions.get_definition(EMPTIED[id])
		RoomItems.carry(piece, definition, piece.get_parent(), "showroom")
