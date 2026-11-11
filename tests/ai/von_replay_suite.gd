extends UnitSuite
## Native unit suite for `DecisionStub.decide`, the answer of a replayed, live or recorded Von ask:
## a replay answers by key and maps the recorded pick back to the offered id; an ask the recording
## lacks, and a recorded pick that no offered option matches, are each reported as what they are;
## a live ask after a fault is not asked at all (no ten-second wait per ask), and a recording run
## fills its recording. A stand-in `source` plays the server.

const STATE := "You are in the kitchen."
const QUESTION := "What do you open?"

var _saved := {}
var _asked := 0


func before_test() -> void:
	var holder: Script = DecisionStub
	for prop in ["mode", "recording", "misses", "faults", "requests", "source"]:
		_saved[prop] = holder.get(prop)
	DecisionStub.misses = []
	DecisionStub.faults = []
	DecisionStub.requests = []
	DecisionStub.recording = null
	_asked = 0


func after_test() -> void:
	var holder: Script = DecisionStub
	for prop in _saved:
		holder.set(prop, _saved[prop])


func _fridge_or_drawer(_s: String, _q: String, options: Dictionary) -> Dictionary:
	_asked += 1
	for id in options:
		if String(options[id]).contains("fridge"):
			return { "pick": id, "probabilities": { id: 0.9 } }
	return {}


func _options(first: int) -> Dictionary:
	return {
		"do_%d_open" % first: "Open fridge, in the kitchen",
		"do_%d_open" % (first + 1): "Open drawer, in the kitchen",
	}


func test_a_replay_answers_with_the_option_recorded_whatever_its_instance_id() -> void:
	var rec := VonRecording.new()
	rec.add(
		STATE,
		QUESTION,
		_options(100),
		"do_100_open",
		{ "do_100_open": 0.7, "do_101_open": 0.3 },
	)
	DecisionStub.mode = DecisionStub.Mode.REPLAY
	DecisionStub.recording = rec
	var got := DecisionStub.decide(STATE, QUESTION, _options(7000), "", "")
	assert_str(got["pick"]).is_equal("do_7000_open")
	assert_dict(got["probabilities"]).is_equal({ "do_7000_open": 0.7, "do_7001_open": 0.3 })


func test_a_question_the_recording_lacks_is_a_miss_saying_so() -> void:
	DecisionStub.mode = DecisionStub.Mode.REPLAY
	DecisionStub.recording = VonRecording.new()
	assert_dict(DecisionStub.decide(STATE, QUESTION, _options(1), "", "")).is_empty()
	assert_int(DecisionStub.misses.size()).is_equal(1)
	assert_str(DecisionStub.misses[0]["why"]).is_equal("no recorded answer")


func test_a_recorded_pick_no_offered_option_matches_is_reported_as_that() -> void:
	var rec := VonRecording.new()
	rec.add(STATE, QUESTION, _options(1), "do_1_open", {})
	rec.entries[rec.entries.keys()[0]]["pick"] = "do_pick_that_is_gone"
	DecisionStub.mode = DecisionStub.Mode.REPLAY
	DecisionStub.recording = rec
	assert_dict(DecisionStub.decide(STATE, QUESTION, _options(1), "", "")).is_empty()
	assert_int(DecisionStub.misses.size()).is_equal(1)
	assert_str(DecisionStub.misses[0]["why"]).contains("do_pick_that_is_gone").contains("not among")


func test_after_a_fault_later_live_asks_fail_at_once() -> void:
	DecisionStub.mode = DecisionStub.Mode.LIVE
	DecisionStub.source = Callable(self, "_fridge_or_drawer")
	var none := { "x": "something else", "y": "nothing" }
	assert_dict(DecisionStub.decide(STATE, QUESTION, none, "", "")).is_empty()
	assert_int(DecisionStub.faults.size()).is_equal(1)
	assert_int(_asked).is_equal(1)
	assert_dict(DecisionStub.decide(STATE, QUESTION, _options(1), "", "")).is_empty()
	assert_int(_asked).override_failure_message("the second ask never reached Von").is_equal(1)
	assert_int(DecisionStub.faults.size()).is_equal(1)


func test_a_recording_run_records_each_answer_once() -> void:
	DecisionStub.mode = DecisionStub.Mode.RECORD
	DecisionStub.source = Callable(self, "_fridge_or_drawer")
	DecisionStub.recording = VonRecording.new()
	DecisionStub.decide(STATE, QUESTION, _options(10), "", "")
	DecisionStub.decide(STATE, QUESTION, _options(20), "", "")
	assert_int(DecisionStub.recording.entries.size()).is_equal(1)
	var entry: Dictionary = DecisionStub.recording.entries.values()[0]
	assert_str(entry["pick"]).is_equal(VonKey.normalise_pick("do_10_open", _options(10)))
