extends UnitSuite
## Native unit suite (pure geometry) for General's `SeenArea`, architecture interface 11 and
## `docs/player-vision.md` V11: the part of the world the player's view shows live, which Vision
## writes each time it rebuilds the cone (`set_area(polygons, bounds)`) and clears when the view
## lifts (`clear()`), and which Character's visuals and Physics' blood pools ask whether a disc
## `reaches` (`reaches(center, radius)`). A disc reaches the area when any part of it lies inside
## one of the area's polygons; it is wholly outside when none does. With no area set (no view, or a
## lifted one) everything is reached, so nothing is skipped. The expected answers are read off that
## description, the geometry laid out by hand.

## A square, 100 px a side, from (0, 0) to (100, 100), and its bounds.
const SQUARE := [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
## An "L": the square's top and left bars, leaving the lower right quarter (50..100) open.
const ELL := [
	Vector2(0, 0), Vector2(100, 0), Vector2(100, 50), Vector2(50, 50), Vector2(50, 100),
	Vector2(0, 100),
]
## A second, far polygon, 30 px a side at (500, 500).
const FAR := [Vector2(500, 500), Vector2(530, 500), Vector2(530, 530), Vector2(500, 530)]


func after_test() -> void:
	SeenArea.clear()


func _square() -> PackedVector2Array:
	return PackedVector2Array(SQUARE)


func _set_one(points: Array) -> void:
	var polygon := PackedVector2Array(points)
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		bounds = bounds.expand(p)
	SeenArea.set_area([polygon], bounds)


func test_with_no_area_set_everything_is_reached() -> void:
	SeenArea.clear()
	assert_bool(SeenArea.reaches(Vector2(12_345, -678), 60.0)).is_true()


func test_a_disc_inside_the_area_is_reached() -> void:
	_set_one(SQUARE)
	assert_bool(SeenArea.reaches(Vector2(50, 50), 10.0)).is_true()


func test_a_disc_whose_centre_is_inside_but_which_pokes_out_is_reached() -> void:
	_set_one(SQUARE)
	assert_bool(SeenArea.reaches(Vector2(95, 50), 60.0)).is_true()


func test_a_disc_whose_centre_is_outside_but_which_overlaps_an_edge_is_reached() -> void:
	_set_one(SQUARE)
	# 30 px right of the square's right edge, 60 px reach.
	assert_bool(SeenArea.reaches(Vector2(130, 50), 60.0)).is_true()


func test_a_disc_whose_centre_is_outside_and_which_overlaps_a_corner_is_reached() -> void:
	_set_one(SQUARE)
	# 40 px right and 40 px beyond the corner: 56.6 px from it, inside 60.
	assert_bool(SeenArea.reaches(Vector2(140, 140), 60.0)).is_true()


func test_a_disc_just_short_of_an_edge_is_wholly_outside() -> void:
	_set_one(SQUARE)
	# 61 px right of the right edge, 60 px reach.
	assert_bool(SeenArea.reaches(Vector2(161, 50), 60.0)).is_false()


func test_a_disc_just_short_of_a_corner_is_wholly_outside() -> void:
	_set_one(SQUARE)
	# 43 px either way past the corner: 60.8 px from it. Past the edges' own reach, only the
	# corner is near, and it is out of range.
	assert_bool(SeenArea.reaches(Vector2(143, 143), 60.0)).is_false()


func test_a_disc_swallowing_the_whole_area_is_reached() -> void:
	SeenArea.set_area([PackedVector2Array(FAR)], Rect2(500, 500, 30, 30))
	# Its centre is outside the 30 px square, and the whole square is inside the disc: the farthest
	# corner (500, 500) is 61.8 px from (515, 560), inside 70.
	assert_bool(SeenArea.reaches(Vector2(515, 560), 70.0)).is_true()


func test_a_disc_far_away_is_wholly_outside() -> void:
	_set_one(SQUARE)
	assert_bool(SeenArea.reaches(Vector2(5_000, 5_000), 60.0)).is_false()


func test_a_disc_in_a_notch_of_a_concave_area_is_wholly_outside() -> void:
	_set_one(ELL)
	# The open quarter's middle (75, 75) is 25 px from the nearest edges of the "L": a 20 px
	# disc there is in the notch, touching none of it; a 30 px one reaches the bars.
	assert_bool(SeenArea.reaches(Vector2(75, 75), 20.0)).is_false()
	assert_bool(SeenArea.reaches(Vector2(75, 75), 30.0)).is_true()


func test_a_disc_in_a_concave_area_bar_is_reached() -> void:
	_set_one(ELL)
	assert_bool(SeenArea.reaches(Vector2(25, 75), 5.0)).is_true()


func test_any_one_of_several_polygons_reaches() -> void:
	var bounds := Rect2(0, 0, 530, 530)
	SeenArea.set_area([_square(), PackedVector2Array(FAR)], bounds)
	assert_bool(SeenArea.reaches(Vector2(515, 515), 5.0)).is_true()
	assert_bool(SeenArea.reaches(Vector2(50, 50), 5.0)).is_true()
	assert_bool(SeenArea.reaches(Vector2(300, 300), 60.0)).is_false()


func test_a_disc_past_the_bounds_is_wholly_outside_whatever_the_polygons_say() -> void:
	# The bounds are the area's extent: a disc that does not reach them cannot reach the polygons
	# inside them.
	SeenArea.set_area([_square()], Rect2(0, 0, 100, 100))
	assert_bool(SeenArea.reaches(Vector2(250, 50), 60.0)).is_false()


func test_an_empty_area_reaches_nothing() -> void:
	# A view that sees nothing (a polygon-less cone, say) is still a view: nothing is reached.
	SeenArea.set_area([], Rect2())
	assert_bool(SeenArea.reaches(Vector2(0, 0), 60.0)).is_false()


func test_clear_reaches_everything_again() -> void:
	_set_one(SQUARE)
	assert_bool(SeenArea.reaches(Vector2(5_000, 5_000), 60.0)).is_false()
	SeenArea.clear()
	assert_bool(SeenArea.reaches(Vector2(5_000, 5_000), 60.0)).is_true()


func test_set_area_replaces_the_last_area() -> void:
	_set_one(SQUARE)
	SeenArea.set_area([PackedVector2Array(FAR)], Rect2(500, 500, 30, 30))
	assert_bool(SeenArea.reaches(Vector2(50, 50), 5.0)).is_false()
	assert_bool(SeenArea.reaches(Vector2(515, 515), 5.0)).is_true()
