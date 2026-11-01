extends RefCounted
## Pixel-art SHADOW painter (Objects domain, private): the shadow a tall tower throws across the
## street, a transparent layer laid over the real sidewalk and asphalt. It is the tower's footprint
## (`opts.foot`, a Rect2i on the canvas) dragged away from the light (`-canvas.light`: the canvas is
## in the world's frame, so the direction is `PixelArt.away_from_light`'s) for `opts.length` px, one
## hard-edged alpha throughout, the footprint itself left clear. Knobs:
## ObjectArtPodiumConfig.shadow_*, each overridable by `opts` (keyed without the prefix: `color`,
## `alpha`); the painter takes its colour as given (`ObjectArt.AS_GIVEN`).

const Kit = preload("res://scenes/objects/art/paint_kit.gd")


## Paint the shadow of `opts.foot` dragged `opts.length` px onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var foot: Rect2i = opts["foot"]
	var shade := Color(
		opts.get("color", ObjectArtPodiumConfig.shadow_color),
		opts.get("alpha", ObjectArtPodiumConfig.shadow_alpha),
	)
	var drag := (-c.light).normalized() * float(opts["length"])
	for y in c.h:
		var span := _row(Rect2(foot), drag, y)
		if span.y > span.x:
			Kit.fill_rect(c, Rect2i(int(span.x), y, int(span.y - span.x), 1), shade)
	Kit.fill_rect(c, foot, PixelCanvas.CLEAR)


## The columns (from, to) row `y` of the canvas shares with `foot` swept along `drag`, as whole
## pixels; (0, 0) when the sweep never reaches the row.
static func _row(foot: Rect2, drag: Vector2, y: int) -> Vector2:
	var reach := Vector2(0.0, 1.0)
	if absf(drag.y) > 0.0001:
		var a := (float(y) - foot.end.y) / drag.y
		var b := (float(y + 1) - foot.position.y) / drag.y
		reach = Vector2(maxf(0.0, minf(a, b)), minf(1.0, maxf(a, b)))
	elif float(y) >= foot.end.y or float(y + 1) <= foot.position.y:
		return Vector2.ZERO
	if reach.x >= reach.y:
		return Vector2.ZERO
	var shifts := Vector2(drag.x * reach.x, drag.x * reach.y)
	return Vector2(
		floorf(foot.position.x + minf(shifts.x, shifts.y)),
		ceilf(foot.end.x + maxf(shifts.x, shifts.y)),
	)
