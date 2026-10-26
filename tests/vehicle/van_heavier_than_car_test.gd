extends GameTest
## V5 (ticket #54): the van is heavier than the car, accelerates slower, has a lower top speed and a
## wider turn, and slides sooner. A car and a van side by side: the van's mass is the larger; on
## full throttle from rest it is the slower; its top speed (VehicleConfig) is the lower; at the same
## 60 px/s with full steer it turns on a wider circle; and at the same high speed (240 px/s) with
## full steer it slides more (its peak slip()).

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const VehicleFrame := preload("res://tests/_vehicle/vehicle_frame_probe.gd")
const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")
const IDS := [&"c", &"v"]
## The high speed both are held at for the slide comparison (px/s): a fixed 240 px/s, well under
## both tops, so a retune of the top speed leaves it in reach.
const FAST := 240.0


func describe() -> Dictionary:
	return {
		"name": "The van is heavier than the car",
		"description": "Van against car: more mass, slower off the line, a lower top speed, a "
			+ "wider turn at 60 px/s and more slip at the same 240 px/s.",
		"tags": ["vehicle", "car", "van", "drive", "mass"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	# Room for F4's launch (about 1000 px/s after the 1.5 s off the line) and the stop from it
	# before the turns.
	s.arena(Rect2(0, 0, 4400, 2000), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(400, 1000))
	s.vehicle(&"van", &"van", Vector2(400, 1250))
	s.actor(&"c", &"puppet", Vector2(150, 760))
	s.actor(&"v", &"puppet", Vector2(150, 1500))


## Both drivers hold their speed near `target` (throttle below it, brake well above it) with steer
## `steers[i]` for `duration` s, calling `sample` each frame.
func _cruise(
	t: TestContext,
	target: float,
	steers: Array,
	duration: float,
	sample := Callable(),
) -> void:
	var vehicles := _both(t)
	var deadline := t.time + duration
	while t.time < deadline:
		for i in 2:
			var v: Node2D = vehicles[i]
			var throttle := 0.0
			if v.speed() < target - 3.0:
				throttle = 1.0
			elif v.speed() > target + 15.0 and VehicleFrame.along(v) > 0.0:
				throttle = -1.0
			t.puppet(IDS[i]).drive(throttle, steers[i], false)
		await t.frames(1)
		if sample.is_valid():
			sample.call()
	for id in IDS:
		t.puppet(id).drive(0.0, 0.0, false)


## Brake both to a stop, together (one held on the throttle while the other stops would run on
## toward the far wall).
func _stop(t: TestContext) -> void:
	var vehicles := _both(t)
	for id in IDS:
		t.puppet(id).drive(-1.0, 0.0, false)
	await t.until(func(): return vehicles.all(func(v): return VehicleFrame.along(v) <= 2.0), 6.0)
	for id in IDS:
		t.puppet(id).drive(0.0, 0.0, false)
	await t.seconds(0.5)


## The car and the van, in `IDS` order.
func _both(t: TestContext) -> Array:
	return [t.vehicle(&"car") as Node2D, t.vehicle(&"van") as Node2D]


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"c", &"v"]) or not Probe.ready(t, &"van"):
		return
	var car := t.vehicle(&"car") as Node2D
	var van := t.vehicle(&"van") as Node2D
	if not _check_specs(t, car, van):
		return
	if not t.require(
			await VehicleRide.board_by(t, &"c", car, &"front_left"),
			"a driver gets into the car",
	):
		return
	if not t.require(
			await VehicleRide.board_by(t, &"v", van, &"front_left"),
			"a driver gets into the van",
	):
		return
	await t.seconds(0.5)
	await _check_launch(t)
	await _check_turn(t)
	await _check_slide(t)


## The van is the heavier and has the lower top speed (false: no top speed to read, the test has
## ended).
func _check_specs(t: TestContext, car: Node2D, van: Node2D) -> bool:
	t.check(
		float(van.get("mass")) > float(car.get("mass")),
		"the van is heavier (%.0f against %.0f)" % [float(van.get("mass")), float(car.get("mass"))],
	)
	var car_top: Variant = Probe.kind_value(&"car", &"top_speed")
	var van_top: Variant = Probe.kind_value(&"van", &"top_speed")
	if not t.require(
			car_top != null and van_top != null,
			"VehicleConfig gives each kind a top_speed",
	):
		return false
	t.check(
		float(van_top) < float(car_top),
		"the van's top speed is the lower (%.0f against %.0f px/s)"
			% [float(van_top), float(car_top)],
	)
	return true


## Off the line: full throttle for 1.5 s, the van the slower; then both stop.
func _check_launch(t: TestContext) -> void:
	var car := t.vehicle(&"car") as Node2D
	var van := t.vehicle(&"van") as Node2D
	for id in IDS:
		t.puppet(id).drive(1.0, 0.0, false)
	await t.seconds(1.5)
	t.check(
		car.speed() > van.speed() * 1.1,
		"the van accelerates slower (%.0f against the car's %.0f px/s)"
			% [van.speed(), car.speed()],
	)
	await _stop(t)


## The turn at 60 px/s, full steer (car left, van right: they turn away from each other): the van's
## circle is the wider. Then both stop and go back to their start lanes.
func _check_turn(t: TestContext) -> void:
	var car := t.vehicle(&"car") as Node2D
	var van := t.vehicle(&"van") as Node2D
	var both := _both(t)
	await _cruise(t, 60.0, [-1.0, 1.0], 1.5)
	var turned := [0.0, 0.0]
	var travelled := [0.0, 0.0]
	var last := [car.global_rotation, van.global_rotation]
	await _cruise(t, 60.0, [-1.0, 1.0], 1.5, func():
		for i in 2:
			var v: Node2D = both[i]
			turned[i] += absf(angle_difference(last[i], v.global_rotation))
			last[i] = v.global_rotation
			travelled[i] += v.speed() / Engine.physics_ticks_per_second)
	if t.check(turned[0] > 0.1 and turned[1] > 0.1, "both turn (%.2f, %.2f rad)" % turned):
		var car_radius: float = travelled[0] / turned[0]
		var van_radius: float = travelled[1] / turned[1]
		t.check(
			van_radius > car_radius * 1.1,
			"the van turns on a wider circle (%.0f against %.0f px)" % [van_radius, car_radius],
		)
	await _stop(t)
	# Back to the start lanes facing +x: the heading the circles leave them on depends on the
	# tuning, and could aim them at a wall.
	await VehicleRide.move_vehicle(t, car, Vector2(400, 1000), 0.0)
	await VehicleRide.move_vehicle(t, van, Vector2(400, 1250), 0.0)


## The same high speed and full steer: the van slides more.
func _check_slide(t: TestContext) -> void:
	var car := t.vehicle(&"car") as Node2D
	var van := t.vehicle(&"van") as Node2D
	var both := _both(t)
	var fast := FAST
	await _cruise(t, fast, [0.0, 0.0], 3.0)
	t.check(
		car.speed() > fast - 15.0 and van.speed() > fast - 15.0,
		"both reach %.0f px/s (%.0f, %.0f)" % [fast, car.speed(), van.speed()],
	)
	var slips := [0.0, 0.0]
	await _cruise(t, fast, [-1.0, 1.0], 1.0, func():
		for i in 2:
			slips[i] = maxf(slips[i], float(both[i].slip())))
	t.check(
		slips[1] > slips[0],
		"at the same speed and steer the van slides more (slip %.3f against the car's %.3f)"
			% [slips[1], slips[0]],
	)
