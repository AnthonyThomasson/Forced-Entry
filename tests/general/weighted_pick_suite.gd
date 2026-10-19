extends UnitSuite
## Native unit suite (pure logic) for General's `WeightedPick`, architecture interface 11: one
## `rng.randf()` over the total of the weights, each entry in order taking the next stretch;
## `strict` false, a roll on a stretch's end takes that entry, true, the next entry, and one past
## them all the first. The expected values are read off that description, never worked out the way
## the code does. A roll of exactly 0 comes from an rng whose state is 0: its first `randf()` is
## 0.0, which each case using it checks on a twin first, so a different engine rng reads as a broken
## premise, not a WeightedPick bug.

const DRAWS := 4000


## An rng whose first `randf()` is 0.0 (its state 0), the premise `_premise_zero_roll` checks.
func _zero_roll() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.state = 0
	return rng


## An rng seeded with `seed_value`: its twin, seeded the same, rolls the same.
func _seeded(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Checks the premise the zero-roll cases rest on: a twin of `_zero_roll` rolls 0.0.
func _premise_zero_roll() -> void:
	assert_float(_zero_roll().randf()).override_failure_message(
		"premise: an rng at state 0 rolls 0.0"
	).is_equal(0.0)


func test_a_roll_on_the_end_of_a_stretch_takes_that_entry_unless_strict() -> void:
	_premise_zero_roll()
	# a's stretch is [0, 0]: a roll of 0 is on its end.
	assert_that(WeightedPick.key(_zero_roll(), { "a": 0.0, "b": 1.0 })).is_equal("a")
	assert_that(WeightedPick.key(_zero_roll(), { "a": 0.0, "b": 1.0 }, true)).is_equal("b")


func test_strict_past_every_stretch_takes_the_first() -> void:
	# No weight at all: every roll is 0, on the end of every stretch. Strict passes each one by and
	# so takes the first; not strict, the first stretch's end already takes it.
	for seed_value in [1, 7, 99]:
		var weights := { "a": 0.0, "b": 0.0, "c": 0.0 }
		assert_that(WeightedPick.key(_seeded(seed_value), weights, true)).is_equal("a")
		assert_that(WeightedPick.key(_seeded(seed_value), weights)).is_equal("a")


func test_the_keys_take_their_stretches_in_their_order() -> void:
	_premise_zero_roll()
	assert_that(WeightedPick.key(_zero_roll(), { "b": 1.0, "a": 1.0 })).is_equal("b")
	assert_that(WeightedPick.key(_zero_roll(), { "b": 1.0, "a": 1.0 }, true)).is_equal("b")


func test_pick_returns_the_key_column_of_the_drawn_row() -> void:
	_premise_zero_roll()
	var rows := [["p", 0.0, "P"], ["q", 5.0, "Q"]]
	assert_that(WeightedPick.pick(_zero_roll(), rows)).is_equal("p")
	assert_that(WeightedPick.pick(_zero_roll(), rows, 2)).is_equal("P")
	assert_that(WeightedPick.pick(_zero_roll(), rows, 2, 1, true)).is_equal("Q")
	# The weight read from another column: x's stretch is [0, 5], and a roll of 0 lies inside it
	# either way.
	var by_first := [[5.0, "x"], [0.0, "y"]]
	assert_that(WeightedPick.pick(_zero_roll(), by_first, 1, 0)).is_equal("x")
	assert_that(WeightedPick.pick(_zero_roll(), by_first, 1, 0, true)).is_equal("x")


func test_index_returns_the_drawn_row_position() -> void:
	_premise_zero_roll()
	var rows := [["p", 0.0], ["q", 2.0], ["r", 2.0]]
	assert_int(WeightedPick.index(_zero_roll(), rows)).is_equal(0)
	assert_int(WeightedPick.index(_zero_roll(), rows, 1, true)).is_equal(1)
	var two_columns := [[0.0, 9.0], [3.0, 0.0]]
	assert_int(WeightedPick.index(_zero_roll(), two_columns, 0)).is_equal(0)
	assert_int(WeightedPick.index(_zero_roll(), two_columns, 0, true)).is_equal(1)
	assert_int(WeightedPick.index(_zero_roll(), two_columns, 1, true)).is_equal(0)


func test_a_draw_takes_one_roll() -> void:
	var pick := func(rng: RandomNumberGenerator) -> void:
		WeightedPick.pick(rng, [["a", 1.0], ["b", 2.0]])
	var key := func(rng: RandomNumberGenerator) -> void:
		WeightedPick.key(rng, { "a": 1.0, "b": 2.0 })
	var index := func(rng: RandomNumberGenerator) -> void:
		WeightedPick.index(rng, [["a", 1.0], ["b", 2.0]])
	var draws := { "pick": pick, "key": key, "index": index }
	for draw_name in draws:
		var rng := _seeded(12_345)
		var twin := _seeded(12_345)
		(draws[draw_name] as Callable).call(rng)
		twin.randf()
		assert_float(rng.randf()).override_failure_message(
			"%s spends exactly one randf()" % draw_name
		).is_equal(twin.randf())


func test_entries_are_drawn_by_their_weight() -> void:
	var rng := _seeded(2024)
	var b := 0
	for _i in DRAWS:
		if WeightedPick.key(rng, { "a": 1.0, "b": 3.0 }) == "b":
			b += 1
	assert_float(float(b) / DRAWS).override_failure_message(
		"b weighs 3 of 4: %d of %d draws" % [b, DRAWS]
	).is_between(0.72, 0.78)
	var counts := [0, 0, 0]
	for _i in DRAWS:
		counts[WeightedPick.index(rng, [["x", 1.0], ["y", 0.0], ["z", 1.0]])] += 1
	assert_int(counts[1]).override_failure_message("a weight of 0 is never drawn").is_equal(0)
	assert_float(float(counts[0]) / DRAWS).override_failure_message(
		"x and z weigh one each: %s" % [counts]
	).is_between(0.47, 0.53)
