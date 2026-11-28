extends GameTest
## A noodle bowl is as big as the one it replaced (#194, D21 "the old look kept",
## `docs/stacked-items.md` SI16): the flat art laid over its mesh top is the old painter's bowl, a
## pale rim to the edge of its footprint with the broth inside it (two pixels of rim), not a bowl
## with a dark outline ring and a dark well that reads a pixel smaller each side. A bowl with no
## `well` (a fruit bowl, a plain one) is drawn as it was.

const ItemPainter := preload("res://scenes/objects/art/item_painter.gd")
const BOWL := Color(0.9, 0.88, 0.8)
const BROTH := Color(0.74, 0.5, 0.2)


func describe() -> Dictionary:
	return {
		"name": "A noodle bowl is painted the old size",
		"description": "The flat art of a bowl with a well is a pale rim out to the edge of its "
			+ "footprint with the broth inside, as the old noodle painter drew it; a bowl with "
			+ "no well keeps its outline ring and dark well.",
		"tags": ["items", "art", "unbake"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	for plain: bool in [true, false]:  # a row's item (`on_top`) is plain: the noodle bowls are
		_check(t, { "kind": "bowl", "well": BROTH, "plain": plain })
	var bare := PixelCanvas.new(12, 12, 4, Vector2.ZERO)
	ItemPainter.paint(bare, BOWL, "ceramic", { "kind": "bowl" })
	t.check(_near(bare.at(6, 0), BOWL.darkened(0.15)), "no well: the outline ring stays")


## The bowl of art options `opts` is the old noodle bowl.
func _check(t: TestContext, opts: Dictionary) -> void:
	var canvas := PixelCanvas.new(12, 12, 4, Vector2.ZERO)
	ItemPainter.paint(canvas, BOWL, "ceramic", opts)
	t.check(_near(canvas.at(6, 6), BROTH), "the middle is the broth (%s)" % canvas.at(6, 6))
	t.check(
		_near(canvas.at(6, 0), BOWL),
		"the rim reaches the footprint's edge in the bowl's own colour (%s)" % canvas.at(6, 0),
	)
	t.check(_near(canvas.at(6, 1), BOWL), "two pixels of rim (%s)" % canvas.at(6, 1))


## `a` is `b` to within 8-bit quantization.
func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01
