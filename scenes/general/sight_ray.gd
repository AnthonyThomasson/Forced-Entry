class_name SightRay
extends RefCounted
## General domain: the one sight rule (interface 11), shared by the
## NPCs' sight (`AgentVision.sight_hit`) and the player's view (`ViewCone`). A standing eye looks
## OVER low furniture: the line is walked on `PhysicsLayers.SOLID`, skipping each collider whose
## `coverage` (the Objects height proxy, 0 to 100, read through the hittable contract's
## `get_surface()`) is at or below `see_over` and casting again past it, until it reaches its end or
## meets something taller (a wall, which rates 100, or tall furniture). A surface that says it is
## `transparent` (a glass-panel door) is looked through however tall. A collider that cannot say
## its coverage blocks like a wall, so sight never leaks past it. Line of fire and cover stay
## physical, they are not this.

## The caster `hit` borrows for every plain ask.
static var _plain := SightRay.new()

## The coverage at or below which a cast looks over a piece (`hit`'s `see_over`).
var looks_over := 60.0
## The coverage this caster already knows by collider instance id, for a caller that casts many rays
## over the same colliders: a collider in it is not asked again (`get_surface` builds a dictionary
## on each ask). It holds only colliders whose coverage cannot change while it is kept; the caller
## owns it.
var rated := {}
## The ray every cast refills: a view casts hundreds of rays a frame.
var _query := _solid_query()
## The rids the query leaves out as `leave_out` set them, and whether a cast has added to them.
var _standing: Array = []
var _extended := false


## The first hit along `from` to `to` that blocks sight (`intersect_ray`'s dictionary: `collider`,
## `rid`, `position`, `shape`, ...), or {} when the line reaches `to`. `exclude` (rids) is left as
## the caller gave it; `see_over` is the coverage at or below which a piece is looked over.
static func hit(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	to: Vector2,
	exclude: Array,
	see_over: float,
) -> Dictionary:
	_plain.looks_over = see_over
	_plain.leave_out(exclude)
	return _plain._walk(space, from, to)


## Leave the colliders `rids` out of every cast that follows, until the next call. A caster that
## casts many rays past the same colliders sets them once here and casts with `cast`, which does
## not hand the list to the physics server again on each ray. `rids` must not change while it
## stands.
func leave_out(rids: Array) -> void:
	_standing = rids
	_query.exclude = rids
	_extended = false


## `hit` from `from` to `to`, leaving out what `leave_out` named, looking over what `looks_over`
## says, asking `rated` before a collider.
func cast(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> Dictionary:
	var found := _walk(space, from, to)
	if _extended:
		_query.exclude = _standing
		_extended = false
	return found


## The walk of the sight rule: cast, and while the first hit is a piece to look over, cast again
## with it left out.
func _walk(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> Dictionary:
	var skipped := _standing
	_query.from = from
	_query.to = to
	while true:
		var found := space.intersect_ray(_query)
		if found.is_empty():
			return found
		var covers: float = rated.get(found["collider_id"], -1.0)
		if covers < 0.0:
			covers = coverage_of(found["collider"])
		if covers > looks_over:
			return found
		# Low cover: look over it and keep going past it. The list grows by one collider a pass,
		# so the walk ends (finitely many colliders lie on the line).
		if not _extended:
			skipped = _standing.duplicate()
			_extended = true
		skipped.append(found.get("rid"))
		_query.exclude = skipped
	return {}  # unreachable; satisfies the parser


## The coverage (0 to 100) sight reads off a ray-hit collider, through the hittable contract. A
## surface that says it is `transparent` (a glass-panel door) reads 0: it is looked through however
## tall. One that cannot say (no `get_surface`, or no `coverage` in it) is 100, a full blocker.
static func coverage_of(collider: Object) -> float:
	if collider == null or not collider.has_method("get_surface"):
		return 100.0
	var surface: Dictionary = collider.get_surface()
	if bool(surface.get("transparent", false)):
		return 0.0
	return float(surface.get("coverage", 100.0))


## A ray query on the solid layer, for a caster to refill on each cast.
static func _solid_query() -> PhysicsRayQueryParameters2D:
	var query := PhysicsRayQueryParameters2D.new()
	query.collision_mask = PhysicsLayers.SOLID
	return query
