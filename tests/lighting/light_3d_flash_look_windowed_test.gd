extends GameTest
## #193 phase 3 (L9 in 3D, windowed only: the headless renderer draws nothing and compiles no
## shader): the flashes as they look. A grey floor of one room under a camera in a window, lit by
## the ambient alone:
##   - a `shot` lights the floor round its muzzle warm and brighter than the ambient, a pool that
##     ends within its reach, and the floor is the ambient's again once the flash is dark;
##   - a stun's `explosion` washes the floor round it white (every channel near 1), far past what
##     the toon cap allows a lamp, and the cap is back, the floor the ambient's, once it is dark.
## Run: `tools/run_tests.sh --windowed --id=lighting/light_3d_flash_look_windowed`. With
## `LIGHT_SHOT=<dir>` set it saves the pictures.

const SIZE := 512
const HALF := 256.0
const GROUND := Color(0.6, 0.6, 0.6)
const ROOM := Rect2(-HALF, -HALF, HALF * 2.0, HALF * 2.0)
const MUZZLE := Vector2(-200.0, 0.0)
## Far from the muzzle and from the dark lamp, in the room's corner.
const CORNER := Vector2(200.0, 200.0)


func describe() -> Dictionary:
	return {
		"name": "A 3D flash lights its room warm and a stun washes it white (windowed)",
		"description": "A shot lights the floor round its muzzle warm and brighter than the "
			+ "ambient, then it is the ambient again; a stun washes the floor round it white and "
			+ "restores the toon cap when dark. Windowed only.",
		"tags": ["lighting", "3d", "render", "windowed", "flash"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(RenderConfig, &"unit", 1.0)


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	var view := _scene(t)
	await _settle(t)
	var ambient := _linear(view, CORNER)
	t.check(
		absf(ambient.r - GROUND.srgb_to_linear().r * LightingConfig.ambient_color.r) < 0.02,
		"the floor is the art times the ambient before a flash (%s)" % ambient,
	)
	EventBus.post(&"shot", { "position": MUZZLE })
	await _settle(t, 1)
	_check_shot(t, view, ambient)
	await t.seconds(0.4)
	await _settle(t)
	var after := _linear(view, MUZZLE + Vector2(10.0, 0.0))
	t.check(
		absf(after.get_luminance() - ambient.get_luminance()) < ambient.get_luminance() * 0.1,
		"once dark the floor is the ambient's again (%s)" % after,
	)
	EventBus.post(&"explosion", { "position": Vector2.ZERO, "kind": &"stun", "radius": 200.0 })
	await _settle(t, 1)
	var white := _linear(view, Vector2(20.0, 20.0))
	_save(view, "stun")
	t.check(
		minf(white.r, minf(white.g, white.b)) > 0.85,
		"a stun washes the floor round it white (%s)" % white,
	)
	t.check(ToonLight.cap() > ToonLightConfig.cap + 4.0, "the toon cap is lifted for it")
	await t.seconds(1.2)
	await _settle(t)
	var end := _linear(view, CORNER)
	t.check(
		absf(end.get_luminance() - ambient.get_luminance()) < ambient.get_luminance() * 0.1
			and is_equal_approx(ToonLight.cap(), ToonLightConfig.cap),
		"and once it is dark the floor and the cap are as before (%s)" % end,
	)


## A shot's flash: warm and brighter than the ambient at the muzzle, the ambient past its reach.
func _check_shot(t: TestContext, view: SubViewport, ambient: Color) -> void:
	_save(view, "shot")
	var near := _linear(view, MUZZLE + Vector2(10.0, 0.0))
	t.check(
		near.get_luminance() > ambient.get_luminance() * 1.5,
		"a shot lights the floor at its muzzle (%s, ambient %s)" % [near, ambient],
	)
	t.check(near.r / near.b > ambient.r / ambient.b * 1.3, "warm, in the shot's colour")
	var reach: float = (
		float(LightingConfig.flashes[&"shot"]["reach"]) * 0.5 * Lighting3DConfig.range_scale
	)
	var past := _linear(view, MUZZLE + Vector2(reach + 10.0, 0.0))
	t.check(
		absf(past.get_luminance() - ambient.get_luminance()) < ambient.get_luminance() * 0.1,
		"and the floor past its reach is the ambient's (%s)" % past,
	)


## Draw the viewport on demand (a covered window never draws).
func _settle(t: TestContext, frames := 3) -> void:
	await t.frames(frames)
	RenderingServer.force_draw(false)


## Save the picture `<LIGHT_SHOT>/flash_<name>.png` when `LIGHT_SHOT` names a folder.
func _save(view: SubViewport, name: String) -> void:
	var dir := OS.get_environment("LIGHT_SHOT")
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
		view.get_texture().get_image().save_png("%s/flash_%s.png" % [dir, name])


## Linear colour of the picture at ground point `at` (px from the middle, x and z).
func _linear(view: SubViewport, at: Vector2) -> Color:
	return view.get_texture().get_image().get_pixel(
		int(HALF + at.x), int(HALF + at.y)
	).srgb_to_linear()


## The viewport of the scene: a ground and a room whose own light is off, a camera, under the dusk.
func _scene(t: TestContext) -> SubViewport:
	var world := Node2D.new()
	t.world.add_child(world)
	world.add_child(FakeFloor.new(ROOM))
	var dark := FakeLamp.new()  # the room's own light, off: the room is lit, so it gets no fixture
	dark.position = Vector2(HALF - 8.0, -HALF + 8.0)
	world.add_child(dark)
	var view := SubViewport.new()
	view.size = Vector2i(SIZE, SIZE)
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(view)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(SIZE)
	camera.near = 1.0
	camera.far = 700.0
	camera.position = Vector3(0, 400, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	view.add_child(camera)
	var ground := MeshKit.new().box(MeshKit.volume(ROOM, -2.0, 2.0), GROUND).build()
	view.add_child(MeshNodes.instance(ground))
	WorldLighting3D.light(view, world, 1, [{ "key": "room", "rect": ROOM }])
	return view


## A floor of the fake world: the Lighting domain reads its `size`.
class FakeFloor:
	extends Node2D
	var size := Vector2.ZERO

	func _init(rect: Rect2) -> void:
		position = rect.position
		size = rect.size
		add_to_group(&"floors")

	func is_street() -> bool:
		return false


## A piece that gives one light, off.
class FakeLamp:
	extends Node2D

	func get_lights() -> Array:
		return [
			{
				"offset": Vector2.ZERO,
				"colour": Color.WHITE,
				"energy": 0.0,
				"radius": 1.0,
				"shape": &"round",
				"rhythm": [],
				"room_light": true,
				"street": false,
				"height": &"overhead",
				"glow": null,
			},
		]
