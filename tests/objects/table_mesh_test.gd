extends GameTest
## The mesh-kit pattern proved on one kind (#193 phase 2, `domain-art/meshes.md`): Objects registers
## a builder for the table's own hook key (`MirrorProxy.furniture_key("table")`) and the mirror
## shows a table by a kit-built mesh in place of its proxy box: a top over four legs at the table's
## own footprint, the table's height (31 px, the how-to's furniture table), the colour the painter
## draws, the legs a darker tone, and every table of one size and colour sharing the one `Mesh`.
## Expected numbers are the spec's (the footprint is the piece's own `size`, a table stands 31 px,
## the scale is `RenderConfig.unit`); a table at half scale is half as big in every direction.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const ObjectArt := preload("res://scenes/objects/art/object_art.gd")
const SCRATCH := "user://settings_table_mesh_test.json"
const DINING_AT := Vector2(260, 180)
const SECOND_AT := Vector2(520, 300)
const TABLE_HEIGHT := 31.0
const MATCH := {
	"seed": 2,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}


func describe() -> Dictionary:
	return {
		"name": "A table is shown by a kit-built mesh, not its proxy box",
		"description": "Objects' builder gives a table a top over four legs: its footprint wide, "
			+ "31 px tall, the painter's colour with darker legs, one shared mesh for tables "
			+ "alike, half the size at half the scale; Main's 3D view registers it.",
		"tags": ["mirror", "3d", "render", "meshkit"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"dining", "dining_table", DINING_AT)
	s.object(&"second", "dining_table", SECOND_AT)
	s.object(&"small", "side_table", Vector2(100, 100))
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(ObjectMeshConfig, &"table_height", ObjectMeshConfig.table_height)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	await t.frames(5)
	var mirror := _mirror(t)
	ObjectMeshes.register(mirror.builders)
	mirror.mirror(t.world)
	await t.frames(3)
	var dining := t.object(&"dining")
	var node := _mesh_of(mirror, dining)
	if not t.require(node != null, "the dining table is shown by a mesh of its own"):
		return
	_check_shape(t, node, dining, 1.0)
	_check_colours(t, node, dining)
	var second := _mesh_of(mirror, t.object(&"second"))
	t.check(
		second != null and second.mesh == node.mesh,
		"two tables of one size and colour share the one mesh",
	)
	var small := _mesh_of(mirror, t.object(&"small"))
	t.check(
		small != null and small.mesh != node.mesh,
		"a table of another size has a mesh of its own",
	)
	var at := node.global_position
	t.expect_near(at.x, DINING_AT.x, 1.0, "the mesh stands on the table (x)")
	t.expect_near(at.z, DINING_AT.y, 1.0, "the mesh stands on the table (z)")
	t.check(
		(node.material_override as ShaderMaterial).get_shader_parameter(&"albedo_texture") != null,
		"it is drawn in the textured toon, wearing the painter's art",
	)
	# At half scale, every length of the mesh halves (the one conversion is the kit's).
	RenderConfig.unit = 0.5
	var halved := _mirror(t)
	ObjectMeshes.register(halved.builders)
	halved.mirror(t.world)
	await t.frames(3)
	var half := _mesh_of(halved, dining)
	if t.require(half != null, "a table at half scale is shown by a mesh"):
		_check_shape(t, half, dining, 0.5)
	# A retuned height is another mesh, not the cached one.
	ObjectMeshConfig.table_height = 40.0
	var taller := _mirror(t)
	ObjectMeshes.register(taller.builders)
	taller.mirror(t.world)
	await t.frames(3)
	var tall := _mesh_of(taller, dining)
	if t.require(tall != null, "a table is shown after the height is retuned"):
		t.expect_near(tall.mesh.get_aabb().size.y, 40.0 * 0.5, 0.01, "at its new height (x0.5)")
	await _check_main(t)


## The mesh node of `body` when the mirror shows it by a furniture rig (its body solid), else null.
func _mesh_of(mirror: WorldMirror, body: Node) -> MeshInstance3D:
	var shown := mirror.proxies_of(body)
	if shown.size() != 1 or not shown[0] is FurnitureRig:
		return null
	return (shown[0] as FurnitureRig).body


## A top over four legs, at the table's footprint and height times `scale`.
func _check_shape(t: TestContext, node: MeshInstance3D, table: Node, factor: float) -> void:
	var size: Vector2 = table.get("size")
	var box := node.mesh.get_aabb()
	t.expect_near(box.size.x, size.x * factor, 0.01, "as wide as the table (x%.1f)" % factor)
	t.expect_near(box.size.z, size.y * factor, 0.01, "as deep as the table (x%.1f)" % factor)
	t.expect_near(box.size.y, TABLE_HEIGHT * factor, 0.01, "31 px tall (x%.1f)" % factor)
	t.expect_near(box.position.y, 0.0, 0.01, "it stands on the floor (x%.1f)" % factor)
	t.expect_near(box.get_center().x, 0.0, 0.01, "centred on the table's origin (x)")
	t.expect_near(box.get_center().z, 0.0, 0.01, "centred on the table's origin (z)")
	# Four legs: what touches the floor is in the four corners, none in the middle of the span.
	var floor_points := _points_at_height(node.mesh as ArrayMesh, 0.0)
	var corners := {}
	for p in floor_points:
		t.check(
			absf(p.x) > size.x * factor * 0.25 or absf(p.z) > size.y * factor * 0.25,
			"nothing at the floor in the middle of the table (%s)" % p,
		)
		corners["%d%d" % [signf(p.x), signf(p.z)]] = true
	t.expect_eq(corners.size(), 4, "it stands on its four corners")


## The top face is the painter's colour; the legs (faces at the floor end of the sides) darker.
func _check_colours(t: TestContext, node: MeshInstance3D, table: Node) -> void:
	var wood: Color = table.get("color")
	var drawn := ObjectArt.drawn_color(wood)
	var arrays := (node.mesh as ArrayMesh).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var top_seen := false
	var leg_seen := false
	for i in vertices.size():
		var colour := colours[i].linear_to_srgb()
		if normals[i].dot(Vector3.UP) > 0.99 and is_equal_approx(vertices[i].y, TABLE_HEIGHT):
			top_seen = true
			t.check(
				_near(colour, drawn),
				"the top is the painted colour %s, got %s" % [drawn, colour],
			)
		elif absf(normals[i].y) < 0.01 and vertices[i].y < TABLE_HEIGHT * 0.5:
			leg_seen = true
			t.check(
				colour.get_luminance() < drawn.get_luminance() - 0.01,
				"a leg is a darker tone than the top (%s)" % colour,
			)
	t.check(top_seen and leg_seen, "the mesh has a top and legs")


## Main's 3D view registers the table's builder: a match started in 3D shows a table by the kit.
func _check_main(t: TestContext) -> void:
	var window := MainProbe.viewport(t)
	var main := MainProbe.open(window)
	MainProbe.setup_menu(main).queue_free()
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	main.add_child(camera)
	var built: Dictionary = await main.start_match(MATCH.duplicate(true))
	if not t.require(not built.is_empty(), "a 3D match started"):
		return
	await t.frames(4)
	var view := main.get_node_or_null("View3D")
	if t.require(view != null, "Main built the 3D view"):
		t.check(
			view.mirror.builders.has(MirrorProxy.furniture_key("table")),
			"Main's view registers the table's builder",
		)
	await MainProbe.close(t, window)


## Each vertex at `height` (3D units) of `mesh`.
func _points_at_height(mesh: ArrayMesh, height: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for p in vertices:
		if absf(p.y - height) < 0.001:
			out.append(p)
	return out


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.04


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
