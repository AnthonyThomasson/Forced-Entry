extends GameTest
## The pixel post in Main's 3D view (#193 rule 6, interface 27): in the 3D render mode the scene is
## drawn at a low internal resolution, 216 lines at the reference window of 1152x648 (3x), and
## shown with nearest filtering so each internal pixel is about 3 screen pixels at any window
## size; the picture keeps covering the whole window; the outline pass is a quad under the
## camera that takes its widths from `PixelPostConfig`. With `supersample` 2 the 3D picture is
## rendered at twice its size and averaged down (a linear stage) before the nearest upscale.
## Expected numbers are the spec's: 216 lines and a 3 px pixel at 648 high, hence 432 lines at
## 1296, a 16:9 picture 384 wide plus the one-pixel margin all round. Headless proves the wiring,
## not the look (`general/render_3d_match_windowed` draws it).

const MainProbe := preload("res://tests/_main/main_probe.gd")
const SCRATCH := "user://settings_pixel_post_view_test.json"
const SPEC := {
	"seed": 2,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}
const REFERENCE := Vector2i(1152, 648)
const BIG := Vector2i(2304, 1296)


func describe() -> Dictionary:
	return {
		"name": "The 3D view renders at the internal resolution and upscales with nearest",
		"description": "216 lines at 1152x648 (432 at 2304x1296), a nearest-filtered picture "
			+ "covering the window at ~3 px a pixel, the outline quad under the camera from "
			+ "PixelPostConfig, and the supersampled chain when it is on.",
		"tags": ["render", "3d", "pixel", "settings"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.set_static(PixelPostConfig, &"supersample", 1)
	s.set_static(PixelPostConfig, &"silhouette_px", PixelPostConfig.silhouette_px)
	s.von_script([])


func run(t: TestContext) -> void:
	var view := await _start(t, REFERENCE)
	if not t.require(view != null, "a 3D match started"):
		return
	t.expect_eq(view.viewport.size, Vector2i(386, 218), "1152x648: 216 lines plus the margin")
	_check_shown(t, view, REFERENCE, 3.0)
	_check_outline(t, view)
	var big := await _start(t, BIG)
	if not t.require(big != null, "a 3D match started in a bigger window"):
		return
	t.expect_eq(big.viewport.size, Vector2i(770, 434), "2304x1296: 432 lines plus the margin")
	_check_shown(t, big, BIG, 3.0)
	PixelPostConfig.supersample = 2
	var fine := await _start(t, REFERENCE)
	if not t.require(fine != null, "a 3D match started with the supersample on"):
		return
	t.expect_eq(
		fine.viewport.size,
		Vector2i(772, 436),
		"supersample 2: the 3D picture is twice as large",
	)
	t.expect_eq(fine.shown.size, Vector2i(386, 218), "averaged down to the internal size")
	t.check(fine.shown != fine.viewport, "the nearest-shown picture is the averaged one")
	_check_shown(t, fine, REFERENCE, 3.0)
	# A window resize reaches the averaging stage in the same frame as the 3D picture: a stage a
	# frame behind would sample it off the exact two-to-one and blur it.
	var window := fine.get_viewport() as SubViewport
	window.size = Vector2i(1152, 864)
	await t.frames(1)
	t.expect_eq(
		fine.viewport.size, fine.shown.size * 2, "after a resize the stage is half the 3D picture"
	)
	var linear := false
	for child in fine.shown.get_children():
		if child is TextureRect and (child as TextureRect).texture == fine.viewport.get_texture():
			linear = (child as TextureRect).texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST
	t.check(linear, "the 3D picture is averaged down through a filtered stage")


## A 3D match in a Main whose window is `size`; the 3D view once its picture is sized, or null.
func _start(t: TestContext, size: Vector2i) -> Node:
	for old in t.world.find_children("MainViewport", "SubViewport", false, false):
		await MainProbe.close(t, old)
	var window := MainProbe.viewport(t)
	window.size = size
	var main := MainProbe.open(window)
	MainProbe.setup_menu(main).queue_free()
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	main.add_child(camera)
	var built: Dictionary = await main.start_match(SPEC.duplicate(true))
	if built.is_empty():
		return null
	await t.frames(4)
	return main.get_node_or_null("View3D")


## The picture is nearest-filtered, covers the window and each internal pixel is `px` screen pixels.
func _check_shown(t: TestContext, view: Node, window: Vector2i, px: float) -> void:
	var rect: TextureRect = view.rect
	t.expect_eq(rect.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "shown with nearest")
	t.check(
		rect.position.x <= 0.0 and rect.position.y <= 0.0
		and rect.position.x + rect.size.x >= float(window.x)
		and rect.position.y + rect.size.y >= float(window.y),
		"the picture covers the window (%s at %s)" % [rect.size, rect.position],
	)
	var shown: Vector2 = rect.size / Vector2(view.shown.size)
	t.expect_near(shown.x, px, 0.01, "%.2f screen px across an internal pixel" % shown.x)
	t.expect_near(shown.y, px, 0.01, "%.2f screen px down an internal pixel" % shown.y)


## The outline pass: a quad under the 3D camera whose widths are the holder's.
func _check_outline(t: TestContext, view: Node) -> void:
	var quad := view.rig.camera.get_node_or_null(PixelPost.NODE) as MeshInstance3D
	if not t.require(quad != null, "the outline quad is under the camera"):
		return
	var material := quad.material_override as ShaderMaterial
	t.expect_eq(material.get_shader_parameter(&"silhouette_px"), 1.0, "a 1 px silhouette outline")
	t.expect_eq(material.get_shader_parameter(&"crease_px"), 1.0, "a 1 px crease outline")
