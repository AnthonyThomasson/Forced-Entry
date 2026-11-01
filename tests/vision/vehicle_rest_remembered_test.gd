extends GameTest
## V6 (`docs/player-vision.md`): a parked vehicle is remembered where it stands, and moving again it
## is not. A car stands parked (on `WORLD`), a puppet gets in and drives it up to speed (on
## `MOVING` the whole time it is under way) and brakes it to a stop (on `WORLD` again once it has
## stood still): the player's view, in the same world, is the viewer.
##
## It reads (tests/_vision/vision_probe.gd) the car's `visibility_layer` and its `speed()`.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")
const ViewProbe := preload("res://tests/_vision/vision_probe.gd")
## Moving: at least this fast (px/s). Parked: no faster than this (px/s) for this many frames.
const MOVING_SPEED := 5.0
const PARKED_SPEED := 0.5
const PARKED_FRAMES := 10
const ARENA := Rect2(0, 0, 3000, 900)

var _moving_frames := 0
var _parked_frames := 0
var _wrong := 0
var _quiet := 0
var _last_speed := 0.0


func describe() -> Dictionary:
	return {
		"name": "A parked vehicle is remembered, a moving one is not",
		"description": "A car parked is on WORLD, driven up to speed on MOVING, braked to a stop "
			+ "and standing still on WORLD again.",
		"tags": ["vision", "vehicle", "car"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA, { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	s.actor(&"you", &"player", Vector2(100, 700))
	s.vehicle(&"car", &"car", Vector2(300, 300))
	s.actor(&"driver", &"puppet", Vector2(120, 180))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"driver"]):
		return
	var car := t.vehicle(&"car") as Node2D
	await _watch(t, car, 0.5)
	if not t.require(
		await VehicleRide.board_by(t, &"driver", car, &"front_left"),
		"the driver gets into the car",
	):
		return
	await _watch(t, car, 0.5)
	var p := t.puppet(&"driver")
	p.drive(1.0, 0.0, false)
	await _watch_until(t, car, func() -> bool: return car.speed() >= 300.0)
	p.drive(0.0, 0.0, true)
	await _watch_until(t, car, func() -> bool: return car.speed() < PARKED_SPEED)
	await _watch(t, car, 1.0)
	t.check(
		_moving_frames >= 20,
		"premise: the car was seen under way (%d frames over %.0f px/s)"
		% [_moving_frames, MOVING_SPEED],
	)
	t.check(
		_parked_frames >= 3 * PARKED_FRAMES,
		"premise: the car was seen standing still (%d frames)" % _parked_frames,
	)
	t.check(
		_wrong == 0,
		"the car is on MOVING while under way and on WORLD while parked (%d frames not)" % _wrong,
	)


func _watch(t: TestContext, car: Node2D, seconds: float) -> void:
	for _i in int(seconds * 60.0):
		await t.frames(1)
		_look(car)


func _watch_until(t: TestContext, car: Node2D, done: Callable) -> void:
	var deadline := t.time + 12.0
	while t.time < deadline and not done.call():
		await t.frames(1)
		_look(car)


## One frame: under way (this frame and the one before: the layer follows the speed a frame
## behind) it must be on `MOVING`, and standing still for a few frames on `WORLD`.
func _look(car: Node2D) -> void:
	var speed: float = car.speed()
	var before := _last_speed
	_last_speed = speed
	_quiet = _quiet + 1 if speed <= PARKED_SPEED else 0
	if speed >= MOVING_SPEED and before >= MOVING_SPEED:
		_moving_frames += 1
		_wrong += int(car.visibility_layer != ViewProbe.MOVING)
	elif _quiet >= PARKED_FRAMES:
		_parked_frames += 1
		_wrong += int(car.visibility_layer != ViewProbe.WORLD)
