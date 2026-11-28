extends GameTest
## An emptied shelf carries its things as loose items (#194, D21, rule 9,
## `docs/stacked-items.md` SI13): the garage shelving no longer builds its cardboard boxes into its
## mesh; they are free bodies set on its boards where the old look drew them, each asleep with its
## underside on a board's top and inside the shelf's footprint; the shelf is boards, sides and a
## back (a part each), so the compartments between are open to what stands in them.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const AT := Vector2(400, 250)
## The shelving's boards (px above the floor) by its own rule: 77 tall, four boards 2 thick every
## 25 px, the top one at 75..77 carrying nothing on it.
const BOARD_TOPS := [2.0, 27.0, 52.0]
const SLACK := 0.8


func describe() -> Dictionary:
	return {
		"name": "Emptied shelving carries its boxes on its boards",
		"description": "Garage shelving with its boxes as loose items: boxes on every board "
			+ "except the top, each asleep with its underside on a board and inside the "
			+ "footprint, the shelf itself hollow (sides, back, a slab per board).",
		"tags": ["furniture", "3d", "items", "stacking", "unbake"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"shelf", "shelving", AT)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var shelf: Node2D = t.object(&"shelf")
	var definition := ObjectDefinitions.get_definition("shelving")
	t.require(PieceCarries.carries(definition), "premise: the shelving is emptied")
	var parts := PieceHeights.parts_of(definition)
	t.check(parts.size() == 6, "the shelf is 3 side/back parts and 3 boards (%d)" % parts.size())
	t.check(
		absf(PieceHeights.top_of(definition) - 77.0) < 0.01, "the shelf stands 77 px high",
	)
	var placed := RoomItems.carry(shelf, definition, shelf.get_parent(), "test")
	t.require(placed.size() >= 6, "premise: the shelving carries boxes (%d)" % placed.size())
	await t.frames(3)
	for entry: Dictionary in placed:
		var item: Node2D = entry["node"]
		t.check(entry["key"] in ["box", "paint_tin"], "a loose box or tin (%s)" % entry["key"])
		t.check(
			await Probe.settle(t, item, 4.0), "%s settles asleep" % item.name,
		)
	var footprint := Rect2(shelf.global_position - shelf.size * 0.5, shelf.size).grow(1.5)
	var boards: Dictionary = {}
	for entry: Dictionary in placed:
		var item: Node2D = entry["node"]
		var low := Probe.body(item).global_position.y / RenderConfig.unit
		var on_board := BOARD_TOPS.any(func(top: float) -> bool: return absf(low - top) < SLACK)
		t.check(on_board, "%s stands %.2f px up, on a board" % [item.name, low])
		t.check(footprint.has_point(item.global_position), "%s stays over the shelf" % item.name)
		boards[snappedf(low, 1.0)] = true
	t.check(boards.size() == BOARD_TOPS.size(), "boxes on every board but the top (%s)" % [boards])
