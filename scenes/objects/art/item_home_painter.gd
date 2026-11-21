extends RefCounted
## Top-down pixel-art painter of the home's small items (`item_painter.gd` hands a kind it does not
## know here; `docs/stacked-items.md` SI13), the proportions of the props in `props.gd`:
## `keyboard` (a pale slab dotted with keys), `papers` (two sheets, the top one lined), `clock` (a
## face with two hands), `vase` (a glazed round with flowers), `fruit_bowl` (a rim ring and four
## fruits), `cutting_board` (grained wood and a knife), `tools` (a hammer, a wrench and a
## screwdriver) and `vise` (jaws and a screw handle).
## Canonical frame: the front toward +y. The colours are the old props' (the prop palette,
## `ObjectArtDecorConfig.prop_colors`), not the catalogue colour's run-down grade (`base`).

const Kit = preload("res://scenes/objects/art/paint_kit.gd")
## Where the fruits lie from the bowl's middle, px: the old prop's four.
const FRUIT_AT: Array[Vector2i] = [
	Vector2i(-2, -1), Vector2i(2, -2), Vector2i(1, 2), Vector2i(-2, 2),
]


## Paint `kind` onto `c` in `base`; false when it is none of the home's.
static func paint(c: PixelCanvas, _graded: Color, kind: String) -> bool:
	var base := _tone(kind)
	match kind:
		"keyboard":
			_keyboard(c, base)
		"papers":
			_papers(c, base)
		"clock":
			_clock(c, base)
		"vase":
			_vase(c, base)
		"fruit_bowl":
			_fruit_bowl(c, base)
		"cutting_board":
			_board(c, base)
		"tools":
			_tools(c, base)
		"vise":
			_vise(c, base)
		_:
			return false
	return true


## The colour `kind` was drawn in: its prop's main colour.
static func _tone(kind: String) -> Color:
	var palette: Dictionary = ObjectArtDecorConfig.prop_colors
	var tones := {
		"keyboard": palette["plastic_light"],
		"papers": palette["paper"],
		"clock": palette["plastic_dark"],
		"vase": palette["glaze"],
		"fruit_bowl": palette["ceramic"],
		"cutting_board": palette["wood_light"],
		"tools": palette["metal"],
		"vise": (palette["metal"] as Color).darkened(0.35),
	}
	return tones.get(kind, Color.MAGENTA)


## The middle of the canvas.
static func _middle(c: PixelCanvas) -> Vector2i:
	return Vector2i(c.w >> 1, c.h >> 1)


## A keyboard: a slab and a lattice of keys.
static func _keyboard(c: PixelCanvas, base: Color) -> void:
	Kit.fill_rect(c, Rect2i(0, 0, c.w, c.h), base.darkened(0.45), 3)
	Kit.fill_rect(c, Rect2i(1, 1, c.w - 2, c.h - 2), base, 3)
	for y in range(1, c.h - 1):
		for x in range(1 + (y % 2), c.w - 1, 2):
			c.px(x, y, base.darkened(0.22), 3)


## Two sheets of paper, the top one lined with text.
static func _papers(c: PixelCanvas, base: Color) -> void:
	Kit.fill_rect(c, Rect2i(0, 0, c.w - 2, c.h - 1), base.darkened(0.12), 1)
	Kit.fill_rect(c, Rect2i(2, 1, c.w - 2, c.h - 1), base, 2)
	for y in range(3, c.h - 2, 2):
		Kit.fill_rect(c, Rect2i(4, y, maxi(1, c.w - 8), 1), base.darkened(0.45), 2)


## A clock: the dark case, a pale face and two hands.
static func _clock(c: PixelCanvas, base: Color) -> void:
	var at := _middle(c)
	var radius := maxi(1, mini(c.w, c.h) >> 1)
	Kit.disc(c, at, radius, base, 4)
	Kit.disc(c, at, maxi(1, radius - 1), Color(0.575, 0.533, 0.456), 4)
	c.line(at, at + Vector2i(0, -(radius - 2)), Color(0.2, 0.2, 0.19), 4)
	c.line(at, at + Vector2i(radius - 2, 0), Color(0.2, 0.2, 0.19), 4)


## A vase as the prop was drawn: the glazed body, leaves round it and flowers over it.
static func _vase(c: PixelCanvas, base: Color) -> void:
	var at := _middle(c)
	var radius := maxi(1, mini(c.w, c.h) >> 1)
	Kit.disc(c, at, radius - 1, base, 10)
	var leaf: Color = ObjectArtDecorConfig.prop_colors["leaf"]
	var flowers: Array = ObjectArtDecorConfig.prop_colors["flowers"]
	for k in 6:
		var turn := TAU * float(k) / 6.0
		var way := Vector2(cos(turn), sin(turn))
		c.px(at.x + roundi(way.x * 3.5), at.y + roundi(way.y * 3.5), leaf, 11)
		var bloom := at + Vector2i((Vector2(cos(turn + 0.5), sin(turn + 0.5)) * 2.0).round())
		Kit.disc(c, bloom, 1, flowers[k % flowers.size()], 12)


## A fruit bowl as the prop was drawn: a ceramic round with its outline and a slightly darker
## inside, four fruits (the mesh stands a fruit on each, `FRUIT_AT`) each with a pale glint.
static func _fruit_bowl(c: PixelCanvas, base: Color) -> void:
	var at := _middle(c)
	var radius := maxi(1, mini(c.w, c.h) >> 1)
	Kit.disc(c, at, radius, base.darkened(0.35), 4)
	Kit.disc(c, at, maxi(1, radius - 1), base, 4)
	Kit.disc(c, at, maxi(1, radius - 2), base.darkened(0.12), 4)
	var fruit: Array = ObjectArtDecorConfig.prop_colors["fruit"]
	for k in FRUIT_AT.size():
		var p := at + FRUIT_AT[k]
		Kit.disc(c, p, 2, fruit[k % fruit.size()], 6)
		c.px(p.x - 1, p.y - 1, (fruit[k % fruit.size()] as Color).lightened(0.35), 6)


## A cutting board: grained wood, a knife along it.
static func _board(c: PixelCanvas, base: Color) -> void:
	Kit.fill_rect(c, Rect2i(0, 0, c.w, c.h), base.darkened(0.4), 2)
	Kit.fill_rect(c, Rect2i(1, 1, c.w - 2, c.h - 2), base, 2)
	for y in range(3, c.h - 2, 3):
		Kit.fill_rect(c, Rect2i(1, y, c.w - 2, 1), base.darkened(0.12), 2)
	var y := c.h >> 1
	Kit.fill_rect(c, Rect2i(3, y, 7, 1), Color(0.86, 0.88, 0.92), 3)
	Kit.fill_rect(c, Rect2i(11, y, 3, 1), Color(0.16, 0.14, 0.11), 3)


## A hammer, a wrench and a screwdriver laid in three rows.
static func _tools(c: PixelCanvas, base: Color) -> void:
	var lane := maxi(1, floori(c.h / 3.0))
	Kit.fill_rect(c, Rect2i(0, 1, c.w - 3, 1), Color(0.82, 0.66, 0.44), 2)
	Kit.fill_rect(c, Rect2i(c.w - 4, 0, 3, 3), base.darkened(0.3), 2)
	Kit.fill_rect(c, Rect2i(1, lane + 2, c.w - 5, 1), base, 2)
	Kit.disc(c, Vector2i(c.w - 3, lane + 2), 2, base, 2)
	Kit.fill_rect(c, Rect2i(0, lane * 2 + 3, 4, 3), Color(0.9, 0.75, 0.2), 2)
	Kit.fill_rect(c, Rect2i(4, lane * 2 + 4, c.w - 5, 1), base.lightened(0.1), 2)


## A vise: the jaws in a dark frame, a bright line along them and the screw handle.
static func _vise(c: PixelCanvas, base: Color) -> void:
	var body := Rect2i(0, 0, c.w, maxi(3, roundi(c.h * 0.7)))
	Kit.fill_rect(c, body, base.darkened(0.4), 8)
	Kit.fill_rect(c, body.grow(-1), base, 8)
	Kit.fill_rect(c, Rect2i(1, body.size.y >> 1, c.w - 2, 1), base.lightened(0.15), 8)
	Kit.fill_rect(c, Rect2i(c.w >> 1, body.size.y, 1, c.h - body.size.y), base.lightened(0.3), 8)
