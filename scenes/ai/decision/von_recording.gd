class_name VonRecording
extends RefCounted
## AI DECISION sub-domain: the recorded Von answers of one test, the file beside it
## (`<name>_test.von.json`) the test replays instead of asking a live server. An entry holds the key
## fields of one ask (`state`, `question`, the sorted option descriptions as `options`; `VonKey`),
## the `pick` as a normalised id and Von's `probabilities` by normalised id (what the brain overlay
## reads). `add` keeps the first answer for a key (Von answers the same ask the same), in the order
## the asks came; `save` writes the file whole, so an entry the run did not ask for is gone.

## The file format's version; a file of another version does not load.
const VERSION := 1

## key (`VonKey.key`) → entry, in the order the asks came.
var entries := {}


## The recording file beside the test script `test_path`: `a/b_test.gd` → `a/b_test.von.json`.
static func path_for(test_path: String) -> String:
	return test_path.get_basename() + ".von.json"


## The recording in `path`, or null when the file is missing, unreadable or not a recording
## (`FileAccess.file_exists` tells a missing file from the rest).
static func load_file(path: String) -> VonRecording:
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("version") != VERSION or not data.get("entries") is Array:
		return null
	var rec := VonRecording.new()
	for e in data["entries"]:
		if e is Dictionary and e.get("options") is Array:
			rec.entries[VonKey.joined(e.get("state", ""), e.get("question", ""), e["options"])] = e
	return rec


## Record the answer `pick` (an offered id) with `probabilities` (offered id → p) for the ask
## `state`, `question`, `options` (id → description). The first answer for a key is kept.
func add(
	state: String,
	question: String,
	options: Dictionary,
	pick: String,
	probabilities: Dictionary,
) -> void:
	var k := VonKey.key(state, question, options)
	if entries.has(k):
		return
	entries[k] = {
		"state": state,
		"question": question,
		"options": VonKey.descriptions(options),
		"pick": VonKey.normalise_pick(pick, options),
		"probabilities": VonKey.normalise_probabilities(probabilities, options),
	}


## The entry recorded for the ask, `{}` when there is none.
func lookup(state: String, question: String, options: Dictionary) -> Dictionary:
	return entries.get(VonKey.key(state, question, options), {})


## Write the recording whole to `path`, through a temporary file renamed over it, so a run that
## stops half way never leaves a half-written recording. Returns whether the file was written.
func save(path: String) -> bool:
	var temporary := path + ".tmp"
	var f := FileAccess.open(temporary, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({ "version": VERSION, "entries": entries.values() }, "\t") + "\n")
	f.close()
	return DirAccess.rename_absolute(temporary, path) == OK
