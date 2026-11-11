extends UnitSuite
## Native unit suite (pure logic) for `VonKey`, the replay key of a recorded Von decision: the state
## text, the question and the offered descriptions (sorted) make the key, so the order an NPC lists
## its options in does not matter; an instance id inside an option id is replaced by its spawn order
## (`WorldRng.order_of`), so the same fight reads the same in a process that allocated other ids
## first; the " (your current plan)" mark is part of a description and so of the key. Von itself is
## blind to option order and to id names (measured against a live server), which is why the key
## leaves both out. Expected values are read off that description.

const STATE := "You are in the kitchen. Two hostiles are in view."
const QUESTION := "Who do you fight first?"


## A world root with two characters-to-be enrolled in the order given: `[first, second]` are their
## node ids, whose spawn orders are 0 and 1 whatever ids the process handed them. `pad` nodes are
## allocated first, so two worlds built with different pads hold different instance ids.
func _world(pad: int) -> Array:
	var padding: Array = []
	for i in pad:
		padding.append(auto_free(Node.new()))
	var root: Node = auto_free(Node.new())
	WorldRng.register(root, 7)
	var first: Node = auto_free(Node.new())
	var second: Node = auto_free(Node.new())
	root.add_child(first)
	root.add_child(second)
	WorldRng.enrol(first)
	WorldRng.enrol(second)
	return [first.get_instance_id(), second.get_instance_id()]


func test_premise_two_worlds_hand_out_different_instance_ids() -> void:
	var a := _world(0)
	var b := _world(5)
	assert_bool(a[0] == b[0] or a[1] == b[1]).override_failure_message(
		"premise: the two worlds hold different instance ids"
	).is_false()


func test_an_instance_id_becomes_its_spawn_order() -> void:
	var ids := _world(0)
	assert_str(VonKey.normalise_id("t_%d" % ids[0])).is_equal("t_0")
	assert_str(VonKey.normalise_id("t_%d" % ids[1])).is_equal("t_1")
	assert_str(VonKey.normalise_id("lead_seen_%d" % ids[1])).is_equal("lead_seen_1")
	assert_str(VonKey.normalise_id("lead_heading_%d" % ids[0])).is_equal("lead_heading_0")
	assert_str(VonKey.normalise_id("lead_ally_%d" % ids[1])).is_equal("lead_ally_1")


func test_an_object_id_in_a_do_option_is_dropped_for_the_action() -> void:
	# the room the object is in is in the description, and an object is not a spawned character
	assert_str(VonKey.normalise_id("do_48213_sit")).is_equal("do_sit")
	assert_str(VonKey.normalise_id("do_9_lie_down")).is_equal("do_lie_down")


func test_ids_without_an_instance_id_are_kept() -> void:
	for id in ["door_840_190", "explore_west", "lead_shooter", "lead_kitchen_3_4", "flank"]:
		assert_str(VonKey.normalise_id(id)).is_equal(id)


func test_the_same_fight_in_a_process_with_other_ids_has_the_same_key() -> void:
	var a := _world(0)
	var b := _world(9)
	var key_a := VonKey.key(STATE, QUESTION, {
		"t_%d" % a[0]: "Dana — close, in the open", "t_%d" % a[1]: "Rob — far, behind cover",
	})
	var key_b := VonKey.key(STATE, QUESTION, {
		"t_%d" % b[0]: "Dana — close, in the open", "t_%d" % b[1]: "Rob — far, behind cover",
	})
	assert_str(key_a).is_equal(key_b)


func test_the_order_the_options_are_listed_in_is_not_part_of_the_key() -> void:
	var one := VonKey.key(STATE, QUESTION, { "a": "shoot", "b": "hide", "c": "flee" })
	var other := VonKey.key(STATE, QUESTION, { "c": "flee", "a": "shoot", "b": "hide" })
	assert_str(one).is_equal(other)


func test_the_state_the_question_and_each_description_are_part_of_the_key() -> void:
	var base := VonKey.key(STATE, QUESTION, { "a": "shoot", "b": "hide" })
	assert_bool(VonKey.key(STATE + " ", QUESTION, { "a": "shoot", "b": "hide" }) == base).is_false()
	assert_bool(VonKey.key(STATE, QUESTION + "?", { "a": "shoot", "b": "hide" }) == base).is_false()
	assert_bool(VonKey.key(STATE, QUESTION, { "a": "shoot", "b": "duck" }) == base).is_false()
	assert_bool(VonKey.key(STATE, QUESTION, { "a": "shoot" }) == base).is_false()


func test_the_current_plan_mark_stays_in_the_key() -> void:
	var plain := VonKey.key(STATE, QUESTION, { "a": "shoot", "b": "hide" })
	var marked := VonKey.key(STATE, QUESTION, { "a": "shoot", "b": "hide (your current plan)" })
	assert_bool(plain == marked).is_false()


func test_an_option_id_alone_does_not_change_the_key() -> void:
	# Von is blind to id names: renaming ids with the same descriptions asks the same question
	var one := VonKey.key(STATE, QUESTION, { "x0": "shoot", "x1": "hide" })
	var other := VonKey.key(STATE, QUESTION, { "a": "shoot", "b": "hide" })
	assert_str(one).is_equal(other)


func test_a_recorded_pick_maps_back_to_the_offered_id_by_its_normalised_id() -> void:
	var ids := _world(3)
	var offered := { "t_%d" % ids[0]: "Dana", "t_%d" % ids[1]: "Rob" }
	assert_str(VonKey.offered_id("t_1", offered)).is_equal("t_%d" % ids[1])
	assert_str(VonKey.offered_id("t_0", offered)).is_equal("t_%d" % ids[0])
	assert_str(VonKey.offered_id("t_2", offered)).is_equal("")


func test_probabilities_are_stored_and_read_back_under_normalised_ids() -> void:
	var ids := _world(0)
	var offered := { "t_%d" % ids[0]: "Dana", "t_%d" % ids[1]: "Rob" }
	var stored := VonKey.normalise_probabilities({
		"t_%d" % ids[0]: 0.7, "t_%d" % ids[1]: 0.3, "t_999999": 0.5,
	}, offered)
	assert_dict(stored).is_equal({ "t_0": 0.7, "t_1": 0.3 })
	var read := VonKey.offered_probabilities(stored, offered)
	assert_dict(read).is_equal({ "t_%d" % ids[0]: 0.7, "t_%d" % ids[1]: 0.3 })
