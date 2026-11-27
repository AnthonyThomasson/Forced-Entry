extends UnitSuite
## Native unit suite (pure logic) for the textured toon (`MeshNodes.textured`,
## `ToonMaterial.textured`; interface 12, #193 phase 2b): a mesh wearing the 2D painters' art.
## Expected values are the description's (one material per tiling and cut-out, shared by every node
## whatever its art, which each node's atlas place says; the rect in px becomes units by the one
## `RenderConfig.unit`; a null texture is plain toon; a texture's place goes with its last node),
## never the cache's own bookkeeping. How it looks is judged windowed: `art/toon_tex_windowed`.


func _texture(color := Color.RED) -> ImageTexture:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


## Whether `node`'s tint (its `base_color`) is `want`.
func _base(node: GeometryInstance3D, want: Color) -> bool:
	var got: Variant = node.get_instance_shader_parameter(&"base_color")
	return got is Color and (got as Color).is_equal_approx(want)


func _box() -> Mesh:
	return MeshKit.new().box(AABB(Vector3.ZERO, Vector3(8, 4, 8)), Color.WHITE).build()


func test_a_textured_mesh_is_a_node_in_the_textured_toon_showing_the_texture() -> void:
	var texture := _texture()
	var node := MeshNodes.textured(_box(), texture, Rect2(0, 0, 8, 8))
	assert_bool(node is MeshInstance3D).is_true()
	var material := node.material_override as ShaderMaterial
	assert_str(material.shader.resource_path).ends_with("toon_tex.gdshader")
	assert_object(MeshNodes.shown_texture(node)).is_same(texture)
	assert_bool(material.get_shader_parameter(&"tiled")).is_false()
	assert_int(node.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	# Its bands are the shared toon's.
	var shared := ToonMaterial.shared()
	assert_int(material.get_shader_parameter(&"count")).is_equal(
		shared.get_shader_parameter(&"count")
	)
	node.free()


func test_one_material_per_tiling_shared_by_every_texture() -> void:
	var red := _texture()
	var blue := _texture(Color.BLUE)
	var a := MeshNodes.textured(_box(), red, Rect2(0, 0, 8, 8))
	var b := MeshNodes.textured(_box(), red, Rect2(10, 10, 16, 16))
	var other := MeshNodes.textured(_box(), blue, Rect2(0, 0, 8, 8))
	var tiled := MeshNodes.textured(_box(), red, Rect2(0, 0, 8, 8), { "tiled": true })
	assert_object(b.material_override).is_same(a.material_override)
	assert_object(other.material_override).is_same(a.material_override)
	assert_object(tiled.material_override).is_not_same(a.material_override)
	# Each node says where its own texture lies: two textures are two places, one is one.
	var at: Variant = a.get_instance_shader_parameter(&"atlas_rect")
	assert_that(b.get_instance_shader_parameter(&"atlas_rect")).is_equal(at)
	assert_that(other.get_instance_shader_parameter(&"atlas_rect")).is_not_equal(at)
	var tiled_material := tiled.material_override as ShaderMaterial
	assert_bool(tiled_material.get_shader_parameter(&"tiled")).is_true()
	for node: Node in [a, b, other, tiled]:
		node.free()


func test_a_cutout_node_has_a_material_of_its_own_that_draws_no_clear_texel() -> void:
	var red := _texture()
	var plain := MeshNodes.textured(_box(), red, Rect2(0, 0, 8, 8))
	var cut := MeshNodes.textured(_box(), red, Rect2(0, 0, 8, 8), { "cutout": true })
	var again := MeshNodes.textured(_box(), red, Rect2(0, 0, 8, 8), { "cutout": true })
	assert_object(cut.material_override).is_not_same(plain.material_override)
	assert_object(again.material_override).is_same(cut.material_override)
	assert_bool((cut.material_override as ShaderMaterial).get_shader_parameter(&"cutout")).is_true()
	assert_bool(
		(plain.material_override as ShaderMaterial).get_shader_parameter(&"cutout") == true,
	).is_false()
	for node: Node in [plain, cut, again]:
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
	assert_bool(_base(fresh, tint)).is_true()
	assert_int(fresh.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	# An existing node keeps its tint and shadow unless told, and is the node returned.
	var kept := MeshNodes.instance(_box(), tint, false)
	var same := MeshNodes.textured(kept, texture, Rect2(0, 0, 8, 8))
	assert_object(same).is_same(kept)
	assert_bool(_base(kept, tint)).is_true()
	assert_int(kept.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_object(kept.material_override).is_same(fresh.material_override)
	# A batch is a geometry instance too.
	var batch := MeshNodes.batch(_box(), 2)
	MeshNodes.textured(batch, texture, Rect2(0, 0, 8, 8))
	assert_object(batch.material_override).is_same(fresh.material_override)
	for node: Node in [fresh, kept, batch]:
		node.free()


func test_a_node_never_tinted_is_white_not_the_toon_grey() -> void:
	var texture := _texture()
	var bare := MeshInstance3D.new()
	bare.mesh = _box()
	MeshNodes.textured(bare, texture, Rect2(0, 0, 8, 8))
	assert_bool(_base(bare, Color.WHITE)).is_true()
	var batch := MeshNodes.batch(_box(), 2)
	MeshNodes.textured(batch, texture, Rect2(0, 0, 8, 8))
	assert_bool(_base(batch, Color.WHITE)).is_true()
	# A tint it was given stays, and an option sets it.
	var tint := Color(0.2, 0.4, 0.6)
	var tinted := MeshNodes.instance(_box(), tint)
	MeshNodes.textured(tinted, texture, Rect2(0, 0, 8, 8))
	assert_bool(_base(tinted, tint)).is_true()
	MeshNodes.textured(tinted, texture, Rect2(0, 0, 8, 8), { "tint": Color.RED })
	assert_bool(_base(tinted, Color.RED)).is_true()
	for node: Node in [bare, batch, tinted]:
		node.free()


func test_a_texture_is_counted_while_a_node_or_a_caller_holds_it() -> void:
	var alive := ToonMaterial.textured_count()
	var node := MeshNodes.textured(_box(), _texture(Color.GREEN), Rect2(0, 0, 8, 8))
	assert_int(ToonMaterial.textured_count()).is_equal(alive + 1)
	node.free()
	# Nothing holds the texture now.
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


## A texture of `size` whose texels are all unalike, in the order they are laid.
func _speckled(size: Vector2i, seed_value: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			image.set_pixel(x, y, Color.hex(rng.randi()))
	return ImageTexture.create_from_image(image)


func test_the_atlas_holds_every_texture_whole_in_a_place_of_its_own() -> void:
	var nodes: Array[GeometryInstance3D] = []
	var rects: Array[Rect2] = []
	var sizes := [
		Vector2i(64, 64), Vector2i(200, 32), Vector2i(300, 300), Vector2i(7, 5),
		Vector2i(256, 256), Vector2i(256, 256), Vector2i(130, 30),
	]
	for i in sizes.size():
		var texture := _speckled(sizes[i], i)
		var node := MeshNodes.textured(_box(), texture, Rect2(0, 0, 8, 8))
		nodes.append(node)
		var at: Vector4 = node.get_instance_shader_parameter(&"atlas_rect")
		var held := ToonAtlas.pixels(at)
		assert_vector(held.get_size()).is_equal(sizes[i])
		assert_bool(held.get_data() == texture.get_image().get_data()).override_failure_message(
			"texture %d is copied whole" % i
		).is_true()
		var page := floorf(at.x / ToonAtlas.LAYER_STEP)
		var corner := Vector2(at.x - page * ToonAtlas.LAYER_STEP, at.y)
		assert_bool(
			Rect2(Vector2.ZERO, Vector2.ONE * PixelPostConfig.atlas_page).encloses(
				Rect2(corner, Vector2(at.z, at.w))
			)
		).override_failure_message("texture %d lies inside its page" % i).is_true()
		# Pages are put side by side, so two places never overlap.
		var spot := Rect2(
			corner + Vector2(page * PixelPostConfig.atlas_page, 0),
			Vector2(at.z, at.w),
		)
		for other in rects:
			assert_bool(spot.intersects(other)).is_false()
		rects.append(spot)
	for node in nodes:
		node.free()


func test_the_place_of_a_freed_texture_goes_to_the_next_of_its_size() -> void:
	var size := Vector2i(61, 43)
	var first := MeshNodes.textured(_box(), _speckled(size, 1), Rect2(0, 0, 8, 8))
	var at: Vector4 = first.get_instance_shader_parameter(&"atlas_rect")
	first.free()
	ToonAtlas.forget_freed()
	var texture := _speckled(size, 2)
	var second := MeshNodes.textured(_box(), texture, Rect2(0, 0, 8, 8))
	assert_that(second.get_instance_shader_parameter(&"atlas_rect")).is_equal(at)
	assert_bool(ToonAtlas.pixels(at).get_data() == texture.get_image().get_data()).is_true()
	second.free()


func test_a_texture_too_large_for_the_atlas_keeps_a_material_of_its_own() -> void:
	var side := PixelPostConfig.atlas_page
	var large := _speckled(Vector2i(side + 1, 4), 3)
	var node := MeshNodes.textured(_box(), large, Rect2(0, 0, 8, 8))
	var material := node.material_override as ShaderMaterial
	assert_bool(material.get_shader_parameter(&"atlased")).is_false()
	assert_object(material.get_shader_parameter(&"albedo_texture")).is_same(large)
	assert_object(MeshNodes.shown_texture(node)).is_same(large)
	var small := MeshNodes.textured(_box(), _texture(), Rect2(0, 0, 8, 8))
	var other := small.material_override as ShaderMaterial
	assert_bool(other.get_shader_parameter(&"atlased")).is_true()
	node.free()
	small.free()


## A texture a whole page of the atlas, so the next like it opens a page.
func _page() -> ImageTexture:
	var side := PixelPostConfig.atlas_page
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(image)


## The pages the array holds beyond those in use.
func _spare_pages() -> int:
	return ToonAtlas.array().get_layers() - ToonAtlas.pages_used()


func test_a_page_opened_after_a_reserve_does_not_remake_the_array() -> void:
	var nodes: Array[GeometryInstance3D] = [
		MeshNodes.textured(_box(), _texture(), Rect2(0, 0, 8, 8)),
	]
	ToonAtlas.flush()
	# eat into the spare, then ask for it again
	while _spare_pages() >= ToonAtlas.GROW:
		nodes.append(MeshNodes.textured(_box(), _page(), Rect2(0, 0, 8, 8)))
		ToonAtlas.flush()
	ToonAtlas.reserve()
	ToonAtlas.flush()
	assert_int(_spare_pages()).is_greater_equal(ToonAtlas.GROW)
	var layers := ToonAtlas.array().get_layers()
	var used := ToonAtlas.pages_used()
	for i in ToonAtlas.GROW:
		nodes.append(MeshNodes.textured(_box(), _page(), Rect2(0, 0, 8, 8)))
		ToonAtlas.flush()
	assert_int(ToonAtlas.pages_used()).is_equal(used + ToonAtlas.GROW)
	assert_int(ToonAtlas.array().get_layers()).is_equal(layers)
	for node in nodes:
		node.free()


func test_warming_a_texture_puts_it_in_the_atlas_before_a_node_shows_it() -> void:
	var texture := _speckled(Vector2i(12, 9), 11)
	assert_bool(ToonAtlas.holds(texture)).is_false()
	MeshNodes.warm_textured(texture)
	assert_bool(ToonAtlas.holds(texture)).is_true()
	var large := _speckled(Vector2i(PixelPostConfig.atlas_page + 1, 4), 12)
	MeshNodes.warm_textured(large)
	MeshNodes.warm_textured(null)
	assert_bool(ToonAtlas.holds(large)).is_false()
