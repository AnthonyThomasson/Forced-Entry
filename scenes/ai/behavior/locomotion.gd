extends Node
## AI BEHAVIOUR sub-domain — LOCOMOTION. Owns the NavigationAgent2D and turns a target point into
## steering on the character: `move_to()` writes `character.move_input` to follow a navigated path
## around walls and furniture and through doorways. The navmesh (baked by the Navigation domain)
## carves out furniture and rings the house with a walkable outdoor strip, so paths route around a
## piece and reroute through another doorway when one is blocked.
##
## A walk accounts for the characters the NPC KNOWS of (`bodies`: the perception's contacts, what it
## sees or saw a moment ago; never a body it has not seen), and never walks into one. A body at rest
## on the walk is gone round, however far round, by the navigation domain's steering map, which has
## the characters at rest carved out too; when that map has no way round (the body seals the only
## way, or has only just stopped and is not carved yet) or the body stands on the destination, the
## walk stops short of it, waits, and re-plans: a free spot near a taken destination, else the
## caller is told the way is blocked (`take_blocked`) and may choose another walk. Two walkers
## coming at each other do not collide: one gives way (`_give_way`). A walk the entry guard covers
## also keeps out of the view of every doorway into a room not clear for passing when it can
## (`_update_doors`): on the Navigation domain's avoid map, which has those views carved out too,
## when the route round them is within the cap the perception works out. Every other walk is the
## plain map's (furniture only).
##
## Steering always aims at the next navmesh waypoint, so the character's own push physics bulldoze
## furniture sitting on the route without ever tunnelling a wall. It is behaviour's movement tool
## only — it holds no decision or combat state. Falls back to straight-line steering when there is
## no nav agent. It also knows the house's rooms (set each tick by `Behavior`), so the behaviour
## modules can ask which room, if any, a point lies in.

## How a walk goes: on the plain map; round a body at rest by the steering map; held short of a
## body; or round the doorway views by the avoid map.
enum Way {
	PLAIN,
	ROUND,
	HELD,
	DOORS,
}

## Stuck-sensing window (s): displacement is compared over this span while the NPC is trying to
## move.
const STALL_WINDOW := 0.75
## Speed (px/s) below which an NPC that is trying to move counts as not progressing.
const STALL_SPEED := 8.0
## Seconds between recorded trail points, and the most points kept (a short recent-position trail).
const TRAIL_STEP := 0.25
const TRAIL_MAX := 24
## How far (px) the steering map's route may end short of the point it was asked for before a body
## is taken to seal the way (see `_goes_round`).
const BLOCKED_DISTANCE := 24.0
## Farthest (px) short of its goal a route round bodies at rest may end when the plain way on from
## there passes no body: a goal inside the margins the steering map carves round bodies (a stack
## slot between two taken ones) is reached by that last leg (`_last_stretch`).
const LAST_LEG := 64.0
## A known character whose smoothed track is slower than this (px/s) is AT REST: it stands where it
## is, and a walk goes round it or stops short of it; any faster one is a walker, given way to
## (`_give_way`). A walking pace is 150; a body standing still but jostled by another reads 20 to
## 30.
const REST_SPEED := 40.0
## A walk that passes a body's centre closer than this (px) walks into it. Two bodies touch at 28
## px; the steering map's hole round a body at rest keeps a route about 33 to 35 px off it (body
## radius + `NavBuilder.OBSTACLE_MARGIN` + agent radius).
const PASS_CLEARANCE := 32.0
## Whatever the walk, the NPC never steers into a known body closer than this (px, centre to
## centre): the part of its steering toward the body is dropped and it slides past (`keep_off`). The
## agent cuts a path's corners by up to its `path_desired_distance`, which can bring a walk round a
## body a few px inside the route.
const KEEP_OFF := 36.0
## How far along the walk (px) the bodies at rest on it are looked for.
const LOOKAHEAD := 400.0
## A walk held short of a body stands this far (px, centre to centre) from it.
const STOP_GAP := 56.0
## Seconds a walk is held short before it re-plans (a free spot near a taken destination, else the
## caller is told the way is blocked: `take_blocked`), and between later re-plans while it is still
## held.
const WAIT := 0.75
const REPLAN_EVERY := 4.0
## A hold that begins again within `HOLD_GAP` s of game time (`GameClock`, LD1: a pause is no gap)
## of the last one ending, the NPC within `HOLD_MOVED` px of where that one began, is the same hold
## going on (its walk aimed again, a free spot tried, a frame the body read as moving): its clocks
## carry on (`_begin_hold`).
const HOLD_GAP := 0.5
const HOLD_MOVED := 16.0
## A held walk re-plans only once the steering map shows the body it is held by (`_carved`: a body
## carved there has its centre at least this far (px) off the map), or this many s past its re-plan
## time whatever the map shows.
const CARVED_GAP := 16.0
const CARVE_WAIT := 2.0
## Seconds between looks for a way round while held (the steering map catches up with a body that
## has just stopped).
const RECHECK := 0.25
## A free spot near a taken destination: rings this far out from it (px), sampled at
## `FREE_SPOT_ANGLES` angles, the nearest ring first; a spot must stand this far (px) from every
## body at rest (outside its hole, with room to spare).
const FREE_SPOT_RINGS := [44.0, 56.0, 68.0, 80.0, 96.0]
const FREE_SPOT_ANGLES := 12
const FREE_SPOT_CLEAR := 40.0
## A destination moved further than this (px) from the walk's is a new walk.
const NEW_WALK := 8.0
## Giving way to a walker: one closer than `GIVE_RANGE` (px), not at rest, whose straight course and
## the NPC's own come within `GIVE_CLEARANCE` (px, centre to centre) of each other in the next
## `GIVE_HORIZON` seconds, or in the time its own walk still takes when that is shorter. The NPC
## gives way at most `GIVE_MAX` s to one walker. Even with the right of way it stops for a walker on
## course for it closer than `GIVE_IMMINENT` (px): the walker may not have seen it set off (a track
## takes a few frames to show a body moving).
const GIVE_RANGE := 160.0
const GIVE_CLEARANCE := 36.0
const GIVE_IMMINENT := 50.0
const GIVE_HORIZON := 1.2
const GIVE_MAX := 3.0
## A walker sees the NPC when it is within this distance (px) of it, or within the cone of this
## cosine round its facing (a 110 degree view).
const SEES_NEAR := 48.0
const SEES_COS := 0.57
## The pace (px/s) a walk is reckoned at when the character has not got going yet.
const PACE_FLOOR := 100.0
## Seconds between looks at the route a door-avoiding walk takes (the views change as rooms are
## cleared and expire, and the avoid map is only kept for a walk that keeps asking for it).
const DOORS_RECHECK := 2.0

## How close (px) counts as "arrived" when steering straight-line (no nav agent): the controller's
## `arrive_dist`, set by `Behavior.apply_config()`.
var arrive_dist: float
## World-space room rects (`{ key, type, rect }`) of the house, set each tick by `Behavior` from the
## controller's inject.
var rooms: Array = []
## The characters the NPC knows of, set each tick by `Behavior` from the perception's contacts
## (`AgentPerception.contacts`: seen within its contact memory, each with `id`, `pos`, `vel`,
## `facing` and `visible`): the only bodies a walk accounts for.
var bodies: Array = []
## A character no walk treats as an obstacle (the one a melee closes on), by instance id; 0 = none.
var ignore_id: int = 0
## The perception (`walk_route(to)`), asked whether a walk goes round the doorway views.
var views: Node
## The walk under way is one that keeps out of the doorway views (set each tick by `Behavior`: the
## walks the entry guard covers).
var avoid_doors := false
## The entry the walk is the approach of (`"<opening id>><room key>"`, "" for none): it keeps out of
## that room and of that doorway's view (`AgentPerception.walk_route`).
var avoid_entering := ""
## Pathfinding agent, or null (falls back to straight-line).
var _agent: NavigationAgent2D
## The world's navigation map: furniture only, what points are snapped and tested on.
var _plan_map: RID
## The map with the living characters carved out too, or invalid when the world has none.
var _steering_map: RID
## The agent's own arrival distance (px), what a walk arrives within unless it asks for less.
var _reach := 16.0
## The destination of the walk under way (INF: none yet).
var _walk_dest := Vector2.INF
## Where the walk is going: the destination, or a free spot near it when a body stands on it.
var _goal := Vector2.INF
## How the walk goes (`Way`).
var _way: int = Way.PLAIN
## The walk has been checked against the doorway views: it goes round them (`_doors_map`) or needs
## no way round.
var _doors_decided := false
## The avoid map the walk goes round the doorway views on (invalid: the walk is not door-avoiding).
var _doors_map := RID()
## The walk round bodies ended short of a goal no body stands on: it walks the rest plain, held by a
## body on it (`_last_stretch`).
var _last_leg := false
## Seconds until the door-avoiding walk next looks at its route.
var _doors_in := 0.0
## The body at rest the walk is held short of (INF: not held).
var _blocker := Vector2.INF
## Seconds the walk has been held short.
var _held_for := 0.0
## `_held_for` at which the held walk next re-plans.
var _replan_at := WAIT
## Where the NPC stood when the hold under way began (INF: none yet).
var _hold_at := Vector2.INF
## The `GameClock` frame the walk last stopped being held.
var _hold_left := -1
## Seconds until the held walk next looks for a way round, or one gone round off the avoid map looks
## back at it.
var _recheck_in := 0.0
## The held walk re-planned and found no way: the caller should re-decide (`take_blocked`).
var _blocked := false
## The physics frame the walk was last checked in (once a frame).
var _checked_frame := -1
## The walker the NPC is giving way to (instance id; 0 = none).
var _yield_id := 0
## Where it steps aside to while giving way (INF: it waits where it is).
var _yield_spot := Vector2.INF
## Seconds it has been giving way to that walker.
var _yield_for := 0.0
## `keep_off` stopped the walk this frame (a body on every side it would go).
var _kept_off := false
## `_give_way` stopped the walk or turned it aside this frame.
var _yielding := false
## Position at the start of the current stall-sensing window.
var _stall_pos := Vector2.ZERO
## Seconds into the current window.
var _stall_clock := 0.0
## Speed (px/s) measured over the last full window.
var _stall_speed := 0.0
## Seconds the NPC has been trying to move without progressing.
var _stalled_for := 0.0
## Seconds since the last trail point.
var _trail_clock := 0.0
## Recent world positions, oldest first.
var _trail: Array = []
## The NPC's body, handed in once by `bind`: what a walk steers.
var _character: Node


## The key of the room containing world point `p`, or "" when `p` is in no room.
func room_key_at(p: Vector2) -> String:
	for room in rooms:
		if (room["rect"] as Rect2).has_point(p):
			return str(room["key"])
	return ""


## Whether a world point lies within any of the house's rooms (the "inside the house" test).
func inside_house(p: Vector2) -> bool:
	return room_key_at(p) != ""


## Resolve + wire the navigation agent. `agent` may be null (then everything falls back to straight
## line steering). The agent starts on the world's own map (`_plan_map`: furniture only, which
## points are snapped to and tested on); `_set_way` moves it to the steering map for a walk that
## goes round a body at rest.
func setup(agent: NavigationAgent2D) -> void:
	_agent = agent
	if agent == null:
		return
	# The agent has not picked its map yet (its own _ready comes after the controller's), so read it
	# off the world its character stands in.
	var body := agent.get_parent() as Node2D
	if body != null and body.is_inside_tree():
		_plan_map = body.get_world_2d().navigation_map
	_steering_map = NavBuilder.steering_map(_plan_map)
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
		"held_for": snappedf(_held_for, 0.01) if _way == Way.HELD else 0.0,
		"last_leg": _last_leg,
		"giving_way": _yield_id != 0,
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


## Observation only: sample the character's progress each tick. While it is trying to move
## (`move_input` set) it compares displacement over `STALL_WINDOW`; a speed under `STALL_SPEED`
## grows `_stalled_for`. Nothing reacts to it — `debug_progress()` exposes it to the stuck overlay.
func sample(delta: float) -> void:
	var pos: Vector2 = _character.global_position
	_trail_clock += delta
	if _trail_clock >= TRAIL_STEP:
		_trail_clock = 0.0
		_trail.append(pos)
		if _trail.size() > TRAIL_MAX:
			_trail.pop_front()
	if (_character.move_input as Vector2).length() < 0.1:
		_stall_clock = 0.0
		_stall_pos = pos
		_stalled_for = 0.0
		_stall_speed = 0.0
		return
	_stall_clock += delta
	if _stall_clock >= STALL_WINDOW:
		_stall_speed = pos.distance_to(_stall_pos) / _stall_clock
		_stalled_for = _stalled_for + _stall_clock if _stall_speed < STALL_SPEED else 0.0
		_stall_pos = pos
		_stall_clock = 0.0


## Read-only: the movement-progress state sampled by `sample()`, for the stuck debug overlay.
func debug_progress() -> Dictionary:
	return { "stalled_for": _stalled_for, "trail": _trail }


## A world point as a JSON-safe [x, y] int pair.
func _point(p: Vector2) -> Array:
	return [int(p.x), int(p.y)]


## Whether the NPC has reached `point`: the walk there is done (at the point, or at the free spot it
## took near it when a body stands on the point), or within arrive_dist straight-line with no agent.
## Never while the walk is held short. `within` (px) asks for a closer arrival than the agent's own
## (`move_to`).
func reached(point: Vector2, within := 0.0) -> bool:
	if _agent != null:
		_begin(point, within)
		_agent.target_position = _goal
		_last_stretch()
		return _way != Way.HELD and _agent.is_navigation_finished()
	return _character.global_position.distance_to(point) < arrive_dist


## Whether the walk stands, or steps aside, for a body this frame: held short of one in its way (or
## on its destination), giving way to a walker, stopped against one it would otherwise walk into
## (`keep_off`), or done at the free spot beside a taken destination. A caller must not push on
## toward the destination itself then.
func holding() -> bool:
	return _way == Way.HELD or _kept_off or _yielding or _goal != _walk_dest


## The known body the walk is held short of (`Way.HELD`), by instance id: 0 while the walk is not
## held, or when that body is no longer known. What an entry asks of a hold before it gives its slot
## up (`Entry.way_blocked`: a teammate still on its way only waits).
func held_by() -> int:
	if _way != Way.HELD or _blocker == Vector2.INF:
		return 0
	for b in bodies:
		if b["pos"] == _blocker:
			return int(b.get("id", 0))
	return 0


## Where the body the walk is held short of stands (`Way.HELD`), or INF while the walk is not held.
func held_at() -> Vector2:
	return _blocker if _way == Way.HELD else Vector2.INF


## Seconds the walk has been held short of a body (0 while it is not held): from when the hold
## began, whichever body holds it now, and through the walk being aimed again while the NPC stands
## (`_begin_hold`): how long it has stood held.
func held_time() -> float:
	return _held_for if _way == Way.HELD else 0.0


## True once each time a held walk has re-planned and found no way through (the body seals the only
## way and the destination is not taken, or no free spot is near it): the caller's cue to re-decide.
## The walk stays held meanwhile.
func take_blocked() -> bool:
	var b := _blocked
	_blocked = false
	return b


## Steer `character.move_input` toward `dest` along a navigated path (around walls and furniture,
## through doorways) by heading for the next navmesh waypoint each frame, accounting for the
## characters the NPC knows of (`bodies`):
## - a body at rest on the walk is gone round by the steering map, whatever the detour, when that
##   map has a way round it (`Way.ROUND`); with none (it seals the way, or the map has not caught up
##   with it yet) or with the body standing on the destination, the walk is held short of it
##   (`STOP_GAP`), waits, and re-plans (`_check`, `_replan`);
## - a walker coming at the NPC is given way to, unless the NPC has the right of way (`_give_way`).
## Bodies the NPC does not know of are not accounted for: furniture physically on the route (a piece
## shoved off its baked hole) is shoved aside by the character's own push physics. Falls back to
## plain straight-line steering when there is no agent. `within` (px, 0 = the agent's own arrival
## distance) makes the walk end closer to `dest`: a spot others stand beside (a stack slot), where a
## stride short is on the next one.
func move_to(dest: Vector2, within := 0.0) -> void:
	if _agent == null:
		var straight: Vector2 = dest - _character.global_position
		_character.move_input = (Vector2.ZERO
				if straight.length() < arrive_dist
				else straight.normalized())
		return
	_begin(dest, within)
	_agent.target_position = _goal
	_last_stretch()
	_kept_off = false
	_yielding = false
	if _agent.is_navigation_finished() and _way != Way.HELD:
		_character.move_input = Vector2.ZERO
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
			and (here.distance_to(_blocker) <= STOP_GAP or _agent.is_navigation_finished())):
		desired = Vector2.ZERO  # Held: stand short of the body, waiting for it to move.
	_character.move_input = desired
	_give_way()
	keep_off()


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
				and _taker(_resting(_walk_dest, PASS_CLEARANCE), _walk_dest) == Vector2.INF):
			# Done at the free spot beside it, and nobody stands on the destination now: on to it
			# (`_check` is not run once a walk is over).
			_goal = _walk_dest
		return
	_walk_dest = dest
	_goal = dest
	_blocked = false
	_doors_decided = false
	_doors_map = RID()
	_last_leg = false
	_set_way(Way.PLAIN)


## A walk round the doorway views whose avoid map ends short of the goal walks the last stretch on
## the plain map: a goal by a view's edge (a stack slot beside the doorway) is off that map, which
## keeps the body its radius out of the view, and `walk_route` takes a route that ends within
## `AgentDoorViews.AVOID_REACH` of it. Without it the walk would be over where the avoid route ends.
## So does a walk round bodies at rest whose steering map ends short of a goal no body stands on (a
## stack slot between two that are taken lies inside their carved margins): the rest is walked plain
## (`_last_leg`), held short of a body on it; held, it looks again every `RECHECK` for a way round:
## one that ends at the goal, or a new last leg whose plain way passes clear of every known body at
## rest (`_goes_round` with `held_leg`), so it never takes one the body holding it, or another,
## stands on.
func _last_stretch() -> void:
	if _way not in [Way.DOORS, Way.ROUND] or not _agent.is_navigation_finished() \
			or _character.global_position.distance_to(_goal) <= _agent.target_desired_distance:
		return
	if _way == Way.DOORS:
		_doors_map = RID()  # Decided: no way round for the rest of this walk.
	elif _taker(_resting(_goal, PASS_CLEARANCE), _goal) == Vector2.INF:
		_last_leg = true
	else:
		return  # A body stands on the goal: the hold and the free spot beside it are `_check`'s.
	_set_way(Way.PLAIN)
	_agent.target_position = _goal


## Put the walk on `way` and the agent on that way's map; a hold starts its clocks.
func _set_way(way: int) -> void:
	if way == Way.HELD and _way != Way.HELD:
		_begin_hold()
	elif way != Way.HELD and _way == Way.HELD:
		_hold_left = GameClock.frame()
	if way != _way and (way == Way.HELD or way == Way.ROUND):
		_recheck_in = RECHECK
	if way != Way.HELD:
		_blocker = Vector2.INF
	_way = way
	var want := _plan_map
	if way == Way.ROUND and _steering_map.is_valid():
		want = _steering_map
	elif way == Way.DOORS and _doors_map.is_valid():
		want = _doors_map
	if want.is_valid() and _agent.get_navigation_map() != want:
		_agent.set_navigation_map(want)


## The walk is held: a new hold starts its clocks, from where the NPC stands. One the NPC has not
## left (within `HOLD_MOVED` px of where the last began, that one ended under `HOLD_GAP` s of game
## time ago: a pause is no gap) goes on with them, so a walk aimed again, a free spot tried or a
## body that read as moving for a frame does not start the wait over: the re-plan (`take_blocked`)
## and an entry's cap on a hold (`held_time`) come on the time the NPC has stood held.
func _begin_hold() -> void:
	var here: Vector2 = _character.global_position
	var gap := float(GameClock.frame() - _hold_left) / Engine.physics_ticks_per_second
	if (_hold_at != Vector2.INF
			and here.distance_to(_hold_at) <= HOLD_MOVED
			and _hold_left >= 0
			and gap <= HOLD_GAP):
		return
	_hold_at = here
	_held_for = 0.0
	_replan_at = WAIT


## Whether the plain way from where the NPC stands to `p` passes the body the walk is held short of
## (closer than `PASS_CLEARANCE` and than it stands to it now, `_first_on`): the hold seals `p` too.
## False while the walk is not held.
func seals(p: Vector2) -> bool:
	if _way != Way.HELD or _blocker == Vector2.INF or _character == null:
		return false
	var from: Vector2 = _character.global_position
	var route := PackedVector2Array([from, p])
	if _agent != null and NavBuilder.ready(_plan_map):
		route = NavBuilder.route(_plan_map, from, p)
	return _first_on(from, route, 0, [_blocker], INF) != Vector2.INF


## Check the walk against the bodies at rest the NPC knows of, once a physics frame: the first one
## on its path ahead (within `LOOKAHEAD`), or one standing on its goal, and choose the way. True
## when the walk's map or goal changed.
## - On the plain map or round the doorway views, a body on the path is gone round by the steering
##   map when that map has a way round it that clears every known body (`_goes_round`); with none,
##   or a body on the goal, the walk is held short of it.
## - Going round, a body on the steering path (one that map has not carved yet) holds the walk the
##   same way; a walk that keeps out of the doorway views goes back to the avoid map once its route
##   there passes no known body (looked at every `RECHECK` s), so going round a body does not take
##   it through the views for the rest of the walk.
## - Held, the walk goes on its free way (`_free_way`: the avoid map for a walk that keeps out of
##   the doorway views, else the plain map) once nothing known is on it, or round once the steering
##   map has a way round (looked for every `RECHECK` s); after `WAIT` s it re-plans (`_replan`).
func _check() -> bool:
	var frame := Engine.get_physics_frames()
	if frame == _checked_frame:
		return false
	_checked_frame = frame
	var delta := get_physics_process_delta_time()
	var from: Vector2 = _character.global_position
	var resting := _resting(from, LOOKAHEAD + PASS_CLEARANCE)
	var was_map := _agent.get_navigation_map()
	var was_goal := _goal
	_update_doors(delta)
	if _goal != _walk_dest and _taker(resting, _walk_dest) == Vector2.INF:
		_goal = _walk_dest  # The destination is free again.
	var blocker := _taker(resting, _goal)
	var on_goal := blocker != Vector2.INF
	if not on_goal:
		var path: PackedVector2Array = _agent.get_current_navigation_path()
		blocker = _first_on(from, path, _agent.get_current_navigation_path_index(), resting)
	match _way:
		Way.PLAIN, Way.ROUND, Way.DOORS:
			_check_walking(from, resting, blocker, on_goal, delta)
		Way.HELD:
			_check_held(from, resting, blocker, on_goal, delta)
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
		if not on_goal and not _last_leg and _goes_round(from, resting):
			_set_way(Way.ROUND)
		else:
			_set_way(Way.HELD)
			_blocker = blocker
	elif _way == Way.ROUND and _doors_map.is_valid():
		_recheck_in -= delta
		if _recheck_in <= 0.0:
			_recheck_in = RECHECK
			if _clear_on(_doors_map, from, resting):
				_set_way(Way.DOORS)


## `_check` for a held walk: it goes its free way once nothing known is on it (`blocker` INF), round
## once the steering map has a way (looked for every `RECHECK` s), and re-plans after `WAIT` s.
func _check_held(
	from: Vector2,
	resting: Array,
	blocker: Vector2,
	on_goal: bool,
	delta: float,
) -> void:
	_blocker = blocker
	if blocker == Vector2.INF:
		_set_way(_free_way())
		return
	_held_for += delta
	_recheck_in -= delta
	if not on_goal and _recheck_in <= 0.0:
		_recheck_in = RECHECK
		if _goes_round(from, resting, _last_leg):
			# A held last leg goes round by a way to the goal, or to a new last leg clear of every
			# body at rest.
			_last_leg = false
			_set_way(Way.ROUND)
	if (_way == Way.HELD
			and _held_for >= _replan_at
			and (_carved(blocker) or _held_for >= _replan_at + CARVE_WAIT)):
		_replan_at = _held_for + REPLAN_EVERY
		_replan(from, on_goal)


## Whether the steering map has caught up with the body at rest at `pos`: it is re-baked on an
## interval, so a body that has just stopped is carved a moment later, and until then the map shows
## no way round it that may well be there. Its centre is then off the map (by more than
## `CARVED_GAP`). True with no steering map to wait for.
func _carved(pos: Vector2) -> bool:
	if not _steering_map.is_valid() or not NavBuilder.ready(_steering_map):
		return true
	return NavBuilder.snap(_steering_map, pos).distance_to(pos) > CARVED_GAP


## The way a walk goes when no body is in it: round the doorway views when it has been given the
## avoid map, else the plain way.
func _free_way() -> int:
	return Way.DOORS if _doors_map.is_valid() else Way.PLAIN


## Keep the walk out of the doorway views (E18) when it is a walk that does (`avoid_doors`): ask the
## perception for the route to the goal (`walk_route`: the plain one unless it goes into a view of a
## doorway into a room not clear for passing and a route round the views is within the cap) and put
## the walk on the avoid map it names, or leave it plain. Asked each frame until it is decided
## (while the avoid map is being baked the walk goes the plain way), then every `DOORS_RECHECK` s
## for a walk that is round the views, which keeps the map alive and follows the views as rooms are
## cleared and their clear lapses. A body in the way still has its way (`_check`): the walk goes
## round it by the steering map or is held, and the guard secures what views that crosses.
func _update_doors(delta: float) -> void:
	if not avoid_doors or views == null:
		_drop_doors()
		return
	if _doors_decided and not _doors_map.is_valid():
		return  # Needs no way round.
	if _doors_decided:
		_doors_in -= delta
		if _doors_in > 0.0:
			return
	_doors_in = DOORS_RECHECK
	_take_route(views.walk_route(_goal, avoid_entering))


## A walk that does not keep out of the doorway views: it forgets the avoid map, and one on it goes
## the plain way.
func _drop_doors() -> void:
	_doors_decided = false
	if _doors_map.is_valid():
		_doors_map = RID()
		if _way == Way.DOORS:
			_set_way(Way.PLAIN)


## Put the walk on the way the perception's `route` (`walk_route`) names: the avoid map round the
## views, or the plain way; while that map is being baked, ask again next frame.
func _take_route(route: Dictionary) -> void:
	if bool(route["doors"]):
		_doors_decided = true
		_doors_map = route["map"]
		if _way == Way.PLAIN or _way == Way.DOORS:
			_set_way(Way.DOORS)
	elif not bool(route["pending"]):
		_doors_decided = true
		_doors_map = RID()
		if _way == Way.DOORS:
			_set_way(Way.PLAIN)
	else:
		_doors_in = 0.0  # The avoid map is being baked: ask again next frame.


## The held walk re-plans: a body standing on the goal sends it to the nearest free spot near the
## destination; any other hold (a body sealing the only way) tells the caller (`take_blocked`), who
## may choose another walk.
func _replan(from: Vector2, on_goal: bool) -> void:
	if on_goal:
		var spot := _free_spot(from)
		if spot != Vector2.INF:
			_goal = spot
			_last_leg = false
			_set_way(_free_way())
			return
	_blocked = true


## Whether the steering map has a way round from `from` to the goal: its route ends at the goal, or
## within `LAST_LEG` of it with the plain way on from there passing no known body at rest (the last
## leg, `_last_stretch`: of `resting`, or with `held_leg`, a held last leg looking again, of every
## known body at rest, so a new last leg is never one the body holding it, or another, stands on),
## and passes no known body at rest (`resting`) closer than `PASS_CLEARANCE`. Nothing goes round
## before both maps have synchronized.
func _goes_round(from: Vector2, resting: Array, held_leg := false) -> bool:
	if (not _steering_map.is_valid()
			or not NavBuilder.ready(_steering_map)
			or not NavBuilder.ready(_plan_map)):
		return false
	var route := NavBuilder.route(_steering_map, from, _goal)
	if route.is_empty():
		return false
	var end: Vector2 = route[route.size() - 1]
	var goal := NavBuilder.snap(_plan_map, _goal)
	if end.distance_to(goal) > BLOCKED_DISTANCE:
		var leg := NavBuilder.route(_plan_map, end, goal)
		var clear_of := _resting(goal, INF) if held_leg else resting
		if (end.distance_to(goal) > LAST_LEG
				or NavBuilder.path_length(leg) > LAST_LEG
				or _first_on(end, leg, 0, clear_of, INF) != Vector2.INF):
			return false
	return _first_on(from, route, 0, resting) == Vector2.INF


## Whether `map` (synchronized) has a route from `from` to the goal that passes no known body at
## rest (`resting`) closer than `PASS_CLEARANCE`, all the way and not only the first `LOOKAHEAD` px:
## a body just past that on the route would be met a few strides on, and the walk would be sent
## round again.
func _clear_on(map: RID, from: Vector2, resting: Array) -> bool:
	if not NavBuilder.ready(map):
		return false
	return _first_on(from, NavBuilder.route(map, from, _goal), 0, resting, INF) == Vector2.INF


## The known bodies at rest within `reach` px of `around` (the one a melee closes on left out), as
## positions.
func _resting(around: Vector2, reach: float) -> Array:
	var out: Array = []
	for b in bodies:
		if int(b.get("id", 0)) == ignore_id:
			continue
		var pos: Vector2 = b["pos"]
		if ((b.get("vel", Vector2.ZERO) as Vector2).length() < REST_SPEED
				and pos.distance_to(around) <= reach):
			out.append(pos)
	return out


## The body of `resting` standing on `point` (within `PASS_CLEARANCE` of it), or INF.
func _taker(resting: Array, point: Vector2) -> Vector2:
	for pos in resting:
		if (pos as Vector2).distance_to(point) < PASS_CLEARANCE:
			return pos
	return Vector2.INF


## The first body of `resting` that the walk from `from` along `path` (from waypoint `index` on, the
## first `reach` px) passes closer than `PASS_CLEARANCE` and closer than the NPC stands to it now
## (one it already touches, and walks away from, does not stop it), or INF.
func _first_on(
	from: Vector2,
	path: PackedVector2Array,
	index: int,
	resting: Array,
	reach := LOOKAHEAD,
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
## px) it first passes `body` closer than `PASS_CLEARANCE` and closer than the NPC stands to it now,
## or INF when it does not.
func _meets_at(
	from: Vector2,
	path: PackedVector2Array,
	index: int,
	body: Vector2,
	reach: float,
) -> float:
	var limit := minf(PASS_CLEARANCE, from.distance_to(body) - 1.0)
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


## The nearest free spot near the walk's destination, for a walk whose destination a body stands on:
## on the nearest of `FREE_SPOT_RINGS` that has one, the spot nearest the NPC that is open floor,
## clear of every known body at rest by `FREE_SPOT_CLEAR` and on the same side of any wall as the
## destination (its walk from there is short). INF when none.
func _free_spot(from: Vector2) -> Vector2:
	var resting := _resting(_walk_dest, float(FREE_SPOT_RINGS[-1]) + FREE_SPOT_CLEAR)
	for ring in FREE_SPOT_RINGS:
		var best := _free_on_ring(ring, from, resting)
		if best != Vector2.INF:
			return best
	return Vector2.INF


## The free spot on the ring `r` px round the walk's destination nearest the NPC at `from` (open
## floor, clear of `resting` by `FREE_SPOT_CLEAR`, a short walk from the destination), or INF.
func _free_on_ring(r: float, from: Vector2, resting: Array) -> Vector2:
	var best := Vector2.INF
	for k in FREE_SPOT_ANGLES:
		var p: Vector2 = _walk_dest + Vector2.from_angle(TAU * k / FREE_SPOT_ANGLES) * r
		var q := NavBuilder.snap(_plan_map, p)
		if q.distance_to(p) > 3.0 or _crowded(resting, q):
			continue
		if best != Vector2.INF and q.distance_to(from) >= best.distance_to(from):
			continue
		if NavBuilder.path_length(NavBuilder.route(_plan_map, _walk_dest, q)) <= r * 1.5:
			best = q
	return best


## Whether a body of `resting` stands closer than `FREE_SPOT_CLEAR` to `q`.
func _crowded(resting: Array, q: Vector2) -> bool:
	for pos in resting:
		if (pos as Vector2).distance_to(q) < FREE_SPOT_CLEAR:
			return true
	return false


## Give way to a walker coming at the NPC (`move_input` already steers its walk): a known character
## in view, not at rest, within `GIVE_RANGE`, whose course comes within `GIVE_CLEARANCE` of the
## NPC's in the next `GIVE_HORIZON` s. Unless it has the right of way (`_has_way`) and the walker is
## not yet on top of it (`GIVE_IMMINENT`), the NPC steps aside off the walker's line when it stands
## on it (open floor, clear of the other bodies it knows of, never toward the walker), else waits,
## until the walker has gone by; at most `GIVE_MAX` s for one walker.
##
## The look-ahead is cut to the time the NPC's own walk still takes (`_way_left` at its pace) when
## that is shorter: its course is reckoned only to the end of its walk, so it never gives way to a
## walker its walk stops short of, as a follower closing on its spot behind a leader walking on.
## Near the end of its walk that short look-ahead holds for every walker, the `GIVE_IMMINENT` stop
## included.
func _give_way() -> void:
	var me: Vector2 = _character.global_position
	var pace := maxf(_character.get_real_velocity().length(), PACE_FLOOR)
	var mine: Vector2 = _character.move_input * pace
	var horizon := minf(GIVE_HORIZON, _way_left() / pace)
	var other := _walker_in_way(me, mine, horizon)
	if other.is_empty():
		_yield_id = 0
		_yield_spot = Vector2.INF
		return
	if int(other["id"]) != _yield_id:
		_yield_id = int(other["id"])
		_yield_spot = Vector2.INF
		_yield_for = 0.0
	_yield_for += get_physics_process_delta_time()
	if _yield_for > GIVE_MAX:
		return
	# With the right of way the NPC only stops for a walker on top of it.
	if not _has_way(other) and _step_aside(me, other):
		return
	_character.move_input = Vector2.ZERO
	_yielding = true


## The nearest walker the NPC at `me` (stepping at `mine` px/s) gives way to: a known character in
## view, not at rest, within `GIVE_RANGE`, whose course comes within `GIVE_CLEARANCE` in `horizon`
## s, and that it has no right of way over (`_has_way`) or that is closer than `GIVE_IMMINENT`. {}
## when none.
func _walker_in_way(me: Vector2, mine: Vector2, horizon: float) -> Dictionary:
	var other := {}
	var nearest := INF
	for b in bodies:
		if not b.get("visible", false) or int(b.get("id", 0)) == ignore_id:
			continue
		var vel: Vector2 = b.get("vel", Vector2.ZERO)
		var gap: Vector2 = (b["pos"] as Vector2) - me
		if vel.length() < REST_SPEED or gap.length() > GIVE_RANGE or gap.length() >= nearest:
			continue
		if not _converging(gap, vel - mine, horizon):
			continue
		if _has_way(b) and gap.length() >= GIVE_IMMINENT:
			continue
		other = b
		nearest = gap.length()
	return other


## Step the NPC at `me` aside off the line of walker `other` when it stands on it (ahead of the
## walker, within `GIVE_CLEARANCE`): toward the spot `_side_step` finds, kept while it stays off the
## walker's line. True when it steps; false when it has no spot to go to, or is there.
func _step_aside(me: Vector2, other: Dictionary) -> bool:
	var at: Vector2 = other["pos"]
	var line: Vector2 = (other["vel"] as Vector2).normalized()
	var rel: Vector2 = me - at
	var off: Vector2 = rel - line * rel.dot(line)
	if not (rel.dot(line) > 0.0 and off.length() < GIVE_CLEARANCE):
		return false
	if _yield_spot != Vector2.INF and not _off_line(_yield_spot, me, at, line):
		_yield_spot = Vector2.INF  # The walker has turned: that spot is on its way now.
	if _yield_spot == Vector2.INF:
		_yield_spot = _side_step(me, at, line, off, int(other["id"]))
	if _yield_spot == Vector2.INF or me.distance_to(_yield_spot) <= 4.0:
		return false
	_character.move_input = (_yield_spot - me).normalized()
	_yielding = true
	return true


## The last word on a step: drop the part of `move_input` that heads into a known body closer than
## `KEEP_OFF` (the one a melee closes on aside), so the NPC slides past it instead; stopped when
## nothing of the step is left. Every walk ends with it, and so does any other step a behaviour
## module takes (`Combat.apply_back_off`).
func keep_off() -> void:
	_kept_off = false
	var step: Vector2 = _character.move_input
	if step == Vector2.ZERO:
		return
	var me: Vector2 = _character.global_position
	for b in bodies:
		if int(b.get("id", 0)) == ignore_id:
			continue
		var gap: Vector2 = (b["pos"] as Vector2) - me
		if gap.length() >= KEEP_OFF or gap.length() < 0.001:
			continue
		var toward := gap.normalized()
		if step.dot(toward) > 0.0:
			step -= toward * step.dot(toward)
	if step.length() < 0.1:
		_character.move_input = Vector2.ZERO
		_kept_off = true
		return
	_character.move_input = step.normalized()


## Whether two bodies `gap` apart (the other minus this one) closing at relative velocity `rel_vel`
## come within `GIVE_CLEARANCE` of each other within `horizon` s.
func _converging(gap: Vector2, rel_vel: Vector2, horizon: float) -> bool:
	var speed2 := rel_vel.length_squared()
	if speed2 < 1.0 or gap.dot(rel_vel) >= 0.0:
		return false
	var t := clampf(-gap.dot(rel_vel) / speed2, 0.0, horizon)
	return (gap + rel_vel * t).length() < GIVE_CLEARANCE


## How far (px) the walk under way still goes: along the agent's path from where the NPC stands to
## its end.
func _way_left() -> float:
	var path: PackedVector2Array = _agent.get_current_navigation_path()
	var idx: int = _agent.get_current_navigation_path_index()
	var here: Vector2 = _character.global_position
	if idx >= path.size():
		return here.distance_to(_goal)
	var left := here.distance_to(path[idx])
	for i in range(idx + 1, path.size()):
		left += path[i - 1].distance_to(path[i])
	return left


## Whether the NPC has the right of way over walker `b`: `b` sees it (it is near, or within `b`'s
## view by its facing) and the NPC's instance id is the lower. Both reckon the same, so of two
## walkers that see each other one gives way; one that does not see the NPC cannot give way to it,
## so the NPC gives way.
func _has_way(b: Dictionary) -> bool:
	var to_me: Vector2 = _character.global_position - (b["pos"] as Vector2)
	var facing: Vector2 = b.get("facing", Vector2.ZERO)
	var sees := (to_me.length() <= SEES_NEAR
			or (facing != Vector2.ZERO and facing.normalized().dot(to_me.normalized()) >= SEES_COS))
	return sees and _character.get_instance_id() < int(b["id"])


## A spot to step aside to, off the line `line` a walker at `at` comes along (the NPC stands `off`
## from it): on the side it already stands on, else the other, far enough to clear it by
## `GIVE_CLEARANCE`, on open floor, clear of every other body it knows of, and not toward the
## walker. INF when there is none (it then waits where it is).
func _side_step(me: Vector2, at: Vector2, line: Vector2, off: Vector2, walker_id: int) -> Vector2:
	var side: Vector2 = off.normalized() if off.length() > 1.0 else line.orthogonal()
	for s in [side, -side]:
		var step: Vector2 = s
		var spot: Vector2 = me + step * (GIVE_CLEARANCE + 6.0 - off.dot(step))
		if not _off_line(spot, me, at, line):
			continue
		if NavBuilder.snap(_plan_map, spot).distance_to(spot) > 3.0:
			continue
		var crowds := func(b):
			return (int(b.get("id", 0)) != walker_id
					and (b["pos"] as Vector2).distance_to(spot) < FREE_SPOT_CLEAR)
		if bodies.any(crowds):
			continue
		return spot
	return Vector2.INF


## Whether stepping from `me` to `spot` gets off the line `line` of a walker at `at` (`spot` clear
## of it by `GIVE_CLEARANCE`, or behind the walker) without heading toward the walker.
func _off_line(spot: Vector2, me: Vector2, at: Vector2, line: Vector2) -> bool:
	var rel := spot - at
	var clear := (rel.dot(line) <= 0.0
			or (rel - line * rel.dot(line)).length() >= GIVE_CLEARANCE - 1.0)
	var heading := (spot - me).normalized().dot((at - me).normalized())
	return clear and heading < 0.3
