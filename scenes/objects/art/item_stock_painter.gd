extends RefCounted
## Top-down pixel-art painter of the items the shelves and the stockroom give up (Objects domain,
## private; `item_painter.gd` hands the kinds named here to it; `docs/stacked-items.md` SI13):
##   `pallet`: slats across a deck;   `wrapped_box`: a box under shrink wrap with a label;
## `book_stood`: a book's top (its cover and the page edge); `shoes`: a pair of shoes, each a sole
## with its dark opening at the heel;
## `sandbag`: a filled sack with its seam; `hat`: a brim round a crown; `hob`: a plate with a hot
## ring (the ring glows);
## `paint_tin`: a can with its label ring; `pan`: a dish with a handle; `pot`: a round pot with two
## handles.
## Canonical frame: the front toward +y; the catalogue colour is the item's own.

const Kit = preload("res://scenes/objects/art/paint_kit.gd")
const KINDS := [
	"pallet",
	"wrapped_box",
	"book_stood",
	"shoes",
	"paint_tin",
	"hob",
	"pan",
	"pot",
	"sandbag",
	"hat",
]
## Heights for cast shadows.
const _LOW := 3
const _TALL := 10


## Paint the item `kind` onto `c` in `base` (`opts.well`: the colour of what fills a pot, the noodle
## bar's broth).
static func paint(c: PixelCanvas, base: Color, kind: String, opts: Dictionary = {}) -> void:
	match kind:
		"pallet":
			for y in range(0, c.h, 12):
				Kit.fill_rect(c, Rect2i(0, y, c.w, mini(9, c.h - y)), base, 2)
		"wrapped_box":
			var whole := Rect2i(0, 0, c.w, c.h)
			Kit.fill_rect(c, whole, base, _TALL)
			Kit.over_rect(c, whole.grow(-1), Color(0.9, 0.94, 1.0, 0.14))
			Kit.fill_rect(
				c, Rect2i((c.w >> 1) - 5, (c.h >> 1) - 3, 10, 6), Color(0.92, 0.9, 0.84), _TALL + 1
			)
		"book_stood":
			Kit.fill_rect(c, Rect2i(0, 0, c.w, c.h), base, _TALL)
			Kit.fill_rect(c, Rect2i(maxi(0, c.w - 1), 0, 1, c.h), Color(0.92, 0.9, 0.82), _TALL)
		"shoes":
			var sole := maxi(1, (c.w - 1) >> 1)
			for i in 2:
				var r := Rect2i(i * (sole + 1), 0, sole, c.h)
				Kit.fill_rect(c, r, base, _LOW)
				Kit.fill_rect(
					c,
					Rect2i(r.position + Vector2i(1, 1), Vector2i(maxi(1, sole - 2), 2)),
					base.darkened(0.55),
					_LOW,
				)
		"paint_tin":
			var r := maxi(1, mini(c.w, c.h) >> 1)
			var mid := Vector2i(c.w >> 1, c.h >> 1)
			Kit.disc(c, mid, r, base.darkened(0.4), _TALL)
			Kit.disc(c, mid, maxi(1, r - 1), base, _TALL)
			Kit.disc(c, mid, maxi(1, r - 2), ObjectArtDecorConfig.prop_colors["books"][0], _TALL)
		"hob":
			Kit.fill_rect(c, Rect2i(0, 0, c.w, c.h), base, _LOW)
		"sandbag":
			Kit.fill_rect(c, Rect2i(0, 0, c.w, c.h), base, _TALL)
			Kit.fill_rect(c, Rect2i(1, c.h >> 1, maxi(1, c.w - 2), 1), base.darkened(0.25), _TALL)
		"hat":
			var r := maxi(2, mini(c.w, c.h) >> 1)
			var mid := Vector2i(c.w >> 1, c.h >> 1)
			Kit.disc(c, mid, r, base.darkened(0.2), _LOW + 1)
			Kit.disc(c, mid, maxi(1, roundi(r * 0.64)), base, _LOW + 1)
		"pan":
			var r := maxi(1, c.h >> 1)
			Kit.disc(c, Vector2i(r, r), r, base, _TALL)
			Kit.fill_rect(c, Rect2i(2 * r, r - 1, 5, 2), base.darkened(0.2), _TALL)
		_:
			_pot(c, base, opts.get("well"))


## A pot: its steel disc with a dark middle, or, for one with a `well`, the noodle bar's old pot: a
## dark rim, a ring of its steel and the broth inside.
static func _pot(c: PixelCanvas, base: Color, well: Variant) -> void:
	var r := maxi(1, mini(c.w, c.h) >> 1)
	var mid := Vector2i(c.w >> 1, c.h >> 1)
	if well is Color:
		Kit.disc(c, mid, r, base.darkened(0.4), _TALL + 2)
		Kit.disc(c, mid, maxi(1, r - 2), base, _TALL + 3)
		Kit.disc(c, mid, maxi(1, r - 4), (well as Color).darkened(0.2), _TALL + 3)
		return
	Kit.disc(c, mid, r, base, _TALL)
	Kit.disc(c, mid, maxi(1, r - 2), base.darkened(0.45), _TALL)
