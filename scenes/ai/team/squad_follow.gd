extends RefCounted
## AI domain · TEAM — where a squad's followers stand (`docs/leadership.md` LD21, D28): the leader's
## trail and every follower's spot on it, on a ring round a still leader, and out of the leader's
## way. Owned by its `Squad` (`squad.gd`), which hands `follow_spot` here and keeps the published
## reads, read off it; the follow tunables (`gap`, `step`, `ring`, `still_time`, `retarget`,
## `arrive`) are `SquadFollowConfig`'s (`squad_follow_config.gd`). It reads the squad only through
## its public reads (`leader()`, `members()`, `alive`, `follows`), the leader's `global_position`
## and `facing` and its members' `global_position` (the Character API, interface 7), and lays the
## spots on the navigation map and physics space of the squad's own viewport's `World2D`
## (`NavBuilder.snap`, interface 9; a wall ray for the leader's sight).
##
## **The trail.** A point each `TRAIL_STEP` the leader moves (`track`, every physics frame), kept as
## long as the file needs, and the rooms the leader stood in since it led (`_visited`); `reset`
## starts it afresh at a new leader. **The spots** (`spot`) are laid at most once a physics frame
## and only when the leader moved, turned or stopped or the followers changed: on the trail while
## the leader moves (`SquadFollowConfig.gap` back, then `step` further for each next follower), a
## slot on a ring behind the way it came once it has stood `still_time` (`_ring_slots`), then moved
## out of the lane ahead of the leader's facing (`_clear_of_way`).

const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const Squad := preload("res://scenes/ai/team/squad.gd")
## How far (px) the leader moves before its trail takes a new point.
const TRAIL_STEP := 15.0
## How far (px) a ring slot or a spot beside the leader's way may lie from the navigation map and
## still be taken (one in a wall or under furniture is not).
const SLOT_SNAP := 20.0
## How many rings round a still leader are laid before the rest of the followers keep to the trail.
const RINGS := 3
## The leader's way: the lane ahead of its facing this far (px) either side of its line, which a
## body standing in blocks (two bodies touch at 28 px).
const WAY_CLEARANCE := 32.0

## The squad whose followers these are: its reads.
var _squad: Squad = null
## The house's doorways (`WorldGen.get_openings`): no spot lies in one.
var _openings: Array = []
## The house's rooms (`WorldGen.get_rooms`): the rooms the leader has stood in.
var _rooms: Array = []
## The leader's trail, oldest point first: where it was each `TRAIL_STEP` it moved.
var _trail := PackedVector2Array()
## The leader the trail is of.
var _trail_of: Node = null
## When (game s, `GameClock`) the leader last moved a `TRAIL_STEP` (-INF: not since it led).
var _moved_at := -INF
## Member instance id -> its follow spot, as laid on `_spots_at`.
var _spots := {}
## The physics frame `_spots` was laid on (-1: lay them again on the next read).
var _spots_at := -1
## The leader's position the spots were laid for (they are laid again once it moved).
var _spots_from := Vector2.INF
## The leader's heading the spots were laid for (they are laid again once it turned).
var _spots_facing := Vector2.ZERO
## Whether the leader stood still when the spots were laid (they are laid again once it stops or
## sets off).
var _spots_still := false
## The followers the spots were laid for (they are laid again once these change).
var _spots_for: Array = []
## The rooms (keys, "" outside) the leader has stood in since it led: the only ones a follower is
## sent into out of its way (`_clear_of_way`).
var _visited := {}
## Member instance id -> `{ spot, from, way }`: the spot beside the leader's way it was sent to,
## and where the leader stood (`from`) and which way it faced (`way`) then (`_clear_of_way`).
var _aside := {}
## The sight test a ring slot passes (the leader sees it: no wall between).
var _vision: RefCounted = AgentVision.new()


## The follow geometry of `squad`, whose house is `openings` and `rooms`.
func _init(squad: Squad, openings: Array, rooms: Array) -> void:
	_squad = squad
	_openings = openings
	_rooms = rooms


## The living followers, in roster order: each one's place in the file and on the ring.
func followers() -> Array:
	return _squad.members().filter(func(m): return _squad.follows(m))


## The leader's trail, oldest point first.
func trail() -> PackedVector2Array:
	return _trail


## Lay the spots again on the next read (a follower died, the leader changed).
func invalidate() -> void:
	_spots_at = -1


## Start the trail afresh at the squad's leader (none: empty), standing still from the start.
func reset() -> void:
	var lead: Node = _squad.leader()
	_trail = PackedVector2Array()
	_trail_of = lead
	_moved_at = -INF
	_spots_at = -1
	_spots_from = Vector2.INF
	_aside = {}
	_visited = {}
	if lead is Node2D:
		_trail.append((lead as Node2D).global_position)
		_visited[_room_at((lead as Node2D).global_position)] = true


## Take a new trail point once the leader has moved a `TRAIL_STEP` from the last, and keep the
## trail only as long as the file needs.
func track() -> void:
	var lead: Node = _squad.leader()
	if lead != _trail_of:
		reset()
	if not lead is Node2D or _trail.is_empty():
		return
	var here: Vector2 = (lead as Node2D).global_position
	if here.distance_to(_trail[_trail.size() - 1]) < TRAIL_STEP:
		return
	_trail.append(here)
	_visited[_room_at(here)] = true
	_moved_at = GameClock.seconds()
	var keep: float = (
		SquadFollowConfig.gap
			+ SquadFollowConfig.step * maxf(_squad.members().size(), 1.0)
			+ TRAIL_STEP * 2.0
	)
	var length := 0.0
	for i in range(_trail.size() - 1, 0, -1):
		length += _trail[i].distance_to(_trail[i - 1])
		if length > keep:
			_trail = _trail.slice(i - 1)
			return


## Where follower `member` keeps to now (`Vector2.INF` when the squad lays it none): on the
## leader's trail while the leader moves, a slot on the ring behind it once it stands still, and out
## of the leader's way (`_clear_of_way`).
func spot(member: Node) -> Vector2:
	_lay_spots()
	var at: Vector2 = _spots.get(member.get_instance_id(), Vector2.INF)
	if at == Vector2.INF or not member is Node2D:
		return at
	return _clear_of_way(member, at)


## Lay every follower's spot, at most once a physics frame and only when the leader moved, turned
## or stopped, or the followers changed since they were last laid. Once the leader stands still, a
## file spot (one the ring has no slot for) that falls in a doorway steps back along the trail until
## it is clear of it (`_in_doorway`), and the followers behind it with it: one standing in a doorway
## would leave the rest only the way round. A file on the move walks through. A follower whose
## place in the file lies past the trail's oldest point (the leader has not walked that far since it
## led) lies on along the trail's last stretch, unless that lies further from the leader than the
## follower stands: then it keeps where it stands until the leader has drawn further off, since
## sent on past where the leader set off the file would walk away from it and across each other.
func _lay_spots() -> void:
	var frame := GameClock.frame()
	if frame == _spots_at:
		return
	_spots_at = frame
	track()
	var lead := _squad.leader() as Node2D
	if lead == null:
		_spots = {}
		return
	var here := lead.global_position
	var facing := _heading()
	var still: bool = GameClock.seconds() - _moved_at >= SquadFollowConfig.still_time
	var file := followers()
	if not _moved_on(here, facing, still, file):
		return
	_spots = {}
	if not _squad.is_inside_tree():
		return
	var world: World2D = _squad.get_viewport().find_world_2d()
	var ring: Array = _ring_slots(here, facing, file.size(), world) if still else []
	var pushed := 0.0
	for i in file.size():
		var at: Vector2 = ring[i] if i < ring.size() else Vector2.INF
		if at == Vector2.INF:
			pushed = _pushed_clear(i, pushed, still, file.size())
			at = _trail_spot(
				world,
				here,
				file[i],
				SquadFollowConfig.gap + SquadFollowConfig.step * i + pushed,
			)
		_spots[file[i].get_instance_id()] = at


## Whether the spots are laid again for the leader at `here` facing `facing` (`still` or not) and
## the followers `file`: the leader moved, turned or stopped, or the followers changed, since they
## were last laid. When so, what they are laid for now is kept.
func _moved_on(here: Vector2, facing: Vector2, still: bool, file: Array) -> bool:
	if (here.distance_to(_spots_from) <= 1.0
			and absf(facing.angle_to(_spots_facing)) <= 0.02
			and still == _spots_still
			and file == _spots_for):
		return false
	_spots_from = here
	_spots_facing = facing
	_spots_still = still
	_spots_for = file
	return true


## How far (px, from `pushed`, how far the file ahead of it was stepped back) the file spot of
## follower `i` of `count` steps back along the trail: while the leader stands `still`, until the
## spot is out of every doorway, at most `SquadFollowConfig.step` x `count`.
func _pushed_clear(i: int, pushed: float, still: bool, count: int) -> float:
	var gap: float = SquadFollowConfig.gap
	var step: float = SquadFollowConfig.step
	var back := _trail_point(gap + step * i + pushed)
	while still and _in_doorway(back) and pushed < step * count:
		pushed += TRAIL_STEP
		back = _trail_point(gap + step * i + pushed)
	return pushed


## The file spot `dist` px back along the trail from the leader at `here` for `member`, on the
## navigation map of `world`; where `member` stands when that lies past the trail's oldest point
## and further from the leader than the member is.
func _trail_spot(world: World2D, here: Vector2, member: Node2D, dist: float) -> Vector2:
	var back := _trail_point(dist)
	var stands := member.global_position
	if dist > _trail_length() and here.distance_to(back) > here.distance_to(stands):
		return stands
	return NavBuilder.snap(world.navigation_map, back)


## `at`, or, when it or `member` is in the leader's way (`_in_way`), a spot beside that way, on the
## side the member stands on (so two never cross it to swap sides) unless another member stands
## there: a follower never stands where its leader is heading, so a leader turning back the way it
## came walks through its file (D28). With no room beside the way (a corridor) it is a spot further
## ahead along it, so the follower backs off in front of the leader until there is; each in the
## leader's sight (`_open_at`) and in a room the leader has been in (`_visited`), so a follower
## never goes first into a room its leader has not entered. A member sent aside stays there while
## that keeps it out of the way, until the leader has moved a ring on or turned its way back (or
## another member stands there): the way is read off the leader's facing, which swings while it
## looks round (slicing a pie), and a follower sent to and fro would never come to rest out of it.
func _clear_of_way(member: Node, at: Vector2) -> Vector2:
	var lead: Node = _squad.leader()
	var facing = lead.get("facing")
	if not facing is Vector2 or facing == Vector2.ZERO or not _squad.is_inside_tree():
		return at
	var p: Vector2 = (member as Node2D).global_position
	var here := (lead as Node2D).global_position
	var ahead := (facing as Vector2).normalized()
	var kept := _kept_aside(member, p, here, ahead)
	if kept != Vector2.INF:
		return kept
	_aside.erase(member.get_instance_id())
	var across := ahead.orthogonal()
	var spot_in := _in_way(at - here, ahead, across)
	if not spot_in and not _in_way(p - here, ahead, across):
		return at
	var along := clampf(
		((at if spot_in else p) - here).dot(ahead),
		0.0,
		SquadFollowConfig.ring + SquadFollowConfig.step,
	)
	var aside := _beside_way(member, here, ahead, along, _side_of_way(p, at, here, across))
	if aside == Vector2.INF:
		aside = _further_on(member, here, ahead)
	return aside if aside != Vector2.INF else at


## The side of the leader's way (at `here`, `across` it) the member standing at `p` is on, 1 / -1:
## else the side its spot `at` is on, else 1.
static func _side_of_way(p: Vector2, at: Vector2, here: Vector2, across: Vector2) -> float:
	var side := signf((p - here).dot(across))
	if side == 0.0:
		side = signf((at - here).dot(across)) if (at - here).dot(across) != 0.0 else 1.0
	return side


## The spot `member` (standing at `p`) was sent aside to, while that still keeps it out of the way
## of the leader at `here` heading `ahead`: the leader has not moved a ring on nor turned its way
## back, and no other member stands there. Else `Vector2.INF`.
func _kept_aside(member: Node, p: Vector2, here: Vector2, ahead: Vector2) -> Vector2:
	var kept: Dictionary = _aside.get(member.get_instance_id(), {})
	if kept.is_empty():
		return Vector2.INF
	var across := ahead.orthogonal()
	var arrive: float = SquadFollowConfig.arrive
	if (here.distance_to(kept["from"]) < SquadFollowConfig.ring
			and ahead.dot(kept["way"]) > 0.0
			and not _in_way(kept["spot"] - here, ahead, across, WAY_CLEARANCE + arrive)
			and not _in_way(p - here, ahead, across)
			and not _taken(kept["spot"], member)):
		return kept["spot"]
	return Vector2.INF


## A spot beside the way of the leader at `here` heading `ahead`, `along` px ahead of it, on `side`
## of the way (1 / -1 across it) and else on the other, far enough off it that a follower arriving
## short of it, or re-aimed late, stands clear; kept as `member`'s spot aside. `Vector2.INF` when
## neither side has one (open, in a room the leader has been in, not taken).
func _beside_way(member: Node, here: Vector2, ahead: Vector2, along: float, side: float) -> Vector2:
	var world: World2D = _squad.get_viewport().find_world_2d()
	var across := ahead.orthogonal()
	var arrive: float = SquadFollowConfig.arrive
	var off: float = WAY_CLEARANCE + arrive + SquadFollowConfig.retarget
	for s in [side, -side]:
		var beside := _open_at(world, here, here + ahead * along + across * s * off)
		if (beside != Vector2.INF
				and _visited.has(_room_at(beside))
				and absf((beside - here).dot(across)) >= WAY_CLEARANCE + arrive
				and not _taken(beside, member)):
			_aside[member.get_instance_id()] = { "spot": beside, "from": here, "way": ahead }
			return beside
	return Vector2.INF


## A spot past the way of the leader at `here` heading `ahead`, a step further at a time (one in a
## doorway is no spot), kept as `member`'s spot aside; `Vector2.INF` when there is none.
func _further_on(member: Node, here: Vector2, ahead: Vector2) -> Vector2:
	var world: World2D = _squad.get_viewport().find_world_2d()
	var ring: float = SquadFollowConfig.ring
	var step: float = SquadFollowConfig.step
	for k in range(2, 5):
		var further := _open_at(world, here, here + ahead * (ring + step * k))
		if further != Vector2.INF and _visited.has(_room_at(further)):
			_aside[member.get_instance_id()] = { "spot": further, "from": here, "way": ahead }
			return further
	return Vector2.INF


## `want` on the navigation map of `world` (within `SLOT_SNAP`), in sight of the leader at `here`
## (no wall between) and out of every doorway, or `Vector2.INF`: a spot in a wall, under furniture,
## in another room or in a doorway is not one a follower is sent to.
func _open_at(world: World2D, here: Vector2, want: Vector2) -> Vector2:
	var at := NavBuilder.snap(world.navigation_map, want)
	if (at.distance_to(want) > SLOT_SNAP
			or _in_doorway(at)
			or not _vision.wall_hit(world.direct_space_state, here, at).is_empty()):
		return Vector2.INF
	return at


## The key of the house room `p` lies in ("" outside).
func _room_at(p: Vector2) -> String:
	for r: Dictionary in _rooms:
		if (r["rect"] as Rect2).has_point(p):
			return String(r["key"])
	return ""


## Whether `p` lies in one of the house's doorways: within half its width (`WAY_CLEARANCE` at
## least) of its middle, where a body would stand in the way through.
func _in_doorway(p: Vector2) -> bool:
	for o: Dictionary in _openings:
		var half := maxf(float(o.get("width", 0.0)) / 2.0, WAY_CLEARANCE)
		if p.distance_to(o["pos"]) < half:
			return true
	return false


## Whether another living member than `member` (the leader included) stands within
## `WAY_CLEARANCE` of `p`.
func _taken(p: Vector2, member: Node) -> bool:
	for m in _squad.members():
		if (m != member and _squad.alive(m)
				and (m as Node2D).global_position.distance_to(p) < WAY_CLEARANCE):
			return true
	return false


## Whether a point `rel` from the leader lies in its way: ahead of it, within a ring and a step, and
## within `clearance` of its line (`ahead`, `across` its facing and the perpendicular).
func _in_way(
	rel: Vector2,
	ahead: Vector2,
	across: Vector2,
	clearance := WAY_CLEARANCE,
) -> bool:
	var d := rel.dot(ahead)
	return (
		d > 0.0
			and d <= SquadFollowConfig.ring + SquadFollowConfig.step
			and absf(rel.dot(across)) < clearance
	)


## The way the leader faced as it came to a halt: along the last stretch of its trail, or, when it
## has not moved since it led, its facing. A still leader looking round its doors does not swing
## its ring round it.
func _heading() -> Vector2:
	var n := _trail.size()
	if n >= 2 and _trail[n - 1] != _trail[n - 2]:
		return (_trail[n - 1] - _trail[n - 2]).normalized()
	var facing = _squad.leader().get("facing")
	return (facing as Vector2).normalized() if facing is Vector2 else Vector2.RIGHT


## The point `back` px behind the leader along its trail; past the trail's oldest point, on along
## its last stretch (straight behind the leader when it has none).
func _trail_point(back: float) -> Vector2:
	var from: Vector2 = (_squad.leader() as Node2D).global_position
	var left := back
	var dir := Vector2.ZERO
	for i in range(_trail.size() - 1, -1, -1):
		var p := _trail[i]
		var seg := from.distance_to(p)
		if seg <= 0.0:
			continue
		dir = (p - from) / seg
		if seg >= left:
			return from + dir * left
		left -= seg
		from = p
	if dir == Vector2.ZERO:
		dir = -_heading()
	return from + dir * left


## How far (px) the leader's trail reaches back from where it stands to its oldest point.
func _trail_length() -> float:
	var from: Vector2 = (_squad.leader() as Node2D).global_position
	var length := 0.0
	for i in range(_trail.size() - 1, -1, -1):
		length += from.distance_to(_trail[i])
		from = _trail[i]
	return length


## Up to `count` slots round a still leader at `here` facing `facing`: on the ring behind it, the
## slots `SquadFollowConfig.step` apart either side of straight behind it and all less than a right
## angle off it, then on wider rings; each on the navigation map (within `SLOT_SNAP`) and in the
## leader's sight.
func _ring_slots(here: Vector2, facing: Vector2, count: int, world: World2D) -> Array:
	var out: Array = []
	var back := -facing.normalized() if facing != Vector2.ZERO else Vector2.LEFT
	for r in RINGS:
		var radius: float = SquadFollowConfig.ring + SquadFollowConfig.step * r
		out.append_array(_ring_of(world, here, back, radius, count - out.size()))
		if out.size() >= count:
			return out
	return out


## Up to `need` slots (at least one when there is any) on the ring `radius` px behind a still leader
## at `here` (`back` the way behind it): `SquadFollowConfig.step` apart either side of straight
## behind it, each less than a right angle off it, open (`_open_at`).
func _ring_of(world: World2D, here: Vector2, back: Vector2, radius: float, need: int) -> Array:
	var out: Array = []
	var step: float = SquadFollowConfig.step / radius
	var j := 0
	while (j + 0.5) * step < PI / 2.0:
		for side in [1.0, -1.0]:
			var slot := _open_at(world, here, here + back.rotated(side * (j + 0.5) * step) * radius)
			if slot != Vector2.INF:
				out.append(slot)
				if out.size() >= need:
					return out
		j += 1
	return out
