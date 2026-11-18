extends GameTest
## The player's aim skips what the wall fade holds faded (#194 N1, interfaces 26 and 27): the fade
## dithers only the MESH, the twin stays solid, so without this the cursor over floor seen through a
## faded wall or tall piece would aim at the wall's face (D8a) and the shot would fly up from the
## muzzle at it. The fade (Art) tells General's `FadedTwins` which twins it holds faded; `aim_hit`
## (General) looks through them. A piece (a wardrobe) and a wall segment (the arena's east wall) are
## both held: the cursor over the floor behind each aims level (an empty answer) while faded, and
## at the face (cover) while whole, before the fade and once the focus leaves.

const RigProbe := preload("res://tests/_general/rig_probe.gd")
const WARDROBE_AT := Vector2(700, 150)
## How far (px) the floor point is from the face it is behind: at 45 degrees the cursor's line is
## that high where it meets the face.
const GAP := 10.0
const STEP := 0.05
const ARENA := Rect2(0, 0, 1000, 500)
## The plan direction the line of sight runs at yaw 90 (the camera is on the +x side).
const RUN := Vector2(-1.0, 0.0)

## The camera's line of sight, once the rig is open.
var _look := Vector3.ZERO


func describe() -> Dictionary:
	return {
		"name": "The cursor aims through a wall or piece the fade holds faded, at it when whole",
		"description": "With the wall fade holding a wardrobe or a wall segment faded, the cursor "
			+ "over the floor behind it meets nothing (the shot flies level); whole, before the "
			+ "fade and after the focus leaves, it meets the face.",
		"tags": ["pointer", "3d", "aim", "twins", "wall-fade"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])
	s.arena(ARENA)
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"pitch_degrees", 45.0)
	s.actor(&"you", &"player", Vector2(300, 250))
	s.object(&"wardrobe", "wardrobe", WARDROBE_AT)


func run(t: TestContext) -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(300, 250)
	t.world.add_child(camera)
	camera.make_current()
	var rig := RigProbe.open(t.world, camera, 90.0)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	var fade := WallFade.new()
	view.add_child(mirror)
	view.add_child(fade)
	fade.set_process(false)
	fade.listen(mirror)
	ObjectMeshes.register(mirror.builders)
	mirror.mirror(t.world)
	await t.frames(4)
	var you := t.actor(&"you")
	var parts := _parts_of(mirror, t.object(&"wardrobe"))
	t.require(not parts.is_empty(), "premise: the wardrobe is shown by a mesh")
	_look = -rig.camera.global_transform.basis.z
	t.require(
		Vector2(_look.x, _look.z).normalized().is_equal_approx(RUN),
		"premise: at yaw 90 the line of sight runs along -x",
	)
	var behind := Vector2(WARDROBE_AT.x - _half_width(parts) - GAP, WARDROBE_AT.y)
	await _check(t, you, fade, behind, "a wardrobe")
	var wall_face := Vector2(ARENA.end.x - GAP, 250.0)
	await _check(t, you, fade, wall_face, "the east wall")
	await _check_fade_gone(t, you, fade, wall_face)


## The cursor over `floor_point`, just behind a face the camera sees (a piece or the wall): whole it
## meets that face, held faded it meets nothing and the player aims level, whole again once the
## focus leaves.
func _check(
	t: TestContext, you: Node, fade: WallFade, floor_point: Vector2, what: String
) -> void:
	_run(fade, [])
	Pointer.inject(_screen_over(you, PlanSpace.lift(floor_point)))
	await t.frames(2)
	var whole := Pointer.aim_hit(you, you)
	t.expect_eq(whole.get("kind"), &"cover", "%s, whole, is aimed at (%s)" % [what, whole])
	_run(fade, [floor_point])
	t.check(fade.fading > 0, "premise: the fade holds something faded for the focus")
	await t.frames(2)
	var through := Pointer.aim_hit(you, you)
	t.check(through.is_empty(), "%s, held faded, is looked through (%s)" % [what, through])
	t.expect_eq(you.movement.aim_height, CharacterMovement.AIM_LEVEL, "so the player aims level")
	_run(fade, [])
	await t.frames(2)
	var back := Pointer.aim_hit(you, you)
	t.expect_eq(back.get("kind"), &"cover", "%s, whole again, is aimed at (%s)" % [what, back])


## The fade goes (its meshes stay: the view is rebuilt over live bodies) while it holds the wall
## faded: the wall is solid again at once (a held entry that outlived its fade would be looked
## through for good).
func _check_fade_gone(
	t: TestContext, you: Node, fade: WallFade, floor_point: Vector2
) -> void:
	_run(fade, [floor_point])
	await t.frames(2)
	t.check(Pointer.aim_hit(you, you).is_empty(), "premise: the wall is held faded")
	fade.free()
	await t.frames(2)
	var kept := Pointer.aim_hit(you, you)
	t.expect_eq(
		kept.get("kind"),
		&"cover",
		"the wall is aimed at once its fade is gone (%s)" % kept,
	)


func _run(fade: WallFade, foci: Array) -> void:
	for i in 14:
		fade.step(STEP, 90.0, PackedVector2Array(foci))


func _parts_of(mirror: WorldMirror, body: Node) -> Array:
	var parts: Array = []
	for mesh: Node3D in mirror.proxies_of(body):
		if mesh is GeometryInstance3D:
			parts.append(mesh)
		parts.append_array(mesh.find_children("*", "GeometryInstance3D", true, false))
	return parts


## Half the extent along x of the instances together.
func _half_width(parts: Array) -> float:
	var box := AABB()
	for i in parts.size():
		var part := parts[i] as GeometryInstance3D
		var world_box: AABB = part.global_transform * part.get_aabb()
		box = world_box if i == 0 else box.merge(world_box)
	return box.size.x * 0.5


func _screen_over(node: Node, through: Vector3) -> Vector2:
	var ground := through + _look * (-through.y / _look.y)
	return Pointer.screen_of(node, PlanSpace.plan_of(ground))
