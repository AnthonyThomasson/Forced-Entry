extends RefCounted
## AI BEHAVIOUR sub-domain — LOCOMOTION's give way, its part `give_way`: two walkers coming at each
## other do not collide, one gives way (`apply`); whatever the walk, the NPC never steers into a
## known body (`keep_off`); and a walk whose destination a body stands on finds a free spot near it
## (`free_spot`). Built once with its Locomotion, it holds it (a node, so no reference cycle) for
## the body, the walk under way and the bodies its `crowd` knows of.

## Whatever the walk, the NPC never steers into a known body closer than this (px, centre to
## centre): the part of its steering toward the body is dropped and it slides past (`keep_off`). The
## agent cuts a path's corners by up to its `path_desired_distance`, which can bring a walk round a
## body a few px inside the route.
const KEEP_OFF := 36.0
## A free spot near a taken destination: rings this far out from it (px), sampled at
## `FREE_SPOT_ANGLES` angles, the nearest ring first; a spot must stand this far (px) from every
## body at rest (outside its hole, with room to spare).
const FREE_SPOT_RINGS := [44.0, 56.0, 68.0, 80.0, 96.0]
const FREE_SPOT_ANGLES := 12
const FREE_SPOT_CLEAR := 40.0
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

## The Locomotion it belongs to.
var loco: Node
## The walker the NPC is giving way to (instance id; 0 = none).
var yield_id := 0
## `keep_off` stopped the walk this frame (a body on every side it would go).
var kept_off := false
## `apply` stopped the walk or turned it aside this frame.
var yielding := false
## Where it steps aside to while giving way (INF: it waits where it is).
var _yield_spot := Vector2.INF
## Seconds it has been giving way to that walker.
var _yield_for := 0.0


func _init(locomotion: Node) -> void:
	loco = locomotion


## Give way to a walker coming at the NPC (`movement.move_input` already steers its walk): a known
## character in view, not at rest, within `GIVE_RANGE`, whose course comes within `GIVE_CLEARANCE`
## of the NPC's in the next `GIVE_HORIZON` s. Unless it has the right of way (`_has_way`) and the
## walker is not yet on top of it (`GIVE_IMMINENT`), the NPC steps aside off the walker's line when
## it stands on it (open floor, clear of the other bodies it knows of, never toward the walker),
## else waits, until the walker has gone by; at most `GIVE_MAX` s for one walker.
##
## The look-ahead is cut to the time the NPC's own walk still takes (`_way_left` at its pace) when
## that is shorter: its course is reckoned only to the end of its walk, so it never gives way to a
## walker its walk stops short of, as a follower closing on its spot behind a leader walking on.
## Near the end of its walk that short look-ahead holds for every walker, the `GIVE_IMMINENT` stop
## included.
func apply() -> void:
	var character: Node = loco._character
	var me: Vector2 = character.global_position
	var pace := maxf(character.get_real_velocity().length(), PACE_FLOOR)
	var mine: Vector2 = character.movement.move_input * pace
	var horizon := minf(GIVE_HORIZON, _way_left() / pace)
	var other := _walker_in_way(me, mine, horizon)
	if other.is_empty():
		yield_id = 0
		_yield_spot = Vector2.INF
		return
	if int(other["id"]) != yield_id:
		yield_id = int(other["id"])
		_yield_spot = Vector2.INF
		_yield_for = 0.0
	_yield_for += loco.get_physics_process_delta_time()
	if _yield_for > GIVE_MAX:
		return
	# With the right of way the NPC only stops for a walker on top of it.
	if not _has_way(other) and _step_aside(me, other):
		return
	character.movement.move_input = Vector2.ZERO
	yielding = true


## The last word on a step: drop the part of `movement.move_input` that heads into a known body
## closer than `KEEP_OFF` (the one a melee closes on aside), so the NPC slides past it instead;
## stopped when nothing of the step is left. Every walk ends with it, and so does any other step a
## behaviour module takes (`Combat.apply_back_off`).
func keep_off() -> void:
	kept_off = false
	var character: Node = loco._character
	var step: Vector2 = character.movement.move_input
	if step == Vector2.ZERO:
		return
	var me: Vector2 = character.global_position
	for b in loco.crowd.bodies:
		if int(b.get("id", 0)) == loco.crowd.ignore_id:
			continue
		var gap: Vector2 = (b["pos"] as Vector2) - me
		if gap.length() >= KEEP_OFF or gap.length() < 0.001:
			continue
		var toward := gap.normalized()
		if step.dot(toward) > 0.0:
			step -= toward * step.dot(toward)
	if step.length() < 0.1:
		character.movement.move_input = Vector2.ZERO
		kept_off = true
		return
	character.movement.move_input = step.normalized()


## The nearest free spot near the walk's destination, for a walk whose destination a body stands on:
## on the nearest of `FREE_SPOT_RINGS` that has one, the spot nearest the NPC that is open floor,
## clear of every known body at rest by `FREE_SPOT_CLEAR` and on the same side of any wall as the
## destination (its walk from there is short). INF when none.
func free_spot(from: Vector2) -> Vector2:
	var resting: Array = loco.crowd.at_rest(
		loco._walk_dest, float(FREE_SPOT_RINGS[-1]) + FREE_SPOT_CLEAR,
	)
	for ring in FREE_SPOT_RINGS:
		var best := _free_on_ring(ring, from, resting)
		if best != Vector2.INF:
			return best
	return Vector2.INF


## The free spot on the ring `r` px round the walk's destination nearest the NPC at `from` (open
## floor, clear of `resting` by `FREE_SPOT_CLEAR`, a short walk from the destination), or INF.
func _free_on_ring(r: float, from: Vector2, resting: Array) -> Vector2:
	var dest: Vector2 = loco._walk_dest
	var plan_map: RID = loco._plan_map
	var best := Vector2.INF
	for k in FREE_SPOT_ANGLES:
		var p: Vector2 = dest + Vector2.from_angle(TAU * k / FREE_SPOT_ANGLES) * r
		var q := NavBuilder.snap(plan_map, p)
		if q.distance_to(p) > 3.0 or _crowded(resting, q):
			continue
		if best != Vector2.INF and q.distance_to(from) >= best.distance_to(from):
			continue
		if NavBuilder.path_length(NavBuilder.route(plan_map, dest, q)) <= r * 1.5:
			best = q
	return best


## Whether a body of `resting` stands closer than `FREE_SPOT_CLEAR` to `q`.
func _crowded(resting: Array, q: Vector2) -> bool:
	for pos in resting:
		if (pos as Vector2).distance_to(q) < FREE_SPOT_CLEAR:
			return true
	return false


## The nearest walker the NPC at `me` (stepping at `mine` px/s) gives way to: a known character in
## view, not at rest, within `GIVE_RANGE`, whose course comes within `GIVE_CLEARANCE` in `horizon`
## s, and that it has no right of way over (`_has_way`) or that is closer than `GIVE_IMMINENT`. {}
## when none.
func _walker_in_way(me: Vector2, mine: Vector2, horizon: float) -> Dictionary:
	var other := {}
	var nearest := INF
	for b in loco.crowd.bodies:
		if not b.get("visible", false) or int(b.get("id", 0)) == loco.crowd.ignore_id:
			continue
		var vel: Vector2 = b.get("vel", Vector2.ZERO)
		var gap: Vector2 = (b["pos"] as Vector2) - me
		if vel.length() < loco.REST_SPEED or gap.length() > GIVE_RANGE or gap.length() >= nearest:
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
	loco._character.movement.move_input = (_yield_spot - me).normalized()
	yielding = true
	return true


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
	var agent: NavigationAgent2D = loco._agent
	var path: PackedVector2Array = agent.get_current_navigation_path()
	var idx: int = agent.get_current_navigation_path_index()
	var here: Vector2 = loco._character.global_position
	if idx >= path.size():
		return here.distance_to(loco._goal)
	var left := here.distance_to(path[idx])
	for i in range(idx + 1, path.size()):
		left += path[i - 1].distance_to(path[i])
	return left


## Whether the NPC has the right of way over walker `b`: `b` sees it (it is near, or within `b`'s
## view by its facing) and the NPC's instance id is the lower. Both reckon the same, so of two
## walkers that see each other one gives way; one that does not see the NPC cannot give way to it,
## so the NPC gives way.
func _has_way(b: Dictionary) -> bool:
	var character: Node = loco._character
	var to_me: Vector2 = character.global_position - (b["pos"] as Vector2)
	var facing: Vector2 = b.get("facing", Vector2.ZERO)
	var sees := (to_me.length() <= SEES_NEAR
			or (facing != Vector2.ZERO and facing.normalized().dot(to_me.normalized()) >= SEES_COS))
	return sees and character.get_instance_id() < int(b["id"])


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
		if NavBuilder.snap(loco._plan_map, spot).distance_to(spot) > 3.0:
			continue
		var crowds := func(b):
			return (int(b.get("id", 0)) != walker_id
					and (b["pos"] as Vector2).distance_to(spot) < FREE_SPOT_CLEAR)
		if loco.crowd.bodies.any(crowds):
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
