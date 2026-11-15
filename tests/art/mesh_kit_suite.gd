extends UnitSuite
## Native unit suite (pure logic) for Art's mesh kit (`MeshKit`, `MeshCache`; interface 12, #193
## phase 2): the solids a builder composes a piece from. Every expected number is read off the
## solid's description (a box over a footprint is that footprint wide, the height tall; a face of a
## convex solid points away from its middle), the winding against the engine's own `Plane`, never
## worked out the way the kit does. The kit works in px and `build()` converts with
## `RenderConfig.unit` in the one place: a test that changes the unit puts it back.

const RED := Color(0.8, 0.2, 0.2)
const BLUE := Color(0.2, 0.3, 0.8)
const FOOTPRINT := Rect2(10, 20, 40, 30)


## Each triangle of `mesh` as `{ points, normal, colour }` (colour back in sRGB).
func _triangles(mesh: ArrayMesh) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if mesh.get_surface_count() == 0:
		return out
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in range(0, vertices.size(), 3):
		out.append({
			"points": [vertices[i], vertices[i + 1], vertices[i + 2]],
			"normal": normals[i],
			"colour": colours[i].linear_to_srgb(),
		})
	return out


## The volume over `FOOTPRINT` from `base` up `height`.
func _vol(base: float, height: float) -> AABB:
	return MeshKit.volume(FOOTPRINT, base, height)


func _centre(triangle: Dictionary) -> Vector3:
	var points: Array = triangle["points"]
	return (points[0] + points[1] + points[2]) / 3.0


func _area(triangle: Dictionary) -> float:
	var p: Array = triangle["points"]
	return ((p[1] - p[0]) as Vector3).cross(p[2] - p[0]).length() * 0.5


## Every triangle of a convex solid points away from the middle of its box, and the stored normal is
## the engine's (`Plane` of its three points, wound clockwise from the front).
func _assert_outward(mesh: ArrayMesh, inside := Vector3.INF) -> void:
	var middle := mesh.get_aabb().get_center() if inside == Vector3.INF else inside
	for triangle in _triangles(mesh):
		var p: Array = triangle["points"]
		var engine := Plane(p[0], p[1], p[2]).normal
		assert_float(engine.dot(triangle["normal"])).override_failure_message(
			"the winding of %s faces the way its normal says" % [p]
		).is_greater(0.99)
		var away: float = (triangle["normal"] as Vector3).dot(_centre(triangle) - middle)
		assert_float(away).override_failure_message(
			"the face at %s points away from the solid" % [_centre(triangle)]
		).is_greater_equal(0.0)


func _assert_aabb(mesh: ArrayMesh, position: Vector3, size: Vector3) -> void:
	var box := mesh.get_aabb()
	assert_vector(box.position).is_equal_approx(position, Vector3.ONE * 0.001)
	assert_vector(box.size).is_equal_approx(size, Vector3.ONE * 0.001)


func test_a_box_stands_on_its_footprint_at_its_height() -> void:
	var mesh := MeshKit.new().box(_vol(6.0, 25.0), RED).build()
	# 2D (x, y) is 3D (x, height, y): x 10..50, height 6..31, depth 20..50.
	_assert_aabb(mesh, Vector3(10, 6, 20), Vector3(40, 25, 30))
	assert_int(_triangles(mesh).size()).is_equal(12)
	_assert_outward(mesh)


func test_a_box_top_takes_its_own_colour_and_the_rest_the_main_one() -> void:
	var mesh := MeshKit.new().box(_vol(0.0, 10.0), RED, BLUE).build()
	var tops := 0
	for triangle in _triangles(mesh):
		var up := (triangle["normal"] as Vector3).dot(Vector3.UP) > 0.99
		var wanted := BLUE if up else RED
		assert_bool(_close(triangle["colour"], wanted)).override_failure_message(
			"face facing %s is %s, wanted %s" % [triangle["normal"], triangle["colour"], wanted]
		).is_true()
		tops += 1 if up else 0
	assert_int(tops).is_equal(2)  # the top is two triangles


func test_a_face_without_a_top_colour_is_the_main_colour_all_over() -> void:
	for triangle in _triangles(MeshKit.new().box(_vol(0.0, 10.0), RED).build()):
		assert_bool(_close(triangle["colour"], RED)).is_true()


func test_the_kit_converts_px_to_units_in_one_place() -> void:
	var unit := RenderConfig.unit
	RenderConfig.unit = 0.5
	var mesh := MeshKit.new().box(_vol(6.0, 25.0), RED).build()
	RenderConfig.unit = unit
	_assert_aabb(mesh, Vector3(5, 3, 10), Vector3(20, 12.5, 15))


func test_a_wedge_rises_toward_the_named_side_and_is_a_knife_edge_on_the_other() -> void:
	var mesh := MeshKit.new().wedge(_vol(0.0, 20.0), Vector2.RIGHT, RED, BLUE).build()
	_assert_aabb(mesh, Vector3(10, 0, 20), Vector3(40, 20, 30))
	for triangle in _triangles(mesh):
		for p: Vector3 in triangle["points"]:
			if p.y > 0.001:
				assert_float(p.x).override_failure_message("height only on the high side").is_equal(
					50.0
				)
	_assert_outward(mesh, Vector3(30, 2, 35))  # a wedge's box centre lies on its slope
	# The slope is the top: it leans toward the low side (-x) and up, so a sun there lights it.
	var slope := 0
	for triangle in _triangles(mesh):
		var normal: Vector3 = triangle["normal"]
		if normal.y > 0.1 and normal.x < -0.1:
			slope += 1
			assert_bool(_close(triangle["colour"], BLUE)).is_true()
	assert_int(slope).is_equal(2)
	# Turned the other way it rises on the near side (-y of the 2D frame, -z).
	var up_screen := MeshKit.new().wedge(_vol(0.0, 20.0), Vector2.UP, RED).build()
	for triangle in _triangles(up_screen):
		for p: Vector3 in triangle["points"]:
			if p.y > 0.001:
				assert_float(p.z).is_equal(20.0)
	_assert_outward(up_screen, Vector3(30, 2, 35))


func test_a_cylinder_is_as_wide_as_its_radius_and_as_tall_as_its_height() -> void:
	var kit := MeshKit.new()
	kit.sides = 8
	var mesh := kit.cylinder(Vector3(100, 0, 60), 8.0, 30.0, RED, BLUE).build()
	var box := mesh.get_aabb()
	assert_float(box.size.y).is_equal_approx(30.0, 0.001)
	assert_float(box.size.x).is_equal_approx(16.0, 0.001)  # a vertex sits on the x axis
	assert_vector(box.get_center()).is_equal_approx(Vector3(100, 15, 60), Vector3.ONE * 0.001)
	# 8 sides: 8 side quads (16 triangles), and an octagon (6 triangles) as lid and as base.
	assert_int(_triangles(mesh).size()).is_equal(28)
	_assert_outward(mesh)


func test_an_extruded_l_shape_has_the_l_s_area_on_top_either_way_round() -> void:
	var l_shape := PackedVector2Array([
		Vector2(0, 0), Vector2(40, 0), Vector2(40, 20), Vector2(20, 20), Vector2(20, 40),
		Vector2(0, 40),
	])
	var reversed := PackedVector2Array(l_shape)
	reversed.reverse()
	for polygon in [l_shape, reversed]:
		var mesh := MeshKit.new().extrude(polygon, 4.0, 10.0, RED, BLUE).build()
		_assert_aabb(mesh, Vector3(0, 4, 0), Vector3(40, 10, 40))
		var top := 0.0
		var side := 0.0
		for triangle in _triangles(mesh):
			var normal: Vector3 = triangle["normal"]
			if normal.dot(Vector3.UP) > 0.99:
				top += _area(triangle)
				assert_bool(_close(triangle["colour"], BLUE)).is_true()
			elif absf(normal.y) < 0.01:
				side += _area(triangle)
		# 40 x 40 less the 20 x 20 notch, and the walls: the outline's 160 px times the height.
		assert_float(top).is_equal_approx(1200.0, 0.01)
		assert_float(side).is_equal_approx(160.0 * 10.0, 0.01)
		for triangle in _triangles(mesh):
			var p: Array = triangle["points"]
			assert_float(Plane(p[0], p[1], p[2]).normal.dot(triangle["normal"])).is_greater(0.99)


func test_an_extruded_walls_face_away_from_the_inside() -> void:
	# Walls of a concave solid: every side face's normal points away from the polygon's own area.
	var l_shape := PackedVector2Array([
		Vector2(0, 0), Vector2(40, 0), Vector2(40, 20), Vector2(20, 20), Vector2(20, 40),
		Vector2(0, 40),
	])
	for triangle in _triangles(MeshKit.new().extrude(l_shape, 0.0, 10.0, RED).build()):
		var normal: Vector3 = triangle["normal"]
		if absf(normal.y) > 0.01:
			continue
		var at := _centre(triangle)
		# A step outward along the normal leaves the L; a step inward is inside it.
		var out := Vector2(at.x, at.z) + Vector2(normal.x, normal.z) * 0.5
		var inside := Vector2(at.x, at.z) - Vector2(normal.x, normal.z) * 0.5
		assert_bool(Geometry2D.is_point_in_polygon(out, l_shape)).is_false()
		assert_bool(Geometry2D.is_point_in_polygon(inside, l_shape)).is_true()


func test_a_loft_sweeps_its_profile_along_its_path_and_closes_the_ends() -> void:
	# A 4 x 4 square profile along a straight 30 px path on x, at height 10 on the line y = 5.
	var square := PackedVector2Array([
		Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2),
	])
	var path := PackedVector3Array([Vector3(0, 10, 5), Vector3(30, 10, 5)])
	var mesh := MeshKit.new().loft(path, square, RED).build()
	_assert_aabb(mesh, Vector3(0, 8, 3), Vector3(30, 4, 4))
	# Four side quads (8 triangles) and a fan of 4 on each end.
	assert_int(_triangles(mesh).size()).is_equal(16)
	_assert_outward(mesh)
	var ends := 0
	for triangle in _triangles(mesh):
		if absf((triangle["normal"] as Vector3).x) > 0.99:
			ends += 1
	assert_int(ends).is_equal(8)


func test_a_loft_follows_a_bend() -> void:
	var square := PackedVector2Array([
		Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1),
	])
	var path := PackedVector3Array([Vector3(0, 5, 0), Vector3(20, 5, 0), Vector3(20, 5, 20)])
	var mesh := MeshKit.new().loft(path, square, RED).build()
	var box := mesh.get_aabb()
	# The rail runs 20 along x then 20 along y (z in 3D): its box is the L's, a tube wide.
	assert_float(box.size.y).is_equal_approx(2.0, 0.01)
	assert_bool(box.size.x >= 20.0 and box.size.z >= 20.0).is_true()
	assert_bool(box.size.x < 23.0 and box.size.z < 23.0).is_true()


func test_a_tone_is_a_pick_of_the_art_ramp() -> void:
	var base := Color(0.5, 0.4, 0.3)
	# `ArtSurfaceConfig.tones` darkens a tone and lightens a highlight: a shadow is darker than the
	# base, a highlight lighter, and the base itself is the base.
	assert_bool(MeshKit.tone(base, &"base").is_equal_approx(base)).is_true()
	assert_float(MeshKit.tone(base, &"shadow").get_luminance()).is_less(base.get_luminance())
	assert_float(MeshKit.tone(base, &"highlight").get_luminance()).is_greater(base.get_luminance())


func test_an_empty_kit_builds_an_empty_mesh() -> void:
	assert_int(MeshKit.new().build().get_surface_count()).is_equal(0)


func test_a_lopsided_loft_faces_are_each_their_own_planes_normal() -> void:
	# A right-triangle profile (a wedge-shaped rail): x across the path, y up. Along +x, across is
	# +z in 3D and up is +y, so the slanted face leans toward +z and up: normal (0, 10, 6) / |.|.
	var triangle := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(0, 6)])
	var path := PackedVector3Array([Vector3(0, 10, 0), Vector3(30, 10, 0)])
	var mesh := MeshKit.new().loft(path, triangle, RED).build()
	# The triangle's own middle (a third of the way along each leg), not its box's: that lies on the
	# slanted face.
	_assert_outward(mesh, Vector3(15, 12, 10.0 / 3.0))
	var slanted := Vector3(0, 10, 6).normalized()
	var found := 0
	for face in _triangles(mesh):
		if (face["normal"] as Vector3).dot(slanted) > 0.99:
			found += 1
	assert_int(found).override_failure_message("the slanted face has its own normal").is_equal(2)


func test_a_sphere_fills_the_cube_of_its_radius_and_faces_outward() -> void:
	var kit := MeshKit.new()
	kit.sides = 12
	var mesh := kit.sphere(Vector3(40, 10, 30), 8.0, RED).build()
	_assert_aabb(mesh, Vector3(32, 2, 22), Vector3(16, 16, 16))
	_assert_outward(mesh, Vector3(40, 10, 30))


func test_a_capsule_is_its_radius_wide_and_its_height_tall() -> void:
	var kit := MeshKit.new()
	kit.sides = 12
	var mesh := kit.capsule(Vector3(40, 4, 30), 6.0, 30.0, RED).build()
	_assert_aabb(mesh, Vector3(34, 4, 24), Vector3(12, 30, 12))
	_assert_outward(mesh, Vector3(40, 19, 30))


func test_a_capsule_no_taller_than_its_caps_is_a_sphere() -> void:
	var kit := MeshKit.new()
	kit.sides = 12
	var mesh := kit.capsule(Vector3.ZERO, 6.0, 4.0, RED).build()
	assert_float(mesh.get_aabb().size.y).is_equal_approx(12.0, 0.001)


func test_a_cone_stands_on_its_base_and_ends_in_a_point() -> void:
	var kit := MeshKit.new()
	kit.sides = 12
	var mesh := kit.cone(Vector3(40, 2, 30), 8.0, 20.0, RED).build()
	_assert_aabb(mesh, Vector3(32, 2, 22), Vector3(16, 20, 16))
	_assert_outward(mesh, Vector3(40, 7, 30))
	for face in _triangles(mesh):
		for p: Vector3 in face["points"]:
			if p.y > 21.9:
				assert_float(Vector2(p.x - 40, p.z - 30).length()).is_less(0.001)  # one apex


func test_a_posed_part_is_turned_and_placed_as_a_whole() -> void:
	# A wheel: a cylinder of radius 8 and thickness 4 standing on its side (axis along x). A turn
	# of a quarter about z takes up (+y) to -x, so the 4 px of thickness run x 96..100 at 100.
	var wheel := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(100, 20, 50))
	var kit := MeshKit.new()
	kit.sides = 12
	var mesh := kit.pose(wheel).cylinder(Vector3.ZERO, 8.0, 4.0, RED).build()
	_assert_aabb(mesh, Vector3(96, 12, 42), Vector3(4, 16, 16))
	_assert_outward(mesh, Vector3(98, 20, 50))


func test_a_pose_is_left_with_the_identity_and_never_flips_a_mirrored_part_inside_out() -> void:
	var kit := MeshKit.new()
	kit.pose(Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3(60, 0, 0)))
	kit.box(AABB(Vector3.ZERO, Vector3(10, 10, 10)), RED)
	kit.pose(Transform3D.IDENTITY)
	kit.box(AABB(Vector3(0, 0, 20), Vector3(10, 10, 10)), RED)
	var mesh := kit.build()
	_assert_aabb(mesh, Vector3(0, 0, 0), Vector3(60, 10, 30))  # the mirrored box is x 50..60
	for face in _triangles(mesh):
		var p: Array = face["points"]
		assert_float(Plane(p[0], p[1], p[2]).normal.dot(face["normal"])).is_greater(0.99)
		var middle := Vector3(55, 5, 5) if _centre(face).z < 15.0 else Vector3(5, 5, 25)
		assert_float((face["normal"] as Vector3).dot(_centre(face) - middle)).is_greater_equal(0.0)


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.03
