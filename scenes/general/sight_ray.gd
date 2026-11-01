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
		if found.is_empty() or _blocks(found.get("collider"), see_over):
			return found
		# Low cover: look over it and keep going past it. The list grows by one collider a pass,
		# so the walk ends (finitely many colliders lie on the line).
		if not copied:
			skipped = exclude.duplicate()
			copied = true
		skipped.append(found.get("rid"))
	return {}  # unreachable; satisfies the parser


## Whether a ray-hit collider stops sight, read once through the hittable contract: its coverage
## (0 to 100) is above `see_over` and its surface is not `transparent` (a glass-panel door's). One
## that cannot say (no `get_surface`; no `coverage` in it rates 100) blocks like a wall.
static func _blocks(collider: Object, see_over: float) -> bool:
	if collider == null or not collider.has_method("get_surface"):
		return true
	var surface: Dictionary = collider.get_surface()
	return (
		float(surface.get("coverage", 100.0)) > see_over
		and not bool(surface.get("transparent", false))
	)


## A ray query on the solid layer, for `_query` to refill on each cast.
static func _solid_query() -> PhysicsRayQueryParameters2D:
	var query := PhysicsRayQueryParameters2D.new()
	query.collision_mask = PhysicsLayers.SOLID
	return query
