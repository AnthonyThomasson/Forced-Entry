extends RefCounted
## AI PERCEPTION sub-domain — THROW SPOTS: where to throw a grenade from when it cannot be thrown
## from where the NPC stands (docs/grenades.md G17), a typed component of `AgentTactics`
## (`tactics.throws`). It holds the sampling's one setting (`spot_walk`) and nothing else: every
## method takes the geometry it reads, the `tactics` facade, as its first parameter at the call and
## never keeps it (the facade owns this part), and reads the physics space, the navmesh and the
## snapshot's cache through it. It returns DATA only and never decides. The existence search runs in
## steps (`scan_step`, the state is `ThrowScan`'s); the chosen spot is `throw_spot`.

const ThrowScan := preload("res://scenes/ai/perception/throw_scan.gd")
## Rings (px from the NPC, and shares of the throw reach from the burst spot) and directions the
## throw spots are sampled on, and the most candidates routed per call.
const RINGS := [48.0, 96.0, 144.0, 192.0, 240.0]
const REACH_SHARES := [0.95, 0.8]
const DIRECTIONS := 16
const ROUTES := ThrowScan.ROUTES

## Longest walk (px of route) to a throw spot (the perception's `apply_config` sets it).
var spot_walk: float


## How a throw spot ranks (lower first): hidden from the burst spot, then covered against it, then
## in the open.
static func rank(c: Dictionary) -> int:
	return 0 if c["hidden"] else (1 if c["cover"] != "" else 2)


## Where to throw a grenade onto `aim.spot` from when it cannot be thrown from where the NPC stands
## (out of range, or no clear lob: docs/grenades.md G17): a point on the navmesh within `aim.reach`
## of the spot from which `aim.lob` holds (the lob from there is clear), a walk of at most
## `spot_walk` along a route that passes no known hostile, and not inside the rect
## `aim.keep_out` (the room the hostile holds, which the NPC is outside of; an empty rect for none).
## `aim.route` is the walk there as the NPC would walk it and whether it would be stopped on the way
## to go into or secure a doorway (the entry guard, E9 / E15 / E18); invalid, the plain route, no
## detour. Chosen as the fire spots are, and so that the walk needs no detour: one that needs none
## first, then out of the line from the spot (low furniture between: hidden from whoever is there),
## then with cover close by against it (a doorway's jamb, a piece), then the shortest walk.
## `{ point, route_len, hidden, cover, detour }`, or {} when there is none. `points` are the
## candidates (`candidates`, which the snapshot's throws keep once per decision).
func throw_spot(
	tactics: RefCounted, ctx: Dictionary, aim: ThrowAim, ex: Array, points: Array
) -> Dictionary:
	var ranked: Array = _ranked(tactics, ctx, aim, ex, points)
	var walkable := _walkable(tactics, ctx, ranked.slice(0, ROUTES), aim.route)
	if walkable.is_empty():
		return {}
	walkable.sort_custom(func(a, b):
		if a["detour"] != b["detour"]:
			return not a["detour"]
		if rank(a) != rank(b):
			return rank(a) < rank(b)
		return a["route_len"] < b["route_len"])
	return walkable[0]


## One step of a throw-spot existence search (`ThrowScan` holds its state): whether `throw_spot`
## would find a spot, without choosing it. A step is a block of at most `block` raw candidates
## through the cheap tests, the rank pass (when more than `ROUTES` passed), or one route; the
## first `ROUTES` by rank are routed, and the search stops at the first the walk reaches.
func scan_step(tactics: RefCounted, scan: ThrowScan, block: int) -> void:
	match scan.kind:
		ThrowScan.Kind.BLOCK:
			if not scan.raw_made:
				scan.raw = raw(scan.ctx["self_pos"], scan.aim)
				scan.raw_made = true
			var end := mini(scan.cursor + maxi(1, block), scan.raw.size())
			for r: Vector2 in scan.raw.slice(scan.cursor, end):
				_candidate(tactics, scan, r)
			scan.cursor = end
			if end >= scan.raw.size():
				scan.blocks_done()
		ThrowScan.Kind.RANK:
			var ranked := _ranked(tactics, scan.ctx, scan.aim, scan.exclude, scan.points)
			scan.ranked(ranked.slice(0, ROUTES))
		ThrowScan.Kind.ROUTE:
			var point: Vector2 = scan.routed[scan.leg]["point"]
			var leg: Dictionary = tactics.walk_leg(scan.ctx, point, scan.aim.route, spot_walk)
			scan.routed_one(not leg.is_empty())


## The candidate throw spots for `aim` (`points`), each `{ point, hidden, cover }` (hidden from the
## burst spot, else the cover close by against it), sorted by `rank`, then the straight distance.
func found(tactics: RefCounted, ctx: Dictionary, aim: ThrowAim, ex: Array) -> Array:
	return _ranked(tactics, ctx, aim, ex, candidates(tactics, ctx, aim))


## The candidate throw spots for `aim` that pass the cheap tests (`_candidate`), in the order
## found: one scan step over every raw candidate.
func candidates(tactics: RefCounted, ctx: Dictionary, aim: ThrowAim) -> Array:
	var scan := ThrowScan.new(tactics, ctx, aim, [])
	scan.step(ThrowScan.WHOLE)
	return scan.points


## The raw candidates for a throw spot, unsnapped: the `RINGS` round the NPC at `self_pos` out to
## `spot_walk`, then the rings round the aim's spot at each of `REACH_SHARES` of its reach,
## `DIRECTIONS` points each.
func raw(self_pos: Vector2, aim: ThrowAim) -> Array:
	var out: Array = []
	for radius: float in RINGS:
		if radius > spot_walk:
			break
		for i in DIRECTIONS:
			out.append(self_pos + Vector2.RIGHT.rotated(TAU * i / DIRECTIONS) * radius)
	for share: float in REACH_SHARES:
		for i in DIRECTIONS:
			out.append(aim.spot + Vector2.RIGHT.rotated(TAU * i / DIRECTIONS) * aim.reach * share)
	return out


## Raw candidate `r` on the navmesh, or `Vector2.INF` when it fails the cheap tests: past the walk
## or past the reach even once snapped (no navmesh query then), pulled more than the facade's
## `SNAP_TOLERANCE` by the snap, past the reach of the aim's spot, within a `STRIDE` of the NPC, or
## inside the room to keep out of.
func on_navmesh(tactics: RefCounted, ctx: Dictionary, r: Vector2, aim: ThrowAim) -> Vector2:
	var self_pos: Vector2 = ctx["self_pos"]
	var tolerance: float = tactics.SNAP_TOLERANCE
	if self_pos.distance_to(r) > spot_walk or r.distance_to(aim.spot) > aim.reach + tolerance:
		return Vector2.INF
	var p: Vector2 = tactics.snap(ctx, r)
	if (p.distance_to(r) > tolerance
			or p.distance_to(aim.spot) > aim.reach
			or self_pos.distance_to(p) < tactics.STRIDE):
		return Vector2.INF
	if aim.keep_out.has_area() and aim.keep_out.has_point(p):
		return Vector2.INF
	return p


## Raw candidate `r` of `scan` through the cheap tests: onto the navmesh (`on_navmesh`), not one
## already tried, not within 12 px of a point already found, and the lob; qualifying, it joins
## `scan.points`.
func _candidate(tactics: RefCounted, scan: ThrowScan, r: Vector2) -> void:
	var p := on_navmesh(tactics, scan.ctx, r, scan.aim)
	if p == Vector2.INF or scan.tried.has(p):
		return
	scan.tried[p] = true
	if (scan.points.any(func(q): return (q as Vector2).distance_to(p) < 12.0)
			or not scan.aim.lob.call(p)):
		return
	scan.points.append(p)


## `spots` annotated (`{ point, hidden, cover }`) and sorted by `rank`, then the straight
## distance from the NPC.
func _ranked(
	tactics: RefCounted, ctx: Dictionary, aim: ThrowAim, ex: Array, spots: Array
) -> Array:
	var self_pos: Vector2 = ctx["self_pos"]
	var out: Array = []
	for p: Vector2 in spots:
		var hidden: bool = tactics.blocked(ctx["space"], aim.spot, p, ex)
		out.append({
			"point": p,
			"hidden": hidden,
			"cover": "" if hidden else tactics.cover_cached(ctx, p, aim.spot, ex),
		})
	out.sort_custom(func(a, b):
		var ra := rank(a)
		var rb := rank(b)
		if ra != rb:
			return ra < rb
		return self_pos.distance_squared_to(a["point"]) < self_pos.distance_squared_to(b["point"]))
	return out


## Of the throw spots `ranked`, those the walk there reaches (its end within 12 px of the spot), at
## most `spot_walk` long and passing no known hostile, each with its `route_len` and `detour`.
## The walk is `route` (`{ path, len, detour }`), else the plain route with no detour.
func _walkable(
	tactics: RefCounted, ctx: Dictionary, ranked: Array, route: Callable
) -> Array:
	var walkable: Array = []
	for c: Dictionary in ranked:
		var leg: Dictionary = tactics.walk_leg(ctx, c["point"], route, spot_walk)
		if not leg.is_empty():
			walkable.append(c.merged(leg))
	return walkable
