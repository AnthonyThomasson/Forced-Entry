extends GameTest
## A district's structure shares a few textured materials (#193 phase 2b): every wall, floor,
## street slab and door of the 3D mirror wears a painter's flat tile, and one tile is one material
## (`ToonMaterial.textured`: a material per texture and tiling), so the count is the number of
## distinct tiles and looks, not of pieces. The bound is what a district of the catalogue's looks
## holds; the count is in the check's message.

const MAX_MATERIALS := 60


func describe() -> Dictionary:
	return {
		"name": "A district's structure shares a few textured materials",
		"description": "A district mirrored in 3D: every wall segment, floor, street slab and door "
			+ "is textured, and the textured materials number the tiles and looks, not the pieces.",
		"tags": ["mirror", "3d", "render", "perf", "walls", "floors"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(ArtCanvasConfig, &"pixel_size", 1.0)
	s.von_script([])


func run(t: TestContext) -> void:
	var before := ToonMaterial.textured_count()
	WorldGen.generate_district(7, "", Vector2.ZERO, t.world)
	await t.frames(3)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	ObjectMeshes.register(mirror.builders)
	mirror.mirror(t.world)
	await t.frames(4)
	var textured := 0
	var parts := 0
	for node in view.find_children("*", "MeshInstance3D", true, false):
		var material := (node as MeshInstance3D).material_override as ShaderMaterial
		parts += 1
		if material != null and material.get_shader_parameter(&"albedo_texture") != null:
			textured += 1
	var materials := ToonMaterial.textured_count() - before
	t.check(
		textured > 100,
		"the district's structure is textured (%d of %d meshes)" % [textured, parts],
	)
	t.check(
		materials > 0 and materials <= MAX_MATERIALS,
		"%d textured materials serve %d textured meshes (at most %d)" % [
			materials,
			textured,
			MAX_MATERIALS,
		],
	)
