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
const QUERY_MASK := PhysicsLayers.SOLID

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
