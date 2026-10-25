extends RefCounted
## Vehicles domain: the car, top-down pixel art (rendered through Art, `PixelArt.render_turned`), in
## two parts that sandwich its occupants (`opts.part`):
##  - `chassis` (under them): the low, rounded body in its paint, the black bumpers and grille, the
##    bonnet with its creases and the boot lid, and inside the cabin the floor, the seats, the
##    dashboard and steering wheel and the sills the doors close over (the doors themselves are
##    door_painter.gd's, drawn where they swing).
##  - `roof` (over them): the raked windscreen and the rear window in tinted, see-through glass, the
##    roof panel on its pillars, and the lamps. The side glass is each door's own (door_painter.gd),
##    so it can go with the door.
## Painted in the vehicle's frame through vehicle_art.gd; geometry from the car's
## `VehicleConfig.kinds` and `looks` rows.

const Art = preload("res://scenes/vehicle/art/vehicle_art.gd")
## Heights of the parts (the canvas height layer), floor up.
const _FLOOR := 1
const _BODY := 5
const _PILLAR := 9
const _ROOF := 10


## Paint the car's `opts.part` (`chassis` / `roof`) onto `c` in `base` paint, front toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var v := VehiclePaint.new(c, base, opts.get("kind", &"car"))
	Art.paint_parts(v, opts.get("part", "chassis"), _chassis, _roof)


## The body, the bumpers, bonnet and boot, and the open cabin with its seats.
static func _chassis(v: VehiclePaint) -> void:
	_body(v)
	_grille(v)
	_bonnet(v)
	_boot(v)
	_cabin(v)


## The body: a long rounded box, glossy; and the bumpers, black, wrapping the ends.
static func _body(v: VehiclePaint) -> void:
	var c := v.canvas
	var k := v.k
	var base := v.base
	var t := PixelCanvas.tones(base)
	var half: Vector2 = (v.row["size"] as Vector2) * 0.5
	var trim := VehicleArtConfig.trim_color
	var bumper: float = v.look["bumper"]
	var body := PixelCanvas.rounded(
		Art.box(v, -half.x, half.x, -half.y, half.y),
		roundi(float(v.row["corner"]) * 1.1 * k),
	)
	c.fill(body, base, _BODY)
	c.bevel(body, 1, 2, t["highlight"], t["dark"])
	for ends: Array in [[half.x - bumper, half.x], [-half.x, -half.x + bumper]]:
		var b := PixelCanvas.rounded(
			Art.box(v, ends[0], ends[1], -half.y + 4.0, half.y - 4.0),
			roundi(4 * k),
		)
		c.fill(b, trim, _BODY - 1)
		c.bevel(b, 1, 1, trim.lightened(0.18), trim.darkened(0.3))


## The grille between the headlights.
static func _grille(v: VehiclePaint) -> void:
	var c := v.canvas
	var half: Vector2 = (v.row["size"] as Vector2) * 0.5
	var trim := VehicleArtConfig.trim_color
	var bumper: float = v.look["bumper"]
	var head: Vector2 = v.look["head"]
	var grille := PixelCanvas.rounded(
		Art.box(v, half.x - bumper - 5.0, half.x - bumper, -head.x + 6.0, head.x - 6.0),
		roundi(1 * v.k),
	)
	c.fill(grille, trim, _BODY)
	for i in 3:
		var x := half.x - bumper - 1.5 - i * 1.6
		c.line(
			Art.at(v, Vector2(x, -head.x + 8.0)),
			Art.at(v, Vector2(x, head.x - 8.0)),
			trim.lightened(0.15),
		)


## The bonnet: two creases running back to the windscreen, the shut line before it, a sheen.
static func _bonnet(v: VehiclePaint) -> void:
	var c := v.canvas
	var t := PixelCanvas.tones(v.base)
	var half: Vector2 = (v.row["size"] as Vector2) * 0.5
	var bumper: float = v.look["bumper"]
	var bonnet: float = v.look["bonnet"]
	var belt: float = v.look["belt"]
	for side in [-1.0, 1.0]:
		c.line(
			Art.at(v, Vector2(half.x - bumper - 7.0, side * 17.0)),
			Art.at(v, Vector2(bonnet + 3.0, side * 21.0)),
			t["dark"],
		)
		c.line(
			Art.at(v, Vector2(half.x - bumper - 7.0, side * 18.0)),
			Art.at(v, Vector2(bonnet + 3.0, side * 22.0)),
			t["light"],
		)
	c.line(
		Art.at(v, Vector2(bonnet + 1.0, -belt + 2.0)),
		Art.at(v, Vector2(bonnet + 1.0, belt - 2.0)),
		t["shadow"],
	)
	var sheen := PixelCanvas.rounded(
		Art.box(v, bonnet + 4.0, half.x - bumper - 6.0, -half.y + 8.0, half.y - 8.0),
		roundi(6 * v.k),
	)
	c.glare(sheen, v.base.lightened(0.38), 2)


## The boot lid's shut line and its badge.
static func _boot(v: VehiclePaint) -> void:
	var c := v.canvas
	var t := PixelCanvas.tones(v.base)
	var half: Vector2 = (v.row["size"] as Vector2) * 0.5
	var boot: float = v.look["boot"]
	var belt: float = v.look["belt"]
	c.line(
		Art.at(v, Vector2(boot - 1.0, -belt + 4.0)),
		Art.at(v, Vector2(boot - 1.0, belt - 4.0)),
		t["shadow"],
	)
	var badge := Art.at(v, Vector2(-half.x + float(v.look["bumper"]) + 4.0, 0.0))
	c.px(badge.x, badge.y, t["highlight"])
	c.px(badge.x + 1, badge.y, t["highlight"])


## The cabin, open to the sky (the roof part covers it): the floor, the dashboard and wheel, the
## seats, the console; the rear shelf under the back window.
static func _cabin(v: VehiclePaint) -> void:
	var c := v.canvas
	var k := v.k
	var boot: float = v.look["boot"]
	var belt: float = v.look["belt"]
	var floor_shape := PixelCanvas.rounded(
		Art.box(v, boot, v.look["bonnet"], -belt, belt), roundi(4 * k)
	)
	c.fill(floor_shape, VehicleArtConfig.interior_color, _FLOOR)
	c.surface(floor_shape, "fabric", VehicleArtConfig.interior_color)
	Art.sills(v)
	var driver: Vector2 = v.row["seats"][&"driver"]
	Art.dashboard(v, belt - 1.0)
	_console(v, driver)
	Art.seats(v, driver.x - 20.0)
	var shelf := PixelCanvas.rounded(
		Art.box(v, boot, boot + 14.0, -belt + 2.0, belt - 2.0),
		roundi(2 * k),
	)
	c.fill(shelf, VehicleArtConfig.interior_color.darkened(0.2), 2)


## The console between the front seats, beside the `driver`'s seat, and its gear knob.
static func _console(v: VehiclePaint, driver: Vector2) -> void:
	var c := v.canvas
	var console := PixelCanvas.rounded(
		Art.box(v, driver.x - 12.0, (v.look["dash"] as Vector2).x, -5.0, 5.0),
		roundi(2 * v.k),
	)
	c.fill(console, VehicleArtConfig.trim_color.lightened(0.08), 3)
	c.bevel(
		console,
		1,
		1,
		VehicleArtConfig.trim_color.lightened(0.25),
		VehicleArtConfig.trim_color.darkened(0.3),
	)
	var knob := Art.at(v, Vector2(driver.x + 14.0, 0.0))
	c.fill(
		PixelCanvas.disc(knob, maxi(1, roundi(1.5 * v.k))),
		VehicleArtConfig.trim_color.lightened(0.3),
		4,
	)


## The glasshouse over the cabin: windscreen, roof on its pillars, rear window; and the lamps.
static func _roof(v: VehiclePaint) -> void:
	var c := v.canvas
	var t := PixelCanvas.tones(v.base)
	var belt: float = v.look["belt"]
	# The pillars and the frame round the glass: everything from the belt line in, between the
	# windscreen's base and the rear window's, except the door glass (each door's own).
	var frame := PixelCanvas.rounded(
		Art.box(v, v.look["boot"], v.look["bonnet"], -belt, belt), roundi(3 * v.k)
	)
	c.fill(frame, v.base, _PILLAR)
	c.bevel(frame, 1, 1, t["light"], t["shadow"])
	Art.clear_door_glass(v)
	_windows(v)
	_roof_panel(v)
	Art.lamps(v, 0.0, 2, _BODY + 1, _BODY + 1)


## The windscreen and the rear window, tinted glass in black rubbers.
static func _windows(v: VehiclePaint) -> void:
	var look := v.look
	var roof: Vector2 = look["roof"]
	var bonnet: float = look["bonnet"]
	var screen_half: float = look["screen_half"]
	# How wide the windscreen is at x: it narrows toward the roof.
	var in_screen := func(p: Vector2) -> bool:
		return absf(p.y) <= Art.screen_edge(look, p.x) - 1.0 and p.x <= bonnet - 1.0
	var windscreen := Art.region(v, Art.box(v, roof.x, bonnet, -screen_half, screen_half),
			"car_screen/%s" % v.kind, in_screen)
	_glass(v.canvas, windscreen, VehicleArtConfig.glass_color, VehicleArtConfig.trim_color)
	_rear_window(v)


## The rear window, tinted glass in a black rubber, narrowing from `rear_half` at the boot to the
## roof.
static func _rear_window(v: VehiclePaint) -> void:
	var roof: Vector2 = v.look["roof"]
	var roof_half: float = v.look["roof_half"]
	var boot: float = v.look["boot"]
	var rear_half: float = v.look["rear_half"]
	var rear := func(x: float) -> float:
		return lerpf(rear_half, roof_half + 1.0, clampf((x - boot) / (roof.y - boot), 0.0, 1.0))
	var in_rear := func(p: Vector2) -> bool:
		return absf(p.y) <= rear.call(p.x) - 1.0 and p.x >= boot + 1.0
	var back := Art.region(v, Art.box(v, boot, roof.y, -roof_half, roof_half),
			"car_rear/%s" % v.kind, in_rear)
	_glass(v.canvas, back, VehicleArtConfig.glass_color, VehicleArtConfig.trim_color)


## The roof: a lighter, raised panel with a sheen.
static func _roof_panel(v: VehiclePaint) -> void:
	var c := v.canvas
	var t := PixelCanvas.tones(v.base)
	var roof: Vector2 = v.look["roof"]
	var roof_half: float = v.look["roof_half"]
	var panel := PixelCanvas.rounded(
		Art.box(v, roof.y, roof.x, -roof_half, roof_half),
		roundi(7 * v.k),
	)
	c.fill(panel, t["light"], _ROOF)
	c.bevel(panel, 1, 2, t["highlight"], t["dark"])
	c.glare(panel, v.base.lightened(0.42), 2)
	c.outline(panel, t["shadow"])


## Glass in `shape`: the tint, a glint, a rubber seal round it.
static func _glass(c: PixelCanvas, shape: PixelCanvas.Shape, glass: Color, rubber: Color) -> void:
	c.fill(shape, glass, _PILLAR - 1)
	c.glare(shape, Color(glass.lightened(0.55), 0.6), 2)
	c.outline(shape, rubber)
