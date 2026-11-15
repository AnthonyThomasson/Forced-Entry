extends UnitSuite
## Native unit suite (pure logic) for Art's mesh cache (`MeshCache`; interface 12, #193 phase 2):
## the same inputs give the one shared `Mesh`, a key names everything the mesh is made from (the
## scale, the kit's own tunables) and the cache is bounded. Expected values are the description's
## (two equal inputs are one mesh; a different tone is a different key), never the cache's own
## bookkeeping.

const RED := Color(0.8, 0.2, 0.2)
const BLUE := Color(0.2, 0.3, 0.8)


func test_the_cache_hands_the_same_mesh_for_the_same_inputs() -> void:
	MeshCache.clear()
	var made: Array[int] = [0]
	var make := func() -> Mesh:
		made[0] += 1
		return MeshKit.new().box(AABB(Vector3.ZERO, Vector3(10, 10, 10)), RED).build()
	var key := MeshCache.key("table", Vector2(120, 70), RED, { "a": 1, "b": 2 })
	var first := MeshCache.fetch(key, make)
	# The options in another order are the same inputs.
	var again := MeshCache.fetch(
		MeshCache.key("table", Vector2(120, 70), RED, { "b": 2, "a": 1 }),
		make,
	)
	assert_bool(again == first).override_failure_message("one Mesh resource").is_true()
	assert_int(made[0]).is_equal(1)
	for other in [
		MeshCache.key("table", Vector2(120, 71), RED, { "a": 1, "b": 2 }),
		MeshCache.key("table", Vector2(120, 70), BLUE, { "a": 1, "b": 2 }),
		MeshCache.key("chair", Vector2(120, 70), RED, { "a": 1, "b": 2 }),
		MeshCache.key("table", Vector2(120, 70), RED, { "a": 1, "b": 3 }),
	]:
		assert_bool(MeshCache.fetch(other, make) == first).override_failure_message(
			"different inputs are a different mesh: %s" % other
		).is_false()
	assert_int(MeshCache.count()).is_equal(5)
	MeshCache.clear()


func test_a_changed_scale_is_a_different_cache_key() -> void:
	var unit := RenderConfig.unit
	var a := MeshCache.key("table", Vector2(120, 70), RED)
	RenderConfig.unit = unit * 2.0
	var b := MeshCache.key("table", Vector2(120, 70), RED)
	RenderConfig.unit = unit
	assert_bool(a == b).is_false()


func test_every_tone_and_the_round_solids_side_count_are_in_the_cache_key() -> void:
	var plain := MeshCache.key("seat", Vector2(40, 40), RED)
	for knob: Array in [
		[ArtSurfaceConfig, &"tone_outline"], [ArtSurfaceConfig, &"tone_shadow"],
		[ArtSurfaceConfig, &"tone_dark"], [ArtSurfaceConfig, &"tone_light"],
		[ArtSurfaceConfig, &"tone_highlight"], [MeshKitConfig, &"cylinder_sides"],
	]:
		var holder: Object = knob[0]
		var field: StringName = knob[1]
		var was: Variant = holder.get(field)
		if was is int:
			holder.set(field, (was as int) + 3)
		else:
			holder.set(field, (was as float) + 0.05)
		var retuned := MeshCache.key("seat", Vector2(40, 40), RED)
		holder.set(field, was)
		assert_bool(retuned == plain).override_failure_message(
			"%s is not part of the mesh cache key" % field
		).is_false()


func test_the_cache_is_bounded_and_drops_the_one_asked_for_longest_ago() -> void:
	MeshCache.clear()
	var limit := MeshKitConfig.cache_limit
	MeshKitConfig.cache_limit = 3
	var made: Array[int] = [0]
	var make := func() -> Mesh:
		made[0] += 1
		return ArrayMesh.new()
	for label in ["a", "b", "c"]:
		MeshCache.fetch(label, make)
	MeshCache.fetch("a", make)  # asked for again: "b" is now the longest unasked
	MeshCache.fetch("d", make)
	var kept := MeshCache.count()
	var builds := made[0]
	MeshCache.fetch("a", make)  # still there
	MeshCache.fetch("c", make)  # still there
	var still := made[0]
	MeshCache.fetch("b", make)  # was dropped: built again
	MeshKitConfig.cache_limit = limit
	MeshCache.clear()
	assert_int(kept).is_equal(3)
	assert_int(builds).is_equal(4)
	assert_int(still).is_equal(4)
	assert_int(made[0]).is_equal(5)
