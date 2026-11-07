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
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
## Physics frames between an unfamiliar NPC's looks for rooms and furniture it does not know yet.
## Learning is permanent and a decision looks again first, so a glimpse shorter than this still
## counts when it is the moment of a decision.
const LEARN_EVERY_FRAMES := 6
## How many of the scheduled looks it takes to look at every piece of furniture: a look takes each
## `LEARN_SLICES`th of the pieces it does not know yet, so a piece in view is learned at most
## `LEARN_SLICES * LEARN_EVERY_FRAMES` frames later. A decision's own look takes every piece.
const LEARN_SLICES := 3

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
## Whether the latest look was a full one (every unknown piece), not a slice.
var _learned_full := false
## How many sliced looks have been made: piece `i` of `interactables` is looked at on the sliced
## looks where `(i + _slices) % LEARN_SLICES` is 0.
var _slices := 0
## The intake identities already set up: rooms, openings, grenade-slot items and body heights.
var _intake := {}
## How often each piece of intake setup ran (fast-path test observables).
var intake_reads := { &"house": 0, &"carried": 0, &"body": 0 }


func _init(npc_perception: Node) -> void:
	perception = npc_perception


## Debug read: every room tagged by how this NPC regards it right now — the one it stands in
## (`current`), a room it has seen and searched recently (`searched`) or seen but not searched
## (`unsearched`), or one it has not yet seen at all (`unknown`). This is the room reasoning the
## search/room/flank options are placed against, exposed for the tactics debug overlay to draw as
## zones. A pure read of knowledge + the visited-room memory; never perturbs it. The house's rooms
## are those of the latest observe() (`rooms`).
func room_status(self_pos: Vector2) -> Array:
	var known := known_room_keys()
	var here := HouseRooms.at(self_pos, rooms)
	var out: Array = []
	for room in rooms:
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
	_ensure_interactables(house_rooms)
	_learn_carried()
	if not _intake.get("body", false):
		perception.grenades.throw.learn_body()
		_intake["body"] = true
		intake_reads[&"body"] += 1
	_seed_house(house_rooms)
	if (not is_same(_intake.get("rooms"), house_rooms)
			or not is_same(_intake.get("openings"), openings)):
		_intake["rooms"] = house_rooms
		_intake["openings"] = openings
		perception.entry.doorways.set_house(openings, house_rooms)
		intake_reads[&"house"] += 1
	if perception.tuning.entry.enabled:
		var world: World2D = perception._character.get_world_2d()
		# Lay the doorways before a decision needs them.
		perception.entry.doorways.warm_geometry(world.navigation_map, world.direct_space_state)
	rooms = house_rooms


## Learn the carried grenades again only when an item in either grenade slot is a different object.
func _learn_carried() -> void:
	var carried := {}
	var changed := not _intake.has("carried")
	for slot: int in AgentThrow.SLOTS.values():
		var item: Variant = perception._character.inventory.item_in(slot)
		carried[slot] = item
		if not changed and not is_same(item, _intake["carried"].get(slot)):
			changed = true
	if not changed:
		return
	_intake["carried"] = carried
	perception.grenades.throw.learn_carried()
	intake_reads[&"carried"] += 1


## An unfamiliar NPC learns the rooms and objects it can see (permanent once learned). Runs every
## `LEARN_EVERY_FRAMES` frames from `observe()`, offset per NPC so a squad does not look on the same
## frame, and at the start of every decision, so what it knows when it decides is what it sees at
## that moment. The rooms looked for are the house's (`rooms`, kept by `take_in`). A scheduled look
## takes every room but only each `LEARN_SLICES`th piece of furniture it does not know; a `full`
## look (a decision's) takes every piece.
func learn_by_sight(full := false) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _learned_frame and (_learned_full or not full):
		return
	if frame != _learned_frame:
		learn_next = frame + (LEARN_EVERY_FRAMES
				if _learned_frame >= 0
				else 1 + perception.get_instance_id() % LEARN_EVERY_FRAMES)
		if not full:
			_slices += 1
	_learned_frame = frame
	_learned_full = full
	var self_pos: Vector2 = perception._character.global_position
	var facing: Vector2 = perception._character.facing
	var space: PhysicsDirectSpaceState2D = perception._character.get_world_2d().direct_space_state
	var exclude := [perception._character.get_rid()]
	_look_at_rooms(self_pos, facing, space, exclude)
	_look_at_furniture(full, self_pos, facing, space, exclude)


## Learn the rooms not yet known that the NPC stands in or sees the middle of.
func _look_at_rooms(
	self_pos: Vector2,
	facing: Vector2,
	space: PhysicsDirectSpaceState2D,
	exclude: Array,
) -> void:
	# Read once: what is learned here is permanent and only grows.
	var known_rooms_now := known_room_keys()
	for room in rooms:
		if known_rooms_now.has(room["key"]):
			continue  # Already learned: looking again would change nothing.
		var rect: Rect2 = room["rect"]
		var centre := rect.position + rect.size * 0.5
		if (rect.has_point(self_pos)
				or perception.sight.vision.can_see(self_pos, facing, centre, space, exclude)):
			known_rooms_now[room["key"]] = true
			learn_room(room)


## Learn the interactable pieces not yet known that the NPC sees: every one when `full`, else the
## slice this look takes (piece `i` when `(i + _slices) % LEARN_SLICES` is 0).
func _look_at_furniture(
	full: bool,
	self_pos: Vector2,
	facing: Vector2,
	space: PhysicsDirectSpaceState2D,
	exclude: Array,
) -> void:
	var known_objects := known_object_ids()
	for i in interactables.size():
		var obj: Variant = interactables[i]
		if not is_instance_valid(obj) or known_objects.has(obj.get_instance_id()):
			continue
		if not full and (i + _slices) % LEARN_SLICES != 0:
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


## The rooms the NPC knows (all of the house's `rooms` whose key it has learned), in their order.
func known_rooms() -> Array:
	var known := known_room_keys()
	return rooms.filter(func(r): return known.has(r["key"]))


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


## Scan the world once for objects that advertise interactions (static furniture) and stand in a
## room of the house (`house_rooms`; with none, anywhere), caching the refs. The house's furniture
## is all the NPC knows of: a neighbour tower's pieces are outside it (a district's other towers are
## scenery, not places to sit), and learning, remembering and offering them would cost every NPC a
## look at each one all match long. Positions are read live each tick; the set itself doesn't change
## during a run.
func _ensure_interactables(house_rooms: Array) -> void:
	if _scanned:
		return
	_scanned = true
	interactables.clear()
	var root: Node = perception._character.world_root()
	if root != null:
		_collect(root, house_rooms)


## Recursively gather descendants whose get_interactions() is non-empty into `interactables`, those
## standing in a room of `house_rooms` (all of them with no rooms).
func _collect(node: Node, house_rooms: Array) -> void:
	for child in node.get_children():
		if (child.has_method("get_interactions")
				and not (child.get_interactions() as Array).is_empty()
				and (house_rooms.is_empty()
					or not HouseRooms.at(child.global_position, house_rooms).is_empty())):
			interactables.append(child)
		_collect(child, house_rooms)
