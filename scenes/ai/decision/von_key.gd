class_name VonKey
extends RefCounted
## AI DECISION sub-domain: the replay key of a recorded Von decision (see `VonRecording`). Von is a
## stateless ranker, deterministic for the same request, and blind to the order of the options and
## to the names of their ids (measured against a live server): only the state text, the question and
## the option descriptions move its answer. So the key is exactly those, the descriptions sorted;
## the " (your current plan)" mark an NPC's previous plan gets is part of a description and stays.
## An option id still carries an instance id (`t_<id>`, `do_<object id>_<action>`,
## `lead_seen_<id>`, `lead_heading_<id>`, `lead_ally_<id>`), which follows what the process
## allocated earlier: a recorded pick is stored under the id with a character's number replaced by
## its spawn order (`WorldRng.order_of`; a `do_` id drops its object), and maps back to the offered
## id by that normalised id.

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


## The normalised id of each offered option (offered id → normalised id), each unique in the ask:
## options whose ids normalise alike (`do_<object>_open` for several objects, characters the world
## never knew) take `~0`, `~1` … by their description's rank, the order the key sorts them in, so
## the same ask reads the same ids in any process. Options of one description keep their listed
## order.
static func id_map(options: Dictionary) -> Dictionary:
	var groups := {}
	var place := {}
	for id in options:
		place[id] = place.size()
		var alike: Array = groups.get_or_add(normalise_id(String(id)), [])
		alike.append(id)
	var out := {}
	for norm: String in groups:
		var members: Array = groups[norm]
		if members.size() == 1:
			out[members[0]] = norm
			continue
		members.sort_custom(func(a, b):
			var da := String(options[a])
			var db := String(options[b])
			return place[a] < place[b] if da == db else da < db)
		for rank in members.size():
			out[members[rank]] = "%s~%d" % [norm, rank]
	return out


## The normalised id the offered option `pick` is recorded under.
static func normalise_pick(pick: String, options: Dictionary) -> String:
	return id_map(options).get(pick, pick)


## The offered id (key of `options`) whose normalised id is `normalised`, "" when none is.
static func offered_id(normalised: String, options: Dictionary) -> String:
	var ids := id_map(options)
	for id in ids:
		if ids[id] == normalised:
			return String(id)
	return ""


## `probabilities` (offered id → p) stored under normalised ids; an id `options` does not offer is
## left out.
static func normalise_probabilities(probabilities: Dictionary, options: Dictionary) -> Dictionary:
	var ids := id_map(options)
	var out := {}
	for id in ids:
		if probabilities.has(id):
			out[ids[id]] = probabilities[id]
	return out


## Stored `probabilities` (normalised id → p) under the ids `options` offers now.
static func offered_probabilities(probabilities: Dictionary, options: Dictionary) -> Dictionary:
	var ids := id_map(options)
	var out := {}
	for id in ids:
		if probabilities.has(ids[id]):
			out[id] = probabilities[ids[id]]
	return out
