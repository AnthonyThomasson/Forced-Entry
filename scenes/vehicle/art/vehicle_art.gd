extends RefCounted
## Vehicles domain: what the vehicle painters share. A vehicle is painted in the Art domain's
## canonical frame (front toward +y, width across), and drawn turned a quarter back onto the
## vehicle's own frame (x forward, y toward its right side), so a painter thinks in the vehicle's
## frame and these helpers put it on the canvas: `at` (a point), `box` (an axis-aligned box) and
## `region` (any shape, by a test on vehicle-frame points). A door is painted in its own canonical
## frame (`door_frame`): along its length toward the hinge, across its thickness. The seats,
## dashboard, steering wheel and door sills every cabin has are here too, so the car and van
## painters only differ in their bodies.

## Shapes built by `region` (or `cached`), by their key and canvas size.
static var _regions: Dictionary = {}


## The canvas px per vehicle px (1 unless ArtCanvasConfig.pixel_size is not), for a body `length`
## long painted on `c`.
static func scale(c: PixelCanvas, length: float) -> float:
	return c.h / maxf(length, 1.0)


## Vehicle-frame point `p` on the canvas of `v` (its `k` canvas px per vehicle px).
static func at(v: VehiclePaint, p: Vector2) -> Vector2i:
	var c := v.canvas
	return Vector2i(roundi(c.w * 0.5 - p.y * v.k), roundi(c.h * 0.5 + p.x * v.k))


## The canvas rect on the canvas of `v` of the vehicle-frame box from x `x0`..`x1` and y
## `y0`..`y1`.
static func box(v: VehiclePaint, x0: float, x1: float, y0: float, y1: float) -> Rect2i:
	var c := v.canvas
	var k := v.k
	var left := roundi(c.w * 0.5 - maxf(y0, y1) * k)
	var right := roundi(c.w * 0.5 - minf(y0, y1) * k)
	var top := roundi(c.h * 0.5 + minf(x0, x1) * k)
	var bottom := roundi(c.h * 0.5 + maxf(x0, x1) * k)
	return Rect2i(left, top, maxi(right - left, 1), maxi(bottom - top, 1))


## The shape of every pixel in `bounds` (a `box` on the canvas of `v`) whose centre, in the
## vehicle's frame, passes `test`, which must be convex along both canvas axes (each row and column
## one run: a windscreen, a side window). It is kept as a `PixelCanvas.ConvexShape`, so filling,
## bevelling and outlining it cost its edge, not its area; and it depends only on the geometry,
## never on the light, so it is built once per `key` (and canvas size) and reused for every lighting
## step (testing every pixel is most of a paint's cost).
static func region(v: VehiclePaint, bounds: Rect2i, key: String,
		test: Callable) -> PixelCanvas.Shape:
	var c := v.canvas
	var k := v.k
	var cache_key := "%s|%d|%d|%.4f" % [key, c.w, c.h, k]
	if not _regions.has(cache_key):
		var half := Vector2(c.w, c.h) * 0.5
		_regions[cache_key] = convex(bounds, func(x: int, y: int) -> bool:
			return test.call(Vector2((y + 0.5 - half.y) / k, (half.x - x - 0.5) / k)))
	return _regions[cache_key]


## The pixels of `bounds` passing `test` (on canvas pixels), as a ConvexShape: each row's and
## column's first and last inside pixel. A row or column with none is empty.
static func convex(bounds: Rect2i, test: Callable) -> PixelCanvas.Shape:
	var w := bounds.size.x
	var h := bounds.size.y
	var x0 := PackedInt32Array()
	var x1 := PackedInt32Array()
	var y0 := PackedInt32Array()
	var y1 := PackedInt32Array()
	x0.resize(h)
	x1.resize(h)
	y0.resize(w)
	y1.resize(w)
	y0.fill(1 << 30)
	y1.fill(-(1 << 30))
	for ly in h:
		var first := -1
		var last := -1
		for lx in w:
			if test.call(bounds.position.x + lx, bounds.position.y + ly):
				if first < 0:
					first = lx
				last = lx
				y0[lx] = mini(y0[lx], bounds.position.y + ly)
				y1[lx] = maxi(y1[lx], bounds.position.y + ly + 1)
		x0[ly] = bounds.position.x + (first if first >= 0 else 0)
		x1[ly] = bounds.position.x + (last + 1 if first >= 0 else 0)
	for lx in w:
		if y1[lx] < y0[lx]:
			y0[lx] = bounds.position.y
			y1[lx] = bounds.position.y
	return PixelCanvas.ConvexShape.new(bounds, x0, x1, y0, y1)


## The shape `build` makes, built once per `key` (for shapes tested pixel by pixel that never depend
## on the light).
static func cached(key: String, build: Callable) -> PixelCanvas.Shape:
	if not _regions.has(key):
		_regions[key] = build.call()
	return _regions[key]


## The same box on the canvas of `v` on both sides of the centre line (`y0`..`y1` are distances out
## from it): [left, right] rects.
static func both(v: VehiclePaint, x0: float, x1: float, y0: float, y1: float) -> Array[Rect2i]:
	return [box(v, x0, x1, -y1, -y0), box(v, x0, x1, y0, y1)]


## How a door (its `VehicleConfig.kinds` row entry) is painted and drawn: `turn`, the rotation that
## takes the canonical frame onto the shut door (front, +y, toward the hinge along it; across it,
## +x); `outer`, which way across is out of the body (+1: the canonical +x side is the outside);
## `length`.
static func door_frame(def: Dictionary) -> Dictionary:
	var hinge: Vector2 = def["hinge"]
	var handle: Vector2 = def["handle"]
	var length: float = def.get("length", hinge.distance_to(handle))
	var toward: Vector2 = (hinge - handle).normalized()
	var turn := atan2(-toward.x, toward.y)
	var outward := Vector2.LEFT if def["kind"] == &"rear" else Vector2(0.0, signf(handle.y))
	var across := Vector2(cos(turn), sin(turn))
	return { "turn": turn, "outer": 1.0 if across.dot(outward) > 0.0 else -1.0, "length": length }


## Each glazed door's glass span: [{ side (-1 left, +1 right), from, to }] (x, the `looks` row's
## `glass` by its door); only door `only` when given.
static func door_glass(row: Dictionary, look: Dictionary, only: StringName = &"") -> Array:
	var out := []
	var glazed: Dictionary = look["glass"]
	for def: Dictionary in row["doors"]:
		if glazed.has(def["id"]) and (only == &"" or def["id"] == only):
			var span: Vector2 = glazed[def["id"]]
			out.append({
				"side": signf((def["handle"] as Vector2).y),
				"from": span.x,
				"to": span.y,
			})
	return out


## How far out (|y|) the windscreen reaches at x: the roof's half width where it meets the roof,
## `screen_half` at its base.
static func screen_edge(look: Dictionary, x: float) -> float:
	var roof: Vector2 = look["roof"]
	var t := clampf((x - roof.x) / maxf(float(look["bonnet"]) - roof.x, 1.0), 0.0, 1.0)
	return lerpf(float(look["roof_half"]) + 1.0, float(look["screen_half"]), t)


## Whether vehicle-frame point `p` lies in a door's side glass (`gaps` from `door_glass`): within
## its span, out from the roof (or, beside the windscreen, from its pillar) to the belt line.
static func in_door_glass(gaps: Array, look: Dictionary, p: Vector2) -> bool:
	var out := absf(p.y)
	if out > float(look["belt"]) - 0.5:
		return false
	var inner: float = look["roof_half"]
	if p.x > (look["roof"] as Vector2).x:
		inner = screen_edge(look, p.x) + float(look["a_pillar"])
	if out < inner:
		return false
	for g: Dictionary in gaps:
		if signf(p.y) == g["side"] and p.x >= g["from"] and p.x <= g["to"]:
			return true
	return false


## Each glazed door's side-glass shape on the body canvas of `v` (its own glass is drawn by
## door_painter.gd where it is, so the roof leaves a hole there).
static func clear_door_glass(v: VehiclePaint) -> void:
	var look := v.look
	var roof_half: float = look["roof_half"]
	var belt: float = look["belt"]
	for gap: Dictionary in door_glass(v.row, look):
		var one := [gap]
		var y0: float = roof_half if gap["side"] > 0.0 else -belt
		var hole_key := "glass_hole/%s/%s/%s" % [v.kind, gap["side"], gap["from"]]
		var in_gap := func(p: Vector2) -> bool: return in_door_glass(one, look, p)
		var bounds := box(v, gap["from"], gap["to"], y0, y0 + belt - roof_half)
		v.canvas.clear(region(v, bounds, hole_key, in_gap))


## Paint a body painter's `part` of the vehicle `v` (its canvas, paint, kind and rows): its `roof`
## through `roof(v)`, else its `chassis` through `chassis(v)`.
static func paint_parts(v: VehiclePaint, part: String, chassis: Callable, roof: Callable) -> void:
	if part == "roof":
		roof.call(v)
	else:
		chassis.call(v)
	# No cast shadows: a body is repainted for every lighting step it turns through, and on a canvas
	# this size they cost more than the rest of the painting together. Its raised parts are shaded
	# by their bevels instead.


## The lamps on the roof part of the body `v`: the headlights at the nose's corners over the `looks`
## row's `head` |y| span, `lamp` + `head_extra` long and rounded `head_round` px, at height
## `head_height`; the unlit tail lights (`tail_lamps`) at `tail_height`.
static func lamps(v: VehiclePaint, head_extra: float, head_round: int, head_height: int,
		tail_height: int) -> void:
	var c := v.canvas
	var k := v.k
	var row := v.row
	var look := v.look
	var half: Vector2 = (row["size"] as Vector2) * 0.5
	var length: float = look["lamp"]
	var head: Vector2 = look["head"]
	for r in both(v, half.x - length - head_extra, half.x - 1.0, head.x, head.y):
		var lamp := PixelCanvas.rounded(r, roundi(head_round * k))
		c.fill(lamp, VehicleConfig.headlight_color, head_height)
		c.bevel(lamp, 1, 1, Color.WHITE, VehicleConfig.headlight_color.darkened(0.3))
		c.outline(lamp, VehicleConfig.trim_color)
	for rect: Rect2 in tail_lamps(row, look):
		var lamp := PixelCanvas.rounded(
			box(v, rect.position.x, rect.end.x, rect.position.y, rect.end.y),
			roundi(1 * k),
		)
		c.fill(lamp, VehicleConfig.tail_off_color, tail_height)
		c.outline(lamp, VehicleConfig.trim_color)


## The tail lights (vehicle-frame rects, left then right): at the tail's corners, the `looks` row's
## `tail` |y| span, `lamp` long.
static func tail_lamps(row: Dictionary, look: Dictionary) -> Array[Rect2]:
	var half: Vector2 = (row["size"] as Vector2) * 0.5
	var tail: Vector2 = look["tail"]
	var length: float = look["lamp"]
	return [
		Rect2(-half.x + 0.5, -tail.y, length - 0.5, tail.y - tail.x),
		Rect2(-half.x + 0.5, tail.x, length - 0.5, tail.y - tail.x),
	]


## The cabin seats of `v` (its row's vehicle-frame `seats`: id -> point), painted facing forward: a
## bucket for a front seat, a cushion with a backrest for the others, each with a headrest. `rear_x`
## below which a seat is a bench place.
static func seats(v: VehiclePaint, rear_x: float) -> void:
	var seats_at: Dictionary = v.row["seats"]
	for id in seats_at:
		var p: Vector2 = seats_at[id]
		_seat(v, p, p.x < rear_x)


## One seat of `v` at vehicle-frame point `p`, facing forward: a bucket, or a `bench` place's
## cushion with a backrest, with a headrest.
static func _seat(v: VehiclePaint, p: Vector2, bench: bool) -> void:
	var c := v.canvas
	var k := v.k
	var cloth := VehicleConfig.seat_color
	var t := PixelCanvas.tones(cloth)
	var half := 13.0 if bench else 11.0
	var cushion := PixelCanvas.rounded(
		box(v, p.x - 9.0, p.x + 9.0, p.y - half, p.y + half),
		roundi(3 * k),
	)
	c.fill(cushion, cloth, 2)
	c.surface(cushion, "fabric", cloth)
	c.bevel(cushion, 1, 1, t["light"], t["dark"])
	var back := PixelCanvas.rounded(
		box(v, p.x - 16.0, p.x - 9.0, p.y - half, p.y + half),
		roundi(2 * k),
	)
	c.fill(back, t["light"], 4)
	c.bevel(back, 1, 1, t["highlight"], t["dark"])
	var rest := PixelCanvas.rounded(
		box(v, p.x - 15.0, p.x - 11.0, p.y - 5.0, p.y + 5.0),
		roundi(1 * k),
	)
	c.fill(rest, t["dark"], 6)
	c.outline(rest, t["shadow"])
	if not bench:
		# the bucket's seam
		c.line(at(v, Vector2(p.x - 7.0, p.y)), at(v, Vector2(p.x + 7.0, p.y)), t["dark"])


## The dashboard of `v` across the cabin from x `dash.x` to `dash.y` of its `looks` row (|y| up to
## `half`) and a steering wheel ahead of the driver's seat at the row's x `wheel`: seen from above,
## a narrow ring tipped toward the driver.
static func dashboard(v: VehiclePaint, half: float) -> void:
	var c := v.canvas
	var dash: Vector2 = v.look["dash"]
	var wheel_x: float = v.look["wheel"]
	var driver: Vector2 = v.row["seats"][&"driver"]
	var trim := VehicleConfig.trim_color
	var t := PixelCanvas.tones(trim.lightened(0.12))
	var board := PixelCanvas.rounded(box(v, dash.x, dash.y, -half, half), roundi(3 * v.k))
	c.fill(board, t["base"], 5)
	c.bevel(board, 1, 2, t["highlight"], t["shadow"])
	var hood := PixelCanvas.rounded(
		box(v, dash.x - 2.0, dash.x + 6.0, driver.y - 9.0, driver.y + 9.0),
		roundi(2 * v.k),
	)
	c.fill(hood, trim, 6)
	var rim := PixelCanvas.ellipse(
		box(v, wheel_x - 3.0, wheel_x + 3.0, driver.y - 9.0, driver.y + 9.0),
	)
	c.fill(rim, trim, 7)
	var hub := PixelCanvas.ellipse(
		box(v, wheel_x - 1.5, wheel_x + 1.5, driver.y - 6.0, driver.y + 6.0),
	)
	c.fill(hub, t["base"], 6)
	c.px(at(v, Vector2(wheel_x, driver.y)).x, at(v, Vector2(wheel_x, driver.y)).y, trim, 7)


## Under each door of `v` the sill it stands on and the gap it closes, from the body's edge in to
## its `looks` row's `belt` (shown once it opens).
static func sills(v: VehiclePaint) -> void:
	var c := v.canvas
	var doors: Array = v.row["doors"]
	var belt: float = v.look["belt"]
	var sill := VehicleConfig.interior_color.darkened(0.25)
	for def: Dictionary in doors:
		var hinge: Vector2 = def["hinge"]
		var length: float = door_frame(def)["length"]
		var r: Rect2i
		if def["kind"] == &"rear":
			r = box(
				v,
				hinge.x,
				hinge.x + 4.0,
				minf(hinge.y, def["handle"].y),
				maxf(hinge.y, def["handle"].y),
			)
		else:
			var back: float = (hinge.x - length
					if def["kind"] == &"slide"
					else (def["handle"] as Vector2).x)
			r = box(v, back, hinge.x, signf(hinge.y) * belt, hinge.y)
		c.fill(PixelCanvas.rounded(r, 0), sill, 1)
