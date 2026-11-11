class_name VonKey
extends RefCounted
## AI DECISION sub-domain: the replay key of a recorded Von decision (see `VonRecording`). Von is a
## stateless ranker, deterministic for the same request, and blind to the order of the options and
## to the names of their ids (measured against a live server): only the state text, the question and
## the option descriptions move its answer. So the key is exactly those, the descriptions sorted;
## the " (your current plan)" mark an NPC's previous plan gets is part of a description and stays.
## An option id still carries an instance id (`t_<id>`, `do_<object id>_<action>`,
## `lead_seen_<id>`, `lead_heading_<id>`, `lead_ally_<id>`), which follows what the process
## allocated earlier: a recorded pick is stored under the id with that number replaced by its spawn
## order (`WorldRng.order_of`), and maps back to the offered id by that normalised id.

## Separates the key's parts; no state, question or description holds it.
const SEP := "\u0001"

## The ids that end in a character's instance id.
static var _character_id := RegEx.create_from_string(
	"^(t|lead_seen|lead_heading|lead_ally)_(\\d+)$"
)
## An object interaction's id: the object's instance id, then the action.
static var _object_id := RegEx.create_from_string("^do_\\d+_(.+)$")


## The key of one ask: `state` and `question` text and `options` (id → description).
static func key(state: String, question: String, options: Dictionary) -> String:
	return joined(state, question, descriptions(options))


## The key of an ask whose option descriptions `sorted` are already known.
static func joined(state: String, question: String, sorted: Array) -> String:
	return SEP.join([state, question, SEP.join(sorted)])


## The descriptions of `options`, sorted.
static func descriptions(options: Dictionary) -> Array:
	var out: Array = []
	for id in options:
		out.append(String(options[id]))
	out.sort()
	return out


## `id` with its instance id replaced by the spawn order of that character. A `do_` id drops its
## object (an object is no spawned character, and its room is in the description): `do_<action>`.
## A character no longer in the world reads `gone`. Any other id is returned as it is.
static func normalise_id(id: String) -> String:
	var m := _character_id.search(id)
	if m != null:
		var order := WorldRng.order_of(int(m.get_string(2)))
		return "%s_%s" % [m.get_string(1), "gone" if order >= WorldRng.GONE else str(order)]
	m = _object_id.search(id)
	if m != null:
		return "do_" + m.get_string(1)
	return id


## The offered id (key of `options`) whose normalised id is `normalised`, "" when none is.
static func offered_id(normalised: String, options: Dictionary) -> String:
	for id in options:
		if normalise_id(String(id)) == normalised:
			return String(id)
	return ""


## `probabilities` (offered id → p) stored under normalised ids; an id `options` does not offer is
## left out.
static func normalise_probabilities(probabilities: Dictionary, options: Dictionary) -> Dictionary:
	var out := {}
	for id in options:
		if probabilities.has(id):
			out[normalise_id(String(id))] = probabilities[id]
	return out


## Stored `probabilities` (normalised id → p) under the ids `options` offers now.
static func offered_probabilities(probabilities: Dictionary, options: Dictionary) -> Dictionary:
	var out := {}
	for id in options:
		var norm := normalise_id(String(id))
		if probabilities.has(norm):
			out[id] = probabilities[norm]
	return out
