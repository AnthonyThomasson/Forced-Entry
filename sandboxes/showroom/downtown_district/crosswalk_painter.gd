extends RefCounted
## The crossing's paint, a transparent layer over the real asphalt of a four-way junction: a
## vertical road (`opts.v`, a Rect2i) crossing a horizontal one (`opts.h`). Options: `variant` `a`
## clean white zebra bars and stop lines on every arm, `b` the same worn and faded with the tyre
## tracks rubbed through, `c` ladder crossings (two edge lines and the rungs) and a yellow hatched
## box junction in the middle.

const Kit := preload("res://sandboxes/showroom/downtown_district/paint_kit.gd")
const WHITE := Color(0.92, 0.91, 0.86)
const YELLOW := Color(0.96, 0.78, 0.14)
const BAR := 8
const BAR_STEP := 14
const BAR_LEN := 30
const GAP := 12
const LINE := 4


## Paint the crossings of `opts.variant` onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var variant := String(opts.get("variant", "a"))
	var v: Rect2i = opts["v"]
	var h: Rect2i = opts["h"]
	var box := v.intersection(h)
	for arm in _arms(v, h, box):
		_crossing(c, arm, variant == "c")
	if variant == "c":
		_junction(c, box)
	match variant:
		"b":
			Kit.fade(c, 0.6)
			Kit.wear(c, 0.4, 1.0, 28)
			Kit.grime(c, 40, 8, 0.3)
		"c":
			Kit.fade(c, 0.9)
			Kit.wear(c, 0.1, 0.8, 8)
		_:
			Kit.fade(c, 0.92)


## The four arms of the junction: each the zebra zone across its road (`zone`), its stop line
## and whether the bars run along y (`vertical`: the vertical road's arms) or x.
static func _arms(v: Rect2i, h: Rect2i, box: Rect2i) -> Array[Dictionary]:
	var mid := box.get_center()
	var reach := GAP + BAR_LEN
	var north := Rect2i(v.position.x, box.position.y - reach, v.size.x, BAR_LEN)
	var south := Rect2i(v.position.x, box.end.y + GAP, v.size.x, BAR_LEN)
	var west := Rect2i(box.position.x - reach, h.position.y, BAR_LEN, h.size.y)
	var east := Rect2i(box.end.x + GAP, h.position.y, BAR_LEN, h.size.y)
	var stop_n := Rect2i(v.position.x, north.position.y - GAP, mid.x - v.position.x, LINE)
	var stop_s := Rect2i(mid.x, south.end.y + GAP - LINE, v.end.x - mid.x, LINE)
	var stop_w := Rect2i(west.position.x - GAP, mid.y, LINE, h.end.y - mid.y)
	var stop_e := Rect2i(east.end.x + GAP - LINE, h.position.y, LINE, mid.y - h.position.y)
	return [
		{ "zone": north, "vertical": true, "stop": stop_n },
		{ "zone": south, "vertical": true, "stop": stop_s },
		{ "zone": west, "vertical": false, "stop": stop_w },
		{ "zone": east, "vertical": false, "stop": stop_e },
	]


## The zebra bars of one arm (and, for a ladder crossing, the two lines closing them) and its stop
## line.
static func _crossing(c: PixelCanvas, arm: Dictionary, ladder: bool) -> void:
	var zone: Rect2i = arm["zone"]
	var vertical: bool = arm["vertical"]
	var across := zone.size.x if vertical else zone.size.y
	var half_bar := int(BAR / 2.0)
	for k in range(int(BAR_STEP / 2.0), across - int(BAR_STEP / 2.0), BAR_STEP):
		var r := Rect2i(zone.position.x, zone.position.y, zone.size.x, zone.size.y)
		if vertical:
			r = Rect2i(zone.position.x + k - half_bar, zone.position.y, BAR, zone.size.y)
		else:
			r = Rect2i(zone.position.x, zone.position.y + k - half_bar, zone.size.x, BAR)
		Kit.fill_rect(c, r, WHITE)
	if ladder:
		for r in _ladder_lines(zone, vertical):
			Kit.fill_rect(c, r, WHITE)
	Kit.fill_rect(c, arm["stop"], WHITE)


## The two lines that close a ladder crossing, across the road at each end of its bars.
static func _ladder_lines(zone: Rect2i, vertical: bool) -> Array[Rect2i]:
	if vertical:
		return [
			Rect2i(zone.position.x, zone.position.y - LINE, zone.size.x, LINE),
			Rect2i(zone.position.x, zone.end.y, zone.size.x, LINE),
		]
	return [
		Rect2i(zone.position.x - LINE, zone.position.y, LINE, zone.size.y),
		Rect2i(zone.end.x, zone.position.y, LINE, zone.size.y),
	]


## The box junction: a yellow border and two sets of diagonal hatch lines inside it.
static func _junction(c: PixelCanvas, box: Rect2i) -> void:
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var inner := box.grow(-3)
			var edge := not inner.has_point(Vector2i(x, y))
			if edge or (x + y) % 16 < 3 or posmod(x - y, 16) < 3:
				c.px(x, y, YELLOW)
