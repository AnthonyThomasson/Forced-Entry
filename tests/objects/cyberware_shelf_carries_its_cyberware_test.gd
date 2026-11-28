extends GameTest
## The cyberware shelf is bare steel with its cyberware as free items (#194, D21, rule 9,
## `docs/stacked-items.md` SI16): hollow (posts and a board per tier, open between, its body moving
## as the box of its extent), and its arms, eyes, chips and jars are items standing each on a
## board's top, none inside a part, on every tier, seeded by the look (two shelves carry the same),
## and nothing over any of them: the game camera looks down on the shelf, so a board over an item
## would hide it (the tiers step up along the shelf, each its own column, none over another).

const CYBER := ["cyber_arm", "cyber_eye", "cyber_chip", "cyber_jar"]
## The shelf drawn before held about 38 things on three tiers one over another; the stepped one
## holds about two thirds of that, 26 (the lit picture's bars hold it:
## `art/shop_pieces_lit_windowed`).
const MIN_ITEMS := 24
## A thing is inside a part when it is this far (px) into its height.
const INSIDE := 0.3


func describe() -> Dictionary:
	return {
		"name": "The cyberware shelf is hollow and carries its cyberware",
		"description": "A cyberware shelf is posts and boards with open tiers; its rows are "
			+ "arms, eyes, chips and jars, each standing on a board's top clear of every part, "
			+ "on every tier, the same on two shelves of one look.",
		"tags": ["furniture", "items", "stacking", "unbake", "heights"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.object(&"shelf", "cyberware_shelf", Vector2(150, 120))
	s.object(&"twin", "cyberware_shelf", Vector2(150, 220))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var piece: Node2D = t.object(&"shelf")
	var spec := FurnitureSpec.of(piece)
	var definition := ObjectDefinitions.get_definition("cyberware_shelf")
	t.check(PieceHeights.hollow(spec), "the shelf is hollow (open tiers)")
	t.check(
		not (piece.look.art_opts as Dictionary).has("props"), "the shelf paints no props",
	)
	var rows := PieceCarries.canonical(definition, spec)
	t.require(rows.size() >= 6, "premise: the shelf carries its cyberware (%d rows)" % rows.size())
	t.check(
		rows.size() >= MIN_ITEMS,
		"the shelf is as full as the one it replaced (%d items, at least %d)" % [
			rows.size(),
			MIN_ITEMS,
		],
	)
	var lifts := {}
	var kinds := {}
	for row: Dictionary in rows:
		kinds[row["key"]] = int(kinds.get(row["key"], 0)) + 1
	t.check(kinds.size() == CYBER.size(), "every kind of cyberware is on the shelf (%s)" % kinds)
	for row: Dictionary in rows:
		t.check(String(row["key"]) in CYBER, "%s is cyberware" % row["key"])
		t.check(
			ObjectDefinitions.get_definition(String(row["key"])).size() > 0,
			"%s is in the catalogue" % row["key"],
		)
		lifts[snappedf(float(row["lift"]), 0.01)] = true
		_clear(t, spec, row)
	t.expect_eq(lifts.size(), ObjectMeshTechConfig.cyber_tiers, "a row of items on every tier")
	var other := FurnitureSpec.of(t.object(&"twin") as Node2D)
	t.expect_eq(
		PieceCarries.canonical(definition, other), rows, "one look, one layout of cyberware",
	)


## `row` stands on a board's top and is inside no part of the shelf.
func _clear(t: TestContext, spec: FurnitureSpec, row: Dictionary) -> void:
	var size: Vector2 = row["size"]
	var at: Vector2 = (row["at"] as Vector2) + spec.size * 0.5
	var foot := Rect2(at - size * 0.5, size).grow(-0.01)
	var lift := float(row["lift"])
	var rests := false
	for part: Dictionary in PieceHeights.parts(spec):
		var rect: Rect2 = part["rect"]
		var area := Rect2(rect.position * spec.size, rect.size * spec.size)
		if not area.intersects(foot):
			continue
		rests = rests or absf(float(part["top"]) - lift) < INSIDE
		t.check(
			not float(part["base"]) > lift,
			"%s at %s has a part over it, hidden from the game camera (%s)" % [
				row["key"],
				at,
				part,
			],
		)
		t.check(
			not (float(part["base"]) < lift - INSIDE and float(part["top"]) > lift + INSIDE),
			"%s at %s is inside a part (%s)" % [row["key"], at, part],
		)
	t.check(rests, "%s at %s rests on a board's top" % [row["key"], at])
