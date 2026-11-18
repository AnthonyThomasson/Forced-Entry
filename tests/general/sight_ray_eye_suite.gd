extends "res://tests/_general/sight_ray_world.gd"
## Native unit suite for General's `SightRay` eye ray, architecture interface 11 and
## `docs/player-vision.md` V2 (#194 D9): `SightRay.hit(space3d, from, to, exclude)` from an eye
## `eye` px up to a point `height` px up is a 3D line in the twin space (`TwinSpace`); a wall (96
## px) stops it at any height, a table (31 px) only a line that runs under its top, a `transparent`
## piece is looked through; `sees` and `visible_heights` ask it of the points of a body. The pieces
## are the world of `tests/_general/sight_ray_world.gd`.


## The eye ray from an eye `eye` px up at plan x `from` (relative to `ORIGIN`) to the point `height`
## px up at plan x `to`, along the row y 0.
func _ray(
	space: PhysicsDirectSpaceState3D,
	from: float,
	eye: float,
	to: float,
	height: float,
) -> Dictionary:
	return SightRay.hit(
		space, PlanSpace.lift(ORIGIN + Vector2(from, 0.0), eye),
		PlanSpace.lift(ORIGIN + Vector2(to, 0.0), height),
	)


func test_an_eye_ray_over_an_empty_floor_is_clear() -> void:
	var space := await _space3()
	assert_dict(_ray(space, 0.0, SEE_OVER, 300.0, 40.0)).is_empty()


func test_a_wall_stops_an_eye_ray_at_any_height_and_its_twin_names_the_wall() -> void:
	var wall := _piece(Vector2(100.0, 0.0), Vector2(20.0, 200.0), 96.0)
	var space := await _space3()
	for height in [6.0, 40.0, SEE_OVER]:
		var hit := _ray(space, 0.0, SEE_OVER, 300.0, height)
		assert_bool(hit.is_empty()).is_false()
		assert_object(TwinSpace.owner_of(hit["collider"])).is_same(wall)


func test_an_eye_looks_over_a_table_and_a_low_eye_does_not() -> void:
	var table := _piece(Vector2(100.0, 0.0), Vector2(20.0, 60.0), 31.0)
	var space := await _space3()
	assert_dict(_ray(space, 0.0, SEE_OVER, 300.0, SEE_OVER)).is_empty()
	var low := _ray(space, 0.0, 20.0, 300.0, 20.0)
	assert_object(TwinSpace.owner_of(low["collider"])).is_same(table)


func test_an_eye_looks_down_over_a_table_to_the_floor_far_behind_it_not_close_behind() -> void:
	_piece(Vector2(100.0, 0.0), Vector2(20.0, 60.0), 31.0)
	var space := await _space3()
	# The table's far face is at 110: from an eye 69 px up the line to the floor point 20 px past it
	# is still under 31 px there, and the line to one 140 px past it is over.
	assert_bool(_ray(space, 0.0, SEE_OVER, 130.0, 6.0).is_empty()).is_false()
	assert_dict(_ray(space, 0.0, SEE_OVER, 250.0, 6.0)).is_empty()


func test_the_visible_points_of_a_body_are_the_ones_whose_line_is_clear() -> void:
	_piece(Vector2(100.0, 0.0), Vector2(20.0, 60.0), 31.0)
	var space := await _space3()
	var head_chest_hips := PackedFloat32Array([60.0, 40.0, 20.0])
	# 15 px behind the table's far face the head and the chest are over it, the hips are not.
	var seen := SightRay.visible_heights(
		space, PlanSpace.lift(ORIGIN, SEE_OVER), ORIGIN + Vector2(125.0, 0.0), head_chest_hips
	)
	assert_array(Array(seen)).is_equal([60.0, 40.0])
	var eye := PlanSpace.lift(ORIGIN, SEE_OVER)
	assert_bool(SightRay.sees(space, eye, ORIGIN + Vector2(125.0, 0.0), head_chest_hips)).is_true()
	# Right behind it, 2 px past the face, a body ducked below the top is seen at no point.
	var ducked := PackedFloat32Array([28.0, 20.0, 12.0])
	assert_bool(SightRay.sees(space, eye, ORIGIN + Vector2(300.0, 0.0), ducked)).is_true()
	assert_bool(SightRay.sees(space, eye, ORIGIN + Vector2(112.0, 0.0), ducked)).is_false()


func test_an_eye_ray_looks_through_a_transparent_piece_and_stops_at_the_wall_behind() -> void:
	var wall := _piece(Vector2(300.0, 0.0), Vector2(20.0, 200.0), 96.0)
	_glass(Vector2(100.0, 0.0), Vector2(10.0, 200.0))
	var space := await _space3()
	var hit := _ray(space, 0.0, SEE_OVER, 500.0, SEE_OVER)
	assert_object(TwinSpace.owner_of(hit["collider"])).is_same(wall)
	assert_dict(_ray(space, 0.0, SEE_OVER, 200.0, SEE_OVER)).is_empty()


func test_the_twins_an_eye_ray_leaves_out_are_looked_through_and_the_list_is_kept() -> void:
	var wall := _piece(Vector2(100.0, 0.0), Vector2(20.0, 200.0), 96.0)
	var space := await _space3()
	var from := PlanSpace.lift(ORIGIN, SEE_OVER)
	var to := PlanSpace.lift(ORIGIN + Vector2(300.0, 0.0), SEE_OVER)
	var exclude := SightRay.exclude_of(wall)
	assert_array(exclude).has_size(1)
	assert_dict(SightRay.hit(space, from, to, exclude)).is_empty()
	assert_array(exclude).has_size(1)
	assert_bool(SightRay.hit(space, from, to).is_empty()).is_false()


func test_the_space_beside_a_2d_space_is_the_twin_space_of_its_world() -> void:
	var plan := await _space()
	assert_object(TwinSpace.space_for(plan)).is_not_null()
	assert_object(TwinSpace.space_for(plan)).is_same(_twins.space())
