extends UnitSuite
## Native unit suite for `ViewWatch`, the Vision domain's rebuild rule (`docs/player-vision.md` V1,
## "What triggers a rebuild"), at its own seam: bodies in the tree, `stale` asked each frame, the
## eye still. The cost rule: a blocker that moves is not measured again, only a shape coming or
## going on it is. And the reach: a body whose shape lies within the viewer's reach is watched
## whatever the sign of its scale, and one that moves into or out of it forces a rebuild.
## The reach world of `vision/cone_skip_exact` holds the cone itself to a fresh rebuild.

const Watch := preload("res://scenes/vision/view_watch.gd")
## Where the bodies stand: far from the origin, so no other test's body is near.
const ORIGIN := Vector2(60_000.0, 60_000.0)
const EYE := ORIGIN
const FACING := Vector2.RIGHT
const REACH := 2520.0
## A body 3750 px from the eye: beyond the reach (2520) and its own half size.
const FAR := Vector2(3750.0, 0.0)
const SOLID_SIZE := Vector2(14.0, 60.0)
const FRAMES := 40


func _sight() -> Dictionary:
	return {
		"fov_degrees": 110.0,
		"view_distance": REACH,
		"awareness_radius": 48.0,
		"see_over_coverage": 60.0,
	}


func _watch() -> Watch:
	var watch := Watch.new()
	watch.attach(get_tree(), [])
	return watch


## A solid with a rectangle shape `SOLID_SIZE` big, `at` from `ORIGIN`.
func _solid(at: Vector2) -> StaticBody2D:
	var body: StaticBody2D = auto_free(StaticBody2D.new())
	body.collision_layer = PhysicsLayers.SOLID
	body.position = ORIGIN + at
	body.add_child(_shape(SOLID_SIZE))
	add_child(body)
	return body


func _shape(size: Vector2) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
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
	(far.get_child(0) as CollisionShape2D).scale = Vector2(1.0, -200.0)
	_settled(watch)
	assert_int(_creep(watch, far)).is_equal(FRAMES)


func test_a_body_scaled_by_a_negative_scale_is_within_reach() -> void:
	var watch := _watch()
	var far := _solid(FAR)
	far.scale = Vector2(1.0, -200.0)
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
	_settled(watch)
	wide.scale = Vector2.ONE
	assert_bool(watch.stale(EYE, FACING, _sight())).is_true()
