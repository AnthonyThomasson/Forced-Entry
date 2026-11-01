extends RefCounted
## Paint on the road, a transparent layer over real asphalt: two lanes at `opts.lanes` (the x of
## each lane's middle). Options: `variant` `a` large painted Chinese characters (Ruiner), `b` lane
## numbers and arrows, `c` both, faded.

const Glyphs := preload("res://sandboxes/showroom/downtown_district/glyphs.gd")
const Kit := preload("res://sandboxes/showroom/downtown_district/paint_kit.gd")
const PAINT := Color(0.86, 0.84, 0.74)
const DIGITS := 5


## Paint the glyphs of `opts.variant` onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var variant := String(opts.get("variant", "a"))
	var lanes: Array = opts["lanes"]
	var left: int = lanes[0]
	var right: int = lanes[1]
	if variant != "b":
		_characters(c, left, right, variant == "c")
	if variant != "a":
		_numbers(c, left, right, variant == "c")
	if variant == "a":
		Kit.fade(c, 0.85)
		Kit.wear(c, 0.28, 0.95, 18)
	elif variant == "b":
		Kit.fade(c, 0.9)
		Kit.wear(c, 0.18, 0.9, 10)
	else:
		Kit.fade(c, 0.5)
		Kit.wear(c, 0.4, 1.0, 26)


## Large characters: 大 (工 when low) in the left lane, 出口 stacked in the right (`low` puts them
## lower, under the numbers).
static func _characters(c: PixelCanvas, left: int, right: int, low: bool) -> void:
	var top := 190 if low else 50
	var size := 56 if low else 74
	var ink := Kit.ink(PAINT, 7 if low else 9, 0.12)
	Glyphs.draw_hanzi(c, "工" if low else "大", Vector2i(left - int(size / 2.0), top), size, ink)
	var small := 40 if low else 50
	var small_ink := Kit.ink(PAINT, 7, 0.12)
	var x := right - int(small / 2.0)
	Glyphs.draw_hanzi(c, "出", Vector2i(x, top - 10), small, small_ink)
	Glyphs.draw_hanzi(c, "口", Vector2i(x, top + small + 14), small, small_ink)


## A lane number and an arrow in each lane (`top` set by `low`).
static func _numbers(c: PixelCanvas, left: int, right: int, low: bool) -> void:
	var top := 40 if low else 60
	var ink := Kit.ink(PAINT, DIGITS)
	Glyphs.draw_centered(c, "12", left, top, ink)
	Glyphs.draw_centered(c, "13", right, top, ink)
	_arrow(c, Vector2i(left, top + 66))
	_arrow(c, Vector2i(right, top + 66))
	if not low:
		Glyphs.draw_centered(c, "07", left, top + 230, ink)
		Glyphs.draw_centered(c, "24", right, top + 230, ink)
		_arrow(c, Vector2i(left, top + 296))
		_arrow(c, Vector2i(right, top + 296))


## An ahead arrow with its tip at `at.x` and `at.y` its top.
static func _arrow(c: PixelCanvas, at: Vector2i) -> void:
	for k in 26:
		Kit.fill_rect(c, Rect2i(at.x - k, at.y + k, k * 2 + 1, 1), PAINT)
	Kit.fill_rect(c, Rect2i(at.x - 6, at.y + 26, 13, 46), PAINT)
