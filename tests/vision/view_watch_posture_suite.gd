extends UnitSuite
## Native unit suite for `ViewWatch` and a change of the viewer's eye height (a duck, a rise;
## `docs/player-vision.md` V1). The colliders are sorted again by the top each was found with, not
## read from the world anew: in the 10v10 district the full read was 16 ms, one frame, after a
## stretch of frames with no cone work at all (#194 perf-view3). Same seam as `view_watch_suite`.

const Watch := preload("res://scenes/vision/view_watch.gd")
const RawTwins := preload("res://tests/_vision/raw_twins.gd")
const ORIGIN := Vector2(60_000.0, 60_000.0)
const FACING := Vector2.RIGHT
const SOLID_SIZE := Vector2(14.0, 60.0)


func _sight(eye_height := 69.4) -> Dictionary:
	return {
		"fov_degrees": 110.0,
		"view_distance": 2520.0,
		"awareness_radius": 48.0,
		"eye_height": eye_height,
	}


## A solid `SOLID_SIZE` big, `at` from `ORIGIN`, with a twin made by hand.
func _solid(at: Vector2) -> RawTwins.Solid:
	var body: RawTwins.Solid = auto_free(RawTwins.Solid.new())
	body.position = ORIGIN + at
	var shape := RawTwins.Shape.new()
	var rect := RectangleShape2D.new()
	rect.size = SOLID_SIZE
	shape.shape = rect
	body.add_child(shape)
	add_child(body)
	var twin: Node3D = auto_free(RawTwins.RawTwin.build(body))
	body.set_meta(TwinSpace.TWIN_META, twin)
	return body


## Ask and build twice at `sight`: the first ask sorts nothing yet.
func _settled(watch: Watch, sight: Dictionary) -> void:
	for i in 2:
		watch.stale(ORIGIN, FACING, sight)
		watch.look(ORIGIN, FACING, sight)
		watch.built(ORIGIN, FACING, sight)


func test_a_new_eye_height_is_a_rebuild_and_measures_no_body_again() -> void:
	var watch := Watch.new()
	watch.attach(get_tree(), [])
	var near := _solid(Vector2(300.0, 0.0))
	_solid(Vector2(3750.0, 0.0))
	_settled(watch, _sight())
	var measured := watch.measured()
	assert_bool(watch.stale(ORIGIN, FACING, _sight(32.0))).is_true()
	_settled(watch, _sight(32.0))
	assert_int(watch.measured()).is_equal(measured)
	assert_bool(watch.stale(ORIGIN, FACING, _sight(32.0))).is_false()
	assert_bool(watch.stale(ORIGIN, FACING, _sight())).is_true()
	_settled(watch, _sight())
	assert_int(watch.measured()).is_equal(measured)
	assert_bool(watch.stale(ORIGIN, FACING, _sight())).is_false()
	# the solid is still watched after both sorts: moving it is a rebuild
	near.position += Vector2(0.0, 30.0)
	assert_bool(watch.stale(ORIGIN, FACING, _sight())).is_true()
