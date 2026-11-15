extends UnitSuite
## Native unit suite (pure logic) for Art's mesh-kit node helpers (`MeshNodes`, interface 12): where
## a part is placed, how a surface's frame is laid and the node a built mesh is shown by. The
## expected values are read off the descriptions (a decal facing up is the identity frame; one on
## a wall stands its texture upright; the one conversion is `RenderConfig.unit`), never worked out
## the way the helpers do.


func test_place_puts_a_part_at_px_in_units_and_turns_it_about_up() -> void:
	var unit := RenderConfig.unit
	RenderConfig.unit = 0.5
	var node := Node3D.new()
	MeshNodes.place(node, Vector3(10, 20, 30), 0.5)
	RenderConfig.unit = unit
	assert_vector(node.position).is_equal_approx(Vector3(5, 10, 15), Vector3.ONE * 0.001)
	assert_float(node.rotation.y).is_equal_approx(0.5, 0.001)
	node.free()


func test_a_surface_facing_up_is_the_identity_frame() -> void:
	var frame := MeshNodes.surface_frame(Vector3(4, 5, 6))
	assert_vector(frame.origin).is_equal(Vector3(4, 5, 6))
	assert_vector(frame.basis.x).is_equal_approx(Vector3.RIGHT, Vector3.ONE * 0.001)
	assert_vector(frame.basis.y).is_equal_approx(Vector3.UP, Vector3.ONE * 0.001)
	assert_vector(frame.basis.z).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.001)


func test_a_wall_frame_faces_the_wall_and_stands_the_texture_upright() -> void:
	# A wall whose face looks toward +z: the decal's up is +z, and the top of its texture (local
	# -z) points up the wall, to +y.
	var frame := MeshNodes.surface_frame(Vector3.ZERO, Vector3.BACK)
	assert_vector(frame.basis.y).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.001)
	assert_vector(-frame.basis.z).is_equal_approx(Vector3.UP, Vector3.ONE * 0.001)
	# A proper rotation (no mirror image): x cross y is z.
	assert_vector(frame.basis.x.cross(frame.basis.y)).is_equal_approx(
		frame.basis.z, Vector3.ONE * 0.001
	)


func test_spin_turns_a_decal_about_its_own_normal() -> void:
	var frame := MeshNodes.surface_frame(Vector3.ZERO, Vector3.UP, PI * 0.5)
	assert_vector(frame.basis.y).is_equal_approx(Vector3.UP, Vector3.ONE * 0.001)
	# A quarter turn about up takes +x to a horizontal axis at a right angle to where it was.
	assert_float(frame.basis.x.dot(Vector3.RIGHT)).is_equal_approx(0.0, 0.001)
	assert_float(absf(frame.basis.x.y)).is_equal_approx(0.0, 0.001)


func test_an_instance_is_the_shared_material_tinted_and_casting_a_shadow() -> void:
	var mesh := MeshKit.new().box(AABB(Vector3.ZERO, Vector3.ONE), Color.WHITE).build()
	var node := MeshNodes.instance(mesh, Color(0.2, 0.4, 0.6))
	assert_object(node.mesh).is_same(mesh)
	assert_object(node.material_override).is_same(ToonMaterial.shared())
	assert_bool(
		node.get_instance_shader_parameter(&"base_color").is_equal_approx(Color(0.2, 0.4, 0.6))
	).is_true()
	assert_int(node.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	var quiet := MeshNodes.instance(mesh, Color.WHITE, false)
	assert_int(quiet.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	node.free()
	quiet.free()


func test_a_decal_floats_off_its_surface_along_the_normal_and_casts_no_shadow() -> void:
	var frame := MeshNodes.surface_frame(Vector3(10, 20, 30))
	var decal := MeshNodes.decal(Vector2(8, 6), frame)
	assert_vector(decal.position).is_equal_approx(
		Vector3(10, 20.0 + 0.15, 30), Vector3.ONE * 0.001
	)  # 0.15 px: the decal lift
	assert_int(decal.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var box := decal.mesh.get_aabb()
	assert_vector(box.size).is_equal_approx(Vector3(8, 0, 6), Vector3.ONE * 0.001)
	decal.free()


func test_a_decal_layer_lifts_it_a_step_more_along_the_normal() -> void:
	var frame := MeshNodes.surface_frame(Vector3(10, 4, 20), Vector3(1, 0, 0))
	var base := MeshNodes.decal(Vector2(8, 6), frame)
	var layered := MeshNodes.decal(Vector2(8, 6), frame, null, Color.WHITE, 2.5)
	assert_vector(base.position).is_equal_approx(Vector3(10.15, 4, 20), Vector3.ONE * 0.001)
	# 2.5 layers of 0.25 px more, along the normal (+x) only
	assert_vector(layered.position).is_equal_approx(
		Vector3(10.15 + 0.625, 4, 20), Vector3.ONE * 0.001
	)
	base.free()
	layered.free()


func test_a_decal_material_follows_a_retuned_band_count() -> void:
	var bands := PixelPostConfig.bands
	var material := ToonMaterial.decal(null)
	PixelPostConfig.bands = 4
	ToonMaterial.refresh_all()
	var got: Variant = material.get_shader_parameter(&"count")
	PixelPostConfig.bands = bands
	ToonMaterial.refresh_all()
	assert_int(got).is_equal(4)
	assert_object(ToonMaterial.decal(null)).is_same(material)  # one per texture


func test_a_texture_on_every_wall_facing_stands_upright_and_reads_left_to_right() -> void:
	# Seen from outside the wall (looking along minus its normal, up the screen), the texture's top
	# (local -z) points up and its right (local +x, the way u grows) is the viewer's right: the
	# right of a viewer looking along `look` with `up` above is look x up.
	for normal in [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]:
		var frame := MeshNodes.surface_frame(Vector3.ZERO, normal)
		assert_vector(frame.basis.y).is_equal_approx(normal, Vector3.ONE * 0.001)
		assert_vector(-frame.basis.z).override_failure_message(
			"the top of a texture on a wall facing %s points up" % normal
		).is_equal_approx(Vector3.UP, Vector3.ONE * 0.001)
		assert_vector(frame.basis.x).override_failure_message(
			"a texture on a wall facing %s is not mirrored" % normal
		).is_equal_approx((-normal).cross(Vector3.UP), Vector3.ONE * 0.001)
		assert_float(frame.basis.determinant()).is_equal_approx(1.0, 0.001)


func test_a_spun_wall_decal_turns_about_its_normal() -> void:
	for normal in [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]:
		var plain := MeshNodes.surface_frame(Vector3.ZERO, normal)
		var turned := MeshNodes.surface_frame(Vector3.ZERO, normal, 0.7)
		assert_vector(turned.basis.y).is_equal_approx(normal, Vector3.ONE * 0.001)
		assert_vector(-turned.basis.z).is_equal_approx(
			Vector3.UP.rotated(normal, 0.7), Vector3.ONE * 0.001
		)
		assert_vector(turned.basis.x).is_equal_approx(
			plain.basis.x.rotated(normal, 0.7), Vector3.ONE * 0.001
		)


func test_a_decal_material_goes_with_its_last_decal() -> void:
	var held := ToonMaterial.decal_count()
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	var seen: WeakRef = weakref(texture)
	var decal := MeshNodes.decal(Vector2(4, 4), Transform3D(), texture)
	var again := MeshNodes.decal(Vector2(6, 6), Transform3D(), texture)
	texture = null
	assert_bool(decal.material_override == again.material_override).is_true()  # one per texture
	assert_int(ToonMaterial.decal_count()).is_equal(held + 1)
	decal.free()
	assert_int(ToonMaterial.decal_count()).is_equal(held + 1)  # the other still shows it
	again.free()
	assert_int(ToonMaterial.decal_count()).is_equal(held)
	assert_object(seen.get_ref()).override_failure_message("its texture is freed").is_null()


func test_a_batch_is_one_node_of_many_parts_with_no_shadow() -> void:
	var mesh := MeshKit.new().box(AABB(Vector3.ZERO, Vector3.ONE), Color.WHITE).build()
	var batch := MeshNodes.batch(mesh, 100)
	assert_int(batch.multimesh.instance_count).is_equal(100)
	assert_object(batch.multimesh.mesh).is_same(mesh)
	assert_object(batch.material_override).is_same(ToonMaterial.shared())
	assert_int(batch.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_int(batch.multimesh.visible_instance_count).is_equal(0)  # nothing till shown
	MeshNodes.batch_show(batch, 7)
	assert_int(batch.multimesh.visible_instance_count).is_equal(7)
	MeshNodes.batch_show(batch, 500)
	assert_int(batch.multimesh.visible_instance_count).is_equal(100)  # no more than it holds
	batch.free()


func test_a_part_of_a_batch_stands_where_place_would_put_a_node() -> void:
	var unit := RenderConfig.unit
	RenderConfig.unit = 0.5
	var frame := MeshNodes.part_frame(Vector3(10, 20, 30), 0.5)
	RenderConfig.unit = unit
	assert_vector(frame.origin).is_equal_approx(Vector3(5, 10, 15), Vector3.ONE * 0.001)
	assert_float(frame.basis.get_euler().y).is_equal_approx(0.5, 0.001)


func test_a_figure_is_marked_for_the_post_and_a_plain_node_is_not() -> void:
	var mesh := MeshKit.new().box(AABB(Vector3.ZERO, Vector3.ONE), Color.WHITE).build()
	var node := MeshNodes.instance(mesh)
	assert_bool(node.get_instance_shader_parameter(&"figure") == 1.0).is_false()
	MeshNodes.figure(node)
	assert_float(node.get_instance_shader_parameter(&"figure")).is_equal(1.0)
	MeshNodes.figure(node, false)
	assert_float(node.get_instance_shader_parameter(&"figure")).is_equal(0.0)
	node.free()
