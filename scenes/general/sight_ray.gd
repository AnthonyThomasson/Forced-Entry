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

## The ray every cast refills: a view casts hundreds of rays a frame.
static var _query := _solid_query()


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
	var skipped := exclude
	var copied := false
	while true:
		_query.from = from
		_query.to = to
		_query.exclude = skipped
		var found := space.intersect_ray(_query)
		if found.is_empty() or coverage_of(found.get("collider")) > see_over:
			return found
		# Low cover: look over it and keep going past it. The list grows by one collider a pass,
		# so the walk ends (finitely many colliders lie on the line).
		if not copied:
			skipped = exclude.duplicate()
			copied = true
		skipped.append(found.get("rid"))
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


## A ray query on the solid layer, for `_query` to refill on each cast.
static func _solid_query() -> PhysicsRayQueryParameters2D:
	var query := PhysicsRayQueryParameters2D.new()
	query.collision_mask = PhysicsLayers.SOLID
	return query
