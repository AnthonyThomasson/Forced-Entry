extends Node
## AI BEHAVIOUR sub-domain — LOCOMOTION. Owns the NavigationAgent2D and turns a target point into
## steering on the character: `move_to()` writes `character.movement.move_input` to follow a
## navigated path around walls and furniture and through doorways. The navmesh (baked by the
## Navigation domain) carves out furniture and rings the house with a walkable outdoor strip, so
## paths route around a piece and reroute through another doorway when one is blocked.
##
## A walk accounts for the characters the NPC KNOWS of (its part `crowd`, locomotion/loco_crowd.gd:
## `bodies`, the perception's contacts, what it sees or saw a moment ago; never a body it has not
## seen), and never walks into one. A body at rest on the walk is gone round, however far round, by
## the navigation domain's steering map, which has the characters at rest carved out too; when that
## map has no way round (the body seals the only way, or has only just stopped and is not carved
## yet) or the body stands on the destination, the walk stops short of it, waits, and re-plans: a
## free spot near a taken destination, else the caller is told the way is blocked
## (`crowd.take_blocked`) and may choose another walk. Two walkers coming at each other do not
## collide: one gives way (its part `give_way`, loco_give_way.gd). A walk the entry guard covers
## also keeps out of the view of every doorway into a room not clear for passing when it can (its
## part `doors`, loco_doors.gd): on the Navigation domain's avoid map, which has those views carved
## out too, when the route round them is within the cap the perception works out. Every other walk
## is the plain map's (furniture only). Its part `stall` (loco_stall.gd) samples the character's
## progress for the stuck overlay.
##
## Steering always aims at the next navmesh waypoint, so the character's own push physics bulldoze
## furniture sitting on the route without ever tunnelling a wall. It is behaviour's movement tool
## only — it holds no decision or combat state. Falls back to straight-line steering when there is
## no nav agent. It also holds the house's rooms (set each tick by `Behavior`), which the search
## coverage samples a room from; which room a point lies in is the perception's
## (`confinement.room_at`).

## How a walk goes: on the plain map; round a body at rest by the steering map; held short of a
## body; or round the doorway views by the avoid map.
enum Way {
	PLAIN,
	ROUND,
	HELD,
	DOORS,
}

## The parts (`crowd`, `give_way`, `stall`, `doors`).
const Crowd := preload("res://scenes/ai/behavior/locomotion/loco_crowd.gd")
const GiveWay := preload("res://scenes/ai/behavior/locomotion/loco_give_way.gd")
const Stall := preload("res://scenes/ai/behavior/locomotion/loco_stall.gd")
const Doors := preload("res://scenes/ai/behavior/locomotion/loco_doors.gd")
## The walk's last-leg rule (`PASS_CLEARANCE`), held once with the doorway geometry that predicts
## it (`AgentEntry.slot_reach`).
const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
## A known character whose smoothed track is slower than this (px/s) is AT REST: it stands where it
## is, and a walk goes round it or stops short of it; any faster one is a walker, given way to
## (`give_way`). A walking pace is 150; a body standing still but jostled by another reads 20 to
## 30.
const REST_SPEED := 40.0
## A walk that passes a body's centre closer than this (px) walks into it. Two bodies touch at 28
## px; the steering map's hole round a body at rest keeps a route about 33 to 35 px off it (body
## radius + `NavBuilder.OBSTACLE_MARGIN` + agent radius). Held on `AgentEntry` (`PASS_CLEARANCE`),
## whose slot prediction walks by the same number (`slot_reach`).
const PASS_CLEARANCE := AgentEntry.PASS_CLEARANCE
## How far along the walk (px) the bodies at rest on it are looked for.
const LOOKAHEAD := 400.0
## A walk held short of a body stands this far (px, centre to centre) from it.
const STOP_GAP := 56.0
## A hold that begins again with the NPC within this many px of where the last one began (that one
## ended under `crowd`'s `HOLD_GAP` s of game time ago) is the same hold going on
## (`crowd.begin_hold`).
const HOLD_MOVED := 16.0
## Seconds between looks for a way round while held (the steering map catches up with a body that
## has just stopped).
const RECHECK := 0.25
## A destination moved further than this (px) from the walk's is a new walk.
const NEW_WALK := 8.0

## The NPC's tunables, handed in by `setup`: how close (px) counts as "arrived" when steering
## straight-line (no nav agent) is its `tuning.pace.arrive_dist`, read live.
var tuning: NpcTuning
## World-space room rects (`{ key, type, rect }`) of the house, set each tick by `Behavior` from the
## controller's inject.
var rooms: Array = []
## The bodies the walk accounts for and the ones at rest on it: gone round, or held short of; see
## loco_crowd.gd.
var crowd := Crowd.new(self)
## Giving way to a walker, keeping off a body, a free spot near a taken destination; see
## loco_give_way.gd.
var give_way := GiveWay.new(self)
## The character's progress, sampled for the stuck overlay; see loco_stall.gd.
var stall := Stall.new(self)
## The walk round the doorway views (E18); see loco_doors.gd.
var doors := Doors.new(self)
## Pathfinding agent, or null (falls back to straight-line).
var _agent: NavigationAgent2D
## The world's navigation map: furniture only, what points are snapped and tested on.
var _plan_map: RID
## The agent's own arrival distance (px), what a walk arrives within unless it asks for less.
var _reach := 16.0
## The destination of the walk under way (INF: none yet).
var _walk_dest := Vector2.INF
## Where the walk is going: the destination, or a free spot near it when a body stands on it.
var _goal := Vector2.INF
## How the walk goes (`Way`).
var _way: int = Way.PLAIN
## The NPC's body, handed in once by `bind`: what a walk steers.
var _character: Node


## Keep the NPC's `npc_tuning`, and resolve + wire the navigation agent. `agent` may be null (then
## everything falls back to straight line steering). The agent starts on the world's own map
## (`_plan_map`: furniture only, which points are snapped to and tested on); `_set_way` moves it to
## the steering map for a walk that goes round a body at rest.
func setup(agent: NavigationAgent2D, npc_tuning: NpcTuning) -> void:
	tuning = npc_tuning
	_agent = agent
	if agent == null:
		return
	# The agent has not picked its map yet (its own _ready comes after the controller's), so read it
	# off the world its character stands in.
	var body := agent.get_parent() as Node2D
	if body != null and body.is_inside_tree():
		_plan_map = body.get_world_2d().navigation_map
	crowd.steering_map = NavBuilder.steering_map(_plan_map)
	_reach = agent.target_desired_distance


## Hand in the NPC's body. Called once by `Behavior.bind()`.
func bind(character: Node) -> void:
	_character = character


## Snap a world point onto the navigation mesh so it is actually reachable — a room's geometric
## centre is often inside furniture (off the navmesh), which would make the nav agent treat it as
## unreachable and wedge the NPC trying to shove toward it. Returns `p` unchanged with no nav agent.
func reachable(p: Vector2) -> Vector2:
	if _agent == null:
		return p
	return NavBuilder.snap(_plan_map, p)


## Whether world point `p` lies ON the baked navmesh — i.e. walkable floor, not inside a carved
## furniture hole or outside the walkable area — true when the closest navmesh point is within `tol`
## px of `p`. Returns true when there is no agent or the map isn't baked yet (nothing to test
## against), so callers don't over-filter during the first frames. Used to keep search-coverage
## points off furniture.
func on_navmesh(p: Vector2, tol: float = 8.0) -> bool:
	if _agent == null:
		return true
	if not NavBuilder.ready(_plan_map):
		return true
	return NavBuilder.snap(_plan_map, p).distance_to(p) <= tol


## Read-only: the pathing state behind the current move, for the AI's `debug_state()` snapshot. Uses
## only side-effect-free agent reads — notably NOT `get_next_path_position()`, which advances the
## agent's path index and so would perturb movement if called out of band by an observer. `next` is
## therefore read off the path array at the live index instead.
func debug_state() -> Dictionary:
	if _agent == null:
		return { "agent": false }
	var path: PackedVector2Array = _agent.get_current_navigation_path()
	var idx: int = _agent.get_current_navigation_path_index()
	# Points go out as [x, y] int pairs: JSON (how an observer serializes this) has no Vector2, and
	# pixel precision is ample for diagnosis.
	return {
		"agent": true,
		"target": _point(_agent.target_position),
		"reachable": _agent.is_target_reachable(),
		"finished": _agent.is_navigation_finished(),
		"next": _point(path[idx]) if idx < path.size() else [],
		"way": ["plain", "round", "held", "doors"][_way],
		"held_for": snappedf(crowd.held_for, 0.01) if _way == Way.HELD else 0.0,
		"last_leg": crowd.last_leg,
		"giving_way": give_way.yield_id != 0,
	}


## The walk the nav agent is following: `{ path: PackedVector2Array, index: int }` (the waypoints
## and the one it is heading for), or {} with no agent or no path. Read after `move_to`, so it is
## the walk that was just steered.
func path_ahead() -> Dictionary:
	if _agent == null:
		return {}
	var path: PackedVector2Array = _agent.get_current_navigation_path()
	if path.size() < 2:
		return {}
	return { "path": path, "index": _agent.get_current_navigation_path_index() }


## A world point as a JSON-safe [x, y] int pair.
func _point(p: Vector2) -> Array:
	return [int(p.x), int(p.y)]


## Whether the NPC has reached `point`: the walk there is done (at the point, or at the free spot it
## took near it when a body stands on the point), or within `tuning.pace.arrive_dist` straight-line
## with no agent.
## Never while the walk is held short. `within` (px) asks for a closer arrival than the agent's own
## (`move_to`).
func reached(point: Vector2, within := 0.0) -> bool:
	if _agent != null:
		_begin(point, within)
		_agent.target_position = _goal
		_last_stretch()
		return _way != Way.HELD and _agent.is_navigation_finished()
	return _character.global_position.distance_to(point) < tuning.pace.arrive_dist


## Steer `character.movement.move_input` toward `dest` along a navigated path (around walls and
## furniture, through doorways) by heading for the next navmesh waypoint each frame, accounting for
## the characters the NPC knows of (`crowd.bodies`):
## - a body at rest on the walk is gone round by the steering map, whatever the detour, when that
##   map has a way round it (`Way.ROUND`); with none (it seals the way, or the map has not caught up
##   with it yet) or with the body standing on the destination, the walk is held short of it
##   (`STOP_GAP`), waits, and re-plans (`_check`, `_replan`);
## - a walker coming at the NPC is given way to, unless the NPC has the right of way
##   (`give_way.apply`).
## Bodies the NPC does not know of are not accounted for: furniture physically on the route (a piece
## shoved off its baked hole) is shoved aside by the character's own push physics. Falls back to
## plain straight-line steering when there is no agent. `within` (px, 0 = the agent's own arrival
## distance) makes the walk end closer to `dest`: a spot others stand beside (a stack slot), where a
## stride short is on the next one.
func move_to(dest: Vector2, within := 0.0) -> void:
	if _agent == null:
		var straight: Vector2 = dest - _character.global_position
		_character.movement.move_input = (Vector2.ZERO
				if straight.length() < tuning.pace.arrive_dist
				else straight.normalized())
		return
	_begin(dest, within)
	_agent.target_position = _goal
	_last_stretch()
	give_way.kept_off = false
	give_way.yielding = false
	if _agent.is_navigation_finished() and _way != Way.HELD:
		_character.movement.move_input = Vector2.ZERO
		return
	# Always steer toward the next navmesh waypoint — never the raw destination, which can lie
	# across a wall. `next` is wall-safe, and for an unreachable target it steps toward the closest
	# reachable point.
	var next := _agent.get_next_path_position()
	if _check():
		# The walk changed map or goal: steer by its new path.
		next = _agent.get_next_path_position()
	var here: Vector2 = _character.global_position
	var desired: Vector2 = next - here
	desired = desired.normalized() if desired.length() > 0.001 else Vector2.ZERO
	if (_way == Way.HELD
			and (here.distance_to(crowd.blocker) <= STOP_GAP or _agent.is_navigation_finished())):
		desired = Vector2.ZERO  # Held: stand short of the body, waiting for it to move.
	elif doors.waiting():
		desired = Vector2.ZERO  # The way round the held stack's room is still being baked.
	_character.movement.move_input = desired
	give_way.apply()
	give_way.keep_off()


## Start a walk to `dest`, arriving within `within` px (0 = the agent's own distance), unless it is
## the walk under way (a destination that drifts a few px, a target being followed, carries the walk
## on).
func _begin(dest: Vector2, within := 0.0) -> void:
	var reach := within if within > 0.0 else _reach
	if _agent.target_desired_distance != reach:
		_agent.target_desired_distance = reach
	if _walk_dest != Vector2.INF and dest.distance_to(_walk_dest) <= NEW_WALK:
		if _goal == _walk_dest:
			_goal = dest
		_walk_dest = dest
		if (_goal != _walk_dest
				and crowd.taker(
					crowd.at_rest(_walk_dest, PASS_CLEARANCE),
					_walk_dest,
				) == Vector2.INF):
			# Done at the free spot beside it, and nobody stands on the destination now: on to it
			# (`_check` is not run once a walk is over).
			_goal = _walk_dest
		return
	_walk_dest = dest
	_goal = dest
	crowd.blocked = false
	doors.decided = false
	doors.map = RID()
	crowd.last_leg = false
	_set_way(Way.PLAIN)


## A walk round the doorway views whose avoid map ends short of the goal walks the last stretch on
## the plain map: a goal by a view's edge (a stack slot beside the doorway) is off that map, which
## keeps the body its radius out of the view, and `walk_route` takes a route that ends within
## `AgentDoorViews.AVOID_REACH` of it. Without it the walk would be over where the avoid route ends.
## So does a walk round bodies at rest whose steering map ends short of a goal no body stands on (a
## stack slot between two that are taken lies inside their carved margins): the rest is walked plain
## (`crowd.last_leg`), held short of a body on it; held, it looks again every `RECHECK` for a way
## round: one that ends at the goal, or a new last leg whose plain way passes clear of every known
## body at rest (`crowd.goes_round` with `held_leg`), so it never takes one the body holding it, or
## another, stands on.
func _last_stretch() -> void:
	if _way not in [Way.DOORS, Way.ROUND] or not _agent.is_navigation_finished() \
			or _character.global_position.distance_to(_goal) <= _agent.target_desired_distance:
		return
	if _way == Way.DOORS:
		doors.map = RID()  # Decided: no way round for the rest of this walk.
	elif crowd.taker(crowd.at_rest(_goal, PASS_CLEARANCE), _goal) == Vector2.INF:
		crowd.last_leg = true
	else:
		return  # A body stands on the goal: the hold and the free spot beside it are `_check`'s.
	_set_way(Way.PLAIN)
	_agent.target_position = _goal


## Put the walk on `way` and the agent on that way's map; a hold starts its clocks.
func _set_way(way: int) -> void:
	if way == Way.HELD and _way != Way.HELD:
		crowd.begin_hold()
	elif way != Way.HELD and _way == Way.HELD:
		crowd.hold_left = GameClock.frame()
	if way != _way and (way == Way.HELD or way == Way.ROUND):
		crowd.recheck_in = RECHECK
	if way != Way.HELD:
		crowd.blocker = Vector2.INF
	_way = way
	var want := _plan_map
	if way == Way.ROUND and crowd.steering_map.is_valid():
		want = crowd.steering_map
	elif way == Way.DOORS and doors.map.is_valid():
		want = doors.map
	if want.is_valid() and _agent.get_navigation_map() != want:
		_agent.set_navigation_map(want)


## Whether the plain way from where the NPC stands to `p` passes the body the walk is held short of
## (closer than `PASS_CLEARANCE` and than it stands to it now, `crowd.first_on`): the hold seals `p`
## too.
## False while the walk is not held.
func seals(p: Vector2) -> bool:
	if _way != Way.HELD or crowd.blocker == Vector2.INF or _character == null:
		return false
	var from: Vector2 = _character.global_position
	var route := PackedVector2Array([from, p])
	if _agent != null and NavBuilder.ready(_plan_map):
		route = NavBuilder.route(_plan_map, from, p)
	return crowd.first_on(from, route, 0, [crowd.blocker], INF) != Vector2.INF


## Check the walk against the bodies at rest the NPC knows of, once a physics frame: the first one
## on its path ahead (within `LOOKAHEAD`), or one standing on its goal, and choose the way. True
## when the walk's map or goal changed.
## - On the plain map or round the doorway views, a body on the path is gone round by the steering
##   map when that map has a way round it that clears every known body (`crowd.goes_round`); with
##   none,
##   or a body on the goal, the walk is held short of it.
## - Going round, a body on the steering path (one that map has not carved yet) holds the walk the
##   same way; a walk that keeps out of the doorway views goes back to the avoid map once its route
##   there passes no known body (looked at every `RECHECK` s), so going round a body does not take
##   it through the views for the rest of the walk.
## - Held, the walk goes on its free way (`_free_way`: the avoid map for a walk that keeps out of
##   the doorway views, else the plain map) once nothing known is on it, or round once the steering
##   map has a way round (looked for every `RECHECK` s); after `crowd`'s `WAIT` s it re-plans
##   (`_replan`; `crowd.check_held`).
func _check() -> bool:
	var frame := Engine.get_physics_frames()
	if frame == crowd.checked_frame:
		return false
	crowd.checked_frame = frame
	var delta := get_physics_process_delta_time()
	var from: Vector2 = _character.global_position
	var resting := crowd.at_rest(from, LOOKAHEAD + PASS_CLEARANCE)
	var was_map := _agent.get_navigation_map()
	var was_goal := _goal
	doors.update(delta)
	if _goal != _walk_dest and crowd.taker(resting, _walk_dest) == Vector2.INF:
		_goal = _walk_dest  # The destination is free again.
	var blocker := crowd.taker(resting, _goal)
	var on_goal := blocker != Vector2.INF
	if not on_goal:
		var path: PackedVector2Array = _agent.get_current_navigation_path()
		blocker = crowd.first_on(from, path, _agent.get_current_navigation_path_index(), resting)
	match _way:
		Way.PLAIN, Way.ROUND, Way.DOORS:
			_check_walking(from, resting, blocker, on_goal, delta)
		Way.HELD:
			crowd.check_held(from, resting, blocker, on_goal, delta)
	return _agent.get_navigation_map() != was_map or _goal != was_goal


## `_check` for a walk under way (plain, round or round the doorway views): a body on its path
## (`blocker`) is gone round by the steering map when it can be, else holds the walk; a walk round a
## body that keeps out of the doorway views goes back to the avoid map once its route there is
## clear.
func _check_walking(
	from: Vector2,
	resting: Array,
	blocker: Vector2,
	on_goal: bool,
	delta: float,
) -> void:
	if blocker != Vector2.INF:
		if not on_goal and not crowd.last_leg and crowd.goes_round(from, resting):
			_set_way(Way.ROUND)
		else:
			_set_way(Way.HELD)
			crowd.blocker = blocker
	elif _way == Way.ROUND and doors.map.is_valid():
		crowd.recheck_in -= delta
		if crowd.recheck_in <= 0.0:
			crowd.recheck_in = RECHECK
			if _clear_on(doors.map, from, resting):
				_set_way(Way.DOORS)


## The way a walk goes when no body is in it: round the doorway views when it has been given the
## avoid map, else the plain way.
func _free_way() -> int:
	return Way.DOORS if doors.map.is_valid() else Way.PLAIN


## The held walk re-plans: a body standing on the goal sends it to the nearest free spot near the
## destination; any other hold (a body sealing the only way) tells the caller
## (`crowd.take_blocked`), who
## may choose another walk.
func _replan(from: Vector2, on_goal: bool) -> void:
	if on_goal:
		var spot := give_way.free_spot(from)
		if spot != Vector2.INF:
			_goal = spot
			crowd.last_leg = false
			_set_way(_free_way())
			return
	crowd.blocked = true


## Whether `map` (synchronized) has a route from `from` to the goal that passes no known body at
## rest (`resting`) closer than `PASS_CLEARANCE`, all the way and not only the first `LOOKAHEAD` px:
## a body just past that on the route would be met a few strides on, and the walk would be sent
## round again.
func _clear_on(map: RID, from: Vector2, resting: Array) -> bool:
	if not NavBuilder.ready(map):
		return false
	return crowd.first_on(from, NavBuilder.route(map, from, _goal), 0, resting, INF) == Vector2.INF
