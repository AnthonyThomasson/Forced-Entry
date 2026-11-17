extends GameTest
## #193 phase 3 (L9 in 3D, windowed only: the headless renderer draws nothing and compiles no
## shader): the flashes as they look. A grey floor of one big room under a camera in a window, lit
## by
## the ambient, with a striped plank floor on its left and two overlapping lamp pools on its right:
##   - a `shot` lights the floor round its muzzle warm and brighter than the ambient, a pool that
##     ends within its reach, and the floor is the ambient's again once the flash is dark;
##   - a stun's `explosion` whites out what it reaches: flat white (every channel near 1) with the
##     plank stripes gone, over a whole region and not one pixel, while two overlapping lamp pools
##     and the ambient far from it keep their colour (the flash touches no global);
##   - a stun in a spot the vision mask leaves unseen changes no pixel of the picture.
## Run: `tools/run_tests.sh --windowed --id=lighting/light_3d_flash_look_windowed`. With
## `LIGHT_SHOT=<dir>` set it saves the pictures.

const SIZE := 512
const HALF := 256.0
const GROUND := Color(0.6, 0.6, 0.6)
const ROOM := Rect2(-640.0, -HALF, 1280.0, HALF * 2.0)
const PLANKS := Rect2(-HALF, -128.0, 150.0, 256.0)
const MUZZLE := Vector2(-200.0, -180.0)
const STUN_AT := Vector2(-300.0, 0.0)
## Far from the muzzle, the stun and the lamps: the room's top right corner.
const CORNER := Vector2(200.0, -200.0)
## Where two lamps' pools overlap, out of the stun's reach (455 px from it).
const LAMPS := Vector2(205.0, 100.0)
## A grid inside the planks and the stun's reach, over stripes.
const WHITE_GRID := [Vector2(-240.0, -100.0), Vector2(-120.0, 100.0)]
const GRID_STEPS := Vector2i(7, 9)
## The most the grid's channels may differ over the white-out, and the least any may be.
const FLAT := 0.05
const WHITE := 0.93
## What counts as no change in a pixel's channel.
const SAME := 0.02


func describe() -> Dictionary:
	return {
		"name": "A 3D flash lights its room warm and a stun whites it out flat (windowed)",
		"description": "A shot lights the floor round its muzzle warm and brighter than the "
			+ "ambient, then it is the ambient again; a stun whites out a striped floor flat "
			+ "over a region, leaves two lamp pools far from it and a stun in an unseen spot "
			+ "unchanged. Windowed only.",
		"tags": ["lighting", "3d", "render", "windowed", "flash"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()  # it builds its own view and reads its pixels
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(RenderConfig, &"unit", 1.0)


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	var view := _scene(t)
	await _settle(t)
	var ambient := _linear(view, CORNER)
	var lamps := _linear(view, LAMPS)
	var planks := _linear(view, Vector2(-180.0, 0.0))
	var dusk := ToonLight.shader_ambient(LightingConfig.ambient_color, ToonLightConfig.ambient_gain)
	t.check(
		absf(ambient.r - GROUND.srgb_to_linear().r * dusk.r) < 0.02,
		"the floor is the art times the ambient before a flash (%s)" % ambient,
	)
	EventBus.post(&"shot", { "position": MUZZLE })
	await _settle(t, 1)
	_check_shot(t, view, ambient)
	await t.seconds(0.4)
	await _settle(t)
	t.check(_same(_linear(view, MUZZLE + Vector2(10.0, 0.0)), ambient), "dark again: the ambient")
	EventBus.post(&"explosion", { "position": STUN_AT, "kind": &"stun", "radius": 200.0 })
	await _settle(t, 1)
	_save(view, "stun")
	_check_white_out(t, view)
	t.check(
		_same(_linear(view, LAMPS), lamps),
		"two overlapping lamp pools far from it keep their colour",
	)
	t.check(_same(_linear(view, CORNER), ambient), "and so does the far ambient")
	await t.seconds(1.2)
	await _settle(t)
	t.check(
		_same(_linear(view, Vector2(-180.0, 0.0)), planks),
		"once it is dark the planks are as before",
	)
	await _check_unseen(t, view)


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
	t.check(_same(past, ambient), "and the floor past its reach is the ambient's (%s)" % past)


## The planks, under the stun, are white and flat over a grid, not at one pixel: the stripes and the
## bands' rings are gone.
func _check_white_out(t: TestContext, view: SubViewport) -> void:
	var low := 1.0
	var high := 0.0
	var count := 0
	for ix in GRID_STEPS.x:
		for iy in GRID_STEPS.y:
			var at := Vector2(
				lerpf(WHITE_GRID[0].x, WHITE_GRID[1].x, float(ix) / (GRID_STEPS.x - 1)),
				lerpf(WHITE_GRID[0].y, WHITE_GRID[1].y, float(iy) / (GRID_STEPS.y - 1)),
			)
			var c := _linear(view, at)
			low = minf(low, minf(c.r, minf(c.g, c.b)))
			high = maxf(high, maxf(c.r, maxf(c.g, c.b)))
			count += 1
	t.check(
		low > WHITE,
		"a stun whites the region out (%d pixels, the least channel %.2f)" % [count, low],
	)
	t.check(
		high - low < FLAT,
		"flat: no stripe or ring shows (channels %.2f to %.2f)" % [low, high],
	)


## A stun in a spot the vision mask leaves unseen changes nothing on the picture: the whole left of
## the room is unseen (half a mask of 64 texels), the stun bursts in it.
func _check_unseen(t: TestContext, view: SubViewport) -> void:
	var mask := Image.create(64, 1, false, Image.FORMAT_L8)
	mask.fill(Color.WHITE)
	mask.fill_rect(Rect2i(0, 0, 32, 1), Color.BLACK)
	ToonMask.set_mask(ImageTexture.create_from_image(mask), ROOM, 0.0)
	await _settle(t)
	var before := _linear(view, Vector2(-180.0, 0.0))
	var lamps := _linear(view, LAMPS)
	EventBus.post(&"explosion", { "position": STUN_AT, "kind": &"stun", "radius": 200.0 })
	await _settle(t, 1)
	_save(view, "stun_unseen")
	t.check(
		_same(_linear(view, Vector2(-180.0, 0.0)), before),
		"a stun in an unseen spot changes no pixel there",
	)
	t.check(_same(_linear(view, LAMPS), lamps), "nor the seen lamps")
	ToonMask.clear()


## Whether two colours are the same to `SAME` in every channel.
func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < SAME and absf(a.g - b.g) < SAME and absf(a.b - b.b) < SAME


## Draw the viewport on demand (a covered window never draws) after `frames` frames.
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


## The viewport of the scene: a ground, a striped plank floor, two lamps, a camera, under the dusk.
func _scene(t: TestContext) -> SubViewport:
	var world := Node2D.new()
	t.world.add_child(world)
	world.add_child(FakeFloor.new(ROOM))
	for x in [LAMPS.x - 25.0, LAMPS.x + 25.0]:
		var lamp := FakeLamp.new()
		lamp.position = Vector2(x, LAMPS.y)
		world.add_child(lamp)
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
	var slab := MeshKit.new().box(MeshKit.volume(PLANKS, 2.0, 3.0), Color.WHITE).build()
	view.add_child(MeshNodes.textured(slab, _stripes(), PLANKS))
	WorldLighting3D.light(view, world, 1, [{ "key": "room", "rect": ROOM }])
	return view


## A plank floor's art: rows of a light and a dark wood.
func _stripes() -> Texture2D:
	var image := Image.create(8, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		image.fill_rect(
			Rect2i(0, y, 8, 1),
			Color(0.8, 0.6, 0.4) if y % 4 < 2 else Color(0.3, 0.2, 0.1),
		)
	return ImageTexture.create_from_image(image)


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


## A piece that gives one lamp's light.
class FakeLamp:
	extends Node2D

	func get_lights() -> Array:
		return [
			{
				"offset": Vector2.ZERO,
				"colour": Color.WHITE,
				"energy": 1.2,
				"radius": 90.0,
				"shape": &"round",
				"rhythm": [],
				"room_light": true,
				"street": false,
				"height": &"overhead",
				"glow": null,
			},
		]
