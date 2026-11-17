extends GameTest
## #193 phase 3 (L3, L6 in 3D, windowed only: the headless renderer draws nothing and compiles no
## shader): a room's ceiling fixture throws SHORT shadows, like 2D's drop shadows, not the long
## streaks of a lamp hung low in a small room. A room with its fixture (the light that casts), and
## in it a 70 tall person-sized box and a 96 tall wall beside the centre, each on a side of it:
##   - the shadow lies on the floor past the caster's far edge, so there is one (the light casts);
##   - it is as long as the light's height says, `edge * height / (light - height)` (a few px), and
##     not the metre of a light at the ceiling (`edge * height / (ceiling - height)` is 200+);
##   - past it the floor is lit by the pool again, as the same floor on the other side of the room.
## Run: `tools/run_tests.sh --windowed --id=lighting/light_3d_shadow_length_windowed`. With
## `LIGHT_SHOT=<file.png>` set it saves the picture.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const SIZE := 512
const HALF := 256.0
const GROUND := Color(0.6, 0.6, 0.6)
## The room is bigger than the picture, so its fixture's pool is flat all over it.
const ROOM := Rect2(-300.0, -300.0, 600.0, 600.0)
## A person's height and the wall's: the box on the right and the slab on the left.
const PERSON := Rect2(60.0, -15.0, 30.0, 30.0)
const WALL := Rect2(-90.0, -60.0, 6.0, 120.0)
## A wall far from the fixture (200 px): the fixture is raised with the room so its shadow stays
## short.
const FAR_WALL := Rect2(200.0, -60.0, 6.0, 120.0)
## How much darker than the lit floor is a shadow (the fixture's shadow is part dark).
const DARKER := 0.9
## How far past its analytic length a shadow may reach, px (the filter's softness).
const SLACK := 9.0
## The shortest a shadow may be (so the test sees the shadow of the light that casts).
const LEAST := 6.0
const PERSON_HEIGHT := 70.0
## How far past a caster's edge the row is read (px): the next caster is further than that.
const SCAN := 60


func describe() -> Dictionary:
	return {
		"name": "A ceiling fixture's shadows are short, like 2D's drop shadows (windowed)",
		"description": "A room with its fixture, a 70 tall box and a 96 tall wall: each throws a "
			+ "shadow past its far edge as long as the fixture's height says (a few px, not "
			+ "the length of a light at the ceiling), and the floor past it is lit again. "
			+ "Windowed only.",
		"tags": ["lighting", "3d", "render", "windowed"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.own_picture()
	s.set_static(RenderConfig, &"unit", 1.0)


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	var view := _scene(t)
	await t.frames(6)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	var image := view.get_texture().get_image()
	var shot := OS.get_environment("LIGHT_SHOT")
	if shot != "":
		image.save_png(shot)
	var lit := _luminance(image, Vector2(0.0, 100.0))
	t.check(lit > 0.0, "the floor is lit (%.3f)" % lit)
	var wall_height := ObjectStructureMeshConfig.wall_height
	_check_caster(t, image, lit, { "label": "the person", "edge": PERSON.end.x,
		"height": PERSON_HEIGHT, "side": 1.0 })
	_check_caster(t, image, lit, { "label": "the wall", "edge": -WALL.position.x,
		"height": wall_height, "side": -1.0 })
	_check_caster(t, image, lit, { "label": "the far wall", "edge": FAR_WALL.end.x,
		"height": wall_height, "side": 1.0 })
	var ceiling := LightingFixtureConfig.bulb_height
	t.check(
		PERSON.end.x * PERSON_HEIGHT / (ceiling - PERSON_HEIGHT) > 100.0,
		"a light at the ceiling would throw the person's shadow past 100 px: the cut is needed",
	)


## The shadow of a `caster` (`label`, `edge`: its far edge's px from the room's centre, `height` and
## `side`, +1 right of the centre and -1 left): it starts at the edge, is as long as the fixture's
## height says and ends in the pool's light, measured along the row through the centre.
func _check_caster(t: TestContext, image: Image, lit: float, caster: Dictionary) -> void:
	var edge: float = caster["edge"]
	var height: float = caster["height"]
	var side: float = caster["side"]
	var light := LightingFixtureConfig.shadow_height_for(ROOM.size.x)
	var length := edge * height / (light - height)
	var dark_to := 0.0
	for step in range(1, mini(int(HALF - edge) - 2, SCAN)):
		var tone := _luminance(image, Vector2(side * (edge + float(step) + 1.0), 0.0))
		if tone < lit * DARKER:
			dark_to = float(step)
	t.check(
		dark_to >= LEAST and dark_to <= length + SLACK,
		"%s's shadow past its edge is %.0f px: it should be %.0f (at most %.0f)" % [
			caster["label"], dark_to, length, length + SLACK,
		],
	)


## The viewport: the room's floor and fixture, a person and a wall under a top-down camera.
func _scene(t: TestContext) -> SubViewport:
	var world := Node2D.new()
	t.world.add_child(world)
	world.add_child(FakeFloor.new(ROOM))
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
	camera.far = 900.0
	camera.position = Vector3(0, 600, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	view.add_child(camera)
	var slab := ROOM
	var ground := MeshKit.new().box(MeshKit.volume(slab, -2.0, 2.0), GROUND).build()
	view.add_child(MeshNodes.instance(ground, Color.WHITE, false))
	var person := MeshKit.new().box(MeshKit.volume(PERSON, 0.0, PERSON_HEIGHT), GROUND).build()
	view.add_child(MeshNodes.instance(person))
	var height := ObjectStructureMeshConfig.wall_height
	var wall := MeshKit.new().box(MeshKit.volume(WALL, 0.0, height), GROUND).build()
	view.add_child(MeshNodes.instance(wall))
	var far := MeshKit.new().box(MeshKit.volume(FAR_WALL, 0.0, height), GROUND).build()
	view.add_child(MeshNodes.instance(far))
	var rooms := [{ "key": "room", "rect": ROOM }]
	WorldLighting3D.light(view, world, 1, rooms, func() -> Vector2: return Vector2.ZERO)
	return view


## Luminance of the picture at ground point `at` (px from the middle, x and z).
func _luminance(image: Image, at: Vector2) -> float:
	return image.get_pixel(int(HALF + at.x), int(HALF + at.y)).srgb_to_linear().get_luminance()


## A floor of the fake world, a house's: the Lighting domain reads its `size`.
class FakeFloor:
	extends Node2D
	var size := Vector2.ZERO

	func _init(rect: Rect2) -> void:
		position = rect.position
		size = rect.size
		add_to_group(&"floors")

	func is_street() -> bool:
		return false
