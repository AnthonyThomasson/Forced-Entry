extends GameTest
## The 3D carrier hides a character the 2D view no longer shows (#193, Art's `MeshCarrier`,
## interface 27). A character seated in a vehicle has its collision shape disabled for the ride
## (`set_ride_pose` ... `end_ride`), so its mesh must not stand in the 3D view beside the car while
## it rides, and is back once it steps out (a registered `CHARACTER` builder's mesh has no collision
## shape of its own to be disabled: it is hidden with the body's shapes). A body with its collision
## shape disabled when the carrier first sees it is still meshed (hidden), so it shows when the
## shape is enabled; and a body whose own `visible` is false is hidden whatever its shape (the 2D
## World is hidden in 3D, so a node's own `visible`, not its `is_visible_in_tree`, says whether the
## 2D game draws it). The ride is the puppet's, as `tests/vehicle/board_nearest_door_test.gd`
## boards one.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const VehicleFrame := preload("res://tests/_vehicle/vehicle_frame_probe.gd")
const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")

var _mirror: MeshCarrier


func describe() -> Dictionary:
	return {
		"name": "The 3D carrier hides a seated character, and a body whose 2D node is hidden",
		"description": "A puppet boards a car: its mesh is hidden while it rides and shown "
			+ "again once it is out; a body seen with its shape disabled is meshed and shows "
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
	_mirror = MeshCarrier.new()
	_mirror.builders[MeshKinds.CHARACTER] = func(_body: Node2D) -> Node3D: return Node3D.new()
	_mirror.builders[MeshKinds.FURNITURE] = func(_body: Node2D) -> Node3D: return Node3D.new()
	view.add_child(_mirror)
	_mirror.carry(t.world)
	await t.frames(3)
	var rider := t.actor(&"rider")
	var mesh := _mirror.mesh_of(rider)
	if not t.require(mesh != null, "premise: the character has a mesh"):
		return
	t.check(mesh.visible, "premise: the standing character's mesh shows")
	if not t.require(
			await VehicleRide.board_by(t, &"rider", car, &"front_left"),
			"premise: the puppet boards the car",
	):
		return
	await t.frames(3)
	t.check(not mesh.visible, "a seated character's mesh is hidden")
	if not t.require(await VehicleRide.exit(t, &"rider"), "premise: the puppet gets out"):
		return
	await t.frames(30)
	t.check(mesh.visible, "the character's mesh is back once it is out")
	await _check_disabled_and_hidden(t)


## A body spawned with its shape disabled gets a mesh that is hidden until the shape is enabled;
## one whose own `visible` goes false is hidden while it is.
func _check_disabled_and_hidden(t: TestContext) -> void:
	var body := AnimatableBody2D.new()
	body.sync_to_physics = false  # moved by hand
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
	if not t.require(proxies.size() == 1, "a body seen with its shape disabled is meshed"):
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
