extends GameTest
## V5 (#194 vehicles3d, D13): a vehicle with its engine off that has rolled to a stop goes back to
## sleep, as a parked one is: a sleeping 3D body costs the physics engine nothing, and a fleet that
## never slept would cost every frame (what the vehicle's own step writes each frame must not keep
## it awake).

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const VehicleFrame := preload("res://tests/_vehicle/vehicle_frame_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A vehicle rolled to a stop goes back to sleep",
		"description": "A car and a van given a push roll to a stop and, engine off, are asleep "
			+ "within a few seconds.",
		"tags": ["vehicle", "car", "van", "3d", "sleep"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 4000, 1000), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(300, 300))
	s.vehicle(&"van", &"van", Vector2(300, 700))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car") or not Probe.ready(t, &"van"):
		return
	await t.frames(4)
	for id in [&"car", &"van"]:
		var v := t.vehicle(id) as Node2D
		v.set("linear_velocity", VehicleFrame.forward(v) * 100.0)
	await t.seconds(0.3)
	for id in [&"car", &"van"]:
		var lead := TwinSpace.leader_of(t.vehicle(id))
		t.require(not lead.sleeping, "the %s is awake and rolling" % id)
	await t.seconds(6.0)
	for id in [&"car", &"van"]:
		var lead := TwinSpace.leader_of(t.vehicle(id))
		t.check(
			t.vehicle(id).speed() < 1.0 and lead.sleeping,
			"the %s has stopped (%.1f px/s) and is asleep" % [id, t.vehicle(id).speed()],
		)
