extends UnitSuite
## Native unit suite (pure logic) for Art's `MeshPool` (interface 12): the pool of parts of one
## batch a short-lived thing (a tracer, a casing) takes a place in. The expected values are read
## off the description: a part takes the next place, the parts in use are the first `count` places
## and drawn, a part that leaves is replaced by the last one (which keeps its own frame), and a full
## pool takes no more.

var _box: Mesh = MeshKit.new().box(AABB(Vector3.ZERO, Vector3.ONE), Color.WHITE).build()


func _pool(capacity: int) -> MeshPool:
	return MeshPool.new(MeshNodes.batch(_box, capacity))


func test_parts_take_the_next_places_and_the_batch_shows_them() -> void:
	var pool := _pool(4)
	var a := Object.new()
	var b := Object.new()
	assert_int(pool.add(a)).is_equal(0)
	assert_int(pool.add(b)).is_equal(1)
	assert_int(pool.count).is_equal(2)
	assert_int(pool.node.multimesh.visible_instance_count).is_equal(2)
	assert_object(pool.owner_at(1)).is_same(b)
	a.free()
	b.free()
	pool.node.free()


func test_a_part_added_twice_keeps_its_place() -> void:
	var pool := _pool(4)
	var a := Object.new()
	pool.add(a)
	assert_int(pool.add(a)).is_equal(0)
	assert_int(pool.count).is_equal(1)
	a.free()
	pool.node.free()


func test_a_full_pool_takes_no_more() -> void:
	var pool := _pool(2)
	var parts := [Object.new(), Object.new(), Object.new()]
	pool.add(parts[0])
	pool.add(parts[1])
	assert_int(pool.add(parts[2])).is_equal(-1)
	assert_int(pool.count).is_equal(2)
	assert_int(pool.slot_of(parts[2])).is_equal(-1)
	assert_int(pool.capacity()).is_equal(2)
	for part: Object in parts:
		part.free()
	pool.node.free()


func test_the_last_part_fills_the_place_of_one_that_leaves_with_its_own_frame() -> void:
	var pool := _pool(4)
	var a := Object.new()
	var b := Object.new()
	var c := Object.new()
	for part: Object in [a, b, c]:
		pool.place(pool.add(part), Transform3D(Basis.IDENTITY, Vector3(pool.count, 0, 0)))
	var c_frame := pool.frame_at(pool.slot_of(c))
	pool.remove(a)
	assert_int(pool.count).is_equal(2)
	assert_int(pool.node.multimesh.visible_instance_count).is_equal(2)
	assert_int(pool.slot_of(c)).is_equal(0)
	assert_int(pool.slot_of(b)).is_equal(1)
	assert_int(pool.slot_of(a)).is_equal(-1)
	assert_vector(pool.frame_at(0).origin).is_equal(c_frame.origin)
	assert_vector(pool.frame_at(1).origin).is_equal(Vector3(2, 0, 0))
	for part: Object in [a, b, c]:
		part.free()
	pool.node.free()


func test_removing_the_last_part_or_a_stranger_changes_nothing_else() -> void:
	var pool := _pool(3)
	var a := Object.new()
	var b := Object.new()
	var stranger := Object.new()
	pool.add(a)
	pool.add(b)
	pool.remove(stranger)
	assert_int(pool.count).is_equal(2)
	pool.remove(b)
	assert_int(pool.count).is_equal(1)
	assert_int(pool.slot_of(a)).is_equal(0)
	pool.remove(a)
	assert_int(pool.count).is_equal(0)
	assert_int(pool.node.multimesh.visible_instance_count).is_equal(0)
	for part: Object in [a, b, stranger]:
		part.free()
	pool.node.free()


func test_a_freed_place_is_taken_again() -> void:
	var pool := _pool(2)
	var parts := [Object.new(), Object.new(), Object.new()]
	pool.add(parts[0])
	pool.add(parts[1])
	pool.remove(parts[0])
	assert_int(pool.add(parts[2])).is_equal(1)
	assert_int(pool.count).is_equal(2)
	for part: Object in parts:
		part.free()
	pool.node.free()
