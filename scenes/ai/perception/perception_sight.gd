extends RefCounted
## AI PERCEPTION sub-domain — the perception's sight, its part `sight`: the sight sense
## (agent_vision.gd, `vision`, which it holds) run over every other character — one sighting per
## character it sees, with its movement track, folded into the memory and the hostility rules — what
## is in view now (`visible_now`), whether the NPC is flash-blinded (`blind`, G15), the sight
## cadence (`SIGHT_EVERY_FRAMES`, offset per NPC by the perception node's own instance id), and the
## reads of sight from where the NPC stands: which points it sees, where its sight toward a point is
## first blocked. Built once with its `AgentPerception`, it holds it (a node, so no reference cycle)
## for the body, the memory and its sibling parts.

const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")
## Physics frames between two sight tests of a character that stays inside an NPC's view cone. The
## range and cone test runs every frame, so one that enters the cone is tested at once and one that
## leaves it is dropped at once; only the line of sight and the sighting written from it are renewed
## this often, offset per NPC and target so a squad does not test on the same frame. What the NPC
## holds of a character it sees is at most this many frames old.
const SIGHT_EVERY_FRAMES := 3

## The perception it belongs to.
var perception: Node
## The sight sense (FOV/range/LoS); see agent_vision.gd.
var vision: RefCounted
## Instance ids of characters visible on the latest observe() tick.
var visible_now := {}
## The same one tick earlier (what a character not due for a sight test keeps).
var _visible_before := {}
## Instance ids of characters in the view cone that have had a sight test since they entered it.
var _looked := {}
## Per-character movement track: id → { pos, vel, t, f } (last seen, game msec and game frame).
var _tracks := {}
## The NPC was flash-blinded on the latest observe() tick: it sees nothing new.
var blind := false


func _init(npc_perception: Node) -> void:
	perception = npc_perception


## Every other character (the player included): one sighting per character, superseded while it
## stays visible. Dead characters are skipped — corpses add no tactical information. A
## flash-blinded NPC (G15) sees nothing: no new sighting, and nothing is visible, so what it holds
## stays where it was last seen.
func see(rooms: Array) -> void:
	var self_pos: Vector2 = perception._character.global_position
	var facing: Vector2 = perception._character.facing
	var space: PhysicsDirectSpaceState2D = perception._character.get_world_2d().direct_space_state
	var exclude := [perception._character.get_rid()]
	var now := GameClock.msec()
	var frame := Engine.get_physics_frames()
	var swap := _visible_before
	_visible_before = visible_now
	visible_now = swap
	visible_now.clear()
	blind = perception._character.stun.is_blind()
	if blind:
		_looked.clear()
	for other in (others() if not blind else []):
		if not _due_for_sight(other, self_pos, facing, frame):
			continue
		if not vision.can_see_node(other, self_pos, facing, space, exclude):
			continue
		var sighting := _sighting_of(other, rooms, now)
		visible_now[sighting["id"]] = true
		perception._memory.remember(
			&"saw_character",
			sighting,
			maxf(perception.tuning.memory.contact_ttl, perception.tuning.memory.lead_ttl),
			str(sighting["id"]),
		)
		perception.contacts.hostility.classify(sighting, perception._memory)


## Whether character `other` gets a sight test on physics frame `frame`, keeping the view-cone
## bookkeeping: a dead one or one out of the cone is dropped (its next look is at once); one tested
## since it entered the cone is tested again every `SIGHT_EVERY_FRAMES` frames, offset per NPC and
## target, and until then stays what the last look saw.
func _due_for_sight(other: Node, self_pos: Vector2, facing: Vector2, frame: int) -> bool:
	var id: int = other.get_instance_id()
	if other.get("is_dead") == true:
		_looked.erase(id)
		return false
	if not vision.in_view(self_pos, facing, other.global_position):
		_looked.erase(id)  # Out of the cone: not seen, and its next look is at once.
		return false
	if _looked.has(id) and (frame + perception.get_instance_id() + id) % SIGHT_EVERY_FRAMES != 0:
		if _visible_before.has(id):
			visible_now[id] = true  # Not due: still what the last look saw.
		return false
	_looked[id] = true
	return true


## The sighting of character `other`, seen now (game msec `now`): where it is and its movement
## track, its facing, visible wounds, room, held item, reload and posture.
func _sighting_of(other: Node, rooms: Array, now: int) -> Dictionary:
	var id: int = other.get_instance_id()
	var pos: Vector2 = other.global_position
	var room := HouseRooms.at(pos, rooms)
	var item = other.inventory.current_item()
	var f = other.get("faction")
	return {
		"id": id,
		"node": other,
		"name": str(other.name),
		"faction": f if f != null else &"",
		"ally": perception.contacts.hostility.is_ally(f if f != null else &""),
		"pos": pos,
		"vel": _track(id, pos, now),
		"facing": other.get("facing") if other.get("facing") is Vector2 else Vector2.ZERO,
		"wound_dmg": other.damage_taken(),
		"inside": not room.is_empty(),
		"room_type": room.get("type", "") if not room.is_empty() else "",
		"item": item.display_name if item != null else "nothing",
		"reloading": other.ammo.is_reloading(),
		"posture": other.movement.posture(),
	}


## Update character `id`'s movement track with a sighting at `pos` (game msec `now`) and return its
## smoothed velocity, both measured on the game clock (`GameClock`). A sighting after a long gap
## restarts the track (no velocity across the gap). `tuning.context.track_smoothing` is the share of
## a new velocity taken per game frame, so a sighting that comes several frames after the last takes
## the share they add up to.
func _track(id: int, pos: Vector2, now: int) -> Vector2:
	var frame := GameClock.frame()
	var vel := Vector2.ZERO
	var track = _tracks.get(id)
	if track != null:
		var dt: float = (now - track["t"]) / 1000.0
		if dt > 0.0 and dt < 0.5:
			var steps: int = maxi(frame - int(track["f"]), 1)
			var smoothing: float = perception.tuning.context.track_smoothing
			var share := smoothing if steps == 1 else 1.0 - pow(1.0 - smoothing, steps)
			vel = (track["vel"] as Vector2).lerp((pos - track["pos"]) / dt, share)
		elif dt == 0.0:
			vel = track["vel"]
	_tracks[id] = { "pos": pos, "vel": vel, "t": now, "f": frame }
	return vel


## Every other character in the world (the group `characters`, interface 7) under the shared world
## root, excluding the NPC itself, in tree order. Used by see() to test each for visibility.
func others() -> Array:
	var root: Node = perception._character.world_root()
	if root == null:
		return []
	var out: Array = []
	for c: Node in perception._character.get_tree().get_nodes_in_group(&"characters"):
		if c != perception._character and root.is_ancestor_of(c):
			out.append(c)
	return out


## Of world `points`, the subset the NPC can SEE right now from where it stands — view cone + clear
## line of sight over low cover, the same sight rule used to spot characters (agent_vision.gd). The
## behaviour uses it to track which parts of a room a searcher has covered. Builds the sight query
## from the NPC's body; the NPC excludes itself.
func visible_points(points: Array) -> Array:
	if points.is_empty():
		return []
	var space: PhysicsDirectSpaceState2D = perception._character.get_world_2d().direct_space_state
	var exclude := [perception._character.get_rid()]
	var self_pos: Vector2 = perception._character.global_position
	var facing: Vector2 = perception._character.facing
	var seen: Array = []
	for p in points:
		if vision.can_see(self_pos, facing, p, space, exclude):
			seen.append(p)
	return seen


## Where the NPC's sight from where it stands toward world point `to` is first blocked — over low
## cover, the same rule that spots characters (agent_vision.gd) — or `to` itself when the line
## reaches it. The NPC excludes itself. What the vision overlay draws its visible area from; a pure
## read.
func sight_end(to: Vector2) -> Vector2:
	var space: PhysicsDirectSpaceState2D = perception._character.get_world_2d().direct_space_state
	var hit: Dictionary = vision.sight_hit(
		space,
		perception._character.global_position,
		to,
		[perception._character.get_rid()],
	)
	return hit["position"] if not hit.is_empty() else to
