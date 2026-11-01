extends RefCounted
## The shadow a tall tower throws across the street, a transparent layer laid over the real
## sidewalk and asphalt. It is the tower's footprint (`opts.foot`, a Rect2i on the canvas) dragged
## away from the light (`-canvas.light`: the canvas is in the world's frame, so the direction is
## `PixelArt.away_from_light`'s) for `opts.length` px, the footprint itself left clear. Options:
## `variant` `a` a short hard shadow, `b` a long hard one, `c` a long one that falls off softly.

const Kit := preload("res://sandboxes/showroom/downtown_district/paint_kit.gd")
const SHADE := Color(0.02, 0.02, 0.08)
const LENGTHS := { "a": 44, "b": 170, "c": 170 }
## The darkest the shadow gets, hard and soft.
const HARD := 0.42
const SOFT := 0.5


## Paint the shadow of `opts.foot` for `opts.variant` onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var foot: Rect2i = opts["foot"]
	var variant := String(opts.get("variant", "a"))
	var length: int = LENGTHS[variant]
	var away := (-c.light).normalized()
	# Far to near, each stamp overwriting the last, so a pixel keeps the alpha of the nearest
	# stamp that covers it: the footprint's own distance to it along the light.
	for k in range(length, -1, -1):
		var at := Vector2i((away * float(k)).round())
		var alpha := HARD
		if variant == "c":
			alpha = SOFT * pow(1.0 - float(k) / float(length), 1.4)
		Kit.fill_rect(c, Rect2i(foot.position + at, foot.size), Color(SHADE, alpha))
	Kit.fill_rect(c, foot, PixelCanvas.CLEAR)
