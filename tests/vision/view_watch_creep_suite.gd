extends UnitSuite
## Native unit suite for `ViewWatch.STILL_PX` (`docs/player-vision.md` V1): a blocker that moved no
## more than 0.05 px from where the job snapshot it is where it was (settling bodies creep 0.0005
## to 0.003 px a frame, and each creep restarted the job). Held to: a creeping blocker's snapshot
## never lags the live one by more than `STILL_PX`; a blocker that moves that much or more restarts
## the job (`world_changed`) and starts one (`stale`); creeps add up. The seam is the one of
## `view_watch_handles_suite.gd`: a plan handle with a twin in the tree, the eye still.

const Watch := preload("res://scenes/vision/view_watch.gd")
## Where the handle stands: out of reach of the world's origin, where other tests' bodies are, and
## near enough for a float to hold a creep (a float 60,000 from the origin steps by 0.004 px).
const ORIGIN := Vector2(3000.0, 3000.0)
const FACING := Vector2.RIGHT
const FRAMES := 60


func _sight() -> Dictionary:
	return {
		"fov_degrees": 110.0,
		"view_distance": 2520.0,
		"awareness_radius": 48.0,
		"eye_height": 69.4,
	}


## A tall handle (its twin's top is over the eye) in reach, and a watch that has sorted it.
func _handle() -> Node2D:
	var handle: Node2D = auto_free(Node2D.new())
	handle.add_to_group(TwinSpace.BODIES)
	handle.position = ORIGIN + Vector2(300.0, 0.0)
	add_child(handle)
	var twin: StaticBody3D = auto_free(StaticBody3D.new())
	twin.add_child(TwinShapes.box(Rect2(-7.0, -30.0, 14.0, 60.0), Transform2D.IDENTITY, 0.0, 90.0))
	handle.set_meta(TwinSpace.TWIN_META, twin)
	return handle


func _settled() -> Watch:
	var watch := Watch.new()
	watch.attach(get_tree(), [])
	for i in 3:
		watch.stale(ORIGIN, FACING, _sight())
		watch.built(ORIGIN, FACING, _sight())
	return watch


func test_a_creep_under_the_bound_never_starts_or_restarts_a_job() -> void:
	var handle := _handle()
	var watch := _settled()
	var restarts := 0
	for i in FRAMES:
		handle.position += Vector2(0.0, 0.0005 * (1 + i % 3))  # 0.0005 to 0.0015 px a frame
		if watch.world_changed(_sight()):
			restarts += 1
			watch.built(ORIGIN, FACING, _sight())  # the job begins again on the live pose
		else:
			# nothing restarts the job: the pose it holds never lags the live one by more
			assert_float(watch.lag()).is_less_equal(Watch.STILL_PX)
	# 60 frames of 0.001 px on average add up to 0.06 px: one restart where each frame was one
	assert_int(restarts).is_between(1, 3)


## Creeps add up from the snapshot: a restart is not one per creep but one per bound's worth, and
## the frame after it (`moved_then`: a query that frame may have read the body where it was).
func test_creeps_add_up_to_the_bound_and_then_restart_the_job() -> void:
	var handle := _handle()
	var watch := _settled()
	var restarts := 0
	for i in FRAMES:
		handle.position += Vector2(0.0, 0.004)
		if watch.world_changed(_sight()):
			restarts += 1
			watch.built(ORIGIN, FACING, _sight())
		else:
			assert_float(watch.lag()).is_less_equal(Watch.STILL_PX)
	# 0.004 px a frame: a bound's worth every 13 frames, and the frame after each
	assert_int(restarts).is_between(6, 12)


func test_a_move_of_the_bound_or_more_restarts_the_job_and_starts_one() -> void:
	var handle := _handle()
	var watch := _settled()
	handle.position += Vector2(0.0, Watch.STILL_PX + 0.01)
	assert_bool(watch.world_changed(_sight())).is_true()
	assert_bool(watch.stale(ORIGIN, FACING, _sight())).is_true()
	watch.built(ORIGIN, FACING, _sight())
	watch.built(ORIGIN, FACING, _sight())  # the frame after it, with nothing moved, is clear
	# a turn counts by the extent it swings: 0.0001 rad over a 33 px extent is 0.003 px, 0.003 rad
	# is 0.1
	handle.rotation += 0.0001
	assert_bool(watch.world_changed(_sight())).is_false()
	handle.rotation += 0.003
	assert_bool(watch.world_changed(_sight())).is_true()
	watch.detach()
