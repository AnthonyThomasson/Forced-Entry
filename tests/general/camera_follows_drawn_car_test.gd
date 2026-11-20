extends GameTest
## The camera follows the car as it is drawn (#194 del2d-c5c, interface 27): a car's mesh is carried
## on its 3D twin (`VehicleBody`), whose node pose is the one the engine synced at the start of the
## physics frame, the pose the twin space writes the car's handle from in the same frame. So in a
## render frame (a `_process` after the camera's) the handle, the seat the driver is placed at and
## the drawn mesh are one place: `follow_point()` is the driver's own place, with no lead term in
## the camera. Only a reader that awaits `physics_frame` (before the twin space's write) sees the
## handle a step behind (8 px at 500 px/s); this test reads where a render frame does, so a handle
## written a frame late would fail it.

const CameraController = preload("res://scenes/general/camera_controller.gd")
const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")
const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
## Plan px the followed place may stand off the drawn seat.
const NEAR := 0.5
const SPEED := 500.0
## After the camera (0), the carrier and the rig (50): the camera has read what it follows.
const SAMPLE_PRIORITY := 10


func describe() -> Dictionary:
	return {
		"name": "The camera follows the car as drawn, not a step behind it",
		"description": "A camera following a driver at speed targets the seat where the car is "
			+ "drawn: the car's handle and its rider are written from the twin's pose before the "
			+ "camera reads them; parked it is the seat; on foot the character's own place.",
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
	var mirror := MeshCarrier.new()
	VehicleMeshes.register(mirror.builders)
	view.add_child(mirror)
	mirror.carry(t.world)
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
		"premise: the drawn car is under way (%.1f px a frame, %d frames)" % [seen[1], seen[2]],
	)
	t.check(seen[0] < NEAR, "the camera follows the drawn seat (%.2f px off)" % seen[0])
	t.check(seen[3] < NEAR, "the car's handle is where it is drawn (%.2f px off)" % seen[3])


## Hold `SPEED` for a second, a sampler in the render's `_process` (after the camera's, the view's
## own priority) reading: how far (px) the camera's followed place stood off the drawn seat (the
## car's mesh in the view, plus the driver's seat) at worst, how far the mesh moved between two
## samples at most (the car is under way), how many frames were sampled, and how far the car's
## handle stood off its mesh.
func _drive(t: TestContext, mirror: MeshCarrier, me: Node2D, cam: Camera2D) -> Array:
	var car := t.vehicle(&"car") as Node2D
	var seen: Array = [0.0, 0.0, 0, 0.0]
	var last := [Vector3.INF]
	var sampler := Sampler.new()
	sampler.process_priority = SAMPLE_PRIORITY
	sampler.look = func() -> void:
		var mesh := mirror.mesh_of(car)  # the car as it is drawn
		var seat := me.global_position - car.global_position
		var drawn := PlanSpace.plan_of(mesh.global_position) + seat
		seen[0] = maxf(seen[0], cam.follow_point().distance_to(drawn))
		seen[3] = maxf(seen[3], PlanSpace.plan_of(mesh.global_position).distance_to(
			car.global_position
		))
		if last[0] != Vector3.INF:
			seen[1] = maxf(seen[1], mesh.global_position.distance_to(last[0]) / RenderConfig.unit)
		last[0] = mesh.global_position
		seen[2] += 1
	t.world.add_child(sampler)
	var plan := VehicleRide.hold(SPEED, 0.0, 1.0)
	await VehicleRide.hold_speed(t, &"me", car, plan)
	sampler.queue_free()
	return seen


## A node that calls `look` each render frame at its own `process_priority`.
class Sampler:
	extends Node
	var look: Callable

	func _process(_delta: float) -> void:
		look.call()
