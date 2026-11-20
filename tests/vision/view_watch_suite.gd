extends UnitSuite
## Native unit suite for `ViewWatch`, the Vision domain's rebuild rule (`docs/player-vision.md` V1,
## "What triggers a rebuild"), at its own seam: bodies in the tree, `stale` asked each frame, the
## eye still. The cost rule: a blocker that moves is not measured again, only a shape coming or
## going on it is. And the reach: a body whose shape lies within the viewer's reach is watched
## whatever the sign of its scale, and one that moves into or out of it forces a rebuild.
## The reach world of `vision/cone_skip_exact` holds the cone itself to a fresh rebuild.

const Watch := preload("res://scenes/vision/view_watch.gd")
const RawTwins := preload("res://tests/_vision/raw_twins.gd")
## Where the bodies stand: far from the origin, so no other test's body is near.
const ORIGIN := Vector2(60_000.0, 60_000.0)
const EYE := ORIGIN
const FACING := Vector2.RIGHT
const REACH := 2520.0
## A body 3750 px from the eye: beyond the reach (2520) and its own half size.
const FAR := Vector2(3750.0, 0.0)
const SOLID_SIZE := Vector2(14.0, 60.0)
const FRAMES := 40
## A small pose change (px, degrees): the old pose lag's bounds; a rebuild is due for any of it now.
const LAG_EYE := 5.0
const LAG_FACING := 1.0


func _sight() -> Dictionary:
	return {
		"fov_degrees": 110.0,
		"view_distance": REACH,
		"awareness_radius": 48.0,
		"eye_height": 69.4,
	}


func _watch() -> Watch:
	var watch := Watch.new()
	watch.attach(get_tree(), [])
	return watch


## A solid with a rectangle shape `SOLID_SIZE` big, `at` from `ORIGIN`.
func _solid(at: Vector2) -> RawTwins.Solid:
	var body: RawTwins.Solid = auto_free(RawTwins.Solid.new())
	body.position = ORIGIN + at
	body.add_child(_shape(SOLID_SIZE))
	add_child(body)
	# no twin space here: the solid's twin is made and sorted by hand, as `TwinSpace` would
	var twin: Node3D = auto_free(RawTwins.RawTwin.build(body))
	body.set_meta(TwinSpace.TWIN_META, twin)
	return body


func _shape(size: Vector2) -> RawTwins.Shape:
	var shape := RawTwins.Shape.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	return shape


## The watch asked and told it was built, twice (the first ask answers from the key and sorts no
## body yet): the bodies are sorted, nothing is due.
func _settled(watch: Watch) -> void:
	for i in 2:
		watch.stale(EYE, FACING, _sight())
		watch.built(EYE, FACING, _sight())


## Ask for `FRAMES` frames, `body` moved a pixel each, rebuilt (`built`) whenever it says so.
## Returns how many frames said a rebuild was due.
func _creep(watch: Watch, body: Node2D) -> int:
	var due := 0
	var from := body.position
	for i in FRAMES:
		body.position = from + Vector2(0.0, i + 1.0)
		if watch.stale(EYE, FACING, _sight()):
			due += 1
			watch.built(EYE, FACING, _sight())
	return due


func test_a_blocker_that_moves_every_frame_is_not_measured_again() -> void:
	var watch := _watch()
	var far := _solid(FAR)
	var near := _solid(Vector2(300.0, 0.0))
	_settled(watch)
	var measured := watch.measured()
	_creep(watch, far)
	_creep(watch, near)
	assert_int(watch.measured()).is_equal(measured)


func test_a_shape_that_comes_is_measured_once() -> void:
	var watch := _watch()
	var far := _solid(FAR)
	_settled(watch)
	var measured := watch.measured()
	far.add_child(_shape(SOLID_SIZE))
	_settled(watch)
	assert_int(watch.measured()).is_equal(measured + 1)


func test_a_far_blocker_moving_forces_a_rebuild_only_at_the_backstop() -> void:
	var watch := _watch()
	_settled(watch)
	var far := _solid(FAR)
	_settled(watch)
	var backstops := ceili(float(FRAMES) / VisionConfig.rebuild_every)
	assert_int(_creep(watch, far)).is_less_equal(backstops + 1)


func test_a_shape_stretched_by_a_negative_scale_is_within_reach() -> void:
	var watch := _watch()
	var far := _solid(FAR)
	(far.get_child(0) as RawTwins.Shape).scale = Vector2(1.0, -200.0)
	far.reshape()
	_settled(watch)
	assert_int(_creep(watch, far)).is_equal(FRAMES)


func test_a_body_scaled_by_a_negative_scale_is_within_reach() -> void:
	var watch := _watch()
	var far := _solid(FAR)
	far.scale = Vector2(1.0, -200.0)
	far.reshape()
	_settled(watch)
	assert_int(_creep(watch, far)).is_equal(FRAMES)


func test_a_blocker_that_moves_out_of_the_reach_forces_a_rebuild() -> void:
	var watch := _watch()
	var near := _solid(Vector2(300.0, 0.0))
	_settled(watch)
	near.position = ORIGIN + FAR
	assert_bool(watch.stale(EYE, FACING, _sight())).is_true()


func test_a_blocker_that_moves_into_the_reach_forces_a_rebuild() -> void:
	var watch := _watch()
	var far := _solid(FAR)
	_settled(watch)
	far.position = ORIGIN + Vector2(300.0, 0.0)
	assert_bool(watch.stale(EYE, FACING, _sight())).is_true()


func test_a_blocker_that_shrinks_out_of_the_sector_forces_a_rebuild() -> void:
	var watch := _watch()
	var wide := _solid(Vector2(0.0, 1200.0))
	wide.scale = Vector2(1.0, 100.0)
	wide.reshape()
	_settled(watch)
	wide.scale = Vector2.ONE
	wide.reshape()
	assert_bool(watch.stale(EYE, FACING, _sight())).is_true()


## Ask once about `eye` and `facing` after a settled watch: whether a rebuild is due.
func _due(watch: Watch, eye: Vector2, facing: Vector2, sight := _sight()) -> bool:
	return watch.stale(eye, facing, sight)


## Ask a settled watch, as a job in flight, whether the world changed for a viewer at its pose.
func _changed(watch: Watch, sight := _sight()) -> bool:
	return watch.world_changed(sight)


func test_a_small_pose_change_is_due_at_once() -> void:
	var watch := _watch()
	_settled(watch)
	assert_bool(_due(watch, EYE + Vector2(LAG_EYE - 1.0, 0.0), FACING)).is_true()


func test_a_small_turn_is_due_at_once() -> void:
	var watch := _watch()
	_settled(watch)
	var turned := FACING.rotated(deg_to_rad(LAG_FACING - 0.2))
	assert_bool(_due(watch, EYE, turned)).is_true()


func test_a_changed_sight_number_is_due() -> void:
	var watch := _watch()
	_settled(watch)
	var sight := _sight()
	sight["view_distance"] = REACH - 100.0
	assert_bool(_due(watch, EYE, FACING, sight)).is_true()


func test_a_solid_that_joins_is_due() -> void:
	var watch := _watch()
	_settled(watch)
	_solid(Vector2(300.0, 0.0))
	assert_bool(_due(watch, EYE + Vector2(1.0, 0.0), FACING)).is_true()


## A piece is a plan handle with no child shapes: its `reshaped` signal (a dent, a break) is what
## tells the watch its silhouette changed with no move of its body.
func test_a_piece_that_is_reshaped_is_due() -> void:
	var watch := _watch()
	var piece: Piece = auto_free(Piece.new())
	piece.add_to_group(TwinSpace.BODIES)  # as a piece is: a plan handle the view watches
	piece.add_to_group(TwinSpace.PIECES)
	piece.position = ORIGIN + Vector2(300.0, 0.0)
	add_child(piece)
	_settled(watch)
	assert_bool(_changed(watch)).is_false()
	piece.reshape()
	assert_bool(_changed(watch)).is_true()


func test_a_job_in_flight_does_not_ask_the_pose() -> void:
	# `world_changed` has no pose to ask: nothing moved but the viewer, so the world is as the job
	# began it.
	var watch := _watch()
	_settled(watch)
	assert_bool(_changed(watch)).is_false()


func test_a_job_in_flight_sees_a_blocker_that_moves() -> void:
	var watch := _watch()
	var near := _solid(Vector2(300.0, 0.0))
	_settled(watch)
	near.position += Vector2(0.0, 5.0)
	assert_bool(_changed(watch)).is_true()


func test_a_job_in_flight_does_not_see_a_blocker_that_moves_outside_its_reach() -> void:
	var watch := _watch()
	var far := _solid(FAR)
	_settled(watch)
	far.position += Vector2(0.0, 5.0)
	assert_bool(_changed(watch)).is_false()


func test_a_job_in_flight_sees_a_solid_that_joins() -> void:
	var watch := _watch()
	_settled(watch)
	_solid(Vector2(300.0, 0.0))
	assert_bool(_changed(watch)).is_true()


func test_a_job_in_flight_sees_a_changed_sight_number() -> void:
	var watch := _watch()
	_settled(watch)
	var sight := _sight()
	sight["fov_degrees"] = 90.0
	assert_bool(_changed(watch, sight)).is_true()


func test_a_job_in_flight_is_held_to_the_pose_it_began_from() -> void:
	# A solid beside the live eye that the job's own sector never reaches is no change to it: the
	# sector stays that of the pose `look`/`stale` last took.
	var watch := _watch()
	_settled(watch)
	var behind := _solid(Vector2(-1200.0, 0.0))
	behind.position += Vector2(0.0, 5.0)
	assert_bool(_changed(watch)).is_false()


## A body gives its twin a frame after it joins: until then it has no height and blocks like a wall,
## and the watch sorts it again when the twin comes (a low piece stops being a blocker).
func test_a_body_whose_twin_comes_later_is_sorted_again() -> void:
	var watch := _watch()
	var piece := _solid(Vector2(300.0, 0.0))
	piece.remove_meta(TwinSpace.TWIN_META)  # no twin yet
	_settled(watch)
	assert_int(_creep(watch, piece)).is_equal(FRAMES)  # no twin yet: a wall's worth
	var twin: Node3D = auto_free(Node3D.new())
	twin.add_child(TwinShapes.box(Rect2(-7.0, -30.0, 14.0, 60.0), Transform2D.IDENTITY, 0.0, 20.0))
	piece.set_meta(TwinSpace.TWIN_META, twin)
	_settled(watch)
	var backstops := ceili(float(FRAMES) / VisionConfig.rebuild_every)
	assert_int(_creep(watch, piece)).is_less_equal(backstops + 1)


## A bare piece: a `Node2D` that says it was reshaped.
class Piece:
	extends Node2D
	signal reshaped

	func reshape() -> void:
		reshaped.emit()
