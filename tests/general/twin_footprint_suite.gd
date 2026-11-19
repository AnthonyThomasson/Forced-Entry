extends UnitSuite
## Native unit suite for General's `TwinShapes.footprint_of`: the floor-plan polygon (px, plan
## space, convex) a 3D shape casts on the floor, which is what the navigation bake and the player's
## view read of a twin now that no 2D collider stands beside it. The expected corners are the
## shapes' sizes and placements, worked out here by hand from the description.

const EPS := 0.01


## The polygon's bounding rect.
func _bounds(poly: PackedVector2Array) -> Rect2:
	var rect := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		rect = rect.expand(p)
	return rect


## Whether the polygon holds a vertex within EPS of `corner`.
func _has_corner(poly: PackedVector2Array, corner: Vector2) -> bool:
	for p in poly:
		if p.distance_to(corner) < EPS:
			return true
	return false


func test_a_box_is_its_rectangle_on_the_floor() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 30.0, 20.0)
	var at := Transform3D(Basis.IDENTITY, PlanSpace.lift(Vector2(100.0, 50.0), 15.0))
	var poly := TwinShapes.footprint_of(box, at)
	assert_int(poly.size()).is_equal(4)
	for corner in [Vector2(80, 40), Vector2(120, 40), Vector2(120, 60), Vector2(80, 60)]:
		assert_bool(_has_corner(poly, corner)).override_failure_message(
			"a corner %s of the 40x20 rectangle centred on (100, 50): %s" % [corner, poly]
		).is_true()


func test_a_box_turned_a_quarter_swaps_its_sides() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 30.0, 20.0)
	var at := Transform3D(Basis(Vector3.UP, PI * 0.5), PlanSpace.lift(Vector2(100.0, 50.0), 15.0))
	var rect := _bounds(TwinShapes.footprint_of(box, at))
	assert_float(rect.size.x).is_equal_approx(20.0, EPS)
	assert_float(rect.size.y).is_equal_approx(40.0, EPS)
	assert_vector(rect.get_center()).is_equal_approx(Vector2(100.0, 50.0), Vector2(EPS, EPS))


func test_a_box_on_its_side_casts_the_hull_of_its_corners() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 30.0, 20.0)  # a table lying on its end: its 30 high side now spans x
	var at := Transform3D(Basis(Vector3.BACK, PI * 0.5), PlanSpace.lift(Vector2(100.0, 50.0), 20.0))
	var rect := _bounds(TwinShapes.footprint_of(box, at))
	assert_float(rect.size.x).is_equal_approx(30.0, EPS)
	assert_float(rect.size.y).is_equal_approx(20.0, EPS)


func test_an_upright_cylinder_is_a_sixteen_sided_disc() -> void:
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 10.0
	cylinder.height = 40.0
	var at := Transform3D(Basis.IDENTITY, PlanSpace.lift(Vector2(30.0, 30.0), 20.0))
	var poly := TwinShapes.footprint_of(cylinder, at)
	assert_int(poly.size()).is_equal(16)
	for p in poly:
		assert_float(p.distance_to(Vector2(30.0, 30.0))).is_equal_approx(10.0, EPS)


func test_a_convex_hull_casts_its_points_and_nothing_inside() -> void:
	var hull := ConvexPolygonShape3D.new()
	var cloud := PackedVector3Array()
	for p in [Vector2(0, 0), Vector2(60, 0), Vector2(60, 10), Vector2(0, 10), Vector2(30, 5)]:
		cloud.append(PlanSpace.lift(p, 0.0))
		cloud.append(PlanSpace.lift(p, 90.0))
	hull.points = cloud
	var poly := TwinShapes.footprint_of(hull, Transform3D.IDENTITY)
	assert_int(poly.size()).is_equal(4)
	assert_bool(_has_corner(poly, Vector2(60, 10))).is_true()
	assert_bool(_has_corner(poly, Vector2(30, 5))).is_false()


func test_a_shape_with_no_floor_cast_has_no_footprint() -> void:
	assert_int(TwinShapes.footprint_of(WorldBoundaryShape3D.new(), Transform3D.IDENTITY).size()) \
		.is_equal(0)
