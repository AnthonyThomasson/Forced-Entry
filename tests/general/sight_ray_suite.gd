extends "res://tests/_general/sight_ray_world.gd"
## Native unit suite for General's `SightRay` plan cast, architecture interface 11 and
## `docs/player-vision.md` V2 (#194 D9): the player's cone is a floor-plan polygon, so its rays run
## on the plan: `SightRay.plan_hit(space, from, to, exclude, see_over)` is the first thing on the
## line from `from` to `to` (on `PhysicsLayers.SOLID`) that stands above `see_over`, the eye's
## height in px. A collider's height is its twin's top (`top_of`); a lower one is looked over, a
## taller one, or one with no twin, blocks like a wall, a `transparent` surface (a glass-panel door)
## is looked through however tall. The pieces are the world of `tests/_general/sight_ray_world.gd`
## (walls 96, a table 31, a wardrobe above a standing eye, 1.64 m or 69.4 px); the eye ray is
## `sight_ray_eye_suite`'s.


func test_a_clear_line_hits_nothing() -> void:
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(400.0, 0.0))
	assert_dict(SightRay.plan_hit(space, line[0], line[1], [], SEE_OVER)).is_empty()


func test_a_wall_blocks_and_is_the_hit() -> void:
	var wall := _piece(Vector2(200.0, 0.0), Vector2(20.0, 200.0), 96.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(400.0, 0.0))
	var hit := SightRay.plan_hit(space, line[0], line[1], [], SEE_OVER)
	assert_object(hit.get("collider")).is_same(wall)
	assert_float((hit["position"] as Vector2).x).is_equal_approx(ORIGIN.x + 190.0, 0.01)


func test_a_table_is_looked_over_and_the_wall_behind_it_is_the_hit() -> void:
	_piece(Vector2(100.0, 0.0), Vector2(60.0, 60.0), 40.0)
	var wall := _piece(Vector2(300.0, 0.0), Vector2(20.0, 200.0), 96.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(500.0, 0.0))
	assert_object(SightRay.plan_hit(space, line[0], line[1], [], SEE_OVER).get("collider")) \
		.is_same(wall)


func test_a_row_of_low_pieces_is_looked_over_one_by_one() -> void:
	for x in [80.0, 160.0, 240.0, 320.0]:
		_piece(Vector2(x, 0.0), Vector2(30.0, 30.0), 30.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(500.0, 0.0))
	assert_dict(SightRay.plan_hit(space, line[0], line[1], [], SEE_OVER)).is_empty()


func test_a_piece_just_under_the_eye_is_looked_over() -> void:
	_piece(Vector2(100.0, 0.0), Vector2(40.0, 40.0), SEE_OVER - 0.5)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(300.0, 0.0))
	assert_dict(SightRay.plan_hit(space, line[0], line[1], [], SEE_OVER)).is_empty()


func test_a_piece_just_above_the_eye_blocks() -> void:
	var wardrobe := _piece(Vector2(100.0, 0.0), Vector2(40.0, 40.0), SEE_OVER + 0.5)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(300.0, 0.0))
	assert_object(SightRay.plan_hit(space, line[0], line[1], [], SEE_OVER).get("collider")) \
		.is_same(wardrobe)


func test_the_eye_height_is_the_callers() -> void:
	var table := _piece(Vector2(100.0, 0.0), Vector2(40.0, 40.0), 40.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(300.0, 0.0))
	assert_dict(SightRay.plan_hit(space, line[0], line[1], [], 40.0)).is_empty()
	assert_object(_blocker(space, line, 39.0)).is_same(table)


func test_a_body_with_no_twin_blocks_like_a_wall() -> void:
	var mute := _mute(Vector2(100.0, 0.0), Vector2(40.0, 40.0))
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(300.0, 0.0))
	assert_object(SightRay.plan_hit(space, line[0], line[1], [], SEE_OVER).get("collider")) \
		.is_same(mute)


func test_an_excluded_body_is_not_in_the_way_and_the_list_is_left_as_it_was() -> void:
	var wall := _piece(Vector2(100.0, 0.0), Vector2(20.0, 200.0), 96.0)
	_piece(Vector2(50.0, 0.0), Vector2(20.0, 20.0), 30.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(300.0, 0.0))
	var exclude: Array = [wall.get_rid()]
	assert_dict(SightRay.plan_hit(space, line[0], line[1], exclude, SEE_OVER)).is_empty()
	assert_array(exclude).has_size(1)


func test_the_top_of_a_collider_is_its_twins_and_a_wall_when_it_has_none() -> void:
	var table := _piece(Vector2(100.0, 0.0), Vector2(40.0, 40.0), 40.0)
	var mute := _mute(Vector2(200.0, 0.0), Vector2(40.0, 40.0))
	await _space()
	assert_float(SightRay.top_of(table)).is_equal_approx(40.0, 0.01)
	assert_float(SightRay.top_of(mute)).is_equal(INF)
	assert_float(SightRay.top_of(null)).is_equal(INF)


func test_a_character_is_looked_over_at_any_height() -> void:
	var walker := _piece(Vector2(100.0, 0.0), Vector2(30.0, 30.0), 74.0)
	walker.movement = auto_free(Node.new())
	await _space()
	assert_float(SightRay.top_of(walker)).is_equal(0.0)


func test_a_transparent_piece_is_looked_through_however_tall() -> void:
	var wall := _piece(Vector2(300.0, 0.0), Vector2(20.0, 200.0), 96.0)
	_glass(Vector2(100.0, 0.0), Vector2(10.0, 200.0))
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(500.0, 0.0))
	# The glass is 100 tall, as tall as the wall, and is not the hit; the wall behind it is.
	assert_object(_blocker(space, line, SEE_OVER)).is_same(wall)
	# Whatever the limit: a caller that looks over nothing still sees through glass.
	assert_object(_blocker(space, line, 0.0)).is_same(wall)


func test_a_transparent_piece_alone_hits_nothing() -> void:
	_glass(Vector2(100.0, 0.0), Vector2(10.0, 200.0))
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(300.0, 0.0))
	assert_dict(SightRay.plan_hit(space, line[0], line[1], [], SEE_OVER)).is_empty()


func test_the_top_of_a_transparent_piece_is_zero() -> void:
	var glass := _glass(Vector2(100.0, 0.0), Vector2(10.0, 200.0))
	var wall := _piece(Vector2(200.0, 0.0), Vector2(10.0, 200.0), 96.0)
	await _space()
	assert_float(SightRay.top_of(glass)).is_equal(0.0)
	assert_float(SightRay.top_of(wall)).is_equal_approx(96.0, 0.01)


func test_a_caster_looks_through_a_transparent_piece() -> void:
	var wall := _piece(Vector2(300.0, 0.0), Vector2(20.0, 200.0), 96.0)
	_glass(Vector2(100.0, 0.0), Vector2(10.0, 200.0))
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(500.0, 0.0))
	var caster := SightRay.new()
	caster.looks_over = SEE_OVER
	caster.leave_out([])
	assert_object(caster.cast(space, line[0], line[1]).get("collider")).is_same(wall)


func test_the_line_ends_at_its_target() -> void:
	_piece(Vector2(300.0, 0.0), Vector2(20.0, 200.0), 96.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(250.0, 0.0))
	assert_dict(SightRay.plan_hit(space, line[0], line[1], [], SEE_OVER)).is_empty()


func test_a_caster_leaves_out_what_it_was_told_and_looks_over_the_rest() -> void:
	var table := _piece(Vector2(100.0, 0.0), Vector2(40.0, 40.0), 40.0)
	var wall := _piece(Vector2(300.0, 0.0), Vector2(20.0, 200.0), 96.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(500.0, 0.0))
	var caster := SightRay.new()
	caster.looks_over = SEE_OVER
	caster.leave_out([wall.get_rid()])
	# The wall is left out; the table, not named, is looked over: nothing is in the way.
	assert_dict(caster.cast(space, line[0], line[1])).is_empty()
	# The cast looked past the table with it added to the list, and put the standing list back:
	# the next cast, from the far side, meets the table's top again, not a leftover exclusion.
	caster.looks_over = 30.0
	assert_object(caster.cast(space, line[0], line[1]).get("collider")).is_same(table)


func test_a_caster_asks_its_rated_before_the_collider() -> void:
	var wardrobe := _piece(Vector2(100.0, 0.0), Vector2(40.0, 40.0), 90.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(300.0, 0.0))
	var caster := SightRay.new()
	caster.looks_over = SEE_OVER
	caster.leave_out([])
	assert_object(caster.cast(space, line[0], line[1]).get("collider")).is_same(wardrobe)
	# What it was told of the collider stands in place of the collider's own answer.
	caster.rated = { wardrobe.get_instance_id(): 10.0 }
	assert_dict(caster.cast(space, line[0], line[1])).is_empty()


func test_a_plain_hit_is_not_changed_by_a_caster_left_out_list() -> void:
	var wall := _piece(Vector2(100.0, 0.0), Vector2(20.0, 200.0), 96.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(300.0, 0.0))
	var caster := SightRay.new()
	caster.leave_out([wall.get_rid()])
	assert_dict(caster.cast(space, line[0], line[1])).is_empty()
	# `hit` takes its own list each ask, whatever another caster has been told to leave out.
	assert_object(_blocker(space, line, SEE_OVER)).is_same(wall)


func test_consecutive_hits_do_not_leak_their_exclude_or_limit_into_each_other() -> void:
	var table := _piece(Vector2(100.0, 0.0), Vector2(40.0, 40.0), 40.0)
	var wall := _piece(Vector2(300.0, 0.0), Vector2(20.0, 200.0), 96.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(500.0, 0.0))
	# The wall left out, the table looked over: nothing in the way.
	assert_dict(SightRay.plan_hit(space, line[0], line[1], [wall.get_rid()], SEE_OVER)).is_empty()
	# The next ask names nothing and looks over less: the table is the hit, not the wall, and the
	# earlier ask's list and limit are gone.
	assert_object(_blocker(space, line, 30.0)).is_same(table)
	assert_object(_blocker(space, line, SEE_OVER)).is_same(wall)


## The collider `plan_hit` finds on `line` for an eye `eye` px up (null: the line is clear).
func _blocker(space: PhysicsDirectSpaceState2D, line: Array[Vector2], eye: float) -> Object:
	return SightRay.plan_hit(space, line[0], line[1], [], eye).get("collider")
