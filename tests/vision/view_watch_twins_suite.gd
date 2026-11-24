extends UnitSuite
## Native unit suite for `ViewWatch` and the twin space it hears: the colliders that have no twin
## (hundreds of rugs and mats never get one) are asked again when the twin space says it twinned a
## body, not on each check. The seam is the one of `view_watch_handles_suite.gd`: plan handles in
## the tree, `stale` asked each frame, the eye still.

const Watch := preload("res://scenes/vision/view_watch.gd")
## Where the handle stands: far from the origin, so no other test's body is near.
const ORIGIN := Vector2(60_000.0, 60_000.0)
const FACING := Vector2.RIGHT
const FRAMES := 40


func _sight() -> Dictionary:
	return {
		"fov_degrees": 110.0,
		"view_distance": 2520.0,
		"awareness_radius": 48.0,
		"eye_height": 69.4,
	}


## The watch asked and told it was built, twice (the first ask sorts none).
func _settle(watch: Watch) -> void:
	for i in 2:
		watch.stale(ORIGIN, FACING, _sight())
		watch.built(ORIGIN, FACING, _sight())


## Ask for `FRAMES` frames, `body` moved a pixel each, rebuilt whenever it says so: the frames a
## rebuild was due.
func _creep(watch: Watch, body: Node2D) -> int:
	var due := 0
	var from := body.position
	for i in FRAMES:
		body.position = from + Vector2(0.0, i + 1.0)
		if watch.stale(ORIGIN, FACING, _sight()):
			due += 1
			watch.built(ORIGIN, FACING, _sight())
	return due


func test_a_twin_that_comes_is_sorted_again_when_the_twin_space_says_so() -> void:
	var space: TwinSpace = auto_free(TwinSpace.new())
	var watch := Watch.new()
	watch.attach(get_tree(), [], space)
	var piece: Node2D = auto_free(Node2D.new())
	piece.add_to_group(TwinSpace.BODIES)
	piece.position = ORIGIN + Vector2(300.0, 0.0)
	add_child(piece)
	_settle(watch)
	# no twin yet: it blocks like a wall, so its moving is a rebuild
	assert_int(_creep(watch, piece)).is_equal(FRAMES)
	var twin: Node3D = auto_free(Node3D.new())
	twin.add_child(TwinShapes.box(Rect2(-7.0, -30.0, 14.0, 60.0), Transform2D.IDENTITY, 0.0, 20.0))
	piece.set_meta(TwinSpace.TWIN_META, twin)
	_settle(watch)
	assert_int(_creep(watch, piece)).is_equal(FRAMES)  # nobody said: not asked again
	space.twinned.emit(piece, twin)
	_settle(watch)
	# a low piece (a 20 px top is under the eye): looked over, so its moving costs the backstop only
	var backstops := ceili(float(FRAMES) / VisionConfig.rebuild_every)
	assert_int(_creep(watch, piece)).is_less_equal(backstops + 1)
	watch.detach()


## A body twinned again (`retwinned`) is asked again as a twinned one is.
func test_a_retwinned_body_is_sorted_again_when_the_twin_space_says_so() -> void:
	var space: TwinSpace = auto_free(TwinSpace.new())
	var watch := Watch.new()
	watch.attach(get_tree(), [], space)
	assert_bool(watch.hears_twins()).is_true()
	var piece: Node2D = auto_free(Node2D.new())
	piece.add_to_group(TwinSpace.BODIES)
	piece.position = ORIGIN + Vector2(300.0, 0.0)
	add_child(piece)
	_settle(watch)
	assert_int(_creep(watch, piece)).is_equal(FRAMES)  # no twin yet
	var twin: Node3D = auto_free(Node3D.new())
	twin.add_child(TwinShapes.box(Rect2(-7.0, -30.0, 14.0, 60.0), Transform2D.IDENTITY, 0.0, 20.0))
	piece.set_meta(TwinSpace.TWIN_META, twin)
	space.retwinned.emit(piece, null)
	_settle(watch)
	var backstops := ceili(float(FRAMES) / VisionConfig.rebuild_every)
	assert_int(_creep(watch, piece)).is_less_equal(backstops + 1)
	watch.detach()


## A watch detached hears the twin space no more: a later emit is no error and changes nothing.
func test_a_detached_watch_does_not_hear_the_twin_space() -> void:
	var space: TwinSpace = auto_free(TwinSpace.new())
	var watch := Watch.new()
	watch.attach(get_tree(), [], space)
	watch.detach()
	assert_bool(watch.hears_twins()).is_false()
	space.twinned.emit(null, null)
	space.retwinned.emit(null, null)
	assert_bool(space.twinned.is_connected(watch._on_twin_news)).is_false()
	assert_bool(space.retwinned.is_connected(watch._on_retwinned)).is_false()
