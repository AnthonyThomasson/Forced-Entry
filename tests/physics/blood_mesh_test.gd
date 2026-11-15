extends GameTest
## The blood that lies on the floor of a 3D match (#193 phase 2, Physics): a splat, a footprint and
## a smear are flat meshes a few tenths of a px over the ground in the shape and colour the 2D
## drew, each kind on its own height (a splat under a print), facing up; blood dries in steps of
## tone and, once dry, nothing runs and nothing is built; a splat lives as long as its 2D node,
## prints and smears are kept up to `BloodConfig.print_max`. Asserted at the seams: the layer
## `PhysicsMeshes.install` adds, its `ink` marks and chunks, and the 2D blood it mirrors. The
## numbers are pinned here; the look is judged in a window, `physics_mesh_windowed_test.gd`.

const SCRATCH := "user://settings_blood_mesh_test.json"
const AT := Vector2(300, 300)
## The heights (px) the marks lie at: a splat, a print and a smear (`PhysicsInkConfig`'s layers
## 5.8 and 6.6 of 0.25 over a decal's float of 0.15), and how much higher a splat's wet highlight
## lies (0.4 of a layer).
const SPLAT := 1.6
const PRINT := 1.8
const OVER := 0.1
## The blood's colours (`BloodConfig`): wet and dried, the art's sRGB.
const WET := Color(0.42, 0.02, 0.03)
const DRIED := Color(0.24, 0.04, 0.03)
## Drying: 0.8 s in the 4 steps, so five tones in all, wet to dry.
const DRY_TIME := 0.8
const STEPS := 4
const KEPT := 20


func describe() -> Dictionary:
	return {
		"name": "Blood on the 3D floor is flat meshes that dry in steps and go with their splat",
		"description": "A splat, a print and a smear lie flat over the floor, each on its own "
			+ "height, in the 2D shape and colour; blood dries in steps and then nothing runs; "
			+ "a splat goes with its node; prints and smears are capped as in 2D.",
		"tags": ["mirror", "3d", "render", "physics", "blood"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", true)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.set_static(BloodSplatConfig, &"dry_time", DRY_TIME)
	s.set_static(BloodConfig, &"print_dry_time", DRY_TIME)
	s.set_static(BloodConfig, &"print_max", KEPT)
	s.set_static(PhysicsInkConfig, &"dry_steps", STEPS)
	s.von_script([])


func run(t: TestContext) -> void:
	var mirror := _mirror(t)
	var layer := PhysicsMeshes.install(mirror)
	mirror.mirror(t.world)
	var splat := _splat(t, AT)
	await t.frames(2)
	_check_a_splat(t, layer)
	await _check_drying(t, layer)
	splat.queue_free()
	await t.frames(3)
	t.expect_eq(layer.ink.count_of(InkMark.Kind.SPLAT), 0, "a splat goes with its node")
	await _check_prints(t, layer)


## One splat: flat, face up, over the ground at its height, within its reach, in the blood's colour.
func _check_a_splat(t: TestContext, layer: FxLayer) -> void:
	t.expect_eq(layer.ink.count_of(InkMark.Kind.SPLAT), 1, "a splat lies on the floor")
	var mark := layer.ink.marks(InkMark.Kind.SPLAT)[0]
	t.check(mark.verts.size() >= 3 and mark.verts.size() % 3 == 0, "as triangles")
	var highest := 0.0
	var lowest := INF
	var farthest := 0.0
	for v in mark.verts:
		highest = maxf(highest, v.y)
		lowest = minf(lowest, v.y)
		farthest = maxf(farthest, Vector2(v.x, v.z).distance_to(AT))
	t.expect_near(lowest, SPLAT, 0.001, "its body lies at the splat's height")
	t.check(highest <= SPLAT + OVER + 0.001, "and its highlight a little above (%.2f)" % highest)
	t.check(farthest < 30.0, "within reach of where it fell (%.0f px)" % farthest)
	t.check(_all_face_up(mark), "every triangle faces up")
	t.check(mark.colors[0].is_equal_approx(WET.srgb_to_linear()), "in the blood's colour")
	var chunk := layer.ink.chunk_of(mark)
	t.expect_eq(chunk.mesh.surface_get_array_len(0), mark.verts.size(), "one mesh shows it")


## Whether two colours are the same to the 8 bits a mesh keeps.
func _near(a: Color, b: Color) -> bool:
	var step := 1.0 / 255.0
	return (
		absf(a.r - b.r) <= step and absf(a.g - b.g) <= step and absf(a.b - b.b) <= step
	)


## A drying splat: each step is a tone between wet and dry, then dry, and nothing runs.
func _check_drying(t: TestContext, layer: FxLayer) -> void:
	var tones := {}
	var mark := layer.ink.marks(InkMark.Kind.SPLAT)[0]
	for _i in 30:
		tones[mark.colors[0].to_html()] = true
		await t.seconds(0.05)
	await t.seconds(0.5)
	tones[mark.colors[0].to_html()] = true
	t.check(
		tones.size() >= 3 and tones.size() <= STEPS + 1,
		"it dries in steps (%d)" % tones.size(),
	)
	t.check(mark.colors[0].is_equal_approx(DRIED.srgb_to_linear()), "to the dried colour")
	t.expect_eq(layer.ink.wet(), 0, "then nothing is drying")
	await t.frames(3)
	var chunk := layer.ink.chunk_of(mark)
	var shown: Color = chunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR][0]
	t.check(
		_near(shown, chunk.marks[0].colors[0]) and chunk.marks[0].step > 0,
		"the chunk's mesh was built again as it dried, with no other effect to wake the layer",
	)
	var built := layer.ink.rebuilds
	await t.frames(20)
	t.expect_eq(layer.ink.rebuilds, built, "dry blood is never built again")
	t.check(not layer.is_processing(), "and the layer rests")


## Prints and a smear: over the splats, as the 2D layer's own, up to the cap, the oldest dropped.
func _check_prints(t: TestContext, layer: FxLayer) -> void:
	var decals := BloodDecals.layer(t.world)
	var sole := PackedVector2Array([AT, AT + Vector2(6, 0), AT + Vector2(6, 3), AT + Vector2(0, 3)])
	decals.print_at(sole, 0.85)
	await t.frames(2)
	var print_mark := layer.ink.marks(InkMark.Kind.PRINT)[0]
	t.expect_near(print_mark.verts[0].y, PRINT, 0.001, "a print lies over a splat")
	t.check(_all_face_up(print_mark), "face up")
	var ribbon := decals.ribbon_begin(AT + Vector2(0, 40), 4.0, 0.9)
	for i in 3:
		decals.ribbon_extend(ribbon, AT + Vector2(10.0 * (i + 1), 40), 4.0, 0.9)
	await t.frames(2)
	var smear := layer.ink.marks(InkMark.Kind.RIBBON)[0]
	t.expect_eq(smear.verts.size(), 3 * 6, "a smear is a band a segment (two triangles) at a time")
	t.check(_all_face_up(smear), "face up")
	for i in KEPT * 3:
		var at := AT + Vector2(i * 5 % 400, 100 + i)
		decals.print_at(PackedVector2Array([at, at + Vector2(5, 0), at + Vector2(5, 3)]), 0.5)
	await t.frames(3)
	var held := layer.ink.count_of(InkMark.Kind.PRINT) + layer.ink.count_of(InkMark.Kind.RIBBON)
	t.expect_eq(held, KEPT, "prints and smears are kept as the 2D layer keeps them")
	t.expect_eq(layer.ink.count_of(InkMark.Kind.RIBBON), 0, "the oldest, the smear, went first")


## One splat of the 2D blood, built whole at `at`.
func _splat(t: TestContext, at: Vector2) -> Node:
	var throw := BloodThrow.new()
	throw.size = 3.5
	throw.energy = 0.5
	return BloodSpawner.splat(t.world, at, throw)


## Whether every triangle of `mark` is wound to face up (clockwise on the y-down floor).
func _all_face_up(mark: InkMark) -> bool:
	for i in range(0, mark.verts.size(), 3):
		var a := Vector2(mark.verts[i].x, mark.verts[i].z)
		var b := Vector2(mark.verts[i + 1].x, mark.verts[i + 1].z)
		var c := Vector2(mark.verts[i + 2].x, mark.verts[i + 2].z)
		if (b - a).cross(c - a) < 0.0:
			return false
	return true


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
