extends RefCounted
## Probe helpers (not a test) for the perception cadence tests (`tests/ai/perception/`): a
## perception with its parts built as its controller's `_ready` leaves it, pieces of furniture in
## a body's cone, and a watching NPC with the characters around it.

const AgentPerception := preload("res://scenes/ai/perception/agent_perception.gd")
const SightBody := preload("res://tests/_ai/sight_body_probe.gd")


## A perception with its modules and parts built. Not in the tree: free it with the test.
static func perception() -> Node:
	var made: Node = AgentPerception.new()
	made.setup()
	return made


## A perception with the default tuning applied, standing in for `body` (added to `parent`).
static func perception_of(parent: Node, body: SightBody) -> Node:
	var made := perception()
	made.apply_config(NpcTuning.defaults())
	parent.add_child(body)
	made.set("_character", body)
	return made


## `count` pieces in the cone of a body at the origin facing +x, in the clear, each a distinct spot.
static func furniture(parent: Node, count: int) -> Array:
	var out: Array = []
	for i in count:
		var piece := Node2D.new()
		parent.add_child(piece)
		piece.position = Vector2(150.0 + 30.0 * i, 20.0 * i - 50.0)
		out.append(piece)
	return out


## `ids` sorted, for an order-free comparison.
static func sorted(ids: Array) -> Array:
	var out := ids.duplicate()
	out.sort()
	return out


## A watching NPC at the origin facing +x with its perception, and the characters around it: one
## `ahead` in the cone, one at the `side` and one `behind` (out of the cone), one `bubble` close
## behind it (inside the near bubble), one `dead` ahead. They share `root`.
static func watcher(root: Node2D) -> Dictionary:
	var made := perception()
	made.apply_config(NpcTuning.defaults())
	var body := SightBody.new()
	root.add_child(body)
	body.add_to_group(&"characters")
	made.set("_character", body)
	var others := {}
	for entry in [
		["ahead", Vector2(200.0, 0.0)],
		["side", Vector2(0.0, 300.0)],
		["behind", Vector2(-300.0, 0.0)],
		["bubble", Vector2(-30.0, 0.0)],
		["dead", Vector2(300.0, 0.0)],
	]:
		var other := SightBody.new()
		other.faction = &"invader"
		other.is_dead = entry[0] == "dead"
		root.add_child(other)
		other.position = entry[1]
		other.add_to_group(&"characters")
		others[entry[0]] = other
	return { "root": root, "perception": made, "body": body, "others": others }
