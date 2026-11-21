extends GameTest
## A bookshelf's books are free bodies (#194 unbake-b, D21, rule 9, `docs/stacked-items.md` SI13):
## they stand on the boards asleep at the start (none topples), and a bookshelf knocked over spills
## them: it lies on its side and most of the books are no longer where they stood.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const AT := Vector2(400, 250)
const SLACK := 0.8
## What a book may lean while it stands on a board (a few degrees, as every settled item).
const MAX_LEAN := 8.0


func describe() -> Dictionary:
	return {
		"name": "A bookshelf tips and spills its books",
		"description": "A bookshelf with its books standing on the boards, all asleep upright "
			+ "at the start; knocked over, it lies on its side and the books are carried off "
			+ "where they stood.",
		"tags": ["furniture", "3d", "items", "stacking", "tipping", "unbake"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"shelf", "bookshelf", AT)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var shelf: Node2D = t.object(&"shelf")
	var placed := RoomItems.carry(
		shelf, ObjectDefinitions.get_definition("bookshelf"), shelf.get_parent(), "test"
	)
	t.require(
		placed.size() >= 5,
		"premise: the bookshelf carries runs of books (%d)" % placed.size(),
	)
	await t.frames(3)
	var start: Dictionary = {}
	for entry: Dictionary in placed:
		var book: Node2D = entry["node"]
		t.check(
			await Probe.settle(t, book, 5.0), "%s settles asleep on its board" % book.name,
		)
		t.check(
			Probe.lean(book) < MAX_LEAN,
			"%s stands (leans %.1f degrees)" % [book.name, Probe.lean(book)],
		)
		start[book] = Probe.middle(book)
	var standing := Probe.top(shelf)
	t.require(await Probe.settle(t, shelf, 4.0), "premise: the shelf is asleep")
	Knockback.push(shelf, Vector2(30_000.0, 0.0), Vector2.ZERO, standing - 6.0)
	await t.seconds(0.4)
	await Probe.settle(t, shelf, 8.0)
	if not t.require(
			Probe.lean(shelf) > 60.0,
			"premise: the shelf lies on its side (%.0f degrees)" % Probe.lean(shelf),
	):
		return
	var moved := 0
	for book: Node2D in start:
		await Probe.settle(t, book, 8.0)
		if Probe.middle(book).distance_to(start[book]) > 6.0:
			moved += 1
	t.check(
		moved * 10 >= start.size() * 6,
		"most books were carried off (%d of %d moved over 6 px)" % [moved, start.size()],
	)
