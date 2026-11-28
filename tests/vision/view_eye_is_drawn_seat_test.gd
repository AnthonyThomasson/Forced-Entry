extends GameTest
## The player's view looks from the seat as the car is drawn (#194): a driver's handle is
## placed from the car's handle, which the twin space writes from the pose the drawn mesh stands at
## in the same physics frame. So the eye the view takes at its tick (the viewer's place, read after
## the viewer's own tick) is the drawn seat of the render frame that follows, with no step between
## them at speed. A handle that trailed the mesh by a step (8 px at 500 px/s) would fail it. The
## cone's own pose is as old as its job is (`vision/pose_lag_bounds`): what is held here is the
## place the job starts from.

const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")
const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
## Plan px the eye may stand off the drawn seat.
const NEAR := 0.5
const SPEED := 500.0
## After the view (physics 100): its tick has read the viewer.
const AFTER_VIEW := 101


func describe() -> Dictionary:
	return {
		"name": "The view's eye is the drawn seat while driving",
		"description": "At speed, the place the player's view reads from its viewer at its tick is "
			+ "where the car's mesh and the driver's seat are drawn in the render frame after it.",
		"tags": ["vision", "vehicle", "drive", "twins", "3d"],
		"timeout": 45.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 4200, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	s.vehicle(&"car", &"car", Vector2(300, 300))
	s.actor(&"me", &"puppet", Vector2(150, 80))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me") as Node2D
	var view := SubViewport.new()
	view.world_3d = TwinSpace.of_world(t.world).find_world_3d()
	t.world.add_child(view)
	var mirror := MeshCarrier.new()
	VehicleMeshes.register(mirror.builders)
	view.add_child(mirror)
	mirror.carry(t.world)
	var eyes := PlayerView.watch(t.world, me)
	if not t.require(eyes != null, "premise: the driver has a view"):
		return
	if not t.require(
		await VehicleRide.board_by(t, &"me", car, &"front_left"), "premise: the driver boards"
	):
		return
	await VehicleRide.reach_speed(t, &"me", car, SPEED, 8.0)
	var seen := await _drive(t, mirror, me, car, eyes)
	t.require(
		seen[1] > 30 and seen[2] > 4.0,
		"premise: tick and render were paired (%d frames, %.1f px a frame)" % [seen[1], seen[2]],
	)
	t.check(seen[0] < NEAR, "the view's eye is the drawn seat (%.2f px off)" % seen[0])


## Hold `SPEED` for a second: how far (px) the viewer's place at the view's tick stood off the
## drawn seat of the render frame after it at worst, how many tick and render pairs were read, and
## how far the seat moved between two render frames at most.
func _drive(
	t: TestContext, mirror: MeshCarrier, me: Node2D, car: Node2D, eyes: PlayerView
) -> Array:
	var seen: Array = [0.0, 0, 0.0]
	var eye: Array = [null]
	var last: Array = [null]
	var ticker := Ticker.new()
	ticker.process_physics_priority = AFTER_VIEW
	ticker.look = func() -> void:
		eye[0] = eyes.viewer().global_position
	var renderer := Renderer.new()
	renderer.look = func() -> void:
		var mesh := mirror.mesh_of(car)
		var seat := me.global_position - car.global_position
		var drawn := PlanSpace.plan_of(mesh.global_position) + seat
		if eye[0] != null:
			seen[0] = maxf(seen[0], (eye[0] as Vector2).distance_to(drawn))
			seen[1] += 1
		if last[0] != null:
			seen[2] = maxf(seen[2], (last[0] as Vector2).distance_to(drawn))
		last[0] = drawn
		eye[0] = null
	t.world.add_child(ticker)
	t.world.add_child(renderer)
	await VehicleRide.hold_speed(t, &"me", car, VehicleRide.hold(SPEED, 0.0, 1.0))
	ticker.queue_free()
	renderer.queue_free()
	return seen


## A node that calls `look` at its physics tick.
class Ticker:
	extends Node
	var look: Callable

	func _physics_process(_delta: float) -> void:
		look.call()


## A node that calls `look` each render frame.
class Renderer:
	extends Node
	var look: Callable

	func _process(_delta: float) -> void:
		look.call()
