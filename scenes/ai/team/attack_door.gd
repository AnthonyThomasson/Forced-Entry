extends RefCounted
## AI domain · TEAM — the attack doorway (the defenders' ambush rule): the doorway into the
## leader's room that an attack from a threat point comes through. From the room the point is in
## (outside the house counting as a room its exterior doors join), the shortest way doorway to
## doorway to the leader's room, the cost being the straight walk from the point through each
## doorway in turn; the last doorway on it is the attack doorway. Built from the house's rooms and
## doorways alone (`WorldGen.get_rooms` / `get_openings`, interface 1): no navmesh. Static,
## preloaded (no `class_name`); the squad's `ambush` part asks it.

const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")


## The id (`AgentEntry.opening_id`) of the doorway an attack from `point` comes into room
## `leader_room` by, or "" for none: `point` in `leader_room` (the fight is already inside), a
## leader in no room (`leader_room` ""), `point` at `Vector2.INF`, or no way through.
static func doorway(point: Vector2, leader_room: String, rooms: Array, openings: Array) -> String:
	if leader_room == "" or not point.is_finite():
		return ""
	var start := HouseRooms.key_at(point, rooms)
	if start == leader_room:
		return ""
	# Dijkstra over the doorways, each passed into the room on its far side: `cost` index -> the
	# walk so far, `landed` index -> the room it leads into, `done` the doorways settled.
	var walk := { "cost": {}, "landed": {}, "done": {} }
	_reach(openings, start, point, 0.0, walk)
	var best := _cheapest(walk)
	while best >= 0:
		var here: String = walk["landed"][best]
		if here == leader_room:
			return AgentEntry.opening_id(openings[best])
		walk["done"][best] = true
		_reach(openings, here, openings[best]["pos"], float(walk["cost"][best]), walk)
		best = _cheapest(walk)
	return ""


## Weigh each doorway of room `here` not yet done in `walk`, walked to straight from `from` after
## `walked` px: kept in `walk` (its walk and the room it leads into) when it is the shortest walk to
## it yet.
static func _reach(
	openings: Array,
	here: String,
	from: Vector2,
	walked: float,
	walk: Dictionary,
) -> void:
	for j in openings.size():
		var beyond = _beyond(openings[j], here)
		if walk["done"].has(j) or beyond == null:
			continue
		var through := walked + from.distance_to(openings[j]["pos"])
		if not walk["cost"].has(j) or through < float(walk["cost"][j]):
			walk["cost"][j] = through
			walk["landed"][j] = beyond


## The index of the cheapest doorway `walk` has reached and not settled, or -1.
static func _cheapest(walk: Dictionary) -> int:
	var best := -1
	for i: int in walk["cost"]:
		if walk["done"].has(i):
			continue
		if best < 0 or float(walk["cost"][i]) < float(walk["cost"][best]):
			best = i
	return best


## The room doorway `o` leads into from room `here` ("" = outside): the other room it joins, ""
## for an exterior door gone out by; null when `o` is not a doorway of `here`.
static func _beyond(o: Dictionary, here: String) -> Variant:
	var joins: Array = (o.get("rooms", []) as Array).map(func(k): return String(k))
	if here == "":
		return joins[0] if joins.size() == 1 else null
	if not joins.has(here):
		return null
	if joins.size() == 1:
		return ""
	return joins[1] if joins[0] == here else joins[0]
