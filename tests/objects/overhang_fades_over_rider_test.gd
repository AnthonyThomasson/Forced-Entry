extends GameTest
## A character riding in a vehicle keeps an awning faded as a walker does: the overhang fades for
## any `characters` member under its drawn area, and a rider's body is off the physics layers for
## the whole ride (the vehicle carries it). A car with a rider seated is moved under the opaque
## awning: the awning fades to a quarter of its opacity; the car is moved out again: it comes back
## to opaque and the fade watcher sleeps.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")
const OverhangVisuals := preload("res://scenes/objects/overhang_visuals.gd")
## The spec's opacity under it (the fade's own test holds the same number).
const FADED_ALPHA := 0.25
const ALPHA_SLACK := 0.03
## Where the awning hangs and where the car waits, clear of it.
const AWNING_AT := Vector2(500, 150)
const CAR_AT := Vector2(500, 500)


func describe() -> Dictionary:
	return {
		"name": "An awning stays faded over a character riding in a car",
		"description": "A puppet seated in a car; the car is moved under an opaque awning: the "
			+ "awning fades to about a quarter alpha, and is opaque again (watcher asleep) once "
			+ "the car has gone.",
		"tags": ["objects", "overhang", "awning", "fade", "vehicle"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 800), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.object(&"awning", "awning", AWNING_AT)
	s.vehicle(&"car", &"car", CAR_AT)
	s.actor(&"me", &"puppet", Vector2(150, 700))


func _alpha(overhang: CanvasItem) -> float:
	var alpha := 1.0
	var node: Node = overhang
	while node is CanvasItem:
		alpha *= (node as CanvasItem).modulate.a * (node as CanvasItem).self_modulate.a
		node = node.get_parent()
	return alpha


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var overhang := t.object(&"awning").find_child("Overhang", true, false) as CanvasItem
	if not t.require(overhang != null, "the awning has an Overhang"):
		return
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me")
	if not t.require(
		await VehicleRide.board_by(t, &"me", car, &"front_left"), "the puppet is seated"
	):
		return
	t.require(is_equal_approx(_alpha(overhang), 1.0), "the awning is opaque with the car away")
	var area: Rect2 = overhang.get_global_transform() * overhang.get_rect()
	var shift: Vector2 = area.get_center() - me.global_position
	await VehicleRide.move_vehicle(t, car, car.global_position + shift, 0.0)
	await t.seconds(0.6)
	t.check(
		area.has_point(me.global_position),
		"the rider is under the awning (at %s, area %s)" % [me.global_position, area],
	)
	t.check(
		absf(_alpha(overhang) - FADED_ALPHA) <= ALPHA_SLACK,
		"the awning fades over the rider (alpha %.2f)" % _alpha(overhang),
	)
	await VehicleRide.move_vehicle(t, car, CAR_AT, 0.0)
	await t.seconds(0.6)
	t.check(
		is_equal_approx(_alpha(overhang), 1.0),
		"the awning is opaque again once the car has gone (alpha %.2f)" % _alpha(overhang),
	)
	await t.frames(3)
	var reads: int = OverhangVisuals.FadeWatcher.group_reads
	await t.frames(10)
	t.expect_eq(
		OverhangVisuals.FadeWatcher.group_reads,
		reads,
		"no character-group read once the rider has gone",
	)
