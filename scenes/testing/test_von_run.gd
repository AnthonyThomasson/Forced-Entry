class_name VonRun
extends RefCounted
## Testing domain: how one requires_von test's Von decisions are answered in the test session
## (test_session.gd) and what that run leaves behind. `mode` is a `DecisionStub.Mode`: REPLAY plays
## the recording file beside the test (or the descriptor's `recording`), LIVE asks the server with
## the fixed hold, RECORD does too and writes the file when the test passed; SCRIPT means the stub
## is not involved (a `live_only` test, or no Von at all). The stub appends the asks it could not
## answer to `misses` (replay: no recorded answer) and `faults` (live: no answer from Von);
## `problems` turns them into failed checks naming the question and the command that records the
## test.

## A `DecisionStub.Mode`.
var mode := DecisionStub.Mode.SCRIPT
## The recording replayed (REPLAY) or filled (RECORD), null otherwise or when the file is missing.
var recording: VonRecording = null
## Asks the recording had no answer for.
var misses: Array = []
## Asks the server did not answer.
var faults: Array = []
## How many of the misses and of the faults are already checks of the test.
var _reported := [0, 0]
## The test's descriptor.
var _entry: Dictionary


func _init(
	entry: Dictionary,
	run_mode: DecisionStub.Mode,
	require_recording := false,
) -> void:
	_entry = entry
	mode = run_mode
	if mode == DecisionStub.Mode.REPLAY or mode == DecisionStub.Mode.LIVE:
		recording = VonRecording.load_file(path())
		if recording == null and not (mode == DecisionStub.Mode.REPLAY and require_recording):
			mode = DecisionStub.Mode.SCRIPT
	if mode == DecisionStub.Mode.LIVE:
		recording = null  # live asks the server, and writes nothing


## The recording file of the test: beside its script, or the descriptor's `recording`.
func path() -> String:
	return String(_entry.get("recording", VonRecording.path_for(String(_entry["path"]))))


## The command that records the test.
func command() -> String:
	return "tools/run_tests.sh --record-von --id=%s" % _entry["id"]


## Why the test cannot be replayed, "" when it can: its recording is missing or is no recording.
func missing() -> String:
	if mode != DecisionStub.Mode.REPLAY or recording != null:
		return ""
	return "No Von recording %s (missing, or not a recording): record it with %s" % [
		path(),
		command(),
	]


## Make the test's decisions come from its recording or the server: add the stub's statics to
## `setup`, which the world sets with its own and restores with them.
func arm(setup: TestSetup) -> void:
	if mode == DecisionStub.Mode.SCRIPT:
		return
	if mode == DecisionStub.Mode.RECORD:
		recording = VonRecording.new()
	var armed := {
		&"active": true, &"mode": mode, &"recording": recording, &"misses": misses,
		&"faults": faults, &"requests": [],
	}
	for prop: StringName in armed:
		setup.statics.append([DecisionStub, prop, armed[prop]])


## Fail `ctx` for each ask the recording had no answer for and each one the server did not answer
## (a recording cannot be written without it): the test cannot go on without the answer. Returns
## whether it added any.
func problems(ctx: TestContext) -> bool:
	if misses.size() == _reported[0] and faults.size() == _reported[1]:
		return false
	for miss: Dictionary in misses.slice(_reported[0]):
		ctx.check(false, "Von recording %s has no answer for the question \"%s\" (%d options): "
				% [path(), String(miss["question"]).left(120), miss["options"].size()]
				+ "re-record with " + command())
	for fault: String in faults.slice(_reported[1]):
		ctx.check(false, "Von gave no answer, so no recording can be written (%s)" % fault)
	_reported = [misses.size(), faults.size()]
	return true


## Write the recording when the run recorded and the test ended `status_text` PASS or GAP.
func save(status_text: String) -> void:
	if (mode == DecisionStub.Mode.RECORD and faults.is_empty()
			and (status_text == "PASS" or status_text == "GAP")):
		recording.save(path())
