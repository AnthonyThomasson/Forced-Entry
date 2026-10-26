extends RefCounted
## AI PERCEPTION sub-domain — the perception's house, its part `house`: what the NPC knows of the
## house — its rooms (`rooms`, as handed to the latest observe()), its doorways (`openings`) and
## entrance (`entry_point`), injected by its composer, the rooms and furniture it has learned
## (`saw_room` / `saw_object`, seeded for a familiar NPC, else learned by sight every
## `LEARN_EVERY_FRAMES`, offset per NPC by the perception node's own instance id), the interactables
## and its post — and the read of it the tactics overlay draws (`room_status`). Built once with its
## `AgentPerception`, it holds it (a node, so no reference cycle) for the body, the memory and its
## sibling parts.

const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")
## Physics frames between an unfamiliar NPC's looks for rooms and furniture it does not know yet.
## Learning is permanent and a decision looks again first, so a glimpse shorter than this still
## counts when it is the moment of a decision.
const LEARN_EVERY_FRAMES := 6

## The perception it belongs to.
var perception: Node
## The house entrance in world space (injected by its composer for an invader), offered while
## outside.
var entry_point: Vector2 = Vector2.ZERO
## The house's doorways (`WorldGen.get_openings`, injected by its composer), for tactical entry.
var openings: Array = []
## The house's rooms, as handed to the latest observe().
var rooms: Array = []
## The NPC's spawn position, captured on the first observe() call.
var post := Vector2.ZERO
## Whether post has been captured yet.
var _post_set := false
## Cached world objects that advertise interactions (static furniture).
var interactables: Array = []
## Whether the one-time interactable scan has run.
var _scanned := false
## Whether the familiar-NPC house-knowledge seed has run.
var _seeded := false
## First physics frame the next look for unknown rooms and furniture may run.
var learn_next := 0
## Physics frame of the latest such look (-1 = none yet).
var _learned_frame := -1


func _init(npc_perception: Node) -> void:
	perception = npc_perception


## Debug read: every room tagged by how this NPC regards it right now — the one it stands in
## (`current`), a room it has seen and searched recently (`searched`) or seen but not searched
## (`unsearched`), or one it has not yet seen at all (`unknown`). This is the room reasoning the
## search/room/flank options are placed against, exposed for the tactics debug overlay to draw as
## zones. A pure read of knowledge + the visited-room memory; never perturbs it.
func room_status(house_rooms: Array, self_pos: Vector2) -> Array:
	var known := known_room_keys()
	var here := HouseRooms.at(self_pos, house_rooms)
	var out: Array = []
	for room in house_rooms:
		var status: StringName
		if not here.is_empty() and room["key"] == here["key"]:
			status = &"current"
		elif not known.has(room["key"]):
			status = &"unknown"
		elif (perception._memory.age_of(&"visited_room", "key", room["key"])
				> perception.tuning.memory.search_ttl):
			status = &"unsearched"
		else:
			status = &"searched"
		out.append({
			"rect": room["rect"],
			"type": str(room["type"]).replace("_", " "),
			"status": status,
		})
	return out


## Before a look: capture the NPC's post on the first call, scan the interactables once, learn the
## grenades carried and the body's heights, seed a familiar NPC's house knowledge, hand the house to
## the doorway geometry (laying the doorways ahead while `tuning.entry.enabled`) and keep
## `house_rooms`.
func take_in(house_rooms: Array) -> void:
	if not _post_set:
		post = perception._character.global_position
		_post_set = true
	_ensure_interactables()
	perception.grenades.throw.learn_carried()
	perception.grenades.throw.learn_body()
	_seed_house(house_rooms)
	perception.entry.doorways.set_house(openings, house_rooms)
	if perception.tuning.entry.enabled:
		var world: World2D = perception._character.get_world_2d()
		# Lay the doorways before a decision needs them.
		perception.entry.doorways.warm_geometry(world.navigation_map, world.direct_space_state)
	rooms = house_rooms


## An unfamiliar NPC learns the rooms and objects it can see (permanent once learned). Runs every
## `LEARN_EVERY_FRAMES` frames from `observe()`, offset per NPC so a squad does not look on the same
## frame, and at the start of every decision, so what it knows when it decides is what it sees at
## that moment.
func learn_by_sight(house_rooms: Array) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _learned_frame:
		return
	learn_next = frame + (LEARN_EVERY_FRAMES
			if _learned_frame >= 0
			else 1 + perception.get_instance_id() % LEARN_EVERY_FRAMES)
	_learned_frame = frame
	var self_pos: Vector2 = perception._character.global_position
	var facing: Vector2 = perception._character.facing
	var space: PhysicsDirectSpaceState2D = perception._character.get_world_2d().direct_space_state
	var exclude := [perception._character.get_rid()]
	# Read once: what is learned here is permanent and only grows.
	var known_rooms_now := known_room_keys()
	for room in house_rooms:
		if known_rooms_now.has(room["key"]):
			continue  # Already learned: looking again would change nothing.
		var rect: Rect2 = room["rect"]
		var centre := rect.position + rect.size * 0.5
		if (rect.has_point(self_pos)
				or perception.sight.vision.can_see(self_pos, facing, centre, space, exclude)):
			known_rooms_now[room["key"]] = true
			learn_room(room)
	var known_objects := known_object_ids()
	for obj in interactables:
		if not is_instance_valid(obj) or known_objects.has(obj.get_instance_id()):
			continue
		if perception.sight.vision.can_see_node(obj, self_pos, facing, space, exclude):
			known_objects[obj.get_instance_id()] = true
			_learn_object(obj)


## Seed a familiar NPC's house knowledge once: remember every room and interactable as already-known
## (permanent ttl). An unfamiliar NPC skips this and learns by sight in observe(). Needs the rooms
## list, so it runs on the first observe() (not _ready).
func _seed_house(house_rooms: Array) -> void:
	if _seeded or not perception.tuning.memory.familiar_with_house:
		return
	_seeded = true
	for room in house_rooms:
		learn_room(room)
	for obj in interactables:
		if is_instance_valid(obj):
			_learn_object(obj)


## Remember a room as known (permanent).
func learn_room(room: Dictionary) -> void:
	if not known_room_keys().has(room["key"]):
		perception._memory.remember(&"saw_room", { "key": room["key"] }, 0.0, str(room["key"]))


## Remember an interactable object as known (permanent), keyed by instance id.
func _learn_object(obj: Object) -> void:
	if not known_object_ids().has(obj.get_instance_id()):
		perception._memory.remember(
			&"saw_object",
			{ "id": obj.get_instance_id() },
			0.0,
			str(obj.get_instance_id()),
		)


## The rooms the NPC knows (all of `house_rooms` whose key it has learned), in `house_rooms` order.
func known_rooms(house_rooms: Array) -> Array:
	var known := known_room_keys()
	return house_rooms.filter(func(r): return known.has(r["key"]))


## The set of room keys the NPC currently knows (from `saw_room` memory), as a lookup dict.
func known_room_keys() -> Dictionary:
	var out := {}
	for data in perception._memory.recall_all(&"saw_room"):
		out[data.get("key")] = true
	return out


## The set of interactable instance ids the NPC currently knows (from `saw_object` memory).
func known_object_ids() -> Dictionary:
	var out := {}
	for data in perception._memory.recall_all(&"saw_object"):
		out[data.get("id")] = true
	return out


## Scan the world once for objects that advertise interactions (static furniture), caching the refs.
## Positions are read live each tick; the set itself doesn't change during a run.
func _ensure_interactables() -> void:
	if _scanned:
		return
	_scanned = true
	interactables.clear()
	var root: Node = perception._character.world_root()
	if root != null:
		_collect(root)


## Recursively gather descendants whose get_interactions() is non-empty into `interactables`.
func _collect(node: Node) -> void:
	for child in node.get_children():
		if (child.has_method("get_interactions")
				and not (child.get_interactions() as Array).is_empty()):
			interactables.append(child)
		_collect(child)
