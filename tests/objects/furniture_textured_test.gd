extends GameTest
## A furniture piece's 3D mesh wears its 2D painter's flat art (#193 phase 2b, `FurnitureArt`,
## `domain-art/textured-toon.md`): the rig's body (and a bed's blanket) shows the piece's unlit
## render through Art's textured toon, the art projected straight down onto the footprint, turned
## with the piece (the mesh is built turned), a piece with an overhang wearing one canvas over its
## footprint and its overhang. Pieces of one look share one material, and the damage tint is
## still written on the same nodes.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const ObjectArt := preload("res://scenes/objects/art/object_art.gd")
const SCRATCH := "user://settings_furniture_textured_test.json"


func describe() -> Dictionary:
	return {
		"name": "A furniture mesh wears its painter's flat art",
		"description": "The rig's solids are textured: the painter's unlit render over the "
			+ "footprint (turned with the piece, one canvas over footprint and overhang), one "
			+ "material for pieces of a look, the blanket too, the damage tint kept.",
		"tags": ["mirror", "3d", "render", "furniture", "art"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.object(&"sofa", "sofa", Vector2(120.0, 120.0))
	s.object(&"sofa_b", "sofa", Vector2(320.0, 120.0))
	s.object(
		&"sofa_left",
		"sofa",
		Vector2(520.0, 120.0),
		{ "facing": Vector2.LEFT, "rotated": true },
	)
	s.object(&"bed", "bed", Vector2(120.0, 300.0))
	s.object(&"lamp", "streetlight", Vector2(420.0, 300.0))
	s.object(&"sign", "awning", Vector2(620.0, 300.0), { "facing": Vector2.UP })
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	await t.frames(5)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	ObjectMeshes.register(mirror.builders)
	mirror.mirror(t.world)
	await t.frames(3)
	var sofa := _rig(t, mirror, &"sofa")
	var other := _rig(t, mirror, &"sofa_b")
	var left := _rig(t, mirror, &"sofa_left")
	if not t.require(sofa != null and other != null and left != null, "the sofas have rigs"):
		return
	_check_dressed(t, sofa, t.object(&"sofa"))
	t.check(
		sofa.body.material_override == other.body.material_override,
		"two sofas of one look share one material",
	)
	_check_turned(t, left, t.object(&"sofa_left"))
	_check_blanket(t, mirror)
	_check_overhang(t, mirror, &"lamp")
	_check_overhang(t, mirror, &"sign")
	_check_tint(t, sofa, t.object(&"sofa"))


func _rig(t: TestContext, mirror: WorldMirror, id: StringName) -> FurnitureRig:
	var shown := mirror.proxies_of(t.object(id))
	return shown[0] as FurnitureRig if shown.size() == 1 and shown[0] is FurnitureRig else null


## The art the sofa's body wears: the flat render, on the whole footprint.
func _check_dressed(t: TestContext, rig: FurnitureRig, piece: Node) -> void:
	var size: Vector2 = piece.get("size")
	var material := rig.body.material_override as ShaderMaterial
	t.check(
		material != null and material.shader != ToonMaterial.shared().shader,
		"the body is textured",
	)
	var flat := ObjectArt.flat(
		"sofa", size, piece.get("color"),
		piece.look.art_opts.merged({ "material": piece.object_material }, true),
	)
	t.check(
		material.get_shader_parameter(&"albedo_texture") == flat,
		"the body wears the sofa's flat render",
	)
	t.check(
		rig.body.get_instance_shader_parameter(&"uv_rect")
			== Vector4(-size.x * 0.5, -size.y * 0.5, size.x, size.y),
		"the art spans the footprint",
	)


## A sofa facing left wears the canonical art turned a quarter: its front row is the left column.
func _check_turned(t: TestContext, rig: FurnitureRig, piece: Node) -> void:
	var size: Vector2 = piece.get("size")
	var material := rig.body.material_override as ShaderMaterial
	var worn: Image = (material.get_shader_parameter(&"albedo_texture") as Texture2D).get_image()
	t.check(
		worn.get_size() == Vector2i(size),
		"the turned art is the footprint's size: %s" % worn.get_size(),
	)
	var canon := ObjectArt.flat(
		"sofa", Vector2(size.y, size.x), piece.get("color"),
		piece.look.art_opts.merged({ "material": piece.object_material }, true),
	).get_image()
	var front_row := canon.get_height() - 1
	var same := true
	for x in canon.get_width():
		same = same and worn.get_pixel(0, x) == canon.get_pixel(x, front_row)
	t.check(same, "the front of the art lies along the left edge for a piece facing left")
	t.check(
		rig.body.get_instance_shader_parameter(&"uv_rect")
			== Vector4(-size.x * 0.5, -size.y * 0.5, size.x, size.y),
		"the turned art spans the turned footprint",
	)


## The bed's blanket wears the same art over the same footprint.
func _check_blanket(t: TestContext, mirror: WorldMirror) -> void:
	var rig := _rig(t, mirror, &"bed")
	if not t.require(rig is FurnitureBedRig, "the bed has its rig"):
		return
	var blanket := (rig as FurnitureBedRig).blanket
	t.check(
		blanket.material_override == rig.body.material_override
			and blanket.get_instance_shader_parameter(&"uv_rect")
			== rig.body.get_instance_shader_parameter(&"uv_rect"),
		"the blanket wears the body's art",
	)


## An overhang piece's canvas covers its footprint and its overhang.
func _check_overhang(t: TestContext, mirror: WorldMirror, id: StringName) -> void:
	var rig := _rig(t, mirror, id)
	if not t.require(rig != null, "%s has a rig" % id):
		return
	var piece := t.object(id)
	var uv: Vector4 = rig.body.get_instance_shader_parameter(&"uv_rect")
	var rect := Rect2(uv.x, uv.y, uv.z, uv.w)
	var spec := FurnitureSpec.of(piece)
	var turn := Transform2D(spec.turns * PI * 0.5, Vector2.ZERO)
	t.check(
		spec.overhang.has_area()
			and rect.grow(0.01).encloses(turn * spec.overhang)
			and rect.grow(0.01).encloses(turn * Rect2(-spec.size * 0.5, spec.size)),
		"%s: the art covers the footprint and the overhang (%s)" % [id, rect],
	)


## The damage tint lands on the textured body as on a plain one.
func _check_tint(t: TestContext, rig: FurnitureRig, piece: Node) -> void:
	piece.physics.deformable.damage_total = 2000.0
	piece.physics.deformable.changed.emit()
	t.check(
		rig.body.get_instance_shader_parameter(&"base_color") == rig.tint()
			and rig.tint() != Color.WHITE,
		"the damage tint is written on the textured body",
	)
