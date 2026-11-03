extends RefCounted
## Pixel-art CROSSING painter (Objects domain, private): the paint of one arm of a junction, a
## transparent layer over the asphalt, worn and faded. Canonical frame: the junction at the bottom
## edge (+y), the road across x. From the junction up: a clear gap, the zebra bars (running along y,
## spaced across x), another gap and the stop line across the approaching lane (the left half, x
## under the middle: the right-hand lane of traffic heading for the junction). The bars have two
## tyre tracks rubbed through them. Knobs: ObjectArtCrossingConfig.crossing_*, each overridable by
## `opts` (keyed without the prefix); the painter takes its colours as given (`ObjectArt.AS_GIVEN`).

const Kit = preload("res://scenes/objects/art/paint_kit.gd")
## A tyre track rubs this far (px) either side of its centre: a wheel's width, 20 px.
const TRACK_HALF := 10
## What a rubbed pixel keeps of its alpha.
const RUBBED_ALPHA := 0.15


## Paint the crossing arm onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var paint_color: Color = opts.get("paint_color", ObjectArtCrossingConfig.crossing_color)
	var line: int = opts.get("line_px", ObjectArtCrossingConfig.crossing_line_px)
	var gap: int = opts.get("gap_px", ObjectArtCrossingConfig.crossing_gap_px)
	var bars := Rect2i(0, line + gap, c.w, maxi(1, c.h - line - gap * 2))
	_bars(c, bars, paint_color, opts)
	Kit.fill_rect(c, Rect2i(0, 0, int(c.w / 2.0), line), paint_color)
	_tracks(c, bars, opts.get("track_rub", ObjectArtCrossingConfig.crossing_track_rub))
	Kit.age(c, opts, {
		"opacity": ObjectArtCrossingConfig.crossing_opacity,
		"wear_chance": ObjectArtCrossingConfig.crossing_wear_chance,
		"wear_depth": ObjectArtCrossingConfig.crossing_wear_depth,
		"wear_scratches": ObjectArtCrossingConfig.crossing_wear_scratches,
	})


## The zebra bars across `zone` (the road's width), one every `step_px`.
static func _bars(c: PixelCanvas, zone: Rect2i, col: Color, opts: Dictionary) -> void:
	var bar: int = opts.get("bar_px", ObjectArtCrossingConfig.crossing_bar_px)
	var step: int = opts.get("step_px", ObjectArtCrossingConfig.crossing_step_px)
	for x in range(int(step / 2.0), c.w - int(step / 2.0), step):
		Kit.fill_rect(
			c,
			Rect2i(zone.position.x + x - int(bar / 2.0), zone.position.y, bar, zone.size.y),
			col,
		)


## Rub `share` of the bars' pixels clean away in the two tyre tracks (a quarter and three quarters
## across), each a wheel's width.
static func _tracks(c: PixelCanvas, zone: Rect2i, share: float) -> void:
	for centre in [c.w * 0.25, c.w * 0.75]:
		for y in range(zone.position.y, zone.end.y):
			for x in range(int(centre) - TRACK_HALF, int(centre) + TRACK_HALF):
				if c.rng.randf() < share:
					var col := c.at(x, y)
					col.a *= RUBBED_ALPHA
					c.px(x, y, col)
