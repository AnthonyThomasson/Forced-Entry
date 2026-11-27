extends GameTest
## A district's structure shares a few textures (#193 phase 2b): every wall, floor, street slab
## and door of the 3D mirror wears a painter's flat tile, so the textures number the distinct tiles
## and looks, not the pieces, and they are all read from the toon's atlas (`ToonAtlas`), so the
## materials number the tilings and cut-outs alone. The bound on textures is what a district of
## the catalogue's looks holds; the counts are in the checks' messages.

const MAX_TEXTURES := 60
## Tiled or not, cut out or not.
const MAX_MATERIALS := 4


func describe() -> Dictionary:
	return {
		"name": "A district's structure shares a few textures",
		"description": "A district mirrored in 3D: every wall segment, floor, street slab and door "
			+ "is textured, and the textures number the tiles and looks, not the pieces.",
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
	WorldGen.generate_district(7, "", Vector2.ZERO, t.world)
	await t.frames(3)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := MeshCarrier.new()
	view.add_child(mirror)
	ObjectMeshes.register(mirror.builders)
	mirror.carry(t.world)
	await t.frames(4)
	var textured := 0
	var parts := 0
	var materials := {}
	var textures := {}
	for body in _structure_bodies(t.world):
		for proxy in mirror.proxies_of(body):
			var meshes := proxy.find_children("*", "MeshInstance3D", true, false)
			if proxy is MeshInstance3D:
				meshes.append(proxy)
			for node in meshes:
				var material := (node as MeshInstance3D).material_override as ShaderMaterial
				parts += 1
				if _is_textured_toon(node as MeshInstance3D):
					textured += 1
					materials[material] = true
					textures[MeshNodes.shown_texture(node as MeshInstance3D)] = true
	t.check(
		textured > 100,
		"the district's structure is textured (%d of %d meshes)" % [textured, parts],
	)
	t.check(
		textures.size() > 0 and textures.size() <= MAX_TEXTURES,
		"%d textures serve %d textured meshes (at most %d)" % [
			textures.size(),
			textured,
			MAX_TEXTURES,
		],
	)
	t.check(
		materials.size() <= MAX_MATERIALS,
		"through %d materials (at most %d)" % [materials.size(), MAX_MATERIALS],
	)


## The district's walls, floors and doors (the furniture wears textures of its own).
func _structure_bodies(root: Node) -> Array:
	var out: Array = []
	for group in [&"floors", &"doors"]:
		for node: Node in root.get_tree().get_nodes_in_group(group):
			if root.is_ancestor_of(node):
				out.append(node)
	for node in NavTwins.walls_under(root):
		if node.has_method(&"segment_shapes"):
			out.append(node)
	return out


## Whether `material` is a textured toon (a decal, a wear mark, has a texture of its own too).
func _is_textured_toon(node: MeshInstance3D) -> bool:
	var material := node.material_override as ShaderMaterial
	return (
		material != null
		and material.shader.resource_path.ends_with("toon_tex.gdshader")
		and MeshNodes.shown_texture(node) != null
	)
