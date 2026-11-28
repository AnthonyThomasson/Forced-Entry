extends GameTest
## A smear ribbon on the 3D floor (#193 phase 2, Physics): the layer finds the ribbon a 2D smear
## grew by the id it wrote into the 2D mark, so two smears grown in turn each get only their own new
## segments (a band of two triangles each, the old ones kept and not laid again); a smear the print
## cap dropped is not grown; an unknown or stale mark is ignored. Asserted at the seams: the layer
## `PhysicsMeshes.install` adds, its `ink` marks and the 2D `BloodDecals` it mirrors.

const SCRATCH := "user://settings_blood_ribbon_mesh_test.json"
const AT := Vector2(300, 300)
## Vertices a segment adds: two triangles.
const SEGMENT := 6
const KEPT := 3


func describe() -> Dictionary:
	return {
		"name": "A smear on the 3D floor grows by its own new segments, found by id",
		"description": "Two smears grown in turn each add only their new bands; a dropped smear "
			+ "is not grown again; a mark the layer does not know is ignored.",
		"tags": ["mirror", "3d", "render", "physics", "blood", "smear"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", true)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.set_static(BloodConfig, &"print_max", KEPT)
	s.von_script([])


func run(t: TestContext) -> void:
	var mirror := _mirror(t)
	var layer := PhysicsMeshes.install(mirror)
	mirror.carry(t.world)
	var decals := BloodDecals.layer(t.world)
	var one := decals.ribbon_begin(AT, 4.0, 0.9)
	var two := decals.ribbon_begin(AT + Vector2(0, 60), 4.0, 0.9)
	t.check(one.has("ink_id") and two.has("ink_id"), "each smear is given an id")
	t.check(one["ink_id"] != two["ink_id"], "its own")
	for i in 3:
		decals.ribbon_extend(one, AT + Vector2(10.0 * (i + 1), 0), 4.0, 0.9)
	decals.ribbon_extend(two, AT + Vector2(10, 60), 4.0, 0.9)
	await t.frames(2)
	var marks := layer.ink.marks(InkMark.Kind.RIBBON)
	t.expect_eq(marks.size(), 2, "two smears lie")
	var sizes := [marks[0].verts.size(), marks[1].verts.size()]
	sizes.sort()
	t.expect_eq(sizes, [SEGMENT, 3 * SEGMENT], "each has a band for each of its own segments")
	var older := marks[0].verts.duplicate()
	var grown := marks[0]
	decals.ribbon_extend(one, AT + Vector2(40, 0), 4.0, 0.9)
	decals.ribbon_extend(two, AT + Vector2(20, 60), 4.0, 0.9)
	await t.frames(2)
	t.expect_eq(
		layer.ink.marks(InkMark.Kind.RIBBON).map(func(m: InkMark) -> int: return m.verts.size()),
		[marks[0].verts.size(), marks[1].verts.size()],
		"the marks are the same, grown",
	)
	var after := grown.verts
	t.expect_eq(after.size(), older.size() + SEGMENT, "one more band, no more")
	t.check(after.slice(0, older.size()) == older, "and the bands laid before are the same")
	_check_ignored(t, layer, decals, one)


## A dropped smear is not grown; an unknown id or none is ignored, with no error.
func _check_ignored(t: TestContext, layer: FxLayer, decals: BloodDecals, one: Dictionary) -> void:
	for i in KEPT + 2:
		decals.print_at(PackedVector2Array([AT, AT + Vector2(5, 0), AT + Vector2(5, 3)]), 0.5)
	t.expect_eq(layer.ink.count_of(InkMark.Kind.RIBBON), 0, "the cap dropped the smears")
	var held := layer.ink.count_of(InkMark.Kind.PRINT)
	layer.ink.ribbon_grew(one)
	layer.ink.ribbon_grew({ "ink_id": 99_999, "points": PackedVector2Array([AT, AT]) })
	layer.ink.ribbon_grew({})
	t.expect_eq(layer.ink.count_of(InkMark.Kind.RIBBON), 0, "a dropped or unknown one is not grown")
	t.expect_eq(layer.ink.count_of(InkMark.Kind.PRINT), held, "and nothing else changed")


func _mirror(t: TestContext) -> MeshCarrier:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := MeshCarrier.new()
	view.add_child(mirror)
	return mirror
