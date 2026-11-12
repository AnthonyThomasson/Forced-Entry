extends GameTest
## Harness self-test: how the test session answers a requires_von test's Von decisions (#205). The
## fixture (von_fixtures/ask_fixture.gd, its recording beside it) asks two recorded questions and
## logs each answer's physics frame; this test plays it through a TestSession of its own:
## - REPLAY (no Von flag, no server): the recorded picks come back, each exactly 12 physics frames
##   after its ask (the spec: about 200 ms at 60 fps), with the recorded probabilities;
## - a question the recording lacks, and a recording that is not there, each FAIL the test naming
##   the command that records it (an unrecorded test is no skip kind: nothing replaces it);
## - a replayed test is not paced in real time, and the gate picks each run's mode from the run's
##   flags: REPLAY with none, LIVE and RECORD with theirs, and no stub at all for a live_only test;
## - RECORD and LIVE with a stand-in answer source (no server needed): the answer lands on the
##   same frame however long Von took, a recorded file holds what the committed fixture holds, and
##   an ask Von did not answer writes nothing and FAILs.

const Catalog = preload("res://scenes/testing/test_catalog.gd")
const VonGate = preload("res://scenes/testing/test_von_gate.gd")
const SessionScript = preload("res://scenes/testing/test_session.gd")
const Fixture = preload("res://tests/_harness/von_fixtures/ask_fixture.gd")
const FIXTURE_PATH := "res://tests/_harness/von_fixtures/ask_fixture.gd"
const COMMITTED := "res://tests/_harness/von_fixtures/ask_fixture.von.json"
const WRITTEN := "user://von_session_test.von.json"
## The frames an answer is held after its ask (the ticket: about 200 ms at 60 fps).
const HOLD := 12

## Wall milliseconds the stand-in source stalls for, like a slow Von.
var _stall_ms := 0


func describe() -> Dictionary:
	return {
		"name": "Von session modes",
		"tags": ["harness", "von"],
		"internal": true,
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(DecisionStub, &"source", Callable(self, "_stand_in_von"))


func run(t: TestContext) -> void:
	await _replay(t)
	await _miss(t)
	await _miss_own_process(t)
	await _missing_file(t)
	await _unreadable_file(t)
	await _gap_tagged(t)
	await _record(t)
	await _live(t)
	_modes(t)


## The answer source of RECORD and LIVE: the option described with "hide" or "Rob" with 0.7, the
## others 0.3; `{}` (no answer) when none is.
func _stand_in_von(_state: String, _question: String, options: Dictionary) -> Dictionary:
	if _stall_ms > 0:
		OS.delay_usec(_stall_ms * 1000)
	var pick := ""
	var probs := {}
	for id in options:
		var favoured: bool = (String(options[id]).contains("hide")
				or String(options[id]).contains("Rob"))
		probs[id] = 0.7 if favoured else 0.3
		if favoured:
			pick = id
	return { "pick": pick, "probabilities": probs } if pick != "" else {}


## Play the fixture through a session of its own: `{ record, log }`, its verdict record and what its
## asks logged. `recording` is the file it replays or writes, `mode` "replay", "record" or "live".
func _play(t: TestContext, recording: String, mode: String, opts := {}) -> Dictionary:
	var session := SessionScript.new()
	t.world.add_child(session)
	session.von.include = opts.get("include", true)
	session.von.record = mode == "record"
	session.von.live = mode == "live"
	var paced := { "yes": false }
	session.world_built.connect(func(_setup): paced["yes"] = session.von.paced())
	Fixture.asked = []
	var entry := Catalog.describe(FIXTURE_PATH)
	entry["recording"] = recording
	entry["tags"] = (entry["tags"] as Array) + opts.get("tags", [])
	entry["own_process"] = opts.get("own_process", false)
	await session.start(entry)
	var record: Dictionary = await session.close()
	session.queue_free()
	return { "record": record, "log": Fixture.asked.duplicate(true), "paced": paced["yes"] }


## The text of every failed check of a verdict `record`.
func _failures(record: Dictionary) -> String:
	return "\n".join(record["checks"].filter(func(c): return not c["ok"])
			.map(func(c): return c["message"]))


## The place in its ask's offered options that the pick of `a` (a fixture log entry) has: an id
## carries an instance id, which a later run does not share.
func _picked(a: Dictionary) -> int:
	return a["offered"].find(a["pick"])


func _replay(t: TestContext) -> void:
	Fixture.extra_ask = false
	# no stand-in answer source: a replay must need no server, nor any pacing the wait for one
	# brings
	var source := DecisionStub.source
	DecisionStub.source = Callable()
	var played := await _play(t, COMMITTED, "replay")
	DecisionStub.source = source
	var asks: Array = played["log"]
	t.expect_eq(played["record"]["status"], "PASS", "replay passes with no server and no flag")
	t.expect_eq(
		played["paced"],
		false,
		"a replay runs at the batch's speed, not paced in real time",
	)
	if not t.require(asks.size() == 2, "the fixture asked its two questions"):
		return
	t.expect_eq(asks[0]["pick"], "b", "the first recorded pick comes back")
	t.expect_eq(asks[1]["pick"], asks[1]["offered"][1],
			"a pick recorded under spawn order 1 comes back as the second character's id")
	t.expect_eq(asks[1]["probabilities"][asks[1]["offered"][1]], 0.7, "with its probabilities")
	for a in asks:
		t.expect_eq(
			a["answered"] - a["asked"],
			HOLD,
			"an answer lands %d frames after its ask" % HOLD,
		)


func _miss(t: TestContext) -> void:
	Fixture.extra_ask = true
	var played := await _play(t, COMMITTED, "replay")
	Fixture.extra_ask = false
	var record: Dictionary = played["record"]
	t.expect_eq(record["status"], "FAIL", "a question the recording lacks fails the test")
	var said := _failures(record)
	t.check(said.contains("What now?"), "naming the missing question: " + said)
	t.check(said.contains("tools/run_tests.sh --record-von --id=" + String(record["id"])),
			"and the command that records the test: " + said)
	var asks: Array = played["log"]
	t.check(asks.size() == 3 and asks[2]["pick"] == "" and asks[2]["answered"] < 0,
			"the ask got no answer, never a silent pick")


func _miss_own_process(t: TestContext) -> void:
	# an own_process test's replay can miss only because this process ran other things first: its
	# failure says so, and names the command that plays it in a process of its own
	Fixture.extra_ask = true
	var plain := await _play(t, COMMITTED, "replay")
	var own := await _play(t, COMMITTED, "replay", { "own_process": true })
	Fixture.extra_ask = false
	t.check(not _failures(plain["record"]).contains("process order"),
			"a test that shares the process is told to re-record only")
	var said := _failures(own["record"])
	t.check(said.contains("process order"), "an own_process miss names process order: " + said)
	t.check(said.contains("tools/run_tests.sh --id=" + String(own["record"]["id"])),
			"and the run that plays it in a process of its own: " + said)
	t.check(said.contains("--record-von"), "and still the command that records it: " + said)


func _missing_file(t: TestContext) -> void:
	var played := await _play(t, "user://no_such_recording.von.json", "replay")
	var record: Dictionary = played["record"]
	t.expect_eq(record["status"], "FAIL", "a requires_von test with no recording fails")
	var said := _failures(record)
	t.check(said.contains("no_such_recording.von.json"), "naming the file: " + said)
	t.check(said.contains("tools/run_tests.sh --record-von --id=" + String(record["id"])),
			"and the command that records the test: " + said)
	t.check(played["log"].is_empty(), "and its world never ran")


func _unreadable_file(t: TestContext) -> void:
	# a file that is there but no recording is no "missing" file: it fails like a missing one
	var bad := "user://von_session_unreadable.von.json"
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string('{"version": 99, "entries": []}')
	f.close()
	var played := await _play(t, bad, "replay")
	DirAccess.remove_absolute(bad)
	t.expect_eq(played["record"]["status"], "FAIL", "an unreadable recording fails the test")
	t.check(_failures(played["record"]).contains("not readable"), "naming it")
	t.check(played["log"].is_empty(), "and its world never ran")


func _gap_tagged(t: TestContext) -> void:
	# a stale recording is never a "gap": the test FAILs whatever it is tagged
	Fixture.extra_ask = true
	var missed := await _play(t, COMMITTED, "replay", { "tags": ["gap"] })
	Fixture.extra_ask = false
	t.expect_eq(missed["record"]["status"], "FAIL", "a miss in a gap-tagged test still fails")
	var absent := await _play(
		t, "user://no_such_recording.von.json", "replay", { "tags": ["gap"] },
	)
	t.expect_eq(absent["record"]["status"], "FAIL", "and so does a missing recording")


func _record(t: TestContext) -> void:
	DirAccess.remove_absolute(WRITTEN)
	var played := await _play(t, WRITTEN, "record")
	t.expect_eq(played["record"]["status"], "PASS", "a recording run passes")
	var written := VonRecording.load_file(WRITTEN)
	var committed := VonRecording.load_file(COMMITTED)
	if not t.require(written != null and committed != null, "the recording was written and reads"):
		return
	# not expect_eq: the entries are keyed by `VonKey.SEP`, a control character a report cannot hold
	t.check(written.entries == committed.entries, "it holds what the committed fixture holds")
	t.check(not FileAccess.file_exists(WRITTEN + ".tmp"), "no temporary file is left behind")
	var replayed := await _play(t, WRITTEN, "replay")
	t.expect_eq(replayed["record"]["status"], "PASS", "and replays what it recorded")
	t.expect_eq(replayed["log"].map(_picked), played["log"].map(_picked), "the same picks")
	# an ask Von does not answer: nothing is written over the recording
	var stamp := FileAccess.get_modified_time(WRITTEN)
	Fixture.extra_ask = true
	var faulty := await _play(t, WRITTEN, "record")
	Fixture.extra_ask = false
	t.expect_eq(faulty["record"]["status"], "FAIL", "a recording run whose ask got no answer fails")
	t.check(_failures(faulty["record"]).contains("Von gave no answer"), "saying why")
	t.expect_eq(FileAccess.get_modified_time(WRITTEN), stamp, "and writes no file")
	DirAccess.remove_absolute(WRITTEN)


func _live(t: TestContext) -> void:
	var replayed := await _play(t, COMMITTED, "replay")
	_stall_ms = 150
	# live is decided by the flags alone: this run has no recording at all
	var live := await _play(t, WRITTEN, "live")
	_stall_ms = 0
	t.expect_eq(live["record"]["status"], "PASS", "a live run passes")
	t.expect_eq(FileAccess.file_exists(WRITTEN), false, "and writes nothing")
	t.expect_eq(live["log"].map(func(a): return a["answered"] - a["asked"]),
			replayed["log"].map(func(a): return a["answered"] - a["asked"]),
			"a slow Von's answer lands on the frame a replay's does")
	t.expect_eq(live["log"].map(_picked), replayed["log"].map(_picked),
			"and picks what the recording picked")


func _modes(t: TestContext) -> void:
	var gate := VonGate.new(t.world)
	var entry := Catalog.describe(FIXTURE_PATH)
	var REPLAY := DecisionStub.Mode.REPLAY
	t.expect_eq(gate.mode_for(entry), REPLAY, "with no Von flag a Von test replays")
	gate.live = true
	t.expect_eq(
		gate.mode_for(entry),
		DecisionStub.Mode.LIVE,
		"--include-von / --require-von run it live",
	)
	gate.record = true
	t.expect_eq(gate.mode_for(entry), DecisionStub.Mode.RECORD, "--record-von records")
	entry["live_only"] = true
	for flags in [[false, false], [true, false], [true, true]]:
		gate.live = flags[0]
		gate.record = flags[1]
		t.expect_eq(
			gate.mode_for(entry),
			DecisionStub.Mode.SCRIPT,
			"a live-only test meets the real client whatever the run does (%s)" % str(flags),
		)
