extends UnitSuite
## Native unit suite for General's `SightRay`, architecture interface 11 and `docs/player-vision.md`
## V2: the one sight rule. `SightRay.hit(space, from, to, exclude, see_over)` is the first thing on
## the line from `from` to `to` (on `PhysicsLayers.SOLID`) that is too tall to see over, or {}
## when the line reaches `to`. A collider is seen over when its `coverage` (what its `get_surface()`
## says, 0 to 100) is at or below `see_over`; a taller one, or one that cannot say, blocks like a
## wall. The expected hits are read off that rule over a space built here: the pieces' heights are
## the brief's (walls 100, a wardrobe above 60, a table below it), the answers the line the rule
## draws.

## Where the pieces stand: far from the origin, so no other test's body is near.
const ORIGIN := Vector2(40_000.0, 40_000.0)
## The brief's see-over height: a piece at or below it is looked over.
const SEE_OVER := 60.0


## A piece `size` big centred at `at` (relative to `ORIGIN`), `coverage` tall.
func _piece(at: Vector2, size: Vector2, coverage: float) -> Piece:
	var piece: Piece = auto_free(Piece.new())
	piece.coverage = coverage
	_shape(piece, at, size)
	return piece


func _mute(at: Vector2, size: Vector2) -> Mute:
	var mute: Mute = auto_free(Mute.new())
	_shape(mute, at, size)
	return mute


func _shape(body: StaticBody2D, at: Vector2, size: Vector2) -> void:
	body.collision_layer = PhysicsLayers.SOLID
	body.position = ORIGIN + at
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	add_child(body)


## The physics space once the bodies added are in it (a body joins the broadphase at the next step).
func _space() -> PhysicsDirectSpaceState2D:
	await get_tree().physics_frame
	await get_tree().physics_frame
	return get_viewport().world_2d.direct_space_state


## The line from `from` to `to`, both relative to `ORIGIN`.
func _line(from: Vector2, to: Vector2) -> Array[Vector2]:
	return [ORIGIN + from, ORIGIN + to]


func test_a_clear_line_hits_nothing() -> void:
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(400.0, 0.0))
	assert_dict(SightRay.hit(space, line[0], line[1], [], SEE_OVER)).is_empty()


func test_a_wall_blocks_and_is_the_hit() -> void:
	var wall := _piece(Vector2(200.0, 0.0), Vector2(20.0, 200.0), 100.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(400.0, 0.0))
	var hit := SightRay.hit(space, line[0], line[1], [], SEE_OVER)
	assert_object(hit.get("collider")).is_same(wall)
	assert_float((hit["position"] as Vector2).x).is_equal_approx(ORIGIN.x + 190.0, 0.01)


func test_a_table_is_looked_over_and_the_wall_behind_it_is_the_hit() -> void:
	_piece(Vector2(100.0, 0.0), Vector2(60.0, 60.0), 40.0)
	var wall := _piece(Vector2(300.0, 0.0), Vector2(20.0, 200.0), 100.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(500.0, 0.0))
	assert_object(SightRay.hit(space, line[0], line[1], [], SEE_OVER).get("collider")) \
		.is_same(wall)


func test_a_table_alone_hits_nothing() -> void:
	_piece(Vector2(100.0, 0.0), Vector2(60.0, 60.0), 40.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(500.0, 0.0))
	assert_dict(SightRay.hit(space, line[0], line[1], [], SEE_OVER)).is_empty()


func test_a_row_of_low_pieces_is_looked_over_one_by_one() -> void:
	for x in [80.0, 160.0, 240.0, 320.0]:
		_piece(Vector2(x, 0.0), Vector2(30.0, 30.0), 30.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(500.0, 0.0))
	assert_dict(SightRay.hit(space, line[0], line[1], [], SEE_OVER)).is_empty()


func test_a_piece_exactly_as_tall_as_the_limit_is_looked_over() -> void:
	_piece(Vector2(100.0, 0.0), Vector2(40.0, 40.0), 60.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(300.0, 0.0))
	assert_dict(SightRay.hit(space, line[0], line[1], [], SEE_OVER)).is_empty()


func test_a_piece_just_above_the_limit_blocks() -> void:
	var wardrobe := _piece(Vector2(100.0, 0.0), Vector2(40.0, 40.0), 61.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(300.0, 0.0))
	assert_object(SightRay.hit(space, line[0], line[1], [], SEE_OVER).get("collider")) \
		.is_same(wardrobe)


func test_the_limit_is_the_callers() -> void:
	var table := _piece(Vector2(100.0, 0.0), Vector2(40.0, 40.0), 40.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(300.0, 0.0))
	assert_dict(SightRay.hit(space, line[0], line[1], [], 40.0)).is_empty()
	assert_object(SightRay.hit(space, line[0], line[1], [], 39.0).get("collider")).is_same(table)


func test_a_body_that_cannot_say_its_height_blocks() -> void:
	var mute := _mute(Vector2(100.0, 0.0), Vector2(40.0, 40.0))
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(300.0, 0.0))
	assert_object(SightRay.hit(space, line[0], line[1], [], SEE_OVER).get("collider")) \
		.is_same(mute)


func test_an_excluded_body_is_not_in_the_way_and_the_list_is_left_as_it_was() -> void:
	var wall := _piece(Vector2(100.0, 0.0), Vector2(20.0, 200.0), 100.0)
	_piece(Vector2(50.0, 0.0), Vector2(20.0, 20.0), 30.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(300.0, 0.0))
	var exclude: Array = [wall.get_rid()]
	assert_dict(SightRay.hit(space, line[0], line[1], exclude, SEE_OVER)).is_empty()
	assert_array(exclude).has_size(1)


func test_the_coverage_of_a_collider_is_what_it_says_and_a_full_blocker_when_it_says_none() -> void:
	var table := _piece(Vector2(100.0, 0.0), Vector2(40.0, 40.0), 40.0)
	var mute := _mute(Vector2(200.0, 0.0), Vector2(40.0, 40.0))
	assert_float(SightRay.coverage_of(table)).is_equal(40.0)
	assert_float(SightRay.coverage_of(mute)).is_equal(100.0)
	assert_float(SightRay.coverage_of(null)).is_equal(100.0)


func test_the_line_ends_at_its_target() -> void:
	_piece(Vector2(300.0, 0.0), Vector2(20.0, 200.0), 100.0)
	var space := await _space()
	var line := _line(Vector2.ZERO, Vector2(250.0, 0.0))
	assert_dict(SightRay.hit(space, line[0], line[1], [], SEE_OVER)).is_empty()


## A solid piece with a height, as the hittable contract reports it (`get_surface().coverage`).
class Piece:
	extends StaticBody2D

	var coverage := 100.0


	func get_surface() -> Dictionary:
		return { "coverage": coverage }


## A solid body that cannot say how tall it is (no `get_surface`).
class Mute:
	extends StaticBody2D
