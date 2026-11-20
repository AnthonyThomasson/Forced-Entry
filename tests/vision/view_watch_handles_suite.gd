extends UnitSuite
## Native unit suite for `ViewWatch` and the plan handles (#194 del2d-c3): a `Node2D` of
## `TwinSpace.BODIES` (a wall, a door, a vehicle) has no engine body, and a watch that read only
## `CollisionObject2D`s would never see a door swing or a car move. The seam is the one of
## `view_watch_suite.gd`: bodies in the tree, `stale` asked each frame, the eye still.

const Watch := preload("res://scenes/vision/view_watch.gd")
## Where the handles stand: far from the origin, so no other test's body is near.
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


## A watch that has sorted what is in the tree (the first ask answers from the key and sorts none).
func _settled() -> Watch:
	var watch := Watch.new()
	watch.attach(get_tree(), [])
	for i in 2:
		watch.stale(ORIGIN, FACING, _sight())
		watch.built(ORIGIN, FACING, _sight())
	return watch


func test_a_plan_handle_that_moves_forces_a_rebuild() -> void:
	var handle: Node2D = auto_free(Node2D.new())
	handle.add_to_group(TwinSpace.BODIES)
	handle.position = ORIGIN + Vector2(300.0, 0.0)
	add_child(handle)
	var watch := _settled()
	var due := 0
	for i in FRAMES:
		handle.position += Vector2(0.0, 1.0)
		if watch.stale(ORIGIN, FACING, _sight()):
			due += 1
			watch.built(ORIGIN, FACING, _sight())
	assert_int(due).is_equal(FRAMES)


## A fallen door that settles flat is no longer in the way: its layer marker flips with no move of
## its transform, and the cone is rebuilt.
func test_a_fallen_door_that_lies_flat_forces_a_rebuild() -> void:
	var door: Door = auto_free(Door.new())
	var hinge := ORIGIN + Vector2(300.0, 0.0)
	door.setup(
		{ "pos": hinge + Vector2(0.0, 26.0), "hinge": hinge, "swing_into": Vector2.RIGHT },
		{ "material": "hollow", "style": "flush", "color": Color.WHITE },
	)
	door.place(self)
	add_child(door)
	var watch := _settled()
	assert_bool(watch.stale(ORIGIN, FACING, _sight())).is_false()
	door.footprint.flat = true
	assert_bool(watch.stale(ORIGIN, FACING, _sight())).is_true()
