extends RefCounted
## AI PERCEPTION sub-domain — the perception's entry, its part `entry`: the doorway geometry for a
## tactical entry (agent_entry.gd, `doorways`) and the allies' entry claims heard on the radio
## (stack/claim_ledger.gd, `ledger`), which it holds, read from where the NPC stands — a doorway's
## geometry and its stack, the side of the door a point or the NPC is on, whether a way reaches a
## slot, the doorways to cover and to watch — and the rooms cleared (E9). Built once with its
## `AgentPerception`, it holds it (a node, so no reference cycle) for the body, the memory and its
## sibling parts.

const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")

## The perception it belongs to.
var perception: Node
## The doorway geometry; see agent_entry.gd.
var doorways: RefCounted
## The allies' entry claims heard on the radio; see stack/claim_ledger.gd.
var ledger: RefCounted


func _init(npc_perception: Node) -> void:
	perception = npc_perception


## The geometry of going through doorway `opening_id` into room `into` (see agent_entry.gd
## `geometry`): the door's frame, the stack slots and pie arc on either side, and the room's corners
## tagged hard or soft. {} when unknown.
func geometry(opening_id: String, into: String) -> Dictionary:
	return doorways.geometry(
		opening_id,
		into,
		perception._character.get_world_2d().navigation_map,
		perception._character.get_world_2d().direct_space_state,
	)


## Mark room `key` cleared: its entry was carried through to the end (or searched by sight to the
## end), by this NPC or by an ally who radioed it. Not the same as having stood in it
## (`visited_room`): a room walked through unprepared is visited, not cleared. It lapses after
## `tuning.memory.search_ttl`, like a searched room. A stack order into it is done.
func mark_cleared(key: String) -> void:
	perception._memory.remember(
		&"cleared_room", { "key": key }, perception.tuning.memory.search_ttl, key
	)
	var held: Dictionary = perception.orders.current()
	if String(held.get("kind", "")) == "stack" and String(held.get("into", "")) == key:
		# A stack order ends at its room cleared (LD9), by this NPC or by an ally who radioed it.
		perception.orders.end(held["id"], "done")


## Whether room `key` is cleared (see `mark_cleared`).
func is_cleared(key: String) -> bool:
	return perception._memory.age_of(
		&"cleared_room",
		"key",
		key,
	) <= perception.tuning.memory.search_ttl


## Whether the NPC can walk from where it stands to `to` with a body standing at each of `bodies` in
## its way (see agent_entry.gd `slot_reach`): 1 yes, 0 no, -1 not known yet (its map is being
## baked).
func slot_reach(to: Vector2, bodies: Array) -> int:
	return doorways.slot_reach(
		perception._character.global_position,
		to,
		perception._character.get_world_2d().navigation_map,
		bodies,
	)


## The doorways out of the cleared room `into` that lead on into a room that is not cleared, other
## than `opening_id` (the one the NPC came in by): what the team covers once the room is clear, as
## `{ id, into, pos, width }` (see agent_entry.gd `watch_doors`).
func watch_doors(into: String, opening_id: String) -> Array:
	return doorways.watch_doors(into, opening_id, is_cleared)


## Every doorway of room `room_key`, outer doors included, as `{ id, pos, width }` (see
## agent_entry.gd `room_doorways`): the places a resting NPC watches.
func room_doorways(room_key: String) -> Array:
	return doorways.room_doorways(room_key)


## The stack at doorway `opening_id` into room `into` as the radio describes it
## (stack/door_stack.gd): the allies' live claims on it (stack/claim_ledger.gd `claims`) over its
## geometry (`geometry`), every slot rule settled the one way. One per doorway a frame. With `into`
## "" it has no geometry: only what the claims alone answer (`team`, `claimed`, `stacking`,
## `going_in`, `released`, `crossing`, `order_claim`) may be asked of it.
func stack(opening_id: String, into := "") -> RefCounted:
	return ledger.stack(opening_id, geometry(opening_id, into) if into != "" else {})


## The side of a doorway (`g` from `geometry()`) point `p` is on, 1 / -1 along its wall: the radio
## claims' `side` (see agent_entry.gd `side_of`).
func side_of(g: Dictionary, p: Vector2) -> int:
	return AgentEntry.side_of(g, p)


## The side of a doorway the NPC stacks on from where it stands in `door_stack` (`stack()`): the
## team's, unless its way there crosses the doorway's view, then its own (a split stack, see
## agent_entry.gd `stack_side_from`).
func stack_side(door_stack: RefCounted) -> int:
	var world: World2D = perception._character.get_world_2d()
	return doorways.stack_side_from(
		door_stack,
		perception._character.global_position,
		world.navigation_map,
		world.direct_space_state,
	)


## Whether point `p` is ground a stack going in by `g` (a doorway's geometry) may walk on to its
## slot (`AgentEntry.slots.on_stack_side`: on the stack side, in its room, out of every other
## doorway's funnel).
func on_stack_side(g: Dictionary, p: Vector2) -> bool:
	return doorways.slots.on_stack_side(doorways, g, p)
