extends GameTest
## The 3D carrier hides a character the 2D view no longer shows (#193, Art's `MeshCarrier`,
## interface 27). A character seated in a vehicle rides (`set_ride_pose` ... `end_ride`), so its
## mesh must not stand in the 3D view beside the car while it rides, and is back once it steps out;
## and a body whose own `visible` is false is hidden (the 2D World is hidden in 3D, so a node's own
## `visible`, not its `is_visible_in_tree`, says whether the 2D game draws it). The ride is the
## puppet's, as `tests/vehicle/board_nearest_door_test.gd`
## boards one.

const ProbeTwins := preload("res://tests/_art/art_probe_twins.gd")
const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const VehicleFrame := preload("res://tests/_vehicle/vehicle_frame_probe.gd")
const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")

var _mirror: MeshCarrier


func describe() -> Dictionary:
	return {
		"name": "The 3D carrier hides a seated character, and a body whose 2D node is hidden",
		"description": "A puppet boards a car: its mesh is hidden while it rides and shown "
			+ "again once it is out; a body with its own visible off is hidden.",
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
	await _check_hidden(t)


## A body whose own `visible` goes false is hidden while it is.
func _check_hidden(t: TestContext) -> void:
	ProbeTwins.install(t.world)
	var body := PlanProbe.handle()
	body.add_to_group(TwinSpace.HARD)  # looked at each frame, as a door or a car is
	body.position = Vector2(700, 150)
	t.world.add_child(body)
	await t.frames(3)
	var proxies: Array = _mirror.proxies_of(body)
	if not t.require(proxies.size() == 1, "a handle with no twin builder is meshed"):
		return
	t.check(proxies[0].visible, "and shown")
	body.visible = false
	await t.frames(3)
	t.check(not proxies[0].visible, "hidden while the body's own visible is off")
	body.visible = true
	await t.frames(3)
	t.check(proxies[0].visible, "and shown when it is on")
	body.queue_free()
