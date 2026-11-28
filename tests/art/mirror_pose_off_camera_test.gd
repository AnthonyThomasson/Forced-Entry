extends GameTest
## The carrier asks a mesh that says how far it reaches (`mirror_reach`) for its pose only while it
## is on the view's camera (interface 27): off it, `mirror_update` is not called; a camera moved
## back onto it, even after the carrier has looked that frame (the camera rig moves it later), has
## it posed in that same frame, before the picture; a mesh that gives no reach is asked every frame.

const ProbeTwins := preload("res://tests/_art/art_probe_twins.gd")
## Where the camera looks while the chairs are off it (px).
const FAR := Vector2(5000, 5000)
## Where the character stands (px).
const STAND := Vector2(300, 400)


func describe() -> Dictionary:
	return {
		"name": "A mesh off the camera is not posed",
		"description": "Off the view's camera a mesh that says its reach is not asked for its "
			+ "pose, and it is posed in the frame the camera comes back to it, paused or not.",
		"tags": ["mirror", "3d", "render"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 800, 500))
	s.set_static(RenderConfig, &"unit", 1.0)
	s.object(&"chair", "armchair", Vector2(300, 200))
	s.object(&"other", "armchair", Vector2(500, 200))
	s.actor(&"one", &"puppet", STAND, { "facing": Vector2.RIGHT })
	s.von_script([])


func run(t: TestContext) -> void:
	await t.frames(5)
	ProbeTwins.install(t.world)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 300.0
	camera.rotation.x = -PI * 0.5
	view.add_child(camera)
	_look_at(camera, Vector2(400, 200))
	var carrier := MeshCarrier.new()
	view.add_child(carrier)
	carrier.builders[MeshKinds.FURNITURE] = func(body: Node2D) -> Node3D:
		return Reaching.new() if body == t.object(&"chair") else Posed.new()
	CharacterMeshes.register(carrier.builders)
	carrier.carry(t.world)
	await t.frames(3)
	var chair := carrier.mesh_of(t.object(&"chair")) as Posed
	var other := carrier.mesh_of(t.object(&"other")) as Posed
	if not t.require(chair != null and other != null, "premise: both chairs are carried"):
		return
	var before := chair.asked
	await t.frames(5)
	t.check(chair.asked > before, "on the camera the mesh is posed")
	_look_at(camera, FAR)
	await t.frames(2)
	before = chair.asked
	var plain := other.asked
	await t.frames(5)
	t.expect_eq(chair.asked, before, "off the camera the mesh that says its reach is not posed")
	t.check(other.asked > plain, "a mesh that says none is asked as before")
	await _check_same_frame(t, camera, chair)
	await _check_paused(t, camera, carrier.mesh_of(t.actor(&"one")) as BodyMesh)


## The camera moved back after the carrier looked: the mesh is posed before the frame ends.
func _check_same_frame(t: TestContext, camera: Camera3D, chair: Posed) -> void:
	var seen := { "before": -1, "after": -1 }
	var mover := Later.new()
	mover.process_priority = 50
	var reader := Later.new()
	reader.process_priority = 100
	mover.act = func() -> void:
		if seen["before"] < 0:
			seen["before"] = chair.asked
			_look_at(camera, Vector2(400, 200))
	reader.act = func() -> void:
		if seen["after"] < 0 and seen["before"] >= 0:
			seen["after"] = chair.asked
	t.world.add_child(mover)
	t.world.add_child(reader)
	await t.frames(3)
	t.check(
		seen["after"] > seen["before"],
		"a camera back on it poses the mesh in that same frame (%d then %d)" % [
			seen["before"],
			seen["after"],
		],
	)


## A character turns round while off the camera, then the match is paused; the camera, moved back
## only after some paused frames (a spectator panning), shows it facing the way it now faces.
func _check_paused(t: TestContext, camera: Camera3D, body: BodyMesh) -> void:
	if not t.require(body != null, "premise: the character is carried"):
		return
	_look_at(camera, STAND)
	t.puppet(&"one").aim_at(STAND + Vector2(1000, 0))
	await t.seconds(0.5)
	if not t.require(_face_ahead(body) > 0.0, "premise: on the camera it faces right"):
		return
	_look_at(camera, FAR)
	await t.frames(2)
	t.puppet(&"one").aim_at(STAND + Vector2(-1000, 0))
	await t.seconds(0.8)
	if not t.require(_face_ahead(body) > 0.0, "premise: turned off the camera, it is not posed"):
		return
	var tree := t.world.get_tree()
	tree.paused = true
	await t.frames(3)
	_look_at(camera, STAND)
	await t.frames(3)
	t.check(
		_face_ahead(body) < 0.0,
		"paused, the camera back on it shows it facing left (face %.1f of its head)"
			% _face_ahead(body),
	)
	tree.paused = false


## How far east of the head's middle the face is.
func _face_ahead(body: BodyMesh) -> float:
	return body.part(BodyMesh.FACE).position.x - body.part(BodyMesh.HEAD).position.x


func _look_at(camera: Camera3D, at: Vector2) -> void:
	camera.position = Vector3(at.x, 1000.0, at.y)


## A mesh that counts the poses it is asked for.
class Posed:
	extends Node3D

	var asked := 0

	func mirror_update(_body: Node2D) -> void:
		asked += 1


## The same, saying it stays within 50 units of its origin.
class Reaching:
	extends Posed

	func mirror_reach() -> float:
		return 50.0


## What moves the camera after the carrier has looked, as the camera rig does; and what reads the
## count in the same frame, after the carrier had its second look.
class Later:
	extends Node

	var act := Callable()

	func _process(_delta: float) -> void:
		if act.is_valid():
			act.call()
