extends GameTest
## V5 (#194 vehicles3d, D13): a vehicle whose engine is already running when its 3D body is built
## (the 3D body is made a frame after the vehicle enters the tree, and a parked one is put to sleep
## then) must not be put to sleep: it drives at once, and it may not sleep while the engine runs.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const SCENE := "res://scenes/vehicle/car.tscn"


func describe() -> Dictionary:
	return {
		"name": "A vehicle started the frame it is built drives at once",
		"description": "A car added to the world with its engine already on and the throttle held "
			+ "is under way within a second, its 3D body awake, and it may not sleep.",
		"tags": ["vehicle", "car", "drive", "3d"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 3000, 1000), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"anchor", &"car", Vector2(300, 800))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"anchor"):
		return
	var car: Node2D = (load(SCENE) as PackedScene).instantiate()
	car.position = Vector2(300, 300)
	t.vehicle(&"anchor").get_parent().add_child(car)
	# the engine on and the throttle held, before the twin space has built the 3D body
	car.drive.start_engine()
	car.drive.intent = { "throttle": 1.0, "steer": 0.0, "handbrake": false, "brake": false }
	await t.seconds(1.0)
	var lead := TwinSpace.leader_of(car)
	if not t.require(lead != null, "the car has a 3D body"):
		return
	t.check(
		car.speed() > 150.0,
		"the car under throttle is under way within a second (%.0f px/s)" % car.speed(),
	)
	t.check(not lead.can_sleep, "its 3D body may not sleep while the engine runs")
	t.check(not lead.sleeping, "and it is awake")
