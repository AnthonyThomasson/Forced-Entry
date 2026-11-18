extends RefCounted
## AI domain: the SIGHT sense for a goal-driven NPC. Pure, stateless geometry — "can this agent see
## that point right now?" — governed by tunable parameters (field of view, range, a close-range
## 360° awareness bubble, and line of sight). It holds NO policy: it never decides, remembers or
## picks. The perception runs each visible thing through it and deposits what is seen into the
## agent's memory (agent_memory.gd), so the "remember" half lives there; this is only the "see"
## half.
##
## A point is visible when it is (a) within `view_distance`, AND (b) either within
## `awareness_radius` of the agent — a near bubble you sense regardless of which way you face — or
## inside the forward cone of half-angle `fov_degrees / 2` around the agent's facing, AND (c)
## reachable by a clear line. For SIGHT that line is a 3D eye ray (General's `SightRay`, #194 D9):
## from the agent's eye, at the height of its posture (a standing eye looks over a table and a
## sofa, a ducked one does not), to a few points on the target (the head, chest and hips at the
## target's posture), seen if any one is clear. Only what stands in the way at that height blocks
## it: walls, doors, furniture and vehicles; a body is never in the way. Set `enabled` to false to
## make everything visible (omniscient), for debugging.
##
## This is SIGHT-only: `blocked()` / `raycast()` below stay fully physical (every solid collider
## counts) because they serve line-of-fire and cover, where a bullet is still stopped by a table
## even though an agent can see across it.
##
## The sight rays are cast in the twin space (interface 29) of the 2D `space` the callers hand in
## (`TwinSpace.space_for`): a world with no twins blocks nothing (the player's cone is the other
## way: a collider with no twin blocks like a wall). The `exclude` rids the callers hand in are not
## read: a body never blocks an eye ray (they stay in the signatures, which the entry and door-view
## chains share with the line-of-fire code).

## Physics layer walls + solid furniture live on (General's `PhysicsLayers.SOLID`, also used by
## CharacterInteraction). This module is the sub-domain's single owner of the solid-geometry ray
## query: the perception runs its line-of-fire and cover tests through `blocked()` / `raycast()`
## below rather than repeating it.
const AgentCover := preload("res://scenes/ai/perception/agent_cover.gd")
const QUERY_MASK := PhysicsLayers.SOLID
## How many bodies on a round's line `body_in_fire_line` looks through (the welcome ones) before it
## calls the line open.
const BODIES_ON_LINE := 4

## Whether vision is gated at all; false = the agent sees everything (omniscient fallback).
var enabled: bool = true
## Maximum distance (px) at which anything can be seen.
var view_distance: float = 2520.0
## Full angular width (degrees) of the forward view cone, centred on the agent's facing.
var fov_degrees: float = 110.0:
	set(value):
		fov_degrees = value
		_half_fov = deg_to_rad(value) * 0.5
## Radius (px) of the 360° near-awareness bubble: things this close are sensed regardless of facing.
var awareness_radius: float = 48.0
## The character this sense belongs to: whose posture sets the height of its eye. None (a sense a
## stack or a door view holds for the standing person it plans for): a standing eye.
var viewer: Object = null
## Half the view cone's width in radians, kept with `fov_degrees`.
var _half_fov := deg_to_rad(110.0) * 0.5
## The ray every cast reuses: the solid layer, nothing else configured.
var _query := _solid_query()
## The 3D ray every `fire_line_clear` refills.
var _fire_ray := PhysicsRayQueryParameters3D.new()
## What `fire_line_clear` answered this physics frame, by shooter, posture, target and point.
var _memo := {}
var _memo_frame := -1


## A ray query on the solid layer, for `_query` to refill on each cast.
static func _solid_query() -> PhysicsRayQueryParameters2D:
	var q := PhysicsRayQueryParameters2D.new()
	q.collision_mask = QUERY_MASK
	return q


## Whether `point` is visible to an agent at `from_pos` facing `facing`, given a physics space state
## (a body is never an obstacle to sight, so the exclude rids the callers hand in are not read). See
## the class note for the full rule. `space` may be null (treated as an unobstructed line) for
## geometry-only tests.
func can_see(
	from_pos: Vector2,
	facing: Vector2,
	point: Vector2,
	space: PhysicsDirectSpaceState2D,
	_exclude: Array,
) -> bool:
	if not enabled:
		return true
	if not _in_view(from_pos, facing, point):
		return false
	return space == null or _sees(
		space,
		from_pos,
		point,
		BodyHeights.sight_points(BodyHeights.STAND),
		[],
	)


## Whether `point` is inside the geometry of sight (view distance and the near bubble or the forward
## cone), ignoring what stands in the way; true for everything when sight is disabled. A cheap test:
## the cast of `can_see` is the costly half.
func in_view(from_pos: Vector2, facing: Vector2, point: Vector2) -> bool:
	return not enabled or _in_view(from_pos, facing, point)


## The geometry half of sight: `point` is within view distance and either inside the near bubble or
## the forward cone.
func _in_view(from_pos: Vector2, facing: Vector2, point: Vector2) -> bool:
	var to := point - from_pos
	var dist := to.length()
	if dist > view_distance:
		return false
	if dist > awareness_radius:
		# Outside the near bubble: must fall within the forward cone.
		if facing == Vector2.ZERO:
			return false
		if absf(facing.angle_to(to)) > _half_fov:
			return false
	return true


## Whether `node` (a Node2D) is visible — convenience wrapper over can_see using its global
## position, and the points of its own body (a character's at its posture, a piece's middle). The
## node's own twin is left out of the rays (it is the endpoint, so it must not count as something
## blocking the line to it); the line is clear when nothing ELSE is between.
func can_see_node(
	node: Node2D,
	from_pos: Vector2,
	facing: Vector2,
	space: PhysicsDirectSpaceState2D,
	_exclude: Array,
) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not enabled:
		return true
	var point := node.global_position
	if not _in_view(from_pos, facing, point):
		# Out of view whatever stands between: no need to cast.
		return false
	if space == null:
		return true
	return _sees(space, from_pos, point, SightRay.target_heights(node), SightRay.exclude_of(node))


## The first hit that blocks SIGHT along `from`→`to` (plan points, a standing body at `to`), or {}
## when any of its points is seen. The hit is `{ position: Vector2 (plan), height: float (px),
## collider: the 2D body }` of the line to its head. Unlike `blocked() ` (physical: any solid
## collider
## stops it), this is the eye ray of the class note. Ignores `enabled`: it answers what the line
## is, the callers decide whether sight is gated. The `exclude` rids (2D) are not read: a body is no
## obstacle to sight.
func sight_hit(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	to: Vector2,
	_exclude: Array,
) -> Dictionary:
	var twins := TwinSpace.space_for(space)
	if twins == null:
		return {}
	var origin := PlanSpace.lift(from, _eye())
	var first := {}
	for height in BodyHeights.sight_points(BodyHeights.STAND):
		var found := SightRay.hit(twins, origin, PlanSpace.lift(to, height))
		if found.is_empty():
			return {}
		if first.is_empty():
			first = found
	return {
		"position": PlanSpace.plan_of(first["position"]),
		"height": PlanSpace.height_of(first["position"]),
		"collider": TwinSpace.owner_of(first["collider"]),
	}


## Whether the eye at plan point `from` sees any of `heights` over plan point `to`, leaving the
## twin rids `exclude` out of the rays.
func _sees(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	to: Vector2,
	heights: PackedFloat32Array,
	exclude: Array,
) -> bool:
	var twins := TwinSpace.space_for(space)
	return twins == null or SightRay.sees(twins, PlanSpace.lift(from, _eye()), to, heights, exclude)


## The height (px) of this agent's eye: its posture's, a standing one with no viewer.
func _eye() -> float:
	if is_instance_valid(viewer):
		return SightRay.eye_of(viewer)
	return BodyHeights.eye(BodyHeights.STAND)


## Whether the straight segment `from`→`to` hits a wall or solid object on the query layer. A pure
## geometry test — it ignores `enabled`, so line-of-fire and cover stay physical even when sight is
## disabled (vision gates what the agent KNOWS; this gates what a straight line can reach).
func blocked(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2, exclude: Array) -> bool:
	return not raycast(space, from, to, exclude).is_empty()


## Whether `shooter` can fire at `target` (a body, or null for a plain point) standing at plan point
## `to`: the 3D line of a round from its muzzle to where it aims, clear of every wall, door, piece
## and vehicle (a body is no obstacle to sight; a glass pane stops a bullet) and of any living body
## but a `welcome` one (`body_in_fire_line`). The muzzle is that of the posture it fires in: the one
## it is in, or, ducked, the pose its shot would rise to (`CharacterRise.pose_along`, near cover or
## far, so what the AI gates its trigger on and what the body does when it pulls it are one rule,
## `docs/cover-and-stance.md` P6): no pose clears cover too tall to fire over, so none. It aims
## where its shot would, from the eye of the pose it fires in and at `to`, where it last knew the
## target (`SightRay.aim_at`: the middle of the part of it that shows, else of its torso; a plain
## point is a standing body's torso), so a piece the round clears at a standing body's torso may
## stop it at a ducked one's head. A world with no twin space has the plan line (`blocked`) alone.
## Asked again for the same shooter, posture, `welcome` and points in one physics frame (the watch
## and the combat both gate on it), it answers from its memo.
func fire_line_clear(
	shooter: Node2D,
	target: Node2D,
	to: Vector2,
	welcome: Callable = Callable(),
) -> bool:
	var space := TwinSpace.space_of(shooter)
	if space == null:
		var rids := [shooter.get_rid()]
		if target is CollisionObject2D and is_instance_valid(target):
			rids.append((target as CollisionObject2D).get_rid())
		return not blocked(
			shooter.get_world_2d().direct_space_state,
			shooter.global_position,
			to,
			rids,
		)
	var frame := Engine.get_physics_frames()
	if frame != _memo_frame:
		_memo.clear()
		_memo_frame = frame
	var key := [
		shooter.global_position,
		SightRay.posture_of(shooter),
		shooter.movement.posture(),
		welcome,
		target.get_instance_id() if is_instance_valid(target) else 0,
		SightRay.posture_of(target) if is_instance_valid(target) else &"",
		to,
	]
	if not _memo.has(key):
		_memo[key] = _fire_clear(space, shooter, target, to, welcome)
	return _memo[key]


## `fire_line_clear` worked out: the 3D line against the world, then against bodies.
func _fire_clear(
	space: PhysicsDirectSpaceState3D,
	shooter: Node2D,
	target: Node2D,
	to: Vector2,
	welcome: Callable,
) -> bool:
	var line := _fire_line(shooter, target, to)
	if line.is_empty():
		return false  # standing on the point, or no pose clears the cover
	_fire_ray.from = line["from"]
	_fire_ray.to = line["to"]
	_fire_ray.collision_mask = SightRay.MASK
	if not space.intersect_ray(_fire_ray).is_empty():
		return false
	return _body_on(space, line, shooter, target, welcome) == null


## The living body other than `shooter` and `target` a round on `fire_line_clear`'s line would meet
## (a body is no obstacle to sight, but a round hits it: whoever stands in the way holds the shot,
## an ally, a bystander or the human player), null when none; a crouched body under the line is
## shot over. `welcome` (a `Callable(body) -> bool`, none by default) names the bodies the round may
## hit and so do not hold it: the known hostiles.
func body_in_fire_line(
	shooter: Node2D,
	target: Node2D,
	to: Vector2,
	welcome: Callable = Callable(),
) -> Node2D:
	var space := TwinSpace.space_of(shooter)
	var line := _fire_line(shooter, target, to) if space != null else {}
	return _body_on(space, line, shooter, target, welcome) if not line.is_empty() else null


## The first living body on `line` that is not `shooter`, `target` or `welcome`, null for none.
func _body_on(
	space: PhysicsDirectSpaceState3D,
	line: Dictionary,
	shooter: Node2D,
	target: Node2D,
	welcome: Callable,
) -> Node2D:
	_fire_ray.from = line["from"]
	_fire_ray.to = line["to"]
	_fire_ray.collision_mask = PhysicsLayers.TWIN_CHARACTER
	var skip := SightRay.exclude_of(shooter) + SightRay.exclude_of(target)
	var found: Node2D = null
	for _pass in BODIES_ON_LINE:
		_fire_ray.exclude = skip
		var hit := space.intersect_ray(_fire_ray)
		if hit.is_empty():
			return _end_body_ray(null)
		var body := TwinSpace.owner_of(hit["collider"])
		if body == null:
			return _end_body_ray(null)  # A twin whose owner is gone is no body.
		found = body
		if not (welcome.is_valid() and welcome.call(body)):
			return _end_body_ray(body)
		skip = skip + [hit["rid"]]
	return _end_body_ray(found)  # Past the cap every body met was welcome: the last holds the shot.


## Clear the body ray's exclusions and answer `body`.
func _end_body_ray(body: Node2D) -> Node2D:
	_fire_ray.exclude = []
	return body


## The 3D line `shooter`'s round flies to `to`, `{ from, to }` as points of the twin space: from its
## muzzle at the posture it fires in to the height it aims at; {} when it stands on the point or,
## ducked, no pose clears the cover on the way. The pose is the one the shot asks of the rise rule,
## from the aim of the eye it has ducked (`CharacterWeapon.aim_height_from`); the round then flies
## to the aim of the eye of the pose it has risen to, as the shot's does.
func _fire_line(shooter: Node2D, target: Node2D, to: Vector2) -> Dictionary:
	var offset: Vector2 = to - shooter.global_position
	if offset.length() < 1.0:
		return {}
	var run := offset.length()
	var pose: StringName = SightRay.posture_of(shooter)
	var height := _aim_from(shooter, pose, target, to)
	if shooter.movement.posture() == &"crouch":
		var risen: StringName = shooter.weapon.rise.pose_along(offset / run, run, height)
		if risen == BodyHeights.NONE:
			return {}
		if BodyHeights.muzzle(risen) > BodyHeights.muzzle(pose):
			pose = risen
			height = _aim_from(shooter, pose, target, to)
	return {
		"from": PlanSpace.lift(shooter.global_position, BodyHeights.muzzle(pose)),
		"to": PlanSpace.lift(to, height),
	}


## The height (px) `shooter` aims at on `target` standing at `to`, its eye in `pose`: where it last
## knew the target (not where it is), a standing body's torso for a plain point.
func _aim_from(shooter: Node2D, pose: StringName, target: Node2D, to: Vector2) -> float:
	if is_instance_valid(target) and target.get("movement") != null:
		return SightRay.aim_at(shooter, BodyHeights.eye(pose), target, to)
	return BodyHeights.sight_points(BodyHeights.STAND)[1]


## The piece that hides a body ducked at plan point `p` from the eye of a threat at `threat` (`eye`
## px up, a standing body's when negative): the first thing the lines from that eye to the ducked
## body's head, chest and hips meet when each one is stopped, null when any one is clear. The real
## 3D lines, so a sofa hides a ducked head from a threat near it or itself low but not from a
## standing one far off, whose eye looks down over its back, nor from the side of its arm or seat.
## A world with no twin space asks the plan line for a piece tall enough (`AgentCover.is_cover`),
## leaving `exclude` out and looking through the bodies on it.
func hiding_piece(
	space: PhysicsDirectSpaceState2D,
	p: Vector2,
	threat: Vector2,
	eye := -1.0,
	exclude: Array = [],
) -> Object:
	var twins := TwinSpace.space_for(space)
	if twins == null:
		return _plan_piece(space, p, threat, exclude)
	var origin := PlanSpace.lift(threat, eye if eye >= 0.0 else BodyHeights.eye(BodyHeights.STAND))
	var first := {}
	for height in BodyHeights.sight_points(BodyHeights.DUCK):
		var found := SightRay.hit(twins, origin, PlanSpace.lift(p, height))
		if found.is_empty():
			return null
		if first.is_empty():
			first = found
	return TwinSpace.owner_of(first["collider"])


## The first piece tall enough to hide a ducked head on the plan line `p`→`threat`, a living body
## looked through; null when there is none.
func _plan_piece(
	space: PhysicsDirectSpaceState2D,
	p: Vector2,
	threat: Vector2,
	exclude: Array,
) -> Object:
	var skipped := exclude
	while true:
		var hit := raycast(space, p, threat, skipped)
		var obj: Object = hit.get("collider")
		if obj == null:
			return null
		if obj is Node and (obj as Node).is_in_group(&"characters"):
			skipped = skipped + [hit["rid"]]
			continue
		return obj if AgentCover.is_cover(obj) else null
	return null  # unreachable; satisfies the parser


## What stops a round from a body standing at plan point `from` on its way to the one at plan point
## `to` (`target`, or a standing body's for null; `posture` overrides the body's posture, a ducked
## one for the spot an NPC will take cover at): `{ body: the 2D piece, wall, door or vehicle it
## meets }`, {} when it is clear. The 3D line runs from a standing muzzle to the middle of the
## target's torso, or, when a piece stops that, to its head (a head that shows over what hides the
## rest is what an NPC aims at, `SightRay.aim_height`); the stop is the torso line's. The line of
## fire of a spot the NPC could stand at, where no shooter is to ask `fire_line_clear` of: a
## standing muzzle is the highest it fires from, and a ducked body rises as high as it needs
## (`CharacterRise.pose_along`, no reach limit), so what a standing muzzle clears a rise clears
## too (`tests/ai/perception/rise_line_matches_rise`). A body in the way is not looked for: it
## moves, the trigger's gate holds the shot for it. A world with no twin space has the plan line
## (`raycast`) alone.
func fire_stop_from(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	to: Vector2,
	target: Node2D = null,
	posture: StringName = BodyHeights.NONE,
) -> Dictionary:
	var twins := TwinSpace.space_for(space)
	if twins == null:
		return _plan_stop(space, from, to)
	var body_posture := posture
	if body_posture == BodyHeights.NONE:
		body_posture = BodyHeights.STAND
		if target != null and is_instance_valid(target) and target.get("movement") != null:
			body_posture = SightRay.posture_of(target)
	var points := BodyHeights.sight_points(body_posture)
	_fire_ray.from = PlanSpace.lift(from, BodyHeights.muzzle(BodyHeights.STAND))
	_fire_ray.collision_mask = SightRay.MASK
	var stop := {}
	for height: float in [points[1], points[0]]:
		_fire_ray.to = PlanSpace.lift(to, height)
		var found := twins.intersect_ray(_fire_ray)
		if found.is_empty():
			return {}
		if stop.is_empty():
			stop = { "body": TwinSpace.owner_of(found["collider"]) }
	return stop


## What stops a round on the plan line (a world with no twin space) from `from` to `to`: the first
## piece on it, a living body looked through (as the 3D line does), `{ body }` or {}.
func _plan_stop(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> Dictionary:
	var ex: Array = []
	while true:
		var hit := raycast(space, from, to, ex)
		if hit.is_empty():
			return {}
		var body: Object = hit["collider"]
		if body is Node and (body as Node).is_in_group(&"characters"):
			ex = ex + [hit["rid"]]
			continue
		return { "body": body }
	return {}  # unreachable; satisfies the parser


## The first solid hit along `from`→`to` on the query layer, or an empty dict when the line is
## clear. Callers that need the blocking collider itself (e.g. a cover test) use this instead of
## `blocked()`.
func raycast(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	to: Vector2,
	exclude: Array,
) -> Dictionary:
	_query.from = from  # One query object, refilled: a snapshot casts thousands of rays.
	_query.to = to
	_query.exclude = exclude
	return space.intersect_ray(_query)


## The first WALL along `from`→`to` (a static body: furniture, which is a rigid body, and characters
## are looked through), or {} when the line reaches `to`. What bounds a doorway's view
## (`AgentDoorViews.door_view`).
func wall_hit(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> Dictionary:
	var ex: Array = []
	while true:
		var hit := raycast(space, from, to, ex)
		if hit.is_empty() or hit.get("collider") is StaticBody2D:
			return hit
		ex = ex.duplicate()
		ex.append(hit.get("rid"))
	return {}  # unreachable; satisfies the parser
