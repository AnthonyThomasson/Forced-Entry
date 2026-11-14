extends UnitSuite
## Native unit suite (pure logic) for `tests/_perf/frame_report.gd`, the worst-frames report
## (`perf.md`): which frames of a window were the slowest and what each had run in it. The expected
## values are read off the description (the N slowest, the slowest first, a tie to the earlier
## frame, what ran = what the counters rose by), never worked out the way the code does.

const Report := preload("res://tests/_perf/frame_report.gd")


func test_the_worst_frames_are_the_slowest_first() -> void:
	var samples: Array[float] = [10.0, 40.0, 12.0, 25.0, 11.0]
	var worst := Report.worst(samples, [], 2)
	assert_int(worst.size()).is_equal(2)
	assert_int(worst[0]["frame"]).is_equal(1)
	assert_float(worst[0]["ms"]).is_equal(40.0)
	assert_int(worst[1]["frame"]).is_equal(3)
	assert_float(worst[1]["ms"]).is_equal(25.0)


func test_a_tie_goes_to_the_earlier_frame() -> void:
	var samples: Array[float] = [30.0, 5.0, 30.0, 30.0]
	var frames: Array = Report.worst(samples, [], 3).map(func(w): return w["frame"])
	assert_array(frames).is_equal([0, 2, 3])


func test_asking_for_more_than_there_are_gives_them_all() -> void:
	var samples: Array[float] = [9.0, 8.0]
	assert_int(Report.worst(samples, [], 5).size()).is_equal(2)
	assert_int(Report.worst([] as Array[float], [], 5).size()).is_equal(0)


func test_a_frame_names_what_ran_in_it() -> void:
	var samples: Array[float] = [10.0, 50.0, 10.0]
	var ran: Array = [{}, { "shots": 2, "asks": 1 }, { "asks": 1 }]
	var worst := Report.worst(samples, ran, 1)
	assert_dict(worst[0]["ran"]).is_equal({ "shots": 2, "asks": 1 })


func test_frames_with_no_counts_are_reported_with_an_empty_ran() -> void:
	var samples: Array[float] = [10.0, 50.0]
	assert_dict(Report.worst(samples, [], 1)[0]["ran"]).is_empty()


func test_deltas_keep_only_what_rose() -> void:
	var first := { "shots": 3, "asks": 7, "cone_starts": 2 }
	var then := { "shots": 5, "asks": 7, "cone_starts": 3, "bakes": 1 }
	assert_dict(Report.deltas(first, then)).is_equal(
		{ "shots": 2, "cone_starts": 1, "bakes": 1 }
	)


func test_ran_between_is_the_rise_between_each_pair_of_samples() -> void:
	var samples := [{ "shots": 0 }, { "shots": 0 }, { "shots": 4 }, { "shots": 5 }]
	var ran := Report.ran_between(samples)
	assert_int(ran.size()).is_equal(3)
	assert_dict(ran[0]).is_empty()
	assert_dict(ran[1]).is_equal({ "shots": 4 })
	assert_dict(ran[2]).is_equal({ "shots": 1 })


func test_a_line_names_the_frame_the_time_and_what_ran() -> void:
	var entry := { "frame": 133, "ms": 41.26, "ran": { "shots": 1, "asks": 2, "cone_starts": 1 } }
	assert_str(Report.line(entry)).is_equal(
		"#133 41.3 ms: 2 decisions asked, 1 shot, 1 cone start"
	)


func test_a_line_with_nothing_counted_says_so() -> void:
	assert_str(Report.line({ "frame": 4, "ms": 33.0, "ran": {} })).is_equal(
		"#4 33.0 ms: nothing counted"
	)


func test_plural_labels_follow_the_count() -> void:
	var entry := { "frame": 0, "ms": 20.0, "ran": { "shots": 3, "bakes": 2, "late_bakes": 1 } }
	assert_str(Report.line(entry)).is_equal(
		"#0 20.0 ms: 3 shots, 2 nav bakes, 1 late bake"
	)


func test_the_tail_counters_have_their_words() -> void:
	var entry := {
		"frame": 7, "ms": 31.0,
		"ran": {
			"tile_bakes": 2, "landings": 1, "avoid_starts": 1, "avoid_rebakes": 3,
			"cone_restarts": 1, "cone_first": 1, "cone_jump": 2, "cone_cap": 1, "cone_units": 90,
			"ragdolls": 4, "sounds": 1,
		},
	}
	assert_str(Report.line(entry)).is_equal(
		"#7 31.0 ms: 1 sound, 4 ragdoll steps, 1 bake landing, 2 steering tile bakes, "
		+ "1 avoid map start, 3 avoid map re-bakes, 1 cone restart, 1 first whole cone, "
		+ "2 jump whole cones, 1 cap whole cone, 90 cone work units"
	)


func test_a_lazy_build_is_named_by_what_it_built() -> void:
	var entry := {
		"frame": 3, "ms": 22.0,
		"ran": { "demand:leads": 1, "demand:grenade_ready": 2, "shots": 1 },
	}
	assert_str(Report.line(entry)).is_equal(
		"#3 22.0 ms: 1 shot, 2 grenade_ready builds, 1 leads build"
	)


func test_a_lazy_build_that_first_appears_is_a_rise_from_nothing() -> void:
	var first := { "shots": 1 }
	var then := { "shots": 1, "demand:entries": 2 }
	assert_dict(Report.deltas(first, then)).is_equal({ "demand:entries": 2 })
