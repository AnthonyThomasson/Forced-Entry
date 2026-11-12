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
## Whether the recording file is there (it may still be unreadable).
var _has_file := false


func _init(entry: Dictionary, run_mode: DecisionStub.Mode) -> void:
	_entry = entry
	mode = run_mode
	if mode == DecisionStub.Mode.REPLAY:
		_has_file = FileAccess.file_exists(path())
		recording = VonRecording.load_file(path()) if _has_file else null


## The recording file of the test: beside its script, or the descriptor's `recording`.
func path() -> String:
	return recording_path(_entry)


## The recording file of the test `entry` (a catalog descriptor): beside its script, or its
## `recording` when it names one.
static func recording_path(entry: Dictionary) -> String:
	var named := String(entry.get("recording", ""))
	return named if named != "" else VonRecording.path_for(String(entry["path"]))


## The command that records the test.
func command() -> String:
	return "tools/run_tests.sh --record-von --id=%s" % _entry["id"]


## Why the test cannot be replayed, "" when it can: its recording file is missing or is
## no recording (a corrupt file, another version).
func missing() -> String:
	if mode != DecisionStub.Mode.REPLAY or recording != null:
		return ""
	if _has_file:
		return "Von recording %s is not readable (corrupt, or of another version): %s" % [
			path(), _rerecord(),
		]
	return "No Von recording %s: record it with %s" % [path(), command()]


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


## Fail `ctx` for each ask the recording had no answer for and each one the server did not answer,
## since the test cannot go on without the answer. Returns whether it added any.
func problems(ctx: TestContext) -> bool:
	if misses.size() == _reported[0] and faults.size() == _reported[1]:
		return false
	for miss: Dictionary in misses.slice(_reported[0]):
		ctx.verdict.hard_check(ctx, "Von recording %s %s for the question \"%s\" (%d options): %s"
				% [
					path(), _says(miss["why"]), String(miss["question"]).left(120),
					miss["options"].size(), _rerecord(),
				])
	for fault: String in faults.slice(_reported[1]):
		ctx.verdict.hard_check(ctx, "Von gave no answer: %s%s"
				% [fault, " (nothing is recorded)" if mode == DecisionStub.Mode.RECORD else ""])
	_reported = [misses.size(), faults.size()]
	return true


## The advice a recording problem ends with. An `own_process` test matches its recording only in a
## process of its own, so its miss may be process order, not a stale recording.
func _rerecord() -> String:
	if not _entry.get("own_process", false):
		return "re-record with " + command()
	return (
		"the miss may be process order (this test replays only in a process of its own): run it"
		+ " through tools/run_tests.sh --id=%s, and re-record with %s only if it misses there too"
		% [_entry["id"], command()]
	)


## The miss reason `why` as the middle of a sentence about the recording.
func _says(why: String) -> String:
	return "has no answer" if why == "no recorded answer" else "cannot answer: " + why


## Write the recording when the run recorded and the test ended `status_text` PASS or GAP.
func save(status_text: String) -> void:
	if (mode == DecisionStub.Mode.RECORD and faults.is_empty()
			and (status_text == "PASS" or status_text == "GAP")):
		recording.save(path())
