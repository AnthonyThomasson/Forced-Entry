class_name SightRay
extends RefCounted
## General domain: the one sight rule (interface 11, #194 D9), shared by the NPCs' sight
## (`AgentVision`), the player's view (`ViewCone`) and what the view draws (`SeenArea`). Sight is
## geometry, not a rating: what blocks a line of sight is what stands in the way at that height,
## and a body's posture sets the height of its eye and of the points it is seen by.
##
## **An eye ray** (`hit`, `clear`, `visible_heights`, `sees`) is a 3D ray in the twin space
## (`TwinSpace`, interface 29) from a viewer's eye (`BodyHeights.eye` of its posture) to a point on
## the target. A body is seen when the ray to any one of its points (`BodyHeights.sight_points`:
## head, chest, hips at its posture) is clear, tried head first, so the first clear point ends the
## ask. Walls, doors, furniture and vehicles block (the twin layers `MASK`); characters do not (a
## body is seen, not an obstacle, as it always was). A piece whose surface says it is `transparent`
## (a glass-panel door) is looked through however tall. A ray that meets nothing, or a space with
## no twins at all, is clear.
##
## **The plan cone** (`plan_hit`, the `cast` of an instance) is the player's view: the cone is a
## floor-plan polygon, so its rays run level along the plan at the viewer's eye height, 3D rays in
## the twin space: a twin blocks when it stands above that height there, a lower piece is looked
## over, a pane looked through. The same rule at one height as the eye ray's. Line of fire and
## cover are physical and are not this.

## The twin layers a sight ray asks: the world and the vehicles, not the characters.
const MASK := PhysicsLayers.TWIN_WORLD | PhysicsLayers.TWIN_VEHICLE
## The height (px) of what lies on the floor (a grenade, a dropped item): the one point it is
## looked at by.
const GROUND_POINT := 6.0
## How far (px) over `looks_over` the plan cast runs, so a piece exactly as tall as the eye, whose
## top face the ray would lie in, is looked over, and one a hair taller blocks.
const LEVEL_OVER := 0.05

## The caster `plan_hit` borrows for every plain ask.
static var _plain := SightRay.new()
## The 3D ray every eye ask refills.
static var _eye_ray := PhysicsRayQueryParameters3D.new()

## The height (px) at or below which a plan cast looks over a piece (`plan_hit`'s `see_over`: the
## viewer's eye).
var looks_over := 0.0
## The 3D ray every plan cast refills: a view casts hundreds of rays a frame.
var _level := PhysicsRayQueryParameters3D.new()
## The twin rids the cast leaves out as `leave_out` set them.
var _standing: Array[RID] = []


# --- The eye ray: a viewer's eye to points on a target, in the twin space ----------------------


## The first thing that blocks sight along `from` to `to` (3D points, the twin space's; `PlanSpace`
## lifts a plan point and a height), as `intersect_ray`'s dictionary (`collider` a twin, `position`,
## ...), or {} when the line reaches `to`. `exclude` (3D rids: a twin) is looked through, as is a
## `transparent` surface.
static func hit(
	space: PhysicsDirectSpaceState3D,
	from: Vector3,
	to: Vector3,
	exclude: Array = [],
) -> Dictionary:
	_eye_ray.from = from
	_eye_ray.to = to
	_eye_ray.collision_mask = MASK
	var skipped := exclude
	while true:
		_eye_ray.exclude = skipped
		var found := space.intersect_ray(_eye_ray)
		if found.is_empty() or not looks_through(found["collider"]):
			return found
		# A pane: look through it and keep going. The list grows by one twin a pass, so the walk
		# ends (finitely many twins lie on the line).
		skipped = skipped.duplicate()
		skipped.append(found["rid"])
	return {}  # unreachable; satisfies the parser


## Whether the eye at the 3D point `eye` sees any of the points `heights` (px) over plan point `to`;
## the first clear one ends the ask.
static func sees(
	space: PhysicsDirectSpaceState3D,
	eye: Vector3,
	to: Vector2,
	heights: PackedFloat32Array,
	exclude: Array = [],
) -> bool:
	for height in heights:
		if hit(space, eye, PlanSpace.lift(to, height), exclude).is_empty():
			return true
	return false


## Which of the points `heights` (px) over plan point `to` the eye at the 3D point `eye` sees, as
## the subset of `heights`, in order.
static func visible_heights(
	space: PhysicsDirectSpaceState3D,
	eye: Vector3,
	to: Vector2,
	heights: PackedFloat32Array,
	exclude: Array = [],
) -> PackedFloat32Array:
	var seen := PackedFloat32Array()
	for height in heights:
		if hit(space, eye, PlanSpace.lift(to, height), exclude).is_empty():
			seen.append(height)
	return seen


## The posture of `body` (`BodyHeights`): a character's by its stance (read duck-typed from its
## `movement`), a standing one for anything else.
static func posture_of(body: Object) -> StringName:
	var movement: Variant = body.get("movement") if body != null else null
	if movement is Object and (movement as Object).has_method(&"body_posture"):
		return (movement as Object).call(&"body_posture")
	return BodyHeights.STAND


## The height (px) of `viewer`'s eye in its posture.
static func eye_of(viewer: Object) -> float:
	return BodyHeights.eye(posture_of(viewer))


## Where `viewer`'s eye is: its plan position lifted to its eye's height.
static func eye_point(viewer: Node2D) -> Vector3:
	return PlanSpace.lift(viewer.global_position, eye_of(viewer))


## The heights (px) sight looks at over `target`: a character's body points at its posture, a
## piece the middle of its height (its own twin is left out by `exclude_of`), anything else
## (a grenade, a dropped item) the floor's `GROUND_POINT`.
static func target_heights(target: Object) -> PackedFloat32Array:
	if target != null and target.get("movement") != null:
		return BodyHeights.sight_points(posture_of(target))
	var twin := TwinSpace.twin_for(target) if target != null else null
	if twin != null:
		return PackedFloat32Array([0.5 * TwinShapes.top_of(twin)])
	return PackedFloat32Array([GROUND_POINT])


## The twin rids `target`'s own body leaves out of a ray that ends inside it (a piece: the line to
## its middle would stop on its own face), none for anything with no twin.
static func exclude_of(target: Object) -> Array:
	var twin := TwinSpace.twin_for(target) if target != null else null
	if twin is CollisionObject3D:
		return [(twin as CollisionObject3D).get_rid()]
	return []


## The points of `target` (a node) that `viewer`'s eye sees: the heights (px) of the head, chest and
## hips, as many as are clear, at the posture each is in; empty when the target is hidden (a world
## with no twins hides nothing: all the points). The query the aim reads (a shot aims at the middle
## of the part that shows).
static func visible_parts(viewer: Node2D, target: Node2D) -> PackedFloat32Array:
	return parts_at(viewer, eye_of(viewer), target, target.global_position)


## `visible_parts` for `target` taken to stand at plan point `at` (where the viewer last knew it,
## not where it is) and the viewer's eye at the height `eye` px (the posture it will fire in, not
## the one it is in).
static func parts_at(
	viewer: Node2D,
	eye: float,
	target: Node2D,
	at: Vector2,
) -> PackedFloat32Array:
	var heights := target_heights(target)
	var space := TwinSpace.space_of(viewer)
	if space == null:
		return heights
	return visible_heights(
		space, PlanSpace.lift(viewer.global_position, eye), at, heights, exclude_of(target)
	)


## The middle height (px) of what `viewer` sees of `target` (the mean of `visible_parts`), -1 when
## it sees none of it.
static func visible_centre(viewer: Node2D, target: Node2D) -> float:
	return _centre(visible_parts(viewer, target))


## The height (px) `viewer` aims at on `target`: the middle of the part of it that shows
## (`visible_centre`: the head when only the head does), else the middle of its torso at its posture
## (a body no point of which shows: the round meets what hides it). The one aim an NPC's shot and
## its line of fire share (#194 D8).
static func aim_height(viewer: Node2D, target: Node2D) -> float:
	return aim_at(viewer, eye_of(viewer), target, target.global_position)


## `aim_height` for `target` taken to stand at plan point `at` and the viewer's eye at `eye` px: the
## aim of a gate that judges a shot before the body has risen to it, from the last-known point.
static func aim_at(viewer: Node2D, eye: float, target: Node2D, at: Vector2) -> float:
	var centre := _centre(parts_at(viewer, eye, target, at))
	if centre >= 0.0:
		return centre
	return BodyHeights.sight_points(posture_of(target))[1]


## The mean of `heights`, -1 for none.
static func _centre(heights: PackedFloat32Array) -> float:
	if heights.is_empty():
		return -1.0
	var sum := 0.0
	for height in heights:
		sum += height
	return sum / heights.size()


## Whether the surface of the 2D body a twin stands for says it is `transparent`: a pane, which
## sight looks through however tall.
static func looks_through(twin: Object) -> bool:
	var body := TwinSpace.owner_of(twin)
	if body == null or not body.has_method("get_surface"):
		return false
	return bool((body.get_surface() as Dictionary).get("transparent", false))


# --- The plan cone: the player's view, a floor-plan polygon -------------------------------------


## The first twin on the plan line `from` to `to`, level at `see_over` (the eye's height, px),
## that blocks sight, or {} when the line reaches `to`: `{ position: plan point, collider: the 2D
## body the twin stands for (null for a twin with none), twin: the twin, collider_id: the twin's
## instance id, shape: the index of the twin's shape it struck, rid: the twin's rid }`. Anything
## standing above `see_over` there blocks (a wall, a tall piece, a door; a doorway's lintel is over
## the eye), what is lower is looked over, a `transparent` surface and a character are looked
## through. `exclude` (3D rids) is left as the caller gave it.
static func plan_hit(
	space: PhysicsDirectSpaceState3D,
	from: Vector2,
	to: Vector2,
	exclude: Array,
	see_over: float,
) -> Dictionary:
	_plain.looks_over = see_over
	_plain.leave_out(exclude)
	return _plain.cast(space, from, to)


## Leave the twins `rids` out of every cast that follows, until the next call. A caster that casts
## many rays past the same twins sets them once here. `rids` must not change while it stands.
func leave_out(rids: Array) -> void:
	_standing.clear()
	for rid: Variant in rids:
		_standing.append(rid)


## `plan_hit` from `from` to `to`, leaving out what `leave_out` named, looking over what is at or
## below `looks_over`.
func cast(space: PhysicsDirectSpaceState3D, from: Vector2, to: Vector2) -> Dictionary:
	_level.from = PlanSpace.lift(from, looks_over + LEVEL_OVER)
	_level.to = PlanSpace.lift(to, looks_over + LEVEL_OVER)
	_level.collision_mask = MASK
	var skipped := _standing
	var copied := false
	while true:
		_level.exclude = skipped
		var found := space.intersect_ray(_level)
		if found.is_empty():
			return found
		if not looks_through(found["collider"]):
			return {
				"position": PlanSpace.plan_of(found["position"]),
				"collider": TwinSpace.owner_of(found["collider"]),
				"twin": found["collider"],
				"collider_id": found["collider_id"],
				"shape": found["shape"],
				"rid": found["rid"],
			}
		# A pane: look through it and keep going. The list grows by one twin a pass, so the walk
		# ends (finitely many twins lie on the line).
		if not copied:
			skipped = _standing.duplicate()
			copied = true
		skipped.append(found["rid"])
	return {}  # unreachable; satisfies the parser


## The height (px above the floor) a 2D collider stands to for sight: the top of its twin
## (`TwinShapes.top_of`: a wall 96, a table 31, a wardrobe 90 or more). A `transparent` surface (a
## glass-panel door) and a character (looked over, as it always was: a body does not hide what lies
## behind it) stand to 0. A collider with no twin, or none that can say, blocks like a wall:
## `INF`.
static func top_of(collider: Object) -> float:
	if collider == null:
		return INF
	if collider.get("movement") != null:
		return 0.0
	if collider.has_method("get_surface"):
		var surface: Dictionary = collider.get_surface()
		if bool(surface.get("transparent", false)):
			return 0.0
	var twin := TwinSpace.twin_for(collider)
	return TwinShapes.top_of(twin) if twin != null else INF
