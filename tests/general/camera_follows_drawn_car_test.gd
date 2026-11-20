extends GameTest
## The camera follows the car as it is drawn (#194 del2d-b3b, interface 27): a car's mesh is carried
## on its 3D twin (`VehicleBody`), which stands one physics step of travel ahead of the 2D footprint
## the seat and the camera's target read (`v / 60` px: 21 px at 1269 px/s). Following a driver, the
## camera reads where the twin is, so the place it follows is where the drawn car and its seat are:
## `follow_point()` is the driver's seat moved by how far the twin leads the footprint, and that
## lead is the step the car took (more the faster it goes, none while it is parked).

const CameraController = preload("res://scenes/general/camera_controller.gd")
const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")
const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
## Plan px the followed place may stand off the drawn seat.
const NEAR := 0.5
const SPEED := 500.0


func describe() -> Dictionary:
	return {
		"name": "The camera follows the car as drawn, not a step behind it",
		"description": "A camera following a driver at speed targets the seat where the car's "
			+ "twin is (its footprint trails by a step of travel); parked, nothing is added; on "
			+ "foot the followed place is the character's own.",
		"tags": ["camera", "vehicle", "drive", "twins", "3d"],
		"timeout": 45.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.lock_interaction([&"camera"])
	s.arena(Rect2(0, 0, 4200, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(300, 300))
	s.actor(&"me", &"puppet", Vector2(150, 80))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me") as Node2D
	var view := SubViewport.new()
	view.world_3d = TwinSpace.of_world(t.world).find_world_3d()  # drawn in the twins' world
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	VehicleMeshes.register(mirror.builders)
	view.add_child(mirror)
	mirror.mirror(t.world)
	var cam := Camera2D.new()
	cam.set_script(CameraController)
	cam.target_path = ^"../me"
	t.world.add_child(cam)
	cam.make_current()
	await t.frames(3)
	t.expect_near(
		cam.follow_point().distance_to(me.global_position), 0.0, NEAR, "on foot it follows the body"
	)
	if not t.require(
		await VehicleRide.board_by(t, &"me", car, &"front_left"), "premise: the driver boards"
	):
		return
	await t.frames(5)
	t.expect_near(
		cam.follow_point().distance_to(me.global_position), 0.0, NEAR, "parked, nothing is added"
	)
	await VehicleRide.reach_speed(t, &"me", car, SPEED, 8.0)
	var seen := await _drive(t, mirror, me, cam)
	t.require(
		seen[1] > 4.0 and seen[2] > 30,
		"premise: the drawn car leads the footprint (%.1f px, %d frames)" % [seen[1], seen[2]],
	)
	t.check(seen[0] < NEAR, "the camera follows the drawn seat (%.2f px off)" % seen[0])


## Hold `SPEED` for a second: how far (px) the camera's followed place stood off the drawn seat (the
## car's mesh in the view, plus the driver's seat) at worst, how far the mesh led the footprint at
## most, and how many frames were sampled.
func _drive(t: TestContext, mirror: WorldMirror, me: Node2D, cam: Camera2D) -> Array:
	var car := t.vehicle(&"car") as Node2D
	var seen: Array = [0.0, 0.0, 0]
	var plan := VehicleRide.hold(SPEED, 0.0, 1.0)
	await VehicleRide.hold_speed(
		t, &"me", car, plan, func() -> void:
			var mesh := mirror.mesh_of(car)  # the car as it is drawn
			var seat := me.global_position - car.global_position
			var drawn := PlanSpace.plan_of(mesh.global_position) + seat
			seen[0] = maxf(seen[0], cam.follow_point().distance_to(drawn))
			var footprint := PlanSpace.lift(car.global_position)
			seen[1] = maxf(seen[1], mesh.global_position.distance_to(footprint))
			seen[2] += 1
	)
	return seen
