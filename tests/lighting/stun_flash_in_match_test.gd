extends GameTest
## #193 phase 3, L9 in 3D (the picture is read only windowed: the headless renderer draws nothing
## and compiles no shader): a stun that goes off in a real Main match in the 3D render mode (not a
## test world's own lighting) shows its flash. Main's own view and lights (`View3D.lighting`, the
## camera's focus and zoom), the stun's own burst (`Explosion.stun` with the grenade's
## `GrenadeConfig` row, as a thrown stun calls it, posting `&"explosion"` on the bus): a flash light
## is lit where it burst, a white-out to the toon light, whether the burst is near the camera's
## centre or on the far side of the view, at zoom 1 and 0.5 and with shots firing; the picture the
## view shows then is whiter
## than before. A burst nobody can see (several screens away) takes no flash.
## Run: `tools/run_tests.sh --windowed --id=lighting/stun_flash_in_match`; with
## `STUN_SHOTS=<dir>` set it saves each burst's picture.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_stun_flash_in_match_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"defenders": { "count": 2 },
	"invaders": { "count": 2 },
}
## How much brighter (mean of the picture's channels) the picture is while the stun's white-out
## holds.
const WHITER := 0.02
## Frames a flash may take to be lit after the burst, and frames to hold before the picture is read.
const LIT_WITHIN := 3
const HOLD_FRAMES := 2

var _main: Node
var _camera: Camera2D
var _window: SubViewport
var _view: Node
var _world: Node2D


func describe() -> Dictionary:
	return {
		"name": "A stun in a real 3D match shows its flash, near and far, at zoom 1 and 0.5",
		"description": "In a Main match in 3D: the stun's burst lights a white-out flash light "
			+ "where it goes off and whitens the picture, near the camera's middle and on the "
			+ "far side of the view, at zoom 1 and 0.5, with shots firing; a burst several "
			+ "screens away takes none. The picture is read only windowed.",
		"tags": ["lighting", "3d", "render", "stun", "flash"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	if not await _start(t):
		return
	var lighting: WorldLighting3D = _view.lighting
	if not t.require(lighting != null, "Main lit the 3D world"):
		return
	for zoom: float in [1.0, 0.5]:
		_camera.zoom = Vector2(zoom, zoom)
		await t.frames(20)
		var middle := _camera.get_screen_center_position()
		var half := Vector2(SIZE) * 0.5 / zoom
		await _burst(t, lighting, "near at zoom %s" % zoom, middle + Vector2(60.0, 40.0), true)
		await _burst(t, lighting, "far side at zoom %s" % zoom, middle + half * 0.8, true)
		await _burst(t, lighting, "in a corner at zoom %s" % zoom, middle - half * 0.95, true)
	await _burst(t, lighting, "several screens away", _camera.get_screen_center_position()
		+ Vector2(6000.0, 6000.0), false)
	await MainProbe.close(t, _window)


## The window and the match: Main's own 3D view, a Watch match.
func _start(t: TestContext) -> bool:
	_window = SubViewport.new()
	_window.size = SIZE
	_window.world_2d = World2D.new()
	_window.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(_window)
	_main = MainProbe.open(_window)
	MainProbe.setup_menu(_main).queue_free()
	_camera = Camera2D.new()
	_camera.name = "MainCamera"
	_camera.set_script(CameraScript)
	_main.add_child(_camera)
	_camera.make_current()
	var built: Dictionary = await _main.start_match(SPEC.duplicate(true))
	if not t.require(not built.is_empty(), "a Watch match started in 3D"):
		return false
	_camera.set_process(false)  # the zoom and place are the test's
	_camera.set_physics_process(false)
	_world = built["world"]
	_view = _main.get_node_or_null("View3D")
	if not t.require(_view != null, "Main built the 3D view"):
		return false
	await t.frames(60)
	return true


## A stun goes off at `at` (the grenade's own call): the flash is lit there (`lit`), whitens the
## picture, and a burst out of sight takes none.
func _burst(
	t: TestContext, lighting: WorldLighting3D, label: String, at: Vector2, lit: bool
) -> void:
	await t.frames(60)  # the last flash is gone
	var windowed := DisplayServer.get_name() != "headless"
	var before: Image = await _picture(t) if windowed else null
	_shoot(at)
	Explosion.stun(at, _world, null, GrenadeConfig.row(&"stun"))
	var flash: OmniLight3D = null
	for _i in LIT_WITHIN:
		flash = Probe.flash_at(lighting, at)
		if flash != null:
			break
		await t.frames(1)
	if not lit:
		t.check(flash == null, "%s: no flash is spent on a burst nobody sees" % label)
		return
	if not t.require(flash != null, "%s: a flash is lit where the stun went off" % label):
		return
	t.expect_eq(Probe.flash_kind(flash), 2, "%s: it is a white-out to the toon light" % label)
	await t.frames(HOLD_FRAMES)
	if not windowed:
		return
	var during := await _picture(t)
	_save(during, label)
	t.check(
		_white(during) - _white(before) >= WHITER,
		"%s: the picture whitens while it holds (%.3f to %.3f of it white)" % [
			label, _white(before), _white(during),
		],
	)


## Fire a shot's flash beside `at` (the bus's `shot`, as a gun posts it), so the pool is busy.
func _shoot(at: Vector2) -> void:
	for k in 3:
		EventBus.post(
			&"shot",
			{ "position": at + Vector2(90.0 + 30.0 * k, 60.0), "attacker": null },
		)


## The picture the window shows now.
func _picture(t: TestContext) -> Image:
	await t.frames(2)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	return _window.get_texture().get_image()


## The share of the picture (on a grid of samples) that is near white.
func _white(image: Image) -> float:
	var white := 0
	var n := 0
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8):
			var c := image.get_pixel(x, y)
			n += 1
			if minf(c.r, minf(c.g, c.b)) > 0.85:
				white += 1
	return float(white) / float(maxi(n, 1))


func _save(image: Image, label: String) -> void:
	var dir := OS.get_environment("STUN_SHOTS")
	if dir == "":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	image.save_png("%s/%s.png" % [dir, label.replace(" ", "_")])
