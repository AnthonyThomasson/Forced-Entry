extends GameTest
## A noodle bar's pot carries its broth in the flat art too (#194, D21 "the old look
## kept", `docs/stacked-items.md` SI16): the flat top the 3D picture draws over the pot's mesh is
## the old painter's pot (a dark rim, a ring of steel, the broth inside), not a steel disc with a
## dark middle, so the lit picture shows a brown broth. A pot with no `well` (the stockroom's) is
## the steel disc it was.

const ItemPainter := preload("res://scenes/objects/art/item_painter.gd")
const ObjectArtScript := preload("res://scenes/objects/art/object_art.gd")
const STEEL := Color(0.55, 0.56, 0.58)
const BROTH := Color(0.74, 0.5, 0.2)


func describe() -> Dictionary:
	return {
		"name": "A noodle pot is painted with its broth",
		"description": "The flat art of a pot with a well has its rim, its steel and the broth "
			+ "in the middle, as the old noodle counter drew it; the art options keep the well; "
			+ "a pot with none is the old steel disc.",
		"tags": ["items", "art", "unbake"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var kept: Dictionary = ObjectArtScript._art_opts(
		"item", { "kind": "pot", "well": BROTH, "height": 11 }
	)
	t.expect_eq(kept.get("well"), BROTH, "the art options keep a pot's well")
	var canvas := PixelCanvas.new(16, 16, 7, Vector2.ZERO)
	ItemPainter.paint(canvas, STEEL, "metal", kept)
	t.check(
		_near(canvas.at(8, 8), BROTH.darkened(0.2)),
		"the middle is the broth (%s)" % canvas.at(8, 8),
	)
	t.check(_near(canvas.at(8, 3), STEEL), "a ring of steel round it (%s)" % canvas.at(8, 3))
	t.check(_near(canvas.at(8, 0), STEEL.darkened(0.4)), "a dark rim (%s)" % canvas.at(8, 0))
	var bare := PixelCanvas.new(16, 16, 7, Vector2.ZERO)
	ItemPainter.paint(bare, STEEL, "metal", { "kind": "pot" })
	t.check(_near(bare.at(8, 8), STEEL.darkened(0.45)), "no well: the old steel disc")


## `a` is `b` to within 8-bit quantization.
func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01
