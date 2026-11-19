extends GameTest
## V6 (#194 vehicles3d, D13): what the vehicle touches is read by a shape query of its body in the
## twin space, whose hits a floor slab, a wall segment and every piece of furniture beside the
## hull share. A car with a ring of chairs against its sides, rolling into four standing characters,
## must still find each of them and strike it as an empty road would: killed at this speed, the
## car's speed less what they took.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const VehicleFrame := preload("res://tests/_vehicle/vehicle_frame_probe.gd")
const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")
## Chairs along each flank of the car, and how far they stand off the hull (px).
const PER_SIDE := 16
## The characters across the car's nose.
const VICTIMS := 4
const OFF := 0.6
const CAR_AT := Vector2(500, 120)
## How fast the car rolls (px/s): past the speed that kills.
const SPEED := 420.0
const GAP := 8.0


func describe() -> Dictionary:
	return {
		"name": "A car among furniture still strikes every character ahead",
		"description": "Thirty-two chairs along both flanks of a car: it still finds and kills "
			+ "the four characters it rolls into, and the chairs do not crowd them out.",
		"tags": ["vehicle", "car", "collision", "character", "furniture", "3d"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 2000, 900), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", CAR_AT)
	for v in VICTIMS:
		s.actor(
			StringName("victim%d" % v),
			&"puppet",
			Vector2(1800, 300 + v * 60),
			{ "max_health": 100.0 },
		)
	for i in PER_SIDE * 2:
		s.object(StringName("chair%d" % i), "chair", Vector2(100 + i * 60, 700))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"victim0", &"victim1", &"victim2", &"victim3"]):
		return
	await t.frames(4)
	var car := t.vehicle(&"car") as Node2D
	_line_the_flanks(t, car)
	await _stand_ahead(t, car)
	await t.frames(30)
	car.set("linear_velocity", VehicleFrame.forward(car) * SPEED)
	await t.seconds(1.5)
	for v in VICTIMS:
		t.check(
			t.actor(StringName("victim%d" % v)).is_dead,
			"character %d across the nose is struck at %.0f px/s and killed" % [v, SPEED],
		)
	t.check(
		car.speed() < SPEED * 0.97,
		"the car gave up some of its speed to the blow (%.0f of %.0f px/s)" % [car.speed(), SPEED],
	)


## Chairs along both flanks of `car`, each just off the hull.
func _line_the_flanks(t: TestContext, car: Node2D) -> void:
	var front := VehicleFrame.forward(car)
	var right := Vector2(-front.y, front.x)
	var half := Vector2(220, 110) * 0.5
	var width := _half_width(t.object(&"chair0"))
	for i in PER_SIDE * 2:
		var side := -1.0 if i < PER_SIDE else 1.0
		var along := -half.x + 14.0 + (i % PER_SIDE) * (half.x * 2.0 - 28.0) / (PER_SIDE - 1)
		var at := car.global_position + front * along + right * side * (half.y + width + OFF)
		(t.object(StringName("chair%d" % i)) as Node2D).global_position = at


## The victims, side by side just ahead of the car's nose.
func _stand_ahead(t: TestContext, car: Node2D) -> void:
	var front := VehicleFrame.forward(car)
	var right := Vector2(-front.y, front.x)
	var radius: float = t.actor(&"victim0").radius
	for v in VICTIMS:
		var across := (v - (VICTIMS - 1) * 0.5) * (radius * 2.0 + 2.0)
		var from: Vector2 = VehicleFrame.edge(car, front) + front * (radius + GAP) + right * across
		await VehicleRide.place(t, StringName("victim%d" % v), from)


## Half the narrow side of a piece's footprint, along the car's flank (px).
func _half_width(piece: Node) -> float:
	for child in piece.get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			return (child.shape as RectangleShape2D).size.y * 0.5
		if child is CollisionShape2D and child.shape is CircleShape2D:
			return (child.shape as CircleShape2D).radius
	return 16.0
