extends UnitSuite
## Native unit suite (pure logic) for Physics' `Deformation.shape_polygon`, architecture interface
## 4, beneath `objects/blast_colliders_match_plain`: a piece of furniture dented a few times keeps a
## simple outline, one `convex_pieces` can cut its collider from. Each case is a dent set a frag
## left on a piece in that test (issue #77), its seeds fixed: a chunk near a corner, whose push
## into one face runs along the other face, with the fragments' dents beside it. Without the
## neighbour cap the corner slides past its neighbour and the outline crosses itself, and the piece
## keeps an older collider.


## The 70x40 coffee table: a chunk on its top face 7 px from the corner, a dent on its right face,
## one slanted into the corner.
func test_a_chunk_by_a_corner_and_a_dent_on_the_other_face() -> void:
	_check_outline("rect", Vector2(70, 40), [
		_impact(Vector2(27.65, -20), Vector2(0, 1), 5.0, true, 2_580_307_969),
		_impact(Vector2(35, -8.78824), Vector2(-1, 0), 2.19882, false, 1_913_389_514),
		_impact(
			Vector2(30.2582, -13.285), Vector2(0.397579, 0.917568), 1.28883, false, 1_220_428_222,
		),
	])


## The same corner of the coffee table, with two slanted dents on the top face.
func test_a_chunk_by_a_corner_and_slanted_dents_beside_it() -> void:
	_check_outline("rect", Vector2(70, 40), [
		_impact(Vector2(27.65, -20), Vector2(0, 1), 5.0, true, 1_845_584_898),
		_impact(
			Vector2(31.9141, -14.0099), Vector2(0.500786, 0.865571), 0.941633, false, 1_762_546_801,
		),
		_impact(
			Vector2(19.0918, -17.3431), Vector2(-0.486935, 0.873438), 3.17672, false, 3_221_886_770,
		),
	])


## The 30x30 side table: a chunk on its left face 9 px from the top corner and a slanted dent by
## that corner.
func test_a_chunk_by_the_corner_of_a_small_square() -> void:
	_check_outline("square", Vector2(30, 30), [
		_impact(Vector2(-15, -5.96466), Vector2(1, 0), 5.0, true, 2_490_647_312),
		_impact(
			Vector2(-10.1121, -10.3626), Vector2(0.919977, -0.391972), 2.719, false, 2_554_682_700,
		),
	])


## An impact record as `Deformation.new_impact` builds one, with its depth and seed given.
func _impact(
	pos: Vector2,
	inward: Vector2,
	depth: float,
	chunk: bool,
	seed_value: int,
) -> Dictionary:
	return {
		"pos": pos, "inward": inward, "depth": depth, "chunk": chunk, "seed": seed_value,
		"blood": 0.0,
	}


## The dented outline of `shape` at `size` crosses itself nowhere (the suite's own check, edge by
## edge), is a polygon the engine triangulates and cuts into convex pieces.
func _check_outline(shape: String, size: Vector2, impacts: Array) -> void:
	var poly := Deformation.shape_polygon(shape, size, impacts)
	var crossing := _first_crossing(poly)
	assert_str(crossing).override_failure_message(
		"the dented outline crosses itself: %s" % crossing
	).is_empty()
	assert_bool(Deformation.is_valid_polygon(poly)).override_failure_message(
		"the dented outline is a valid polygon"
	).is_true()
	assert_int(Deformation.convex_pieces(poly).size()).override_failure_message(
		"convex_pieces cuts the dented outline into pieces"
	).is_greater(0)


## The first two edges of the closed ring `poly` that are not neighbours and meet (cross or
## touch), as words, or "" when none do.
func _first_crossing(poly: PackedVector2Array) -> String:
	var n := poly.size()
	for i in n:
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue
			var a := poly[i]
			var b := poly[(i + 1) % n]
			var c := poly[j]
			var d := poly[(j + 1) % n]
			if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
				return "edge %d %s-%s meets edge %d %s-%s" % [i, a, b, j, c, d]
	return ""
