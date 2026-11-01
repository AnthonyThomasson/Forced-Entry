extends RefCounted

enum Phase {
	NONE,
	APPROACH,
	OPENING,
}

## AI BEHAVIOUR sub-domain — LOCOMOTION's door leaves, its part `leaves` (`docs/doors.md` DR14): a
## door on the stretch of the walk ahead that is not open wide enough to pass. Whatever primitive
## walks (`Locomotion.move_to`), the walker stops beside the door on its latch side, faces it, opens
## it fully (never a toggle: `character.use.doors.open_fully`, so a door another opened is never
## shut) and walks on, leaving it open. A door open wide enough, or knocked down, is no obstacle. A
## door that will not open wide enough (held by furniture, a body, the swing stopped short) is
## refused for a while and makes the walk a blocked one (`crowd.take_blocked`, the existing
## re-decide). Doors are found by the group `doors` and read through the door contract (interface
## 24), duck-typed, so the AI imports nothing of Objects. Built once with its Locomotion, it holds
## it (a node, so no reference cycle).

## How far (px) along the walk ahead a door is looked for.
const LOOKAHEAD := 90.0
## Room (px) beyond a body's width a gap must have for it to pass.
const PASS_MARGIN := 6.0
## How near (px) to the spot beside the latch the walker works it from: a walker beside the spot
## (another is on it) opens the door too.
const SPOT_REACH := 20.0
## A known body this near (px) to the spot, and nearer to it than the walker, is working the door:
## the walker waits `QUEUE_BACK` px further out from the wall, out of its way.
const TAKEN := 30.0
const QUEUE_BACK := 40.0
## Seconds a walker waits its turn at the door before giving up on it.
const QUEUE_CAP := 10.0
## Seconds a walk to the spot may take before the door is given up on.
const APPROACH_CAP := 4.0
## Seconds after a use that the door gets to open before the use is judged to have failed, and how
## long (s) the leaf standing still counts as stopped short.
const OPEN_WAIT := 1.2
const STILL_TIME := 0.25
## How many times the door is used before it is given up on (a body in the arc may clear).
const TRIES := 2
## Seconds a door given up on stays refused.
const REFUSE_TIME := 45.0
## A walk's other doorway counts as passed within this many px of its middle.
const VIA_REACH := 22.0
## Seconds between the blocked calls of a walk whose only way is through a refused door.
const REBLOCK_TIME := 1.5

## The Locomotion it belongs to.
var loco: Node
## The game time (s) until which a refused door (by instance id) is refused.
var refused: Dictionary = {}
## The perception's house part (`AgentPerception.house`: its `openings`), set by `Behavior.setup`:
## where the other ways into a room are.
var house: RefCounted
## Seconds until a walk with a refused door and no other way raises its blocked again.
var _reblock_in := 0.0
var _detour := Detour.new()
## The door being worked, the spot beside its latch the walker works it from, and how far along.
var _door: Node2D
var _spot := Vector2.INF
var _phase := Phase.NONE
var _clock := 0.0
var _used := 0
var _still := 0.0
var _last_angle := 0.0
## Seconds spent waiting behind another walker at the latch.
var _queued := 0.0
## The physics frame `work` last ran: a primitive that stopped walking leaves the door.
var _worked_frame := -10


func _init(locomotion: Node) -> void:
	loco = locomotion


## Work a door in the way of the walk, once a frame from `Locomotion.move_to`: true when this
## frame's steering is the door's (the walker goes to its latch side, or stands there using it),
## false when the walk goes on as it was.
func work(delta: float) -> bool:
	var frame := Engine.get_physics_frames()
	if frame - _worked_frame > 3:
		_reset()  # The walker stopped walking meanwhile (another primitive): the door is forgotten.
	_worked_frame = frame
	if _door != null:
		if not is_instance_valid(_door) or _door.is_down() or _passable(_door):
			_reset()
			return false
		if _phase == Phase.APPROACH and _in_the_way() != _door:
			_reset()  # A new walk that no longer crosses it.
			return false
		return _work_door(delta)
	var door := _in_the_way()
	if door == null:
		return false
	if _is_refused(door):
		return _stand_short(delta)
	_begin(door)
	return _work_door(delta)


## The destination the walk steers for: `dest`, or the middle of another doorway when the way to
## `dest` runs through a door given up on (`_is_refused`), until that doorway is passed. Another
## destination is worked out afresh. With no other way the walk keeps `dest` and `work` stands it
## short of the door, raising the blocked walk.
func redirect(dest: Vector2) -> Vector2:
	if not _any_refused():
		_detour.via = Vector2.INF
		_detour.planned = false
		return dest
	if _detour.planned and dest.distance_to(_detour.dest) <= loco.NEW_WALK:
		if _detour.via == Vector2.INF:
			return dest
		if (not _detour.passed
				and loco._character.global_position.distance_to(_detour.via) <= VIA_REACH):
			_detour.passed = true
		return dest if _detour.passed else _detour.via
	_detour.via = Vector2.INF
	_detour.dest = dest
	_detour.passed = false
	_detour.planned = true
	var here: Vector2 = loco._character.global_position
	var refused_doors := _refused_doors()
	if not _crosses_any(NavBuilder.route(loco._plan_map, here, dest), refused_doors):
		return dest
	var best := INF
	for opening: Dictionary in house.openings:
		var middle: Vector2 = opening["pos"]
		if _is_doorway_of(middle, refused_doors):
			continue
		var first := NavBuilder.route(loco._plan_map, here, middle)
		var rest := NavBuilder.route(loco._plan_map, middle, dest)
		if _crosses_any(first, refused_doors) or _crosses_any(rest, refused_doors):
			continue
		var length := NavBuilder.path_length(first) + NavBuilder.path_length(rest)
		if length < best:
			best = length
			_detour.via = middle
	return _detour.via if _detour.via != Vector2.INF else dest


## Face the door being used when the eyes are elsewhere, so that it is in reach ahead: run after the
## watch stage, which puts the eyes where it likes. A door already in reach is left to the eyes.
func face() -> void:
	if _door == null or _phase != Phase.OPENING:
		return
	var character: Node = loco._character
	if not character.use.doors.reaches(_door):
		character.movement.aim_point = _leaf_origin(_door)


## Whether a door is being worked now (the walk stands or goes to its latch side for it).
func working() -> bool:
	return _door != null


## Whether the walk is on its way to another doorway round a refused door, not yet through it.
func detouring() -> bool:
	return _detour.via != Vector2.INF and not _detour.passed


## Whether a standing door that is not open all the way across its doorway (`gap()` below its
## `width`: the leaf is turned less than 60 degrees from shut) and not see-through (a glass-panel
## door's surface says `transparent`) stands in the doorway whose middle is `middle`: the view
## through that doorway is blocked by the leaf.
func shuts_view_at(middle: Vector2) -> bool:
	for door: Node2D in loco._character.get_tree().get_nodes_in_group(&"doors"):
		if (not door.is_down()
				and door.gap() < float(door.width)
				and _is_doorway_of(middle, [door])
				and not bool(door.get_surface().get("transparent", false))):
			return true
	return false


## Whether `door` is open wide enough for the walker's body to pass.
func _passable(door: Node2D) -> bool:
	return door.gap() >= 2.0 * float(loco._character.radius) + PASS_MARGIN


## The nearest door along the walk's next `LOOKAHEAD` px whose doorway the walk crosses and which is
## not open wide enough, or null. Read off the agent's path as the walk was just steered.
func _in_the_way() -> Node2D:
	var path: PackedVector2Array = loco._agent.get_current_navigation_path()
	var index: int = loco._agent.get_current_navigation_path_index()
	var here: Vector2 = loco._character.global_position
	var doors := _standing_doors()
	if doors.is_empty():
		return null
	var from := here
	var walked := 0.0
	for i in range(index, path.size()):
		var to := path[i]
		for door: Node2D in doors:
			if _crosses(from, to, door):
				return door
		walked += from.distance_to(to)
		if walked > LOOKAHEAD:
			break
		from = to
	return null


## Take up `door`: the spot beside its latch on the side the walker stands on.
func _begin(door: Node2D) -> void:
	_door = door
	_spot = door.latch_side_spot(loco._character.global_position)
	_phase = Phase.APPROACH
	_clock = 0.0
	_used = 0
	_still = 0.0
	_queued = 0.0


## Forget the door being worked.
func _reset() -> void:
	_door = null
	_spot = Vector2.INF
	_phase = Phase.NONE


## One frame of working `_door`: the walk to its latch side, then standing there using it until it
## is open wide enough, and the giving up.
func _work_door(delta: float) -> bool:
	var character: Node = loco._character
	var here: Vector2 = character.global_position
	_clock += delta
	if _phase == Phase.APPROACH:
		if _taken(here):
			_queued += delta
			return _queue(here) if _queued <= QUEUE_CAP else _give_up()
		_queued = 0.0
		if here.distance_to(_spot) > SPOT_REACH:
			if _clock > APPROACH_CAP:
				return _give_up()
			character.movement.move_input = (_spot - here).normalized()
			character.movement.aim_point = _leaf_origin(_door)
			loco.give_way.keep_off()
			return true
		_phase = Phase.OPENING
		_clock = 0.0
	character.movement.move_input = Vector2.ZERO
	character.movement.aim_point = _leaf_origin(_door)
	return _open(delta)


## Whether a known body nearer to the spot than the walker stands on it: another is working the
## door.
func _taken(here: Vector2) -> bool:
	for body: Dictionary in loco.crowd.bodies:
		var at: Vector2 = body["pos"]
		if at.distance_to(_spot) < TAKEN and at.distance_to(_spot) < here.distance_to(_spot) - 2.0:
			return true
	return false


## Wait for the one at the latch, `QUEUE_BACK` px out from the wall behind its spot, until the door
## is open (`work` then lets the walk go on).
func _queue(here: Vector2) -> bool:
	var character: Node = loco._character
	var side := signf((_spot - _leaf_origin(_door)).dot(_door.swing_into))
	var out: Vector2 = _door.swing_into * side
	var waiting := _spot + out * QUEUE_BACK
	character.movement.move_input = (
		(waiting - here).normalized() if here.distance_to(waiting) > 6.0 else Vector2.ZERO
	)
	character.movement.aim_point = _leaf_origin(_door)
	return true


## Standing at the latch: use the door, wait for it to open, use it again if it stopped short, and
## give it up when it will not open wide enough.
func _open(delta: float) -> bool:
	var character: Node = loco._character
	var angle: float = _door.angle()
	if _used == 0 or (_clock > OPEN_WAIT or _still > STILL_TIME):
		if _used >= TRIES:
			return _give_up()
		if character.use.doors.open_fully(_door):
			_used += 1
			_clock = 0.0
			_still = 0.0
			_last_angle = angle
		elif _clock > OPEN_WAIT:
			return _give_up()
		return true
	_still = _still + delta if _clock > STILL_TIME and is_equal_approx(angle, _last_angle) else 0.0
	_last_angle = angle
	return true


## The door will not open wide enough: refuse it for a while and make the walk a blocked one.
func _give_up() -> bool:
	refused[_door.get_instance_id()] = GameClock.seconds() + REFUSE_TIME
	loco.crowd.blocked = true
	_reset()
	return false


## A walk whose way runs through the refused `door` and has no other: it stands short of the door
## and tells the caller, now and every `REBLOCK_TIME` s, that its way is blocked.
func _stand_short(delta: float) -> bool:
	_reblock_in -= delta
	if _reblock_in <= 0.0:
		_reblock_in = REBLOCK_TIME
		loco.crowd.blocked = true
	loco._character.movement.move_input = Vector2.ZERO
	return true


## The doors given up on that still stand and are still refused.
func _refused_doors() -> Array:
	return _standing_doors().filter(func(door: Node2D) -> bool: return _is_refused(door))


## Whether any door is refused now.
func _any_refused() -> bool:
	var now := GameClock.seconds()
	for id in refused.keys():
		if float(refused[id]) <= now:
			refused.erase(id)
	return not refused.is_empty()


## Whether `point` is the middle of the doorway of one of `doors`.
func _is_doorway_of(point: Vector2, doors: Array) -> bool:
	for door: Node2D in doors:
		if point.distance_to(_leaf_origin(door)) < float(door.width) * 0.5 + 4.0:
			return true
	return false


## The middle of `door`'s doorway (its leaf as it stands shut).
func _leaf_origin(door: Node2D) -> Vector2:
	return door.leaf_pose(0.0).origin


## Whether the segment `a` to `b` crosses `door`'s doorway, jamb to jamb.
func _crosses(a: Vector2, b: Vector2, door: Node2D) -> bool:
	var pose: Transform2D = door.leaf_pose(0.0)
	var half: Vector2 = pose.x * float(door.width) * 0.5
	return Geometry2D.segment_intersects_segment(
		a,
		b,
		pose.origin - half,
		pose.origin + half,
	) != null


## The doors that stand and are not open wide enough.
func _standing_doors() -> Array:
	var found: Array = []
	for door: Node2D in loco._character.get_tree().get_nodes_in_group(&"doors"):
		if not door.is_down() and not _passable(door):
			found.append(door)
	return found


## Whether `path` crosses the doorway of any of `doors`.
func _crosses_any(path: PackedVector2Array, doors: Array) -> bool:
	for i in range(1, path.size()):
		for door: Node2D in doors:
			if _crosses(path[i - 1], path[i], door):
				return true
	return false


## Whether `door` was given up on and is still refused.
func _is_refused(door: Node2D) -> bool:
	var until: float = refused.get(door.get_instance_id(), -1.0)
	return until > GameClock.seconds()


## The doorway a walk goes by instead of a refused door's (`redirect`): the middle of that doorway
## (`via`, `Vector2.INF` for none), the destination it was worked out for (`dest`), whether it has
## been worked out (`planned`) and whether the walk is through it (`passed`).
class Detour:
	extends RefCounted
	var via := Vector2.INF
	var dest := Vector2.INF
	var planned := false
	var passed := false
