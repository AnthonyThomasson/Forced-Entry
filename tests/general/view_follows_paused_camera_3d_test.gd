extends GameTest
## The player's view keeps up with a camera that moves while the tree is paused (#193 turn-ctl,
## vision-mask): the command menu and the spectator inspector pause the tree, the camera rig keeps
## following the sim's camera (it runs while paused), and the view's live mask is a window of the
## world about that camera, laid again when the camera drifts out of it, so the view must keep
## running through the pause or the cone's light would stop at the old window's edge. Main is run
## whole over a played 3D match; the tree is paused and the camera is moved far off; the window then
## covers where the camera now is.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const Ground := preload("res://scenes/vision/view_ground.gd")
const SCRATCH := "user://settings_view_paused_turn_test.json"
const SPEC := {
	"seed": 3,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}
## Where the camera is moved to while paused, far past any window about where it was.
const FAR := Vector2(9000.0, 200.0)
## Frames the tree stays paused.
const PAUSED_FRAMES := 10


func describe() -> Dictionary:
	return {
		"name": "The 3D view's live mask follows a camera that moves while the tree is paused",
		"description": "A played 3D match, the tree paused (a menu open) and the camera moved "
			+ "far off: the view's live window is laid about where the camera now is, not "
			+ "left where the pause found it.",
		"tags": ["render", "3d", "vision", "pause"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.switch(&"vision.enabled", true)
	s.von_script([])


func run(t: TestContext) -> void:
	var viewport := MainProbe.viewport(t)
	var main := MainProbe.open(viewport)
	var built := await _play(main)
	if not t.require(not built.is_empty(), "premise: a played match started in 3D"):
		await MainProbe.close(t, viewport)
		return
	var view: PlayerView = built["world"].find_child("PlayerView", true, false)
	var camera: Camera2D = main.get_node("MainCamera")
	await t.frames(10)
	var ground: Ground = view.ground
	if not t.require(ground != null, "premise: the view is the 3D one"):
		await MainProbe.close(t, viewport)
		return
	t.check(ground.window.has_point(camera.position), "premise: the window covers the camera")
	var anchors: int = ground.counts["anchors"]
	main.get_tree().paused = true
	camera.position = FAR
	await t.frames(PAUSED_FRAMES)
	t.check(
		ground.window.has_point(FAR),
		"the window follows the camera moved while paused (%s, camera at %s)" % [
			ground.window,
			FAR,
		],
	)
	t.check(ground.counts["anchors"] > anchors, "it was laid again")
	main.get_tree().paused = false
	await MainProbe.close(t, viewport)


## Main with a camera, and a played match in 3D started in it.
func _play(main: Node) -> Dictionary:
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	camera.position = Vector2(300.0, 200.0)
	main.add_child(camera)
	camera.make_current()
	var spec := SPEC.duplicate(true)
	spec["human"] = { "node": main.get_node("Player"), "side": &"invader", "lead": false }
	return await main.start_match(spec)
