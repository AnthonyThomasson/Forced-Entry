extends RefCounted
## AI domain · TEAM — the human stepping up to a doorway (`docs/leadership.md` LD24, D27), a part
## its `PlayerStack` builds once and holds as `step_up`: which doorway nobody stacks at the human
## has stood stepped up to for `PlayerStack.STEP_UP_TIME`, where its own claim goes. It holds its
## stack (a node, so no reference cycle) for the human, the house's doorways, the doorways the human
## declined and the doorway geometry.

const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
const PlayerStack := preload("res://scenes/ai/team/player_stack.gd")

## The stack it belongs to.
var stack: PlayerStack
## The doorway the human stands stepped up to ("" none).
var _stepping := ""
## Since when (`GameClock.seconds()`) the human has stood stepped up to `_stepping`.
var _stepping_since := 0.0


func _init(human_stack: PlayerStack) -> void:
	stack = human_stack


## The doorway the human has stepped up to (`{ id, into, geo }`, {} for none): one no stack forms
## at (`stacking_now`) nor declined, on whose stack side it has stood `STEP_UP_TIME` against the
## wall beside the opening (out from the wall plane and past the jamb along it, each within
## `STEP_UP_REACH`): where the first of a stack stands. Not a pure query: each call advances the
## step-up timer (`_stepping`, restarted at `GameClock.seconds()` whenever the doorway stood at
## changes), so it is called once per check.
func stepped(stacking_now: Dictionary) -> Dictionary:
	var pos := stack._char.global_position
	var world := stack._char.get_world_2d()
	var found := {}
	for o: Dictionary in stack._openings:
		var door: Vector2 = o["pos"]
		var half := float(o.get("width", 80.0)) * 0.5
		var id := AgentEntry.opening_id(o)
		if (pos.distance_to(door) > half + PlayerStack.STEP_UP_REACH * 2.0
				or stacking_now.has(id)
				or stack._barred.has(id)):
			continue
		for key in o.get("rooms", []):
			var geo: Dictionary = stack._entry.geometry(
				id, str(key), world.navigation_map, world.direct_space_state,
			)
			if geo.is_empty() or not stack._entry.slots.on_stack_side(stack._entry, geo, pos):
				continue
			var out := (pos - door).dot(geo["out"])
			var lateral := absf((pos - door).dot(geo["along"]))
			if (out > 0.0
					and out <= PlayerStack.STEP_UP_REACH
					and lateral >= half
					and lateral <= half + PlayerStack.STEP_UP_REACH):
				found = { "id": id, "into": str(key), "geo": geo }
				break
		if not found.is_empty():
			break
	var here := str(found.get("id", ""))
	if here != _stepping:
		_stepping = here
		_stepping_since = GameClock.seconds()
	if here == "" or GameClock.seconds() - _stepping_since < PlayerStack.STEP_UP_TIME:
		return {}
	return found
