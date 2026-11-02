extends UnitSuite
## Native unit suite (pure geometry) for what `PlayerView.sees(point)` asks of the view's polygons
## (`ViewCone.contains`, `docs/player-vision.md` V1): a point is seen when it is inside the cone or
## the bubble, by the even-odd rule on the polygon, not the engine's
## `Geometry2D.is_point_in_polygon`, which says "inside" for points well outside a cone whose
## corners lie along a wall. The polygons are laid out by hand; the expected answers are read off
## the geometry.

const Cone := preload("res://scenes/vision/view_cone.gd")
const Probe := preload("res://tests/_vision/vision_probe.gd")
const INSIDE := Vector2(900, 500)
## A square bubble, 96 px a side, round (0, 0).
const BUBBLE := [Vector2(-48, -48), Vector2(48, -48), Vector2(48, 48), Vector2(-48, 48)]


func _cone(cone: Array, bubble: Array = []) -> Cone:
	var found := Cone.new()
	found.cone = PackedVector2Array(cone)
	found.bubble = PackedVector2Array(bubble)
	return found


func test_a_point_far_outside_a_cone_with_corners_along_a_wall_is_not_seen() -> void:
	assert_bool(_cone(Probe.WALL_CONE).contains(Probe.OUTSIDE)).is_false()


func test_a_point_inside_that_cone_is_seen() -> void:
	assert_bool(_cone(Probe.WALL_CONE).contains(INSIDE)).is_true()


func test_the_bubble_is_seen_when_the_cone_is_not() -> void:
	var cone := _cone(Probe.WALL_CONE, BUBBLE)
	assert_bool(cone.contains(Vector2(-30, 20))).is_true()
	assert_bool(cone.contains(Vector2(-60, 0))).is_false()


func test_no_polygon_sees_nothing() -> void:
	assert_bool(_cone([]).contains(Vector2.ZERO)).is_false()
