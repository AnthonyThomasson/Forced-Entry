extends RefCounted
## AI BEHAVIOUR sub-domain — LOCOMOTION's crowd, its part `crowd`: the characters a walk accounts
## for (`bodies`: the ones the NPC KNOWS of) and the ones at rest on it. A body at rest on the walk
## is gone round, however far round, by the navigation domain's steering map, which has the
## characters at rest carved out too (`goes_round`); when that map has no way round (the body seals
## the only way, or has only just stopped and is not carved yet) or the body stands on the
## destination, the walk is held short of it, waits, and re-plans (`check_held`): a free spot near a
## taken destination, else the caller is told the way is blocked (`take_blocked`). Built once with
## its Locomotion, it holds it (a node, so no reference cycle) for the body, the walk under way and
## its way.

## How far (px) the steering map's route may end short of the point it was asked for before a body
## is taken to seal the way (see `goes_round`).
const BLOCKED_DISTANCE := 24.0
## Farthest (px) short of its goal a route round bodies at rest may end when the plain way on from
## there passes no body: a goal inside the margins the steering map carves round bodies (a stack
## slot between two taken ones) is reached by that last leg (`Locomotion._last_stretch`).
const LAST_LEG := 64.0
## Seconds a walk is held short before it re-plans (a free spot near a taken destination, else the
## caller is told the way is blocked: `take_blocked`), and between later re-plans while it is still
## held.
const WAIT := 0.75
const REPLAN_EVERY := 4.0
## A hold that begins again within `HOLD_GAP` s of game time (`GameClock`, LD1: a pause is no gap)
## of the last one ending, the NPC within `Locomotion.HOLD_MOVED` px of where that one began, is the
## same hold going on (its walk aimed again, a free spot tried, a frame the body read as moving):
## its clocks carry on (`begin_hold`).
const HOLD_GAP := 0.5
## A held walk re-plans only once the steering map shows the body it is held by (`_carved`: a body
## carved there has its centre at least this far (px) off the map), or this many s past its re-plan
## time whatever the map shows.
const CARVED_GAP := 16.0
const CARVE_WAIT := 2.0

## The Locomotion it belongs to.
var loco: Node
## The characters the NPC knows of, set each tick by `Behavior` from the perception's contacts
## (`AgentPerception.contacts`: seen within its contact memory, each with `id`, `pos`, `vel`,
## `facing` and `visible`): the only bodies a walk accounts for.
var bodies: Array = []
## A character no walk treats as an obstacle (the one a melee closes on), by instance id; 0 = none.
var ignore_id: int = 0
## The map with the living characters carved out too, or invalid when the world has none.
var steering_map: RID
## The walk round bodies ended short of a goal no body stands on: it walks the rest plain, held by a
## body on it (`Locomotion._last_stretch`).
var last_leg := false
## The body at rest the walk is held short of (INF: not held).
var blocker := Vector2.INF
## Seconds the walk has been held short.
var held_for := 0.0
## The `GameClock` frame the walk last stopped being held.
var hold_left := -1
## Seconds until the held walk next looks for a way round, or one gone round off the avoid map looks
## back at it.
var recheck_in := 0.0
## The held walk re-planned and found no way: the caller should re-decide (`take_blocked`).
var blocked := false
## The physics frame the walk was last checked in (once a frame).
var checked_frame := -1
## `held_for` at which the held walk next re-plans.
var _replan_at := WAIT
## Where the NPC stood when the hold under way began (INF: none yet).
var _hold_at := Vector2.INF


func _init(locomotion: Node) -> void:
	loco = locomotion


## Whether the walk stands, or steps aside, for a body this frame: held short of one in its way (or
## on its destination), giving way to a walker, stopped against one it would otherwise walk into
## (`give_way.keep_off`), or done at the free spot beside a taken destination. A caller must not
## push on toward the destination itself then.
func holding() -> bool:
	return (loco._way == loco.Way.HELD
			or loco.give_way.kept_off
			or loco.give_way.yielding
			or loco._goal != loco._walk_dest)


## The known body the walk is held short of (`Way.HELD`), by instance id: 0 while the walk is not
## held, or when that body is no longer known. What an entry asks of a hold before it gives its slot
## up (`Entry.way_blocked`: a teammate still on its way only waits).
func held_by() -> int:
	if loco._way != loco.Way.HELD or blocker == Vector2.INF:
		return 0
	for b in bodies:
		if b["pos"] == blocker:
			return int(b.get("id", 0))
	return 0


## Where the body the walk is held short of stands (`Way.HELD`), or INF while the walk is not held.
func held_at() -> Vector2:
	return blocker if loco._way == loco.Way.HELD else Vector2.INF


## Seconds the walk has been held short of a body (0 while it is not held): from when the hold
## began, whichever body holds it now, and through the walk being aimed again while the NPC stands
## (`begin_hold`): how long it has stood held.
func held_time() -> float:
	return held_for if loco._way == loco.Way.HELD else 0.0


## True once each time a held walk has re-planned and found no way through (the body seals the only
## way and the destination is not taken, or no free spot is near it): the caller's cue to re-decide.
## The walk stays held meanwhile.
func take_blocked() -> bool:
	var b := blocked
	blocked = false
	return b


## The walk is held: a new hold starts its clocks, from where the NPC stands. One the NPC has not
## left (within `Locomotion.HOLD_MOVED` px of where the last began, that one ended under `HOLD_GAP`
## s of game time ago: a pause is no gap) goes on with them, so a walk aimed again, a free spot
## tried or a body that read as moving for a frame does not start the wait over: the re-plan
## (`take_blocked`) and an entry's cap on a hold (`held_time`) come on the time the NPC has stood
## held.
func begin_hold() -> void:
	var here: Vector2 = loco._character.global_position
	var gap := float(GameClock.frame() - hold_left) / Engine.physics_ticks_per_second
	if (_hold_at != Vector2.INF
			and here.distance_to(_hold_at) <= loco.HOLD_MOVED
			and hold_left >= 0
			and gap <= HOLD_GAP):
		return
	_hold_at = here
	held_for = 0.0
	_replan_at = WAIT


## `Locomotion._check` for a held walk: it goes its free way once nothing known is on it (`body`
## INF), round once the steering map has a way (looked for every `Locomotion.RECHECK` s), and
## re-plans after `WAIT` s.
func check_held(from: Vector2, resting: Array, body: Vector2, on_goal: bool, delta: float) -> void:
	blocker = body
	if body == Vector2.INF:
		loco._set_way(loco._free_way())
		return
	held_for += delta
	recheck_in -= delta
	if not on_goal and recheck_in <= 0.0:
		recheck_in = loco.RECHECK
		if goes_round(from, resting, last_leg):
			# A held last leg goes round by a way to the goal, or to a new last leg clear of every
			# body at rest.
			last_leg = false
			loco._set_way(loco.Way.ROUND)
	if (loco._way == loco.Way.HELD
			and held_for >= _replan_at
			and (_carved(body) or held_for >= _replan_at + CARVE_WAIT)):
		_replan_at = held_for + REPLAN_EVERY
		loco._replan(from, on_goal)


## Whether the steering map has a way round from `from` to the goal: its route ends at the goal, or
## within `LAST_LEG` of it with the plain way on from there passing no known body at rest (the last
## leg, `Locomotion._last_stretch`: of `resting`, or with `held_leg`, a held last leg looking again,
## of every known body at rest, so a new last leg is never one the body holding it, or another,
## stands on), and passes no known body at rest (`resting`) closer than
## `Locomotion.PASS_CLEARANCE`. Nothing goes round before both maps have synchronized.
func goes_round(from: Vector2, resting: Array, held_leg := false) -> bool:
	var plan_map: RID = loco._plan_map
	if (not steering_map.is_valid()
			or not NavBuilder.ready(steering_map)
			or not NavBuilder.ready(plan_map)):
		return false
	var route := NavBuilder.route(steering_map, from, loco._goal)
	if route.is_empty():
		return false
	var end: Vector2 = route[route.size() - 1]
	var goal := NavBuilder.snap(plan_map, loco._goal)
	if end.distance_to(goal) > BLOCKED_DISTANCE:
		var leg := NavBuilder.route(plan_map, end, goal)
		var clear_of := at_rest(goal, INF) if held_leg else resting
		if (end.distance_to(goal) > LAST_LEG
				or NavBuilder.path_length(leg) > LAST_LEG
				or first_on(end, leg, 0, clear_of, INF) != Vector2.INF):
			return false
	return first_on(from, route, 0, resting) == Vector2.INF


## The known bodies at rest within `reach` px of `around` (the one a melee closes on left out), as
## positions.
func at_rest(around: Vector2, reach: float) -> Array:
	var rest_speed: float = loco.REST_SPEED
	var out: Array = []
	for b in bodies:
		if int(b.get("id", 0)) == ignore_id:
			continue
		var pos: Vector2 = b["pos"]
		if ((b.get("vel", Vector2.ZERO) as Vector2).length() < rest_speed
				and pos.distance_to(around) <= reach):
			out.append(pos)
	return out


## The body of `resting` standing on `point` (within `Locomotion.PASS_CLEARANCE` of it), or INF.
func taker(resting: Array, point: Vector2) -> Vector2:
	var clearance: float = loco.PASS_CLEARANCE
	for pos in resting:
		if (pos as Vector2).distance_to(point) < clearance:
			return pos
	return Vector2.INF


## The first body of `resting` that the walk from `from` along `path` (from waypoint `index` on, the
## first `reach` px) passes closer than `Locomotion.PASS_CLEARANCE` and closer than the NPC stands
## to it now (one it already touches, and walks away from, does not stop it), or INF.
func first_on(
	from: Vector2,
	path: PackedVector2Array,
	index: int,
	resting: Array,
	reach: float = loco.LOOKAHEAD,
) -> Vector2:
	if resting.is_empty() or index >= path.size():
		return Vector2.INF
	var best := Vector2.INF
	var best_along := INF
	for pos in resting:
		var along := _meets_at(from, path, index, pos, reach)
		if along < best_along:
			best_along = along
			best = pos
	return best


## How far (px) along the walk from `from` along `path` (from waypoint `index` on, the first `reach`
## px) it first passes `body` closer than `Locomotion.PASS_CLEARANCE` and closer than the NPC stands
## to it now, or INF when it does not.
func _meets_at(
	from: Vector2,
	path: PackedVector2Array,
	index: int,
	body: Vector2,
	reach: float,
) -> float:
	var limit := minf(loco.PASS_CLEARANCE, from.distance_to(body) - 1.0)
	var walked := 0.0
	var a := from
	for i in range(index, path.size()):
		var b: Vector2 = path[i]
		var closest := Geometry2D.get_closest_point_to_segment(body, a, b)
		if closest.distance_to(body) < limit:
			return walked + a.distance_to(closest)
		walked += a.distance_to(b)
		if walked >= reach:
			break
		a = b
	return INF


## Whether the steering map has caught up with the body at rest at `pos`: it is re-baked on an
## interval, so a body that has just stopped is carved a moment later, and until then the map shows
## no way round it that may well be there. Its centre is then off the map (by more than
## `CARVED_GAP`). True with no steering map to wait for.
func _carved(pos: Vector2) -> bool:
	if not steering_map.is_valid() or not NavBuilder.ready(steering_map):
		return true
	return NavBuilder.snap(steering_map, pos).distance_to(pos) > CARVED_GAP
