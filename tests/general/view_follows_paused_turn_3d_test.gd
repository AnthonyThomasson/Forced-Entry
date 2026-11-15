extends GameTest
## The player's view keeps up with a camera that turns while the tree is paused (#193 turn-ctl):
## the command menu and the spectator inspector pause the tree, the camera rig keeps turning on Q /
## E (it runs while paused), and the view's cone mask, memory and composite are placed by the same
## camera each frame, so they must keep running through the pause or the cone and the dim would stay
## where the camera was. Main is run whole over a played 3D match; the tree is paused and E is held;
## the composite's screen-to-world matrix then still is the one of the camera as it now stands
## (the inverse of the ground-to-screen affine the ground layer wears).

const MainProbe := preload("res://tests/_main/main_probe.gd")
const SCRATCH := "user://settings_view_paused_turn_test.json"
const SPEC := {
	"seed": 3,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}
## Frames E is held while paused (about half a second: a 45 degree turn).
const PAUSED_FRAMES := 30


func describe() -> Dictionary:
	return {
		"name": "The 3D view's cone and dim follow a camera that turns while the tree is paused",
		"description": "A played 3D match, the tree paused (a menu open) and E held: the camera "
			+ "turns, and the view's composite is repositioned for the new yaw, not left where "
			+ "the pause found it.",
		"tags": ["render", "3d", "vision", "pause"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_2D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.set_static(GroundLayer, &"enabled", false)
	s.switch(&"vision.enabled", true)
	s.von_script([])


func run(t: TestContext) -> void:
	var viewport := MainProbe.viewport(t)
	var main := MainProbe.open(viewport)
	var built := await _play(main)
	if not t.require(not built.is_empty(), "premise: a played match started in 3D"):
		await MainProbe.close(t, viewport)
		return
	var view: Node = built["world"].find_child("PlayerView", true, false)
	var rig: CameraRig = main.get_node("View3D").rig
	await t.frames(10)
	var composite := view.get_node("GroundVision/Composite") as CanvasItem
	var before := rig.yaw
	await _turn_while_paused(t, main.get_tree())
	t.check(
		absf(wrapf(rig.yaw - before, -180.0, 180.0)) > 10.0,
		"premise: the camera turned while the tree was paused (%s -> %s)" % [before, rig.yaw],
	)
	var cam := Pointer.screen_transform(view).affine_inverse()
	var seen: Vector2 = (composite.material as ShaderMaterial).get_shader_parameter("inv_x")
	t.check(
		seen.distance_to(cam.x) < 0.0005,
		"the composite is placed for the turned camera (%s, the camera's %s)" % [seen, cam.x],
	)
	await MainProbe.close(t, viewport)


## Main with a camera, and a played match in 3D started in it.
func _play(main: Node) -> Dictionary:
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	camera.position = Vector2(300.0, 200.0)
	main.add_child(camera)
	camera.make_current()
	var spec := SPEC.duplicate(true)
	spec["render"] = "3d"
	spec["human"] = { "node": main.get_node("Player"), "side": &"invader", "lead": false }
	return await main.start_match(spec)


## Pause the tree (a menu is open) and hold E for a while, then unpause.
func _turn_while_paused(t: TestContext, tree: SceneTree) -> void:
	tree.paused = true
	Input.action_press("camera_turn_right")
	await t.frames(PAUSED_FRAMES)
	Input.action_release("camera_turn_right")
	await t.frames(2)
	tree.paused = false
