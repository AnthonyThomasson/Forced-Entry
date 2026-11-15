extends UnitSuite
## Native unit suite (pure logic) for the textured toon (`MeshNodes.textured`,
## `ToonMaterial.textured`; interface 12, #193 phase 2b): a mesh wearing the 2D painters' art.
## Expected values are the description's (one material per texture and tiling, shared by the nodes
## that show it; the rect
## in px becomes units by the one `RenderConfig.unit`; a null texture is plain toon; the material
## goes with its last node), never the cache's own bookkeeping. How it looks is judged windowed:
## `art/toon_tex_windowed`.


func _texture(color := Color.RED) -> ImageTexture:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _box() -> Mesh:
	return MeshKit.new().box(AABB(Vector3.ZERO, Vector3(8, 4, 8)), Color.WHITE).build()


func test_a_textured_mesh_is_a_node_in_the_textured_toon_showing_the_texture() -> void:
	var texture := _texture()
	var node := MeshNodes.textured(_box(), texture, Rect2(0, 0, 8, 8))
	assert_bool(node is MeshInstance3D).is_true()
	var material := node.material_override as ShaderMaterial
	assert_str(material.shader.resource_path).ends_with("toon_tex.gdshader")
	assert_object(material.get_shader_parameter(&"albedo_texture")).is_same(texture)
	assert_bool(material.get_shader_parameter(&"tiled")).is_false()
	assert_int(node.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	# Its bands are the shared toon's.
	var shared := ToonMaterial.shared()
	assert_int(material.get_shader_parameter(&"count")).is_equal(
		shared.get_shader_parameter(&"count")
	)
	node.free()


func test_one_material_per_texture_and_tiling_shared_by_the_nodes_showing_it() -> void:
	var red := _texture()
	var blue := _texture(Color.BLUE)
	var a := MeshNodes.textured(_box(), red, Rect2(0, 0, 8, 8))
	var b := MeshNodes.textured(_box(), red, Rect2(10, 10, 16, 16))
	var other := MeshNodes.textured(_box(), blue, Rect2(0, 0, 8, 8))
	var tiled := MeshNodes.textured(_box(), red, Rect2(0, 0, 8, 8), { "tiled": true })
	assert_object(b.material_override).is_same(a.material_override)
	assert_object(other.material_override).is_not_same(a.material_override)
	assert_object(tiled.material_override).is_not_same(a.material_override)
	var tiled_material := tiled.material_override as ShaderMaterial
	assert_bool(tiled_material.get_shader_parameter(&"tiled")).is_true()
	for node: Node in [a, b, other, tiled]:
		node.free()


func test_the_rect_is_px_in_and_units_out_per_instance() -> void:
	var unit := RenderConfig.unit
	RenderConfig.unit = 0.5
	var texture := _texture()
	var a := MeshNodes.textured(_box(), texture, Rect2(-20, -10, 40, 20))
	var b := MeshNodes.textured(_box(), texture, Rect2(0, 0, 8, 8))
	RenderConfig.unit = unit
	assert_object(a.material_override).is_same(b.material_override)
	assert_object(a.get_instance_shader_parameter(&"uv_rect")).is_equal(Vector4(-10, -5, 20, 10))
	assert_object(b.get_instance_shader_parameter(&"uv_rect")).is_equal(Vector4(0, 0, 4, 4))
	a.free()
	b.free()


func test_a_null_texture_is_the_plain_toon() -> void:
	var node := MeshNodes.textured(_box(), null, Rect2(0, 0, 8, 8))
	assert_object(node.material_override).is_same(ToonMaterial.shared())
	node.free()


func test_options_tint_and_shadow_a_new_node_and_an_existing_one() -> void:
	var texture := _texture()
	var tint := Color(0.2, 0.4, 0.6)
	var fresh := MeshNodes.textured(
		_box(), texture, Rect2(0, 0, 8, 8), { "tint": tint, "casts_shadow": false }
	)
	assert_bool(fresh.get_instance_shader_parameter(&"base_color").is_equal_approx(tint)).is_true()
	assert_int(fresh.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	# An existing node keeps its tint and shadow unless told, and is the node returned.
	var kept := MeshNodes.instance(_box(), tint, false)
	var same := MeshNodes.textured(kept, texture, Rect2(0, 0, 8, 8))
	assert_object(same).is_same(kept)
	assert_bool(kept.get_instance_shader_parameter(&"base_color").is_equal_approx(tint)).is_true()
	assert_int(kept.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_object(kept.material_override).is_same(fresh.material_override)
	# A batch is a geometry instance too.
	var batch := MeshNodes.batch(_box(), 2)
	MeshNodes.textured(batch, texture, Rect2(0, 0, 8, 8))
	assert_object(batch.material_override).is_same(fresh.material_override)
	for node: Node in [fresh, kept, batch]:
		node.free()


func test_the_material_goes_with_its_last_node_and_texture() -> void:
	var alive := ToonMaterial.textured_count()
	var node := MeshNodes.textured(_box(), _texture(Color.GREEN), Rect2(0, 0, 8, 8))
	assert_int(ToonMaterial.textured_count()).is_equal(alive + 1)
	node.free()
	# Nothing holds the material nor its texture now.
	assert_int(ToonMaterial.textured_count()).is_equal(alive)


func test_a_tuning_change_reaches_a_live_textured_material() -> void:
	var texture := _texture()
	var node := MeshNodes.textured(_box(), texture, Rect2(0, 0, 8, 8))
	var material := node.material_override as ShaderMaterial
	var dim := MeshKitConfig.textured_side_dim
	MeshKitConfig.textured_side_dim = 0.5
	ToonMaterial.refresh_all()
	var read: float = material.get_shader_parameter(&"side_dim")
	MeshKitConfig.textured_side_dim = dim
	assert_float(read).is_equal_approx(0.5, 0.0001)
	node.free()


func test_the_textured_toon_and_the_toon_share_one_light() -> void:
	# The shaders are one source: each includes the shared include, none restates light().
	for path in [
		"res://scenes/art/post/toon.gdshader",
		"res://scenes/art/post/toon_tex.gdshader",
		"res://scenes/art/post/decal.gdshader",
	]:
		var code := FileAccess.get_file_as_string(path)
		var includes := code.contains("toon_common.gdshaderinc")
		assert_bool(includes).override_failure_message(path).is_true()
		assert_bool(code.contains("void light()")).override_failure_message(path).is_false()
