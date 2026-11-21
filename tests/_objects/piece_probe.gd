extends RefCounted
## Helper of the free-furniture tests (#194 furn3d): reads a piece's 3D body (the truth once the
## twin space has taken the piece over: interface 29) and what became of it, in terms a test can
## state from the world alone (how far the piece leans, how high its top is, whether it sleeps).


## The free 3D body of `piece`, or null when it has none (a piece with no twin space, or a static
## one).
static func body(piece: Node) -> RigidBody3D:
	return TwinSpace.twin_for(piece) as RigidBody3D


## How far (degrees) the piece's up axis leans from the world's up: 0 upright, 90 lying on a side.
static func lean(piece: Node) -> float:
	var lead := body(piece)
	return rad_to_deg(acos(clampf(lead.global_transform.basis.y.y, -1.0, 1.0))) if lead else 0.0


## The plan point under the piece's centre of mass now: where a piece lying on its side is (its
## origin, the 2D body's, stays where its foot was).
static func middle(piece: Node) -> Vector2:
	var lead := body(piece)
	return PlanSpace.plan_of(lead.global_transform * lead.center_of_mass)


## The height (px) of the piece's centre of mass now.
static func centre(piece: Node) -> float:
	return body(piece).centre_height()


## Whether the piece's 3D body is asleep.
static func asleep(piece: Node) -> bool:
	var lead := body(piece)
	return lead != null and lead.sleeping


## The height (px) of the highest point of the piece's 3D shapes now (its top, tipped or not).
static func top(piece: Node) -> float:
	var lead := body(piece)
	var best := -INF
	for child in lead.get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		var box := holder.shape as BoxShape3D
		if box == null:
			continue
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var corner := Vector3(box.size.x * sx, box.size.y * sy, box.size.z * sz) * 0.5
					var world := lead.global_transform * (holder.transform * corner)
					best = maxf(best, world.y / RenderConfig.unit)
	return best


## Wait until the piece's 3D body sleeps (or `timeout` sim s pass): true if it did.
static func settle(t: TestContext, piece: Node, timeout: float) -> bool:
	return await t.until(func() -> bool: return asleep(piece), timeout)


## The ray flown level at `height` px from plan point `from` to plan point `to` through the twin
## space: the hit's `position`, `collider` and `owner` (the 2D body the collider stands for), {} for
## none.
static func ray_level(t: TestContext, from: Vector2, to: Vector2, height: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		PlanSpace.lift(from, height), PlanSpace.lift(to, height), PhysicsLayers.TWIN_ALL
	)
	var space: PhysicsDirectSpaceState3D = t.world.twin_space().space()
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		hit["owner"] = TwinSpace.owner_of(hit["collider"])
	return hit


## The plan point inside `rect` (10 px grid, 50 px in from its edges) farthest from every piece of
## the world but those in `skip`, by the gap from its middle to the piece's bounding circle: a spot
## a free piece set there touches nothing (a room's middle may hold a bed, and a piece set on one
## is settled clear of it and leans on it).
static func clear_spot(t: TestContext, rect: Rect2, skip: Array = []) -> Vector2:
	var best := rect.get_center()
	var best_gap := -INF
	var pieces := t.world.get_tree().get_nodes_in_group(TwinSpace.PIECES)
	var x := rect.position.x + 50.0
	while x < rect.end.x - 50.0:
		var y := rect.position.y + 50.0
		while y < rect.end.y - 50.0:
			var gap := INF
			for piece: Node2D in pieces:
				if skip.has(piece):
					continue
				var size: Vector2 = piece.get(&"size")
				var reach := maxf(size.x, size.y) * 0.5
				gap = minf(gap, piece.global_position.distance_to(Vector2(x, y)) - reach)
			if gap > best_gap:
				best_gap = gap
				best = Vector2(x, y)
			y += 10.0
		x += 10.0
	return best
