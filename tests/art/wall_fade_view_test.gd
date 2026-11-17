extends GameTest
## The wall fade in a 3D match, through Main's real view (#193 rule 9, interface 27): Main's view
## builds it, wraps the walls' builders so the walls it shows are known to it, and gives it the
## sim's camera, which names the characters to look after (the combatants while spectating). Then,
## with the characters it looks after stood on the camera's far side of two real walls, the walls'
## segments between them and the camera fade and the rest stay whole, a segment a hit rebuilds
## keeps its fade the frame it is replaced, and a wall whose characters have gone is whole again.
## The stand-in for the camera only says where the characters stand (a match's own wander about).

const MainProbe := preload("res://tests/_main/main_probe.gd")
const Probe := preload("res://tests/_art/art_wall_fade_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_wall_fade_view_test.json"
const MATCH := {
	"seed": 2,
	"defenders": { "count": 2 },
	"invaders": { "count": 2 },
}
## How far a character stands from the middle of the wall segment it is behind, along the camera's
## line: just past its face, since at the 80 degree pitch a 96 px wall hides only what stands within
## 17 px of it.
const STANDOFF := 9.0
## The gap between a door's face and the character behind it.
const DOOR_GAP := 4.0
## Walls whose segments are this far apart do not fade for each other's characters.
const APART := 400.0

var _world: Node
var _view: CanvasLayer
var _fade: WallFade
var _stand_in: Source


func describe() -> Dictionary:
	return {
		"name": "Main's 3D view fades the walls between the camera and the characters it follows",
		"description": "The view builds the wall fade over the camera and its walls; a wall "
			+ "segment between the camera and a character fades, around every character when "
			+ "spectating, a rebuilt segment keeps its fade, and walls come back when they leave.",
		"tags": ["mirror", "3d", "render", "wall-fade"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(WallFadeConfig, &"faded_amount", 0.25)
	s.switch(&"physics.debris", false)
	s.switch(&"nav.rebake", false)
	s.von_script([])


func run(t: TestContext) -> void:
	var window := MainProbe.viewport(t)
	var camera := await _start(t, window)
	if camera == null:
		return
	_view_is_wired(t, camera)
	_spectating_names_the_combatants(t, camera)
	_fade.source = _stand_in
	var walls := Probe.walls(_view.mirror, _world, APART)
	if not t.require(walls.size() >= 2, "the match has two walls far apart to stand behind"):
		return
	var yaw: float = _view.rig.yaw
	var back := Probe.back_of(yaw)
	var markers := [_stand_behind(t, walls[0], back), _stand_behind(t, walls[1], back)]
	await _fades_around_each(t, walls, markers)
	await _hit_keeps_the_fade(t, walls[0])
	await _a_door_fades(t, back)
	_stand_in.targets = []
	await t.seconds(0.6)
	t.expect_near(
		Probe.level(walls[0]["part"]),
		1.0,
		0.001,
		"the character gone: its wall is whole",
	)
	t.expect_near(Probe.level(walls[1]["part"]), 1.0, 0.001, "and so is the other")
	await MainProbe.close(t, window)


## A Watch match in 3D under `window`, the camera running the real controller; null when it failed.
func _start(t: TestContext, window: SubViewport) -> Camera2D:
	var main := MainProbe.open(window)
	MainProbe.setup_menu(main).queue_free()
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	camera.set_script(CameraScript)
	main.add_child(camera)
	camera.make_current()
	var built: Dictionary = await main.start_match(MATCH.duplicate(true))
	if not t.require(not built.is_empty(), "a Watch match started in 3D"):
		return null
	await t.frames(6)
	_world = built["world"]
	_view = main.get_node("View3D")
	_fade = _view.fade
	_stand_in = Source.new()
	main.add_child(_stand_in)
	return camera


func _view_is_wired(t: TestContext, camera: Camera2D) -> void:
	t.check(_fade.source == camera and _fade.rig == _view.rig, "the view gives it camera and rig")
	t.check(_fade.count() > 0, "it knows the walls the view shows (%d units)" % _fade.count())


## One character, then two (spectating): each one's wall fades, nothing else, and a still view
## writes nothing.
func _fades_around_each(t: TestContext, walls: Array, markers: Array) -> void:
	_stand_in.targets = [markers[0]["marker"]]
	await t.seconds(0.6)
	t.expect_near(
		Probe.level(walls[0]["part"]),
		0.25,
		0.08,
		"the wall between camera and character fades",
	)
	t.expect_near(Probe.level(walls[1]["part"]), 1.0, 0.001, "a wall far from it stays whole")
	_stand_in.targets = [markers[0]["marker"], markers[1]["marker"]]
	await t.seconds(0.6)
	t.expect_near(
		Probe.level(walls[0]["part"]),
		0.25,
		0.08,
		"spectating: the first one's wall fades",
	)
	t.expect_near(Probe.level(walls[1]["part"]), 0.25, 0.08, "and the second's")
	await t.frames(3)
	t.expect_eq(_fade.written, 0, "a still view writes nothing")


## A closed door between the camera and a character fades with its leaf and handle, and comes back.
func _a_door_fades(t: TestContext, back: Vector2) -> void:
	var door: Node2D = null
	for node: Node in _world.get_tree().get_nodes_in_group(&"doors"):
		if _world.is_ancestor_of(node) and _view.mirror.proxies_of(node).size() == 1:
			door = node as Node2D
			break
	if not t.require(door != null, "the match has a door shown by a mesh"):
		return
	var mesh: Node3D = _view.mirror.proxies_of(door)[0]
	var parts := mesh.find_children("*", "GeometryInstance3D", true, false)
	if not t.require(not parts.is_empty(), "the door's mesh has instances"):
		return
	var box := AABB()
	for i in parts.size():
		var part := parts[i] as GeometryInstance3D
		var world_box: AABB = part.global_transform * part.get_aabb()
		box = world_box if i == 0 else box.merge(world_box)
	var marker := Node2D.new()
	var depth := absf(back.x) * box.size.x * 0.5 + absf(back.y) * box.size.z * 0.5
	marker.position = Vector2(box.get_center().x, box.get_center().z) - back * (depth + DOOR_GAP)
	_world.add_child(marker)
	_stand_in.targets = [marker]
	await t.seconds(0.8)
	t.check(
		parts.all(func(p: Node) -> bool: return Probe.level(p) < 0.5),
		"a door between the camera and a character fades with all its parts",
	)
	_stand_in.targets = []
	await t.seconds(0.8)
	t.check(
		parts.all(func(p: Node) -> bool: return Probe.level(p) > 0.99),
		"and is whole when it leaves",
	)
	marker.queue_free()


## The sim's camera, spectating, names every combatant; following, the player.
func _spectating_names_the_combatants(t: TestContext, camera: Camera2D) -> void:
	var named: Array = camera.call(&"focus_targets")
	t.expect_eq(named.size(), 4, "spectating: the camera names every combatant")
	t.check(
		named.all(func(c): return c is Node2D and c.is_in_group(&"characters")),
		"and they are characters",
	)
	var following := Camera2D.new()
	following.set_script(CameraScript)
	var player := Node2D.new()
	player.name = "Player"
	var parent := Node.new()
	parent.add_child(player)
	parent.add_child(following)
	t.world.add_child(parent)
	var alone: Array = following.call(&"focus_targets")
	t.expect_eq(alone, [player], "following: the camera names the player")
	parent.queue_free()


## A marker (a stand-in character) on the far side of `wall`'s segment from the camera, close
## behind it; added to the wall's record.
func _stand_behind(t: TestContext, wall: Dictionary, back: Vector2) -> Dictionary:
	var marker := Node2D.new()
	marker.position = Probe.behind(wall, back, STANDOFF)
	t.world.add_child(marker)
	wall["marker"] = marker
	return wall


## Hits on the faded segment rebuild it; the instance that replaces it is faded the frame it comes.
func _hit_keeps_the_fade(t: TestContext, wall: Dictionary) -> void:
	var body: Node = wall["body"]
	var mesh: Node3D = wall["mesh"]
	var before: int = mesh.rebuilds
	var old: Node = (mesh.call(&"segments") as Dictionary)[wall["index"]]
	var at: Vector2 = wall["centre"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for volley in 4:
		for k in 5:
			var hit := HitInfo.new()
			hit.position = at + Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-3.0, 3.0))
			hit.normal = Vector2.DOWN
			hit.direction = Vector2.UP
			hit.damage = rng.randf_range(20.0, 40.0)
			hit.speed_factor = 1.0
			body.take_hit(hit)
		await t.frames(1)
	var waited := 0
	while mesh.rebuilds == before and waited < 60:
		await t.frames(1)
		waited += 1
	if not t.require(mesh.rebuilds > before, "premise: the hits rebuilt a segment"):
		return
	var part: Node = (mesh.call(&"segments") as Dictionary).get(wall["index"])
	if not t.require(part != null and part != old, "premise: the hit segment is a new instance"):
		return
	t.check(
		Probe.level(part) < 0.5,
		"the rebuilt segment is faded as it comes (%f)" % Probe.level(part),
	)
	wall["part"] = part


## What the fade's camera is: it names the nodes to look after.
class Source extends Node:
	var targets: Array[Node2D] = []

	func focus_targets() -> Array[Node2D]:
		return targets
