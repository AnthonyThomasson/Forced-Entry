extends GameTest
## A 3D camera following a driver whose vehicle's zoom-out jitters about a step boundary keeps its
## step (#193 phase 2b; the zoom-out is the vehicle's `view_zoom_out()`, read duck-typed as the
## camera does). The zoom-out `out` makes the automatic zoom 1 - out: the nearest-step boundary
## between 1x and 0.5x is 0.707 (out 0.293). A stand-in driver and vehicle hold `out` where the test
## puts it, so the numbers are worked by hand: 0.1 shows 1x, a jitter of 0.27 / 0.32 about the
## boundary changes nothing, 0.5 shows 0.5x, a jitter of 0.27 / 0.32 again (from below) changes
## nothing, and 0.05 shows 1x.

const CameraController = preload("res://scenes/general/camera_controller.gd")
const RigProbe = preload("res://tests/_general/rig_probe.gd")

var _ride: FakeRide
var _cam: Camera2D


func describe() -> Dictionary:
	return {
		"name": "A 3D camera's zoom holds while a vehicle's zoom-out jitters at a boundary",
		"description": "Following a driver in 3D, a zoom-out jittering across the 1x / 0.5x "
			+ "boundary holds the step it was on; a clear change moves it.",
		"tags": ["camera", "zoom", "vehicle", "3d"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])
	s.arena(Rect2(0, 0, 800, 500))


func run(t: TestContext) -> void:
	var driver := FakeDriver.new()
	driver.name = "Driver"
	_ride = FakeRide.new()
	driver.use = FakeUse.new()
	driver.use.ride = _ride
	t.world.add_child(driver)
	_cam = Camera2D.new()
	_cam.set_script(CameraController)
	_cam.target_path = ^"../Driver"
	t.world.add_child(_cam)
	_cam.make_current()
	RigProbe.open(t.world, _cam, 0.0)
	await _hold(t, 0.1)
	t.expect_eq(_cam.zoom.x, 1.0, "a gentle zoom-out shows 1x")
	await _jitter(t, 0.27, 0.32)
	t.expect_eq(_cam.zoom.x, 1.0, "jittering across the boundary from above holds 1x")
	await _hold(t, 0.5)
	t.expect_eq(_cam.zoom.x, 0.5, "a clear zoom-out shows 0.5x")
	await _jitter(t, 0.27, 0.32)
	t.expect_eq(_cam.zoom.x, 0.5, "jittering across the boundary from below holds 0.5x")
	await _hold(t, 0.05)
	t.expect_eq(_cam.zoom.x, 1.0, "a clear return shows 1x")


func _hold(t: TestContext, out: float) -> void:
	_ride.out = out
	await t.frames(4)


## Alternate the zoom-out between `a` and `b` every frame for 30 frames, watching the zoom.
func _jitter(t: TestContext, a: float, b: float) -> void:
	var seen := {}
	for i in 30:
		_ride.out = a if i % 2 == 0 else b
		await t.frames(1)
		seen[_cam.zoom.x] = true
	t.expect_eq(seen.size(), 1, "the zoom took one value through the jitter (%s)" % [seen.keys()])


class FakeRide extends Node:
	var out := 0.0

	func view_zoom_out() -> float:
		return out


class FakeUse extends RefCounted:
	var ride: Node

	func vehicle() -> Node:
		return ride


class FakeDriver extends Node2D:
	var use: FakeUse
