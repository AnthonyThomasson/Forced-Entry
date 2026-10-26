extends RefCounted
## Vehicles domain: the van, top-down pixel art (rendered through Art, `PixelArt.render_turned`), in
## the same two parts as the car (`opts.part`), but boxy:
##  - `chassis` (under the occupants): a long square-cornered body, a short snub nose with a wide
##    grille, black bumpers (a step plate at the back), the cab (floor, dashboard and wheel, two
##    seats either side of the engine cover), a bulkhead behind it, and the bare cargo bay (plywood
##    floor, tie-down rails, benches) seen when the slide or rear doors open; the slide door's rail
##    runs along the right flank.
##  - `roof` (over them): the upright windscreen in tinted glass, then one tall, flat roof over cab
##    and cargo alike, stiffened by ribs across it with a vent on top: no side or back windows
##    behind the cab. And the lamps.
## Painted in the vehicle's frame through vehicle_art.gd; geometry from the van's
## `VehicleConfig.kinds` and `looks` rows.

const Art = preload("res://scenes/vehicle/art/vehicle_art.gd")
## Heights of the parts (the canvas height layer), floor up.
const _FLOOR := 1
const _BODY := 5
const _PILLAR := 10
const _ROOF := 12
## px between the roof's ribs.
const _RIB_GAP := 17.0


## Paint the van's `opts.part` (`chassis` / `roof`) onto `c` in `base` paint, front toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var v := VehiclePaint.new(c, base, opts.get("kind", &"van"))
	Art.paint_parts(v, opts.get("part", "chassis"), _chassis, _roof)


## The body, the nose and bumpers, the cab and the cargo bay.
static func _chassis(v: VehiclePaint) -> void:
	var c := v.canvas
	var t := PixelCanvas.tones(v.base)
	var half: Vector2 = (v.row["size"] as Vector2) * 0.5
	var body := PixelShape.rounded(
		Art.box(v, -half.x, half.x, -half.y, half.y),
		roundi(float(v.row["corner"]) * v.k),
	)
	c.fill(body, v.base, _BODY)
	c.bevel(body, 1, 2, t["highlight"], t["dark"])
	_bumpers(v)
	_nose(v)
	_cab(v)
	_cargo_bay(v)
	Art.sills(v)
	Art.seats(v, (v.row["seats"][&"driver"] as Vector2).x - 20.0)
	_slide_rail(v)


## Bumpers: a deep one at the nose, one at the tail with a step plate in its middle.
static func _bumpers(v: VehiclePaint) -> void:
	var c := v.canvas
	var k := v.k
	var half: Vector2 = (v.row["size"] as Vector2) * 0.5
	var trim := VehicleArtConfig.trim_color
	var bumper: float = v.look["bumper"]
	var nose := PixelShape.rounded(
		Art.box(v, half.x - bumper, half.x, -half.y + 3.0, half.y - 3.0),
		roundi(3 * k),
	)
	c.fill(nose, trim, _BODY - 1)
	c.bevel(nose, 1, 1, trim.lightened(0.18), trim.darkened(0.3))
	var tail := PixelShape.rounded(
		Art.box(v, -half.x, -half.x + bumper - 2.0, -half.y + 3.0, half.y - 3.0),
		roundi(2 * k),
	)
	c.fill(tail, trim, _BODY - 1)
	var step := PixelShape.rounded(
		Art.box(v, -half.x - 0.5, -half.x + bumper, -20.0, 20.0),
		roundi(1 * k),
	)
	c.fill(step, trim.lightened(0.22), _BODY)
	for i in 4:
		var y := -15.0 + i * 10.0
		c.line(
			Art.at(v, Vector2(-half.x + 1.0, y)),
			Art.at(v, Vector2(-half.x + bumper - 1.0, y)),
			trim,
		)


## The snub nose: a wide grille of slats between the headlights, the bonnet's shut line, a sheen.
static func _nose(v: VehiclePaint) -> void:
	var c := v.canvas
	var t := PixelCanvas.tones(v.base)
	var half: Vector2 = (v.row["size"] as Vector2) * 0.5
	var trim := VehicleArtConfig.trim_color
	var bumper: float = v.look["bumper"]
	var bonnet: float = v.look["bonnet"]
	var belt: float = v.look["belt"]
	var head: Vector2 = v.look["head"]
	var grille := PixelShape.rounded(
		Art.box(v, half.x - bumper - 9.0, half.x - bumper, -head.x + 4.0, head.x - 4.0),
		roundi(1 * v.k),
	)
	c.fill(grille, trim, _BODY)
	for i in 4:
		var x := half.x - bumper - 1.5 - i * 2.0
		c.line(
			Art.at(v, Vector2(x, -head.x + 6.0)),
			Art.at(v, Vector2(x, head.x - 6.0)),
			trim.lightened(0.18),
		)
	c.line(
		Art.at(v, Vector2(bonnet + 1.0, -belt + 2.0)),
		Art.at(v, Vector2(bonnet + 1.0, belt - 2.0)),
		t["shadow"],
	)
	c.glare(
		PixelShape.rounded(
			Art.box(v, bonnet + 2.0, half.x - bumper - 10.0, -half.y + 6.0, half.y - 6.0),
			roundi(3 * v.k),
		),
		v.base.lightened(0.3), 1,
	)


## The cab: floor, dashboard and wheel, the engine cover between the seats (the seats are painted
## after the cargo bay); the bulkhead behind them.
static func _cab(v: VehiclePaint) -> void:
	var c := v.canvas
	var k := v.k
	var trim := VehicleArtConfig.trim_color
	var belt: float = v.look["belt"]
	var driver: Vector2 = v.row["seats"][&"driver"]
	var bulkhead: float = (v.look["pillars"][0] as Vector2).y
	var cab := PixelShape.rounded(
		Art.box(v, bulkhead, v.look["bonnet"], -belt, belt), roundi(3 * k)
	)
	c.fill(cab, VehicleArtConfig.interior_color, _FLOOR)
	c.surface(cab, "fabric", VehicleArtConfig.interior_color)
	Art.dashboard(v, belt - 1.0)
	var cover := PixelShape.rounded(
		Art.box(v, driver.x - 14.0, (v.look["dash"] as Vector2).x, -9.0, 9.0),
		roundi(3 * k),
	)
	c.fill(cover, trim.lightened(0.1), 3)
	c.bevel(cover, 1, 1, trim.lightened(0.28), trim.darkened(0.3))
	var wall := PixelShape.rounded(Art.box(v, bulkhead - 4.0, bulkhead, -belt, belt), 0)
	c.fill(wall, v.base.darkened(0.25), 6)


## The cargo bay: a plywood floor of sheets laid across, with tie-down rails along it.
static func _cargo_bay(v: VehiclePaint) -> void:
	var c := v.canvas
	var half: Vector2 = (v.row["size"] as Vector2) * 0.5
	var bumper: float = v.look["bumper"]
	var belt: float = v.look["belt"]
	var bulkhead: float = (v.look["pillars"][0] as Vector2).y
	var wood := VehicleArtConfig.cargo_floor_color
	var bay := PixelShape.rounded(
		Art.box(v, -half.x + bumper - 2.0, bulkhead - 4.0, -belt, belt),
		roundi(2 * v.k),
	)
	c.fill(bay, wood, _FLOOR)
	c.speckle(bay.bounds, wood, 0.06, 0.06)
	var sheet := -half.x + bumper + 30.0
	while sheet < bulkhead - 8.0:
		c.line(
			Art.at(v, Vector2(sheet, -belt + 1.0)),
			Art.at(v, Vector2(sheet, belt - 1.0)),
			wood.darkened(0.18),
		)
		sheet += 30.0
	for y in [-belt + 4.0, -14.0, 14.0, belt - 4.0]:
		c.line(
			Art.at(v, Vector2(-half.x + bumper, y)),
			Art.at(v, Vector2(bulkhead - 6.0, y)),
			wood.darkened(0.35),
		)


## The slide door's rail along the right flank, behind its opening.
static func _slide_rail(v: VehiclePaint) -> void:
	var t := PixelCanvas.tones(v.base)
	var half: Vector2 = (v.row["size"] as Vector2) * 0.5
	for def: Dictionary in v.row["doors"]:
		if def["kind"] == &"slide":
			var rail_y := signf((def["hinge"] as Vector2).y) * (half.y - 1.5)
			var front: float = (def["hinge"] as Vector2).x - float(def["length"])
			v.canvas.line(
				Art.at(v, Vector2(front - float(def["length"]) + 2.0, rail_y)),
				Art.at(v, Vector2(front, rail_y)),
				t["outline"],
			)


## The upright windscreen, the one tall roof with its ribs and vent, and the lamps.
static func _roof(v: VehiclePaint) -> void:
	var c := v.canvas
	var t := PixelCanvas.tones(v.base)
	var look := v.look
	var roof: Vector2 = look["roof"]
	var belt: float = look["belt"]
	var bonnet: float = look["bonnet"]
	var screen_half: float = look["screen_half"]
	var frame := PixelShape.rounded(
		Art.box(v, float(look["boot"]) - 3.0, bonnet, -belt, belt), roundi(3 * v.k)
	)
	c.fill(frame, v.base, _PILLAR)
	c.bevel(frame, 1, 1, t["light"], t["shadow"])
	Art.clear_door_glass(v)
	var in_screen := func(p: Vector2) -> bool:
		return absf(p.y) <= Art.screen_edge(look, p.x) - 1.0 and p.x <= bonnet - 1.0
	var windscreen := Art.region(v, Art.box(v, roof.x, bonnet, -screen_half, screen_half),
			"van_screen/%s" % v.kind, in_screen)
	c.fill(windscreen, VehicleArtConfig.glass_color, _PILLAR - 1)
	c.glare(windscreen, Color(VehicleArtConfig.glass_color.lightened(0.55), 0.6), 3)
	c.outline(windscreen, VehicleArtConfig.trim_color)
	_roof_panel(v)
	Art.lamps(v, 2.0, 1, _BODY + 1, _ROOF)


## The roof, square-edged and flat, a little paler than the body, ribbed across, with its vent.
static func _roof_panel(v: VehiclePaint) -> void:
	var c := v.canvas
	var t := PixelCanvas.tones(v.base)
	var roof: Vector2 = v.look["roof"]
	var roof_half: float = v.look["roof_half"]
	var boot: float = v.look["boot"]
	var panel := PixelShape.rounded(
		Art.box(v, boot - 2.0, roof.x, -roof_half, roof_half),
		roundi(4 * v.k),
	)
	c.fill(panel, t["light"], _ROOF)
	c.bevel(panel, 1, 2, t["highlight"], t["dark"])
	var x := roof.x - 10.0
	while x > boot + 6.0:
		c.line(
			Art.at(v, Vector2(x, -roof_half + 4.0)),
			Art.at(v, Vector2(x, roof_half - 4.0)),
			t["highlight"],
		)
		c.line(
			Art.at(v, Vector2(x - 1.0, -roof_half + 4.0)),
			Art.at(v, Vector2(x - 1.0, roof_half - 4.0)),
			t["dark"],
		)
		x -= _RIB_GAP
	_vent(v, t)
	c.outline(panel, t["shadow"])


## The vent on the roof, its slats in `t`'s shadow.
static func _vent(v: VehiclePaint, t: Dictionary) -> void:
	var c := v.canvas
	var vent := PixelShape.rounded(Art.box(v, -78.0, -60.0, -9.0, 9.0), roundi(2 * v.k))
	c.fill(vent, t["base"].darkened(0.08), _ROOF + 2)
	c.bevel(vent, 1, 1, t["highlight"], t["shadow"])
	c.outline(vent, t["outline"])
	for i in 3:
		var vx := -74.0 + i * 5.0
		c.line(Art.at(v, Vector2(vx, -6.0)), Art.at(v, Vector2(vx, 6.0)), t["shadow"])
