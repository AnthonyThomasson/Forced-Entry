extends GameTest
## The 3D view draws the picture at `PixelPostConfig.supersample` at rest and at `turn_supersample`
## only while a quarter turn is under way (#193 phase 2b, M1): the cost of the 2x picture is paid
## for the turn, about 0.4 s, not all the time. Main's `View3D` on its own in a window: at rest the
## 3D viewport is the picture's size and shown directly; pressing E turns the camera and for the
## turn the viewport is twice the picture, averaged down through the stage with the outline's widths
## doubled; at the end it is back, at once with the yaw landing on its cardinal.

const ViewScript := preload("res://scenes/main_view3d.gd")


func describe() -> Dictionary:
	return {
		"name": "The supersample is paid only while the camera turns",
		"description": "At rest the 3D viewport is the picture's size and shown directly; during a "
			+ "quarter turn it is twice that, through the averaging stage, the outline widened; "
			+ "after the turn it is back.",
		"tags": ["render", "3d", "pixel", "camera"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])
	s.set_static(PixelPostConfig, &"supersample", 1)
	s.set_static(PixelPostConfig, &"turn_supersample", 2)
	s.set_static(PixelPostConfig, &"silhouette_px", 1.0)


func run(t: TestContext) -> void:
	var window := SubViewport.new()
	window.size = Vector2i(640, 360)
	window.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(window)
	var camera := Camera2D.new()
	window.add_child(camera)
	camera.make_current()
	var view: CanvasLayer = ViewScript.new()
	window.add_child(view)
	view.begin(camera)
	await t.frames(5)
	var picture: Vector2i = view.rig.internal_size()
	t.expect_eq(view.viewport.size, picture, "at rest the 3D viewport is the picture's size")
	t.check(view.shown == view.viewport, "and it is shown directly")
	t.expect_eq(_silhouette(view), 1.0, "with the outline's own width")

	Input.action_press("camera_turn_right")
	await t.frames(3)
	Input.action_release("camera_turn_right")
	await t.frames(2)
	t.check(view.rig.turning(), "premise: the camera is turning")
	t.expect_eq(view.viewport.size, picture * 2, "turning, the viewport is twice the picture")
	t.check(view.shown != view.viewport, "shown through the averaging stage")
	t.expect_eq(view.shown.size, picture, "which is the picture's size")
	t.expect_eq(_silhouette(view), 2.0, "the outline is twice as wide in drawn pixels")
	await t.seconds(1.0)
	t.expect_near(view.rig.yaw, 90.0, 0.001, "the turn ended on east")
	t.expect_eq(view.viewport.size, picture, "after it the viewport is the picture's size again")
	t.check(view.shown == view.viewport, "shown directly again")
	t.expect_eq(_silhouette(view), 1.0, "and the outline is back")


## The outline's silhouette width as the shader has it.
func _silhouette(view: CanvasLayer) -> float:
	var quad := view.rig.camera.get_node(PixelPost.NODE) as MeshInstance3D
	return (quad.material_override as ShaderMaterial).get_shader_parameter(&"silhouette_px")
