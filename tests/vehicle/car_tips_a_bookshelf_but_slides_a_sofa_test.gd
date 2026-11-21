extends GameTest
## V6 (#194 vehicles3d, D13): a vehicle strikes furniture through the physics of two free bodies,
## at the height its bumper meets it. A car rolling at a bookshelf (tall, thin, light) catches it
## low and over it goes; the same car at a sofa (low, wide, heavy) only slides it, upright.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const PieceProbe := preload("res://tests/_objects/piece_probe.gd")
const VehicleFrame := preload("res://tests/_vehicle/vehicle_frame_probe.gd")
## How fast the cars roll (px/s): a lane's worth of speed.
const SPEED := 500.0
const SHELF_AT := Vector2(900, 300)
const SOFA_AT := Vector2(900, 800)


func describe() -> Dictionary:
	return {
		"name": "A car tips a bookshelf over and only slides a sofa",
		"description": "Rolling at 500 px/s, a car meets a bookshelf: the blow at the bumper's "
			+ "height lays it over, and the car carries on. The same car meets a sofa: it slides "
			+ "it on, still upright.",
		"tags": ["vehicle", "car", "collision", "furniture", "tipping", "3d"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 2600, 1100), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car_a", &"car", Vector2(300, 300))
	s.vehicle(&"car_b", &"car", Vector2(300, 800))
	s.object(&"shelf", _solid_bookshelf(), SHELF_AT)
	s.object(&"sofa", "sofa", SOFA_AT)


func run(t: TestContext) -> void:
	await t.frames(4)
	var shelf := t.object(&"shelf")
	var sofa: Node2D = t.object(&"sofa")
	if not t.require(
			PieceProbe.body(shelf) != null and PieceProbe.body(sofa) != null,
			"premise: both pieces have free 3D bodies",
	):
		return
	var standing := PieceProbe.top(shelf)
	for id in [&"car_a", &"car_b"]:
		var car := t.vehicle(id)
		car.set("linear_velocity", VehicleFrame.forward(car) * SPEED)
	var sofa_from: Vector2 = sofa.global_position
	var leaned := 0.0
	for _i in 150:
		await t.frames(1)
		leaned = maxf(leaned, PieceProbe.lean(shelf))
	await PieceProbe.settle(t, shelf, 8.0)
	await PieceProbe.settle(t, sofa, 8.0)
	t.check(
		leaned > 60.0,
		"the bookshelf went over (leaned %.0f degrees from upright at most)" % leaned,
	)
	t.check(standing > 50.0, "premise: it stood tall (%.1f px)" % standing)
	t.check(
		PieceProbe.lean(sofa) < 10.0,
		"the sofa stayed upright (%.1f degrees)" % PieceProbe.lean(sofa),
	)
	t.check(
		sofa.global_position.distance_to(sofa_from) > 40.0,
		"and was slid on (%.0f px)" % sofa.global_position.distance_to(sofa_from),
	)
	t.check(
		(t.vehicle(&"car_a").global_position as Vector2).x > SHELF_AT.x - 150.0,
		"the car that met the bookshelf carried on",
	)


## The bookshelf as a solid tall, thin, light piece, as before the unbake (D21): its boards are
## hollow now (a bumper meets an open compartment), and its books are items.
func _solid_bookshelf() -> Dictionary:
	var shelf: Dictionary = ObjectDefinitions.get_definition("bookshelf").duplicate(true)
	shelf["art_opts"] = { "contents": "books" }
	return shelf
