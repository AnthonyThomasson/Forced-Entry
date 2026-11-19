extends GameTest
## A car with its engine off that has rolled to a stop goes back to sleep even with people standing
## against it (#194 chars3d-b): its contacts see to a living character touching it every frame, and
## what they write to keep the car's speed along the contact must be written only when it changes,
## or the engine counts each write as a push and the car never rests.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const VehicleFrame := preload("res://tests/_vehicle/vehicle_frame_probe.gd")
const CAR_AT := Vector2(300, 300)
## The push (px/s) the car is given: it stops within a few px, beside the people it began beside.
const ROLL := 30.0
## Half the car's width (px): its body is 110 px across.
const CAR_HALF_WIDTH := 55.0


func describe() -> Dictionary:
	return {
		"name": "A stopped car beside standing people goes to sleep",
		"description": "A car given a push rolls to a stop with two people against its sides and "
			+ "is asleep within a few seconds.",
		"tags": ["vehicle", "car", "3d", "sleep", "character"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 800), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", CAR_AT)
	s.actor(&"left", &"puppet", CAR_AT + Vector2(0.0, -75.0))
	s.actor(&"right", &"puppet", CAR_AT + Vector2(0.0, 75.0))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"left", &"right"]):
		return
	await t.frames(4)
	var car := t.vehicle(&"car") as Node2D
	# against the car's flanks, a hair (0.5 px) off its side: inside the contacts' touch margin
	for pair: Array in [[&"left", -1.0], [&"right", 1.0]]:
		var who := t.actor(pair[0])
		who.global_position = car.global_position + Vector2(
			0.0, float(pair[1]) * (CAR_HALF_WIDTH + who.radius + 0.5)
		)
	await t.frames(3)
	car.set("linear_velocity", VehicleFrame.forward(car) * ROLL)
	await t.seconds(0.3)
	var lead := TwinSpace.leader_of(car)
	t.require(not lead.sleeping, "premise: the car is awake and rolling")
	for id in [&"left", &"right"]:
		var gap: float = absf(t.actor(id).global_position.y - car.global_position.y)
		t.require(
			gap < CAR_HALF_WIDTH + t.actor(id).radius + 1.0,
			"premise: %s stands against the car's side (%.1f px off)" % [id, gap],
		)
	await t.seconds(6.0)
	t.check(
		car.speed() < 1.0 and lead.sleeping,
		"the car has stopped (%.1f px/s) and is asleep" % car.speed(),
	)
