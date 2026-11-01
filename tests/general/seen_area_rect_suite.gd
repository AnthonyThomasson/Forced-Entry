extends UnitSuite
## Native unit suite (pure geometry) for General's `SeenArea`, architecture interface 11 and
## `docs/player-vision.md` V11: besides a disc (`seen_area_suite.gd`), an axis-aligned rectangle
## `reaches_rect(rect)` the area: any part of it lies inside one of the area's polygons. What draws
## a long, thin thing (a blood pool's box) asks it, so the circle round the box, which reaches far
## past a long box's ends, does not make it seen. With no area set everything is reached. The
## expected answers are read off that description, the geometry laid out by hand.

## A square, 100 px a side, from (0, 0) to (100, 100).
const SQUARE := [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
## An "L": the square's top and left bars, leaving the lower right quarter (50..100) open.
const ELL := [
	Vector2(0, 0), Vector2(100, 0), Vector2(100, 50), Vector2(50, 50), Vector2(50, 100),
	Vector2(0, 100),
]


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


func test_with_no_area_set_every_rect_is_reached() -> void:
	SeenArea.clear()
	assert_bool(SeenArea.reaches_rect(Rect2(12_345, -678, 4, 4))).is_true()


func test_a_rect_inside_the_area_is_reached() -> void:
	_set_one(SQUARE)
	assert_bool(SeenArea.reaches_rect(Rect2(20, 20, 30, 30))).is_true()


func test_a_rect_overlapping_an_edge_is_reached() -> void:
	_set_one(SQUARE)
	assert_bool(SeenArea.reaches_rect(Rect2(90, 40, 60, 20))).is_true()


func test_a_rect_swallowing_the_whole_area_is_reached() -> void:
	_set_one(SQUARE)
	assert_bool(SeenArea.reaches_rect(Rect2(-50, -50, 300, 300))).is_true()


func test_a_rect_crossing_the_area_with_both_ends_outside_is_reached() -> void:
	_set_one(SQUARE)
	# A bar through the square's middle: none of its corners is inside the square and none of the
	# square's corners inside the bar, yet they cross.
	assert_bool(SeenArea.reaches_rect(Rect2(-50, 45, 200, 10))).is_true()


func test_a_rect_just_short_of_an_edge_is_wholly_outside() -> void:
	_set_one(SQUARE)
	assert_bool(SeenArea.reaches_rect(Rect2(101, 20, 40, 40))).is_false()


func test_a_rect_in_a_notch_of_a_concave_area_is_wholly_outside() -> void:
	_set_one(ELL)
	assert_bool(SeenArea.reaches_rect(Rect2(60, 60, 30, 30))).is_false()
	assert_bool(SeenArea.reaches_rect(Rect2(40, 60, 30, 30))).is_true()


func test_a_long_rect_beside_the_area_is_wholly_outside_though_its_circle_reaches() -> void:
	_set_one(SQUARE)
	# 200 by 100, 10 px right of the square: the disc round it (centre (210, 50), radius 111.8)
	# reaches back to x = 98, the rect itself to x = 110 only.
	var rect := Rect2(110, 0, 200, 100)
	assert_bool(SeenArea.reaches(rect.get_center(), rect.size.length() * 0.5)).is_true()
	assert_bool(SeenArea.reaches_rect(rect)).is_false()


func test_a_rect_past_the_bounds_is_wholly_outside() -> void:
	SeenArea.set_area([_square()], Rect2(0, 0, 100, 100))
	assert_bool(SeenArea.reaches_rect(Rect2(250, 40, 20, 20))).is_false()


func test_an_empty_area_reaches_no_rect() -> void:
	SeenArea.set_area([], Rect2())
	assert_bool(SeenArea.reaches_rect(Rect2(0, 0, 10, 10))).is_false()


func test_a_rect_that_only_just_pokes_into_the_area_is_reached() -> void:
	_set_one(SQUARE)
	assert_bool(SeenArea.reaches_rect(Rect2(99.9, 40, 20, 20))).is_true()
	assert_bool(SeenArea.reaches_rect(Rect2(100.1, 40, 20, 20))).is_false()


func test_a_rect_far_from_a_cone_the_engine_calls_inside_is_wholly_outside() -> void:
	# A cone from an eye at (700, 350) to the far wall, its corners along the wall and floor
	# collinear: `Geometry2D.is_point_in_polygon` says (715.9, 503) is inside it, but it lies west
	# of the cone's near edge (eye to (946, 706), at x = 806 on that row) by 90 px.
	var cone := PackedVector2Array(
		[
			Vector2(700, 350), Vector2(968.875977, -6.000001), Vector2(1406, 14.202365),
			Vector2(962.224731, 706), Vector2(946.102722, 706),
		],
	)
	SeenArea.set_area([cone], Rect2(700, -6, 706, 712))
	assert_bool(SeenArea.reaches_rect(Rect2(710, 498, 12, 10))).is_false()
	assert_bool(SeenArea.reaches(Vector2(715.9464, 502.9528), 10.0)).is_false()
	assert_bool(SeenArea.reaches_rect(Rect2(800, 498, 12, 10))).is_true()
