extends UnitSuite
## Native unit suite (pure geometry) for what `PlayerView.sees(point)` asks of the view's polygons
## (`ViewCone.contains`, `docs/player-vision.md` V1): a point is seen when it is inside the cone or
## the bubble, by the even-odd rule on the polygon, not the engine's
## `Geometry2D.is_point_in_polygon`, which says "inside" for points well outside a cone whose
## corners lie along a wall. The polygons are laid out by hand; the expected answers are read off
## the geometry.

const Cone := preload("res://scenes/vision/view_cone.gd")
## A cone from an eye at (700, 350) to the far wall, its corners along the wall and floor
## collinear: the engine says (715.9464, 502.9528) is inside it, but it lies west of the cone's near
## edge (the eye to (946.1, 706), at x = 806 on that row) by 90 px.
const WALL_CONE := [
	Vector2(700, 350), Vector2(968.875977, -6.000001), Vector2(1406, 14.202365),
	Vector2(962.224731, 706), Vector2(946.102722, 706),
]
const OUTSIDE := Vector2(715.9464, 502.9528)
const INSIDE := Vector2(900, 500)
## A square bubble, 96 px a side, round (0, 0).
const BUBBLE := [Vector2(-48, -48), Vector2(48, -48), Vector2(48, 48), Vector2(-48, 48)]


func _cone(cone: Array, bubble: Array = []) -> Cone:
	var found := Cone.new()
	found.cone = PackedVector2Array(cone)
	found.bubble = PackedVector2Array(bubble)
	return found


func test_a_point_far_outside_a_cone_with_corners_along_a_wall_is_not_seen() -> void:
	assert_bool(_cone(WALL_CONE).contains(OUTSIDE)).is_false()


func test_a_point_inside_that_cone_is_seen() -> void:
	assert_bool(_cone(WALL_CONE).contains(INSIDE)).is_true()


func test_the_bubble_is_seen_when_the_cone_is_not() -> void:
	var cone := _cone(WALL_CONE, BUBBLE)
	assert_bool(cone.contains(Vector2(-30, 20))).is_true()
	assert_bool(cone.contains(Vector2(-60, 0))).is_false()


func test_no_polygon_sees_nothing() -> void:
	assert_bool(_cone([]).contains(Vector2.ZERO)).is_false()
