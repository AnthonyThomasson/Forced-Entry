extends RefCounted
## AI PERCEPTION sub-domain — the perception's views, its part `views`: the doorway views and the
## walk that keeps out of them (agent_door_views.gd, `views`, which it holds; E15, E18), read from
## where the NPC stands — the first doorway or view a walk comes to, which the entry guard secures,
## the views avoided, the route walked, whether the avoid map its routes are measured on is baked —
## and the walk rules it pushes into them: which rooms count as clear for passing, on an ordered
## stack's walk too (`ordered`, `docs/leadership.md` D4, D11, D20). Built once with its
## `AgentPerception`, it holds it (a node, so no reference cycle) for the body, the memory and its
## sibling parts.

const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
## The longest (game ms, `GameClock`) a decision waits for the avoid map its routes are measured on
## (`routes_ready`).
const WARM_CAP_MS := 3000

## The perception it belongs to.
var perception: Node
## The doorway views and the walk that keeps out of them; see agent_door_views.gd.
var views: RefCounted
## Whether the NPC is walking an ordered stack's way to its door (`docs/leadership.md` LD9), set
## each tick by the behaviour: that walk keeps out of the doorway views whatever
## `tuning.entry.enabled` says (D4), and for an NPC that does not clear rooms by entry
## (`tuning.entry.enabled` off) a room it has stood in lately and seen no hostile in counts as clear
## for passing (`_seen_empty`, D11); the room its stack holds always does (`_stack_room`).
var ordered := false:
	set(value):
		if value != ordered:
			ordered = value
			sync_walks()
## When (`GameClock.msec()`) the decision began waiting for the avoid map; -1: not waiting.
var _warming_since := -1
## `_stack_room()` this frame...
var _held_room := ""
## ... worked out on this physics frame.
var _held_room_frame := -1


func _init(npc_perception: Node) -> void:
	perception = npc_perception


## Push the walk rules into the doorway views: walks keep out of the doorway views where the entry
## guard runs (`tuning.entry_guard.enabled`, with `tuning.entry.enabled` or on an ordered stack's
## walk, D4), and a room counts as clear for passing when it was cleared lately (`_is_pass_clear`)
## or, on an ordered walk, when its stack holds it (`_stack_room`) or, for an NPC that does not
## clear rooms by entry, it has seen it empty (`_seen_empty`, D11).
func sync_walks() -> void:
	if views == null:
		return
	views.avoid_views = (perception.tuning.entry_guard.enabled
			and (perception.tuning.entry.enabled or ordered))
	# Its way round the room it stacks on is taken however long (D4).
	views.ordered_approach = ordered
	views.pass_clear = ((_passable if not perception.tuning.entry.enabled else _pass_clear_ordered)
			if ordered
			else _is_pass_clear)


## The first doorway on the walk `path` (from waypoint `from_idx`, `max_dist` px of it at most) that
## leads into a room that is not cleared (nor, on an ordered walk, the room its stack holds, or for
## an NPC that does not clear rooms by entry seen empty: D11), as `{ opening, into, dist }`,
## or {} (see agent_door_views.gd `threshold_ahead`). A held stack's member in a doorway of the room
## it keeps out of (the confinement's `keep_out`, D31) is not in that room yet.
func threshold_ahead(path: PackedVector2Array, from_idx: int, max_dist: float) -> Dictionary:
	var clear: Callable = perception.entry.is_cleared
	if ordered:
		# The room its stack holds is passed through (D20), and, for an NPC that does not clear
		# rooms by entry, a room seen empty (D11).
		clear = func(key: String) -> bool:
			return (
				perception.entry.is_cleared(key)
				or key == _stack_room()
				or (not perception.tuning.entry.enabled and _seen_empty(key))
			)
	views.kept_out = perception.confinement.keep_out
	return views.threshold_ahead(
		path, from_idx, perception._character.global_position, clear, max_dist
	)


## The first doorway view the walk `path` goes into without entering the room behind it, as
## `{ opening, into, dist }`, or {} (see agent_door_views.gd `passing_ahead`): a doorway to be
## secured before the NPC crosses its view (E15, E18).
func passing_ahead(path: PackedVector2Array, from_idx: int, max_dist: float) -> Dictionary:
	return views.passing_ahead(
		path,
		from_idx,
		perception._character.global_position,
		max_dist,
		perception._character.get_world_2d(),
	)


## Whether room `key` counts as safe to walk past: cleared within
## `tuning.entry_guard.pass_clear_time` (a room cleared longer ago is cleared for the entry,
## `entry.is_cleared`, but a doorway into it is not safe to walk past again).
func _is_pass_clear(key: String) -> bool:
	return (perception._memory.age_of(&"cleared_room", "key", key)
			<= perception.tuning.entry_guard.pass_clear_time)


## Whether the NPC has stood in room `key` within `tuning.entry_guard.pass_clear_time` and has seen
## no hostile in it since (the latest sighting of each hostile it knows of, within that time, lies
## elsewhere): a room seen empty (`docs/leadership.md` D11). A room only glimpsed through its
## doorway was not stood in, so it is not.
func _seen_empty(key: String) -> bool:
	if (perception._memory.age_of(&"visited_room", "key", key)
			> perception.tuning.entry_guard.pass_clear_time):
		return false
	for c in perception.contacts.sightings(
			null, perception.tuning.entry_guard.pass_clear_time, -1.0, true
	):
		if HouseRooms.key_at(c["pos"], perception.house.rooms) == key:
			return false
	return true


## Whether room `key` counts as clear for passing on an ordered walk of an NPC that does not clear
## rooms by entry (D11): cleared lately, seen empty, or held by its stack (`_stack_room`).
func _passable(key: String) -> bool:
	return _pass_clear_ordered(key) or _seen_empty(key)


## Whether room `key` counts as clear for passing on an ordered stack's walk: cleared lately, or the
## room its stack holds (`_stack_room`).
func _pass_clear_ordered(key: String) -> bool:
	return _is_pass_clear(key) or key == _stack_room()


## The room an ordered stack holds (`docs/leadership.md` D20): on the walk of a member to the stack
## its live order names (`ordered`), the room that stack stands in once a member under the same
## order holds its slot there (its claim radioed `ready`, or `bang`): that room counts as cleared
## for passing, so the walk is not sent into it by entry. "" for none (outside the house, no slot
## held yet, or no ordered walk). Worked out once a physics frame.
func _stack_room() -> String:
	var frame := Engine.get_physics_frames()
	if frame == _held_room_frame:
		return _held_room
	_held_room_frame = frame
	_held_room = ""
	var held: Dictionary = perception.orders.current()
	if not ordered or str(held.get("kind", "")) != "stack":
		return _held_room
	var opening := str(held.get("opening", ""))
	for m in perception.entry.stack(opening).team:
		if m["order_id"] == str(held.get("id", "")) and StackClaim.in_slot(m["step"]):
			_held_room = str(
				perception.entry.geometry(opening, str(held.get("into", ""))).get("from", "")
			)
			break
	return _held_room


## Whether the routes a snapshot measures can be the ones the NPC will walk (see agent_door_views.gd
## `warm`): the avoid map for the doorway views from the room it stands in is baked. Asking starts
## the bake. After `WARM_CAP_MS` of waiting it is true anyway, so a decision never waits for good.
func routes_ready() -> bool:
	var world: World2D = perception._character.get_world_2d()
	if views.warm(
			perception._character.global_position, world.navigation_map, world.direct_space_state
	):
		_warming_since = -1
		return true
	var now := GameClock.msec()
	if _warming_since < 0:
		_warming_since = now
	return now - _warming_since > WARM_CAP_MS


## The doorway views the NPC's walks keep out of from where it stands, each `{ id, into, poly }`
## (see agent_door_views.gd `avoided`): what the entry plan overlay draws.
func avoided() -> Array:
	var world: World2D = perception._character.get_world_2d()
	return (views.views_from(
		perception._character.global_position, world.navigation_map, world.direct_space_state,
	)
			if views.avoid_views
			else [])


## The route the NPC walks from where it stands to `to` (see agent_door_views.gd `walk_route`): the
## plain one, or the one that keeps out of the views of the doorways into rooms not clear for
## passing when there is one within the cap. `entering` (`"<opening id>><room key>"`): the entry the
## walk is the approach of, which keeps out of that room and its doorway's view. `from` (INF: where
## the NPC stands) is where the walk sets out from, for a leg of a walk read ahead. `uncapped`: the
## way round that room is taken however long it is (a held stack's member, D31).
func walk_route(
		to: Vector2,
		entering := "",
		from := Vector2.INF,
		uncapped := false,
) -> Dictionary:
	var world: World2D = perception._character.get_world_2d()
	var at: Vector2 = perception._character.global_position if from == Vector2.INF else from
	var space := world.direct_space_state
	if uncapped:
		return views.held_route(at, to, world.navigation_map, space, entering)
	return views.walk_route(at, to, world.navigation_map, space, entering)


## Whether the route from where the NPC stands to `to` goes into room `key`: the plain route, or the
## one on navigation map `on` when given (a walk's steering map round bodies; see
## agent_door_views.gd `plain_enters`).
func walk_enters(to: Vector2, key: String, on := RID()) -> bool:
	var at: Vector2 = perception._character.global_position
	var map: RID = on if on.is_valid() else perception._character.get_world_2d().navigation_map
	return views.plain_enters(at, to, map, key)
