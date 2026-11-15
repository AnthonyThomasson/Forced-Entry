extends GameTest
## The 3D mirror hides a character the 2D view no longer shows (#193, Art's `WorldMirror`,
## interface 27). A character seated in a vehicle has its collision shape disabled for the ride
## (`set_ride_pose` ... `end_ride`), so its capsule must not stand in the 3D view beside the car
## while it rides, and is back once it steps out. A body with its collision shape disabled when the
## mirror first sees it is still mirrored (hidden), so it shows when the shape is enabled; and a
## body whose own `visible` is false is hidden whatever its shape (the 2D World is hidden in 3D, so
## a node's own `visible`, not its `is_visible_in_tree`, says whether the 2D game draws it). The
## ride is the puppet's, as `tests/vehicle/board_nearest_door_test.gd` boards one. A second mirror
## shows characters by a mesh of a domain's own (a registered `CHARACTER` builder): that mesh has no
## collision shape of its own to be disabled, so it is hidden with the body's shapes just the same.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const VehicleFrame := preload("res://tests/_vehicle/vehicle_frame_probe.gd")
const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")

var _mirror: Node3D


func describe() -> Dictionary:
	return {
		"name": "The 3D mirror hides a seated character, and a body whose 2D node is hidden",
		"description": "A puppet boards a car: its capsule is hidden while it rides and shown "
			+ "again once it is out; a body seen with its shape disabled is mirrored and shows "
			+ "when the shape is enabled; a body with its own visible off is hidden.",
		"tags": ["mirror", "3d", "render", "vehicle"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(450, 300))
	s.actor(&"rider", &"puppet", Vector2(150, 100))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"rider"]):
		return
	var car := t.vehicle(&"car") as Node2D
	await t.frames(3)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	_mirror = WorldMirror.new()
	view.add_child(_mirror)
	_mirror.mirror(t.world)
	await t.frames(3)
	var rider := t.actor(&"rider")
	var capsule := _capsule(t, rider)
	if capsule == null:
		return
	t.check(capsule.visible, "premise: the standing character's capsule shows")
	var own := _own_mesh(t, rider)
	if own == null:
		return
	t.check(own.visible, "premise: the standing character's own mesh shows")
	if not t.require(
			await VehicleRide.board_by(t, &"rider", car, &"front_left"),
			"premise: the puppet boards the car",
	):
		return
	await t.frames(3)
	t.check(not capsule.visible, "a seated character's capsule is hidden")
	t.check(not own.visible, "a seated character's own mesh is hidden too")
	if not t.require(await VehicleRide.exit(t, &"rider"), "premise: the puppet gets out"):
		return
	await t.frames(30)
	t.check(capsule.visible, "the character's capsule is back once it is out")
	t.check(own.visible, "and its own mesh")
	await _check_disabled_and_hidden(t)


## The mesh a second mirror shows `body` by, from a `CHARACTER` builder, or null (the test ends).
func _own_mesh(t: TestContext, body: Node) -> Node3D:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var own := WorldMirror.new()
	own.builders[MirrorProxy.CHARACTER] = func(_body: Node2D) -> Node3D: return Node3D.new()
	view.add_child(own)
	own.mirror(t.world)
	var shown := own.proxies_of(body)
	if not t.require(shown.size() == 1, "premise: the character has one own mesh"):
		return null
	return shown[0]


## The character's one capsule, or null (the test ends).
func _capsule(t: TestContext, body: Node) -> Node3D:
	var proxies: Array = _mirror.proxies_of(body)
	if not t.require(proxies.size() == 1, "premise: the character has one proxy"):
		return null
	return proxies[0]


## A body spawned with its shape disabled gets a proxy that is hidden until the shape is enabled;
## one whose own `visible` goes false is hidden while it is.
func _check_disabled_and_hidden(t: TestContext) -> void:
	var body := AnimatableBody2D.new()
	body.position = Vector2(700, 150)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(40, 40)
	shape.shape = box
	shape.disabled = true
	body.add_child(shape)
	t.world.add_child(body)
	await t.frames(3)
	var proxies: Array = _mirror.proxies_of(body)
	if not t.require(proxies.size() == 1, "a body seen with its shape disabled is mirrored"):
		return
	t.check(not proxies[0].visible, "and hidden while the shape is disabled")
	shape.disabled = false
	await t.frames(3)
	t.check(proxies[0].visible, "shown once the shape is enabled")
	body.visible = false
	await t.frames(3)
	t.check(not proxies[0].visible, "hidden while the body's own visible is off")
	body.visible = true
	await t.frames(3)
	t.check(proxies[0].visible, "and shown when it is on")
	body.queue_free()
