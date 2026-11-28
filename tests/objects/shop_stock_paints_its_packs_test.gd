extends GameTest
## A run of bottles or snack packs is painted pack by pack (#194, D21 "the old look kept",
## `docs/stacked-items.md` SI16): the flat art of a run, the top the 3D picture draws, gives each of
## its `spines` its own colour with a dark seam between, as the old fridge, machine and aisle drew
## their packs. One colour for the whole run (the catalogue's graded base) read as a dull brown
## block in the lit picture of an aisle, a quarter of the old one's bright pixels.

const ItemShopPainter := preload("res://scenes/objects/art/item_shop_painter.gd")
const ObjectArtScript := preload("res://scenes/objects/art/object_art.gd")
const SPINES := [
	[0.0, 5.0, 9.0, Color(0.8, 0.1, 0.1)], [5.6, 5.0, 9.0, Color(0.1, 0.3, 0.8)],
	[11.2, 5.0, 9.0, Color(0.1, 0.6, 0.2)], [16.8, 5.0, 9.0, Color(0.9, 0.7, 0.1)],
]


func describe() -> Dictionary:
	return {
		"name": "A run of packs is painted in each pack's own colour",
		"description": "The flat art of a snacks run with four spines holds the four colours; "
			+ "the same through the piece's art options; a run without spines stays one colour "
			+ "with seams.",
		"tags": ["items", "art", "unbake"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var canvas := PixelCanvas.new(23, 6, 7, Vector2.ZERO)
	ItemShopPainter.paint(canvas, Color(0.4, 0.3, 0.2), "snacks", { "spines": SPINES })
	for spine: Array in SPINES:
		var at := canvas.at(roundi(spine[0]) + 2, 3)
		t.check(
			_near(at, spine[3]), "the pack at %s is its own colour (%s)" % [spine[0], at],
		)
	var kept: Dictionary = ObjectArtScript._art_opts("item", { "kind": "snacks", "spines": SPINES })
	t.expect_eq(kept.get("spines"), SPINES, "the art options keep a run's spines")
	var plain := PixelCanvas.new(23, 6, 7, Vector2.ZERO)
	ItemShopPainter.paint(plain, Color(0.4, 0.3, 0.2), "snacks")
	t.check(_near(plain.at(2, 3), Color(0.4, 0.3, 0.2)), "no spines: the run's own colour")


## `a` is `b` to within 8-bit quantization.
func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01
