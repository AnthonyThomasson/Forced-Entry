extends GameTest
## #193 phase 3 (L1, L2, L6 in 3D, windowed only: the headless renderer draws nothing and compiles
## no shader): the dusk as it looks. A grey ground under an orthographic camera, its left half a
## street floor and its right a house floor, a tall wall on the street and an orange lamp in the
## house:
##   - the street is lit by the sky and the house floor by the ambient alone, so the street is
##     brighter and warmer (the sky's pink), and the house floor is the art times the ambient;
##   - the wall's shadow on the street is short (the sun is high): dark right behind the wall, lit
##     again past `wall height / tan(elevation)` of it, the sun's own shadow;
##   - the lamp's pool is warmer and brighter than the ambient at its middle and gone past its
##     radius, and a pool is stepped (more than one tone between its middle and its rim).
## Run: `tools/run_tests.sh --windowed --id=lighting/light_3d_look_windowed`. With
## `LIGHT_SHOT=<file.png>` set it saves the picture.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const SIZE := 256
const HALF := 128.0
const GROUND := Color(0.6, 0.6, 0.6)
const WALL := Rect2(-60.0, -60.0, 12.0, 120.0)
const LAMP_AT := Vector2(70.0, 0.0)
const LAMP_COLOUR := Color(1.0, 0.6, 0.2)
const POOL := 90.0
## The lamp's room and the one next to it, which its pool reaches over (the lamp at x 70, the pool
## to x 160, the rooms meet at x 100): the pool stops at the room's edge.
const LAMP_ROOM := Rect2(0.0, -128.0, 100.0, 256.0)
const NEXT_ROOM := Rect2(100.0, -128.0, 28.0, 256.0)


func _draw(t: TestContext) -> void:
	await t.frames(4)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws


func describe() -> Dictionary:
	return {
		"name": "The 3D dusk looks like dusk: a lit street, a dark house, a short shadow, a "
			+ "lamp's pool (windowed)",
		"description": "A street floor and a house floor under a camera in a window: the sky "
			+ "lights "
			+ "the street warm and not the house; a wall's shadow is short; a lamp's pool is "
			+ "warm, bright at its middle, stepped and gone past its radius. Windowed only.",
		"tags": ["lighting", "3d", "render", "windowed"],
		"timeout": 30.0,
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
	await _draw(t)
	var image := view.get_texture().get_image()
	var shot := OS.get_environment("LIGHT_SHOT")
	if shot != "":
		image.save_png(shot)
	var street := _linear(image, Vector2(-100.0, 90.0))
	var house := _linear(image, Vector2(110.0, 100.0))
	var ambient := ToonLight.shader_ambient(
		LightingConfig.ambient_color,
		ToonLightConfig.ambient_gain,
	)
	var base := GROUND.srgb_to_linear()
	t.check(
		absf(house.r - base.r * ambient.r) < 0.02 and absf(house.b - base.b * ambient.b) < 0.02,
		"the house floor is the art times the ambient (%s)" % house,
	)
	t.check(
		street.get_luminance() > house.get_luminance() * 1.3,
		"the sky lights the street (%s, %s)" % [street, house],
	)
	t.check(street.r / street.b > house.r / house.b * 1.2, "and warm, in the sky's pink")
	_check_shadow(t, image, street)
	_check_pool(t, image, house)
	_check_next_room(t, image, house)


## The viewport of the scene: a ground, a wall, a lamp's lights, a camera, under the dusk.
func _scene(t: TestContext) -> SubViewport:
	var world := Node2D.new()
	t.world.add_child(world)
	world.add_child(FakeFloor.new(Rect2(-HALF, -HALF, HALF, HALF * 2.0), true))
	world.add_child(FakeFloor.new(Rect2(0.0, -HALF, HALF, HALF * 2.0), false))
	var lamp := FakeLamp.new()
	lamp.position = LAMP_AT
	world.add_child(lamp)
	var dark := FakeLamp.new()  # a room's own light, off: the room is lit, so it gets no fixture
	dark.position = Vector2(NEXT_ROOM.get_center().x, NEXT_ROOM.position.y + 8.0)
	dark.energy = 0.0
	dark.radius = 1.0
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
	var slab := Rect2(-HALF, -HALF, HALF * 2.0, HALF * 2.0)
	var ground := MeshKit.new().box(MeshKit.volume(slab, -2.0, 2.0), GROUND).build()
	view.add_child(MeshNodes.instance(ground))
	var height := ObjectStructureMeshConfig.wall_height
	var wall := MeshKit.new().box(MeshKit.volume(WALL, 0.0, height), GROUND).build()
	view.add_child(MeshNodes.instance(wall))
	var rooms := [
		{ "key": "lamp_room", "rect": LAMP_ROOM },
		{ "key": "next_room", "rect": NEXT_ROOM },
	]
	WorldLighting3D.light(view, world, 1, rooms)
	return view


## Linear colour of the picture at ground point `at` (px from the middle, x and z).
func _linear(image: Image, at: Vector2) -> Color:
	return image.get_pixel(int(HALF + at.x), int(HALF + at.y)).srgb_to_linear()


## The wall's shadow lies down the sky's travel, as long as `height / tan(elevation)`: the street
## east of the wall is dark half way along it and lit again past its end.
func _check_shadow(t: TestContext, image: Image, lit: Color) -> void:
	var height := ObjectStructureMeshConfig.wall_height
	var reach := height / tan(deg_to_rad(Lighting3DConfig.sun_elevation))
	var along := (-LightingConfig.sky_from).normalized() * reach
	var east := WALL.end.x
	var inside := _linear(image, Vector2(east + along.x * 0.5, 0.0))
	var past := _linear(image, Vector2(east + along.x + 14.0, 0.0))
	t.check(
		inside.get_luminance() < lit.get_luminance() * 0.8,
		"the wall's shadow is dark beside it (%s, in the sun %s)" % [inside, lit],
	)
	t.check(
		past.get_luminance() > lit.get_luminance() * 0.9,
		"and %.0f px further the street is in the sun again (%s)" % [along.x + 14.0, past],
	)


## The lamp's pool: warmer and brighter at its middle than the ambient floor, stepped to its rim,
## gone past it.
func _check_pool(t: TestContext, image: Image, house: Color) -> void:
	var reach := POOL * Lighting3DConfig.range_scale
	var middle := _linear(image, LAMP_AT + Vector2(0.0, 6.0))
	var tones := {}
	for step in range(0, int(reach) - 4, 3):
		var along := _linear(image, LAMP_AT + Vector2(0.0, float(step) + 6.0))
		tones[snappedf(along.get_luminance(), 0.01)] = true
	var beyond := _linear(image, LAMP_AT + Vector2(0.0, reach + 8.0))
	t.check(
		middle.get_luminance() > house.get_luminance() * 1.5,
		"the lamp lights the floor under it (%s, ambient %s)" % [middle, house],
	)
	t.check(middle.r / middle.b > house.r / house.b * 1.5, "and warm, in its own colour")
	t.check(
		tones.size() >= 4,
		"the pool is stepped: %d tones from its middle to its rim" % tones.size(),
	)
	t.check(
		absf(beyond.get_luminance() - house.get_luminance()) < house.get_luminance() * 0.1,
		"past its radius the floor is the ambient's again (%s)" % beyond,
	)


## The next room, over the line the rooms meet at, is the ambient's: the lamp's pool reaches it by
## distance (the lamp is 30 px from the line, the pool 90) but is not of its room.
func _check_next_room(t: TestContext, image: Image, house: Color) -> void:
	var beside := _linear(image, Vector2(LAMP_ROOM.end.x - 4.0, 0.0))
	var across := _linear(image, Vector2(NEXT_ROOM.position.x + 6.0, 0.0))
	t.check(
		beside.get_luminance() > house.get_luminance() * 1.5,
		"the lamp lights its own room right up to the line (%s)" % beside,
	)
	t.check(
		absf(across.get_luminance() - house.get_luminance()) < house.get_luminance() * 0.1,
		"and not the next room, a few px over it (%s, ambient %s)" % [across, house],
	)


## A floor of the fake world: the Lighting domain reads its `size` and its canvas items' light mask.
class FakeFloor:
	extends Node2D
	var size := Vector2.ZERO
	var street := false

	func _init(rect: Rect2, is_street_floor: bool) -> void:
		position = rect.position
		size = rect.size
		street = is_street_floor
		add_to_group(&"floors")

	func is_street() -> bool:
		return street


## A piece that gives one light.
class FakeLamp:
	extends Node2D
	var energy := 1.0
	var radius := 90.0

	func get_lights() -> Array:
		return [
			{
				"offset": Vector2.ZERO,
				"colour": Color(1.0, 0.6, 0.2),
				"energy": energy,
				"radius": radius,
				"shape": &"round",
				"rhythm": [],
				"room_light": true,
				"street": false,
				"height": &"overhead",
				"glow": null,
			},
		]
