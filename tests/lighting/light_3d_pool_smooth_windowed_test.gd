extends GameTest
## #193 phase 3 (L2-3D, windowed only: the headless renderer draws nothing and compiles no shader):
## a light's pool fades out smoothly, with no ring where a band ends. Three clean floors, each with
## one light (a room's ceiling fixture, an overhead lamp over a floor, a street lamp over a street)
## under the near top-down camera: the picture is read along a radius from the light's middle out
## past its rim, and no two neighbouring pixels of it differ by more than `STEP` of the pool's
## brightest (a stepped pool of eight bands has jumps of an eighth and more, a ring), while the
## pool still falls from its middle to the floor's dusk at its rim.
## Run: `tools/run_tests.sh --windowed --id=lighting/light_3d_pool_smooth_windowed`; with
## `POOL_SHOTS=<dir>` set it saves each floor's picture (`<kind>.png`).

## The picture is SIZE px for SPAN world px (so a pixel is two): a ceiling fixture's pool is wide.
const SIZE := 700
const HALF := 350.0
const SPAN := 1400.0
## The bulb's own glow is skipped: the line starts this many pixels out.
const SKIP := 8
const GROUND := Color(0.6, 0.6, 0.6)
const ROOM := Rect2(-750.0, -750.0, 1500.0, 1500.0)
## The largest step between neighbouring pixels along the radius, of the pool's brightest minus the
## floor's dusk (an eighth is a band's edge).
const STEP := 0.12
## The longest run of equal pixels (a band's width) allowed inside the pool's fall.
const RUN := 4
## How much the pool must fall from its middle to its rim: the rim reads this much of the middle.
const FALLS_TO := 0.35
const RADIUS := 90.0
## Two pixels this close are one tone (an 8-bit step of the picture is about 0.0012 here).
const QUANTUM := 0.0006

var _worst := 0.0


func describe() -> Dictionary:
	return {
		"name": "A light's pool fades out smoothly, with no visible ring (windowed)",
		"description": "A ceiling fixture, an overhead lamp and a street lamp over a clean floor: "
			+ "along a radius from the light out past its rim no neighbouring pixels step by more "
			+ "than a small bound, and the pool still falls. Windowed only.",
		"tags": ["lighting", "3d", "render", "windowed"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(RenderConfig, &"unit", 1.0)


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	for kind: String in ["fixture", "lamp", "street"]:
		var view := _scene(t, kind)
		await t.frames(6)
		RenderingServer.force_draw(false)  # on demand: a covered window never draws
		var image := view.get_texture().get_image()
		_save(image, kind)
		_check(t, image, kind)
		view.queue_free()
		await t.frames(2)
	print("POOLSTEP worst=%.4f" % _worst)


## The radius of `image` from the light's middle (the picture's) to past the pool's rim.
func _check(t: TestContext, image: Image, kind: String) -> void:
	var line: Array[float] = []
	for x in range(int(HALF) + SKIP, SIZE - 1):
		line.append(_luminance(image, x, int(HALF)))
	var floor_tone := line.back() as float
	var top := line.max() as float
	var low := line.min() as float
	t.check(top > low * 1.05, "%s: the pool is in the picture (%.3f to %.3f)" % [kind, low, top])
	var biggest := 0.0
	for i in range(1, line.size()):
		biggest = maxf(biggest, absf(line[i] - line[i - 1]))
	var step := biggest / maxf(top - low, 0.001)
	var plateau := _longest_run(line, low, top)
	_worst = maxf(_worst, step)
	print("POOLRING %s step=%.3f run=%d" % [kind, step, plateau])
	t.check(
		step <= STEP,
		"%s: no ring: the biggest step between neighbours is %.3f of the pool (most %.3f)" % [
			kind, step, STEP,
		],
	)
	t.check(
		plateau <= RUN,
		"%s: no band: the pool's fall has no plateau of %d pixels (most %d)" % [kind, plateau, RUN],
	)
	if kind == "fixture":
		return  # its pool is wider than the picture
	var rim := line[mini(int(RADIUS * Lighting3DConfig.range_scale * SIZE / SPAN), line.size() - 1)]
	t.check(
		absf(rim - floor_tone) <= (top - low) * FALLS_TO,
		"%s: the pool has fallen at its rim (%.3f, the floor %.3f, the pool %.3f to %.3f)" % [
			kind, rim, floor_tone, low, top,
		],
	)


## The longest run of pixels of `line` within a hair of each other where the pool is falling
## (between the plateau at its top, by 3% of its range, and the floor's `low`): a band of a stepped
## pool.
func _longest_run(line: Array[float], low: float, top: float) -> int:
	var from := 0
	var to := line.size() - 1
	var margin := (top - low) * 0.03
	while from < to and line[from] > top - margin:
		from += 1
	while to > from and line[to] < low + margin:
		to -= 1
	var longest := 1
	var streak := 1
	for i in range(from + 1, to + 1):
		streak = streak + 1 if absf(line[i] - line[i - 1]) < QUANTUM else 1
		longest = maxi(longest, streak)
	return longest


func _save(image: Image, kind: String) -> void:
	var dir := OS.get_environment("POOL_SHOTS")
	if dir == "":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	image.save_png("%s/%s.png" % [dir, kind])


## The viewport: a clean floor, a room (or none, in the street) and one light, under a top-down
## camera.
func _scene(t: TestContext, kind: String) -> SubViewport:
	var world := Node2D.new()
	t.world.add_child(world)
	world.add_child(FakeFloor.new(ROOM, kind == "street"))
	var view := SubViewport.new()
	view.size = Vector2i(SIZE, SIZE)
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(view)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = SPAN
	camera.near = 1.0
	camera.far = 900.0
	camera.position = Vector3(0, 600, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	view.add_child(camera)
	var ground := MeshKit.new().box(MeshKit.volume(ROOM, -2.0, 2.0), GROUND).build()
	view.add_child(MeshNodes.instance(ground, Color.WHITE, false))
	var rooms := [] if kind == "street" else [{ "key": "room", "rect": ROOM }]
	if kind != "fixture":
		world.add_child(Lamp.new(kind == "street"))
	WorldLighting3D.light(view, world, 1, rooms, Callable())
	return view


## Luminance of the picture at pixel (`x`, `y`).
func _luminance(image: Image, x: int, y: int) -> float:
	return image.get_pixel(x, y).srgb_to_linear().get_luminance()


## A floor of the fake world, a house's or the street's: the Lighting domain reads its `size`.
class FakeFloor:
	extends Node2D
	var size := Vector2.ZERO
	var street := false

	func _init(rect: Rect2, is_a_street: bool) -> void:
		position = rect.position
		size = rect.size
		street = is_a_street
		add_to_group(&"floors")

	func is_street() -> bool:
		return street


## A piece that gives one light at the world's middle (duck-typed: `get_lights`).
class Lamp:
	extends Node2D
	var _street := false

	func _init(street: bool) -> void:
		_street = street

	func get_lights() -> Array:
		return [
			{
				"offset": Vector2.ZERO,
				"colour": Color(1.0, 0.8, 0.5),
				"energy": 1.0,
				"radius": RADIUS,
				"rhythm": [],
				"room_light": not _street,
				"street": _street,
				"height": &"overhead",
				"lift": 124.0 if _street else 50.0,
			},
		]
