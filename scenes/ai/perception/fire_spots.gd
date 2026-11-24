extends RefCounted
## AI PERCEPTION sub-domain — FIRE SPOTS: where to fight a hostile from (`tactics.fire_spots`), a
## typed component of `AgentTactics` (`agent_tactics.gd`, moved out of it to keep it under the line
## cap). It holds nothing: every method takes the geometry it reads, the `tactics` facade, as its
## first parameter at the call and never keeps it (the facade owns this part), and reads the physics
## space, the navmesh, the cover and route judgements and the snapshot's cache through it. It
## returns DATA only and never decides.

const AgentCover := preload("res://scenes/ai/perception/agent_cover.gd")


## Where to fight `target` from: `here` (this spot, when it has a clear shot in range), firing
## `spots` spread around the target, and an `ambush` spot in cover. Spot candidates come from rings
## around the NPC (`combat_ring_radius`, ×2) and around the target (each of `fire_spot_distances`);
## each must have a clear shot in range and pass `_safe_spot`, and the best is kept per 8-way sector
## around the target (cover close by first, then the shortest step). `here` is never screened:
## staying put is not a move.
func fire_positions(tactics: RefCounted, ctx: Dictionary, target: Dictionary) -> Dictionary:
	var tpos: Vector2 = target["pos"]
	var self_pos: Vector2 = ctx["self_pos"]
	var ex: Array = ctx["exclude"] + tactics.body_rid(target)
	var out := { "here": {}, "spots": [], "ambush": {} }
	if (self_pos.distance_to(tpos) <= tactics.shoot_range
			and not tactics._shot_blocked(ctx, self_pos, tpos, target.get("node"))):
		out["here"] = tactics._annotate(ctx, target, self_pos, ex)
	var rings := _fire_rings(tactics, ctx, target, ex)
	out["spots"] = _sector_spots(tactics, ctx, target, rings["fire"], ex)
	out["ambush"] = _ambush_from(tactics, ctx, target, rings["cover"], ex)
	return out


## The candidate spots to fight from `target` (`{ pos, node }`): `fire`, the points with a clear
## shot on the rings round the NPC (`combat_ring_radius`, ×2) and then those on the rings round the
## target (each of `fire_spot_distances`, snapped onto the navmesh), and `cover`, the ring points
## round the NPC shielded from it.
func _fire_rings(
	tactics: RefCounted, ctx: Dictionary, target: Dictionary, ex: Array
) -> Dictionary:
	var fire: Array = []
	var cover: Array = []
	for radius in [tactics.combat_ring_radius, tactics.combat_ring_radius * 2.0]:
		var ring := _self_combat_spots(tactics, ctx, target, ex, radius)
		fire.append_array(ring["fire"])
		cover.append_array(ring["cover"])
	for dist in tactics.fire_spot_distances:
		fire.append_array(_target_ring(tactics, ctx, target, dist))
	return { "fire": fire, "cover": cover }


## The points of the ring of `dist` round `target` (snapped onto the navmesh) that have a clear shot
## at it.
func _target_ring(
	tactics: RefCounted, ctx: Dictionary, target: Dictionary, dist: float
) -> Array:
	var tpos: Vector2 = target["pos"]
	var node: Variant = target.get("node")
	var fire: Array = []
	for i in tactics.combat_ring_count:
		var turn: float = TAU * i / tactics.combat_ring_count
		var raw: Vector2 = tpos + Vector2.RIGHT.rotated(turn) * dist
		var p := NavBuilder.snap(ctx["map"], raw)
		if (p.distance_to(raw) <= tactics.SNAP_TOLERANCE
				and not tactics._shot_blocked(ctx, p, tpos, node)):
			fire.append(p)
	return fire


## One self-centred combat ring. Its self-to-candidate sight lines are cast once per snapshot with
## the context's own exclusions and shared by every target (`_self_ring_lines`); classification
## against the target remains per target.
func _self_combat_spots(
	tactics: RefCounted, ctx: Dictionary, target: Dictionary, ex: Array, radius: float
) -> Dictionary:
	var tpos: Vector2 = target["pos"]
	var node: Variant = target.get("node")
	var fire: Array = []
	for p: Vector2 in _self_ring_points(tactics, ctx, ex, radius):
		if not tactics._shot_blocked(ctx, p, tpos, node):
			fire.append(p)
	# The same nearest-first sort as `combat_spots`: ring points are equidistant, so the sort's
	# own tie order is part of which spot comes first.
	var self_pos: Vector2 = ctx["self_pos"]
	fire.sort_custom(
		func(a, b): return a.distance_squared_to(self_pos) < b.distance_squared_to(self_pos),
	)
	return { "fire": fire, "cover": _self_cover_spots(tactics, ctx, target, ex, radius) }


## The points of a self-centred ring that hide a ducked body from the hostile `target`
## (`{ pos, node }`) (`hiding_piece`), nearest first.
func _self_cover_spots(
	tactics: RefCounted, ctx: Dictionary, target: Dictionary, ex: Array, radius: float
) -> Array:
	var tpos: Vector2 = target["pos"]
	var node: Variant = target.get("node")
	var cover: Array = []
	for p: Vector2 in _self_ring_points(tactics, ctx, ex, radius):
		if tactics.vision.hiding_piece(ctx["space"], p, tpos, AgentCover.eye_of(node), ex) != null:
			cover.append(p)
	var self_pos: Vector2 = ctx["self_pos"]
	cover.sort_custom(
		func(a, b): return a.distance_squared_to(self_pos) < b.distance_squared_to(self_pos),
	)
	return cover


## The ring points the NPC sees with `ex` excluded. A shared line that hit nothing is clear. One
## that hit a body only `ex` adds (this target's) is cast again with `ex`; any other hit stays a
## block. So the result equals casting every line with `ex`, as `combat_spots` does.
func _self_ring_points(tactics: RefCounted, ctx: Dictionary, ex: Array, radius: float) -> Array:
	var base: Array = ctx["exclude"]
	var extra: Array = ex.filter(func(r): return not base.has(r))
	var points: Array = []
	for line: Dictionary in _self_ring_lines(tactics, ctx, radius):
		var hit: Variant = line["hit"]
		var point: Vector2 = line["point"]
		var cast: bool = hit != null and extra.has(hit)
		if hit == null or (cast and not tactics.blocked(ctx["space"], ctx["self_pos"], point, ex)):
			points.append(point)
	return points


## The ring of `radius` round the NPC as `{ point, hit }` (`hit`: the rid of what its line from the
## NPC first meets with the context's exclusions, null when clear), cast once per snapshot.
func _self_ring_lines(tactics: RefCounted, ctx: Dictionary, radius: float) -> Array:
	var cache: Dictionary = tactics._cache_bucket(ctx, "self_rings")
	if not cache.has(radius):
		var lines: Array = []
		for i in tactics.combat_ring_count:
			var p: Vector2 = (ctx["self_pos"] as Vector2) + Vector2.RIGHT.rotated(
				TAU * i / tactics.combat_ring_count
			) * radius
			var hit: Dictionary = tactics.vision.raycast(
				ctx["space"],
				ctx["self_pos"],
				p,
				ctx["exclude"],
			)
			lines.append({ "point": p, "hit": hit["rid"] if not hit.is_empty() else null })
		cache[radius] = lines
	return cache[radius]


## The firing spots against `target` from `candidates`: the best per 8-way sector round it (cover
## close by first, then the shortest step) that passes `_safe_spot`, sorted cover close by first,
## then a hidden route, then the shortest.
func _sector_spots(
	tactics: RefCounted,
	ctx: Dictionary,
	target: Dictionary,
	candidates: Array,
	ex: Array,
) -> Array:
	var self_pos: Vector2 = ctx["self_pos"]
	var sectors := _by_sector(tactics, ctx, target, candidates, ex)
	var spots: Array = []
	for sector in sectors:
		var group: Array = sectors[sector]
		group.sort_custom(_nearer_cover.bind(self_pos))
		var spot: Variant = _first_safe(tactics, ctx, target, group, ex)
		if spot != null:
			spots.append(spot)
	spots.sort_custom(_better_spot)
	return spots


## Whether sector candidate `a` comes before `b`: cover close by first, then nearer the NPC.
static func _nearer_cover(a: Dictionary, b: Dictionary, self_pos: Vector2) -> bool:
	if (a["cover"] != "") != (b["cover"] != ""):
		return a["cover"] != ""
	return ((a["point"] as Vector2).distance_squared_to(self_pos)
			< (b["point"] as Vector2).distance_squared_to(self_pos))


## Whether firing spot `a` comes before `b`: cover close by first, then a hidden route, then the
## shortest.
static func _better_spot(a: Dictionary, b: Dictionary) -> bool:
	if (a["cover"] != "") != (b["cover"] != ""):
		return a["cover"] != ""
	if a["route_exposed"] != b["route_exposed"]:
		return not a["route_exposed"]
	return a["route_len"] < b["route_len"]


## The first of `group` (`{ point, cover }`, in the order to try them) that passes `_safe_spot`:
## its spot, or null when none does.
func _first_safe(
	tactics: RefCounted, ctx: Dictionary, target: Dictionary, group: Array, ex: Array
) -> Variant:
	for c: Dictionary in group:
		var spot: Variant = _safe_spot(tactics, ctx, target, c["point"], ex)
		if spot != null:
			return spot
	return null


## The `candidates` in shooting range of `tpos` and not under the NPC's feet, by 8-way sector round
## it (sector -> `[{ point, cover }]`, in candidate order). Cheap facts first (range, sector,
## cover): the route checks run later, only until a sector has its spot.
func _by_sector(
	tactics: RefCounted,
	ctx: Dictionary,
	target: Dictionary,
	candidates: Array,
	ex: Array,
) -> Dictionary:
	var tpos: Vector2 = target["pos"]
	var self_pos: Vector2 = ctx["self_pos"]
	var sectors := {}
	for p in candidates:
		if (p.distance_to(tpos) > tactics.shoot_range
				or p.distance_to(self_pos) < tactics.combat_ring_radius * 0.5):
			continue
		var sector := posmod(int(round((p - tpos).angle() / (TAU / 8.0))), 8)
		if not sectors.has(sector):
			sectors[sector] = []
		sectors[sector].append({
			"point": p, "cover": tactics.cover_cached(
				ctx,
				p,
				tpos,
				ex,
				AgentCover.viewer_of(target),
			),
		})
	return sectors


## The ambush spot against `target`: the first of `cover_spots` that passes `_safe_spot`, with the
## piece that shields it as its `cover`; {} when none does.
func _ambush_from(
	tactics: RefCounted,
	ctx: Dictionary,
	target: Dictionary,
	cover_spots: Array,
	ex: Array,
) -> Dictionary:
	for p in cover_spots:
		var amb = _safe_spot(tactics, ctx, target, p, ex)
		if amb != null:
			var piece: Variant = tactics.vision.hiding_piece(
				ctx["space"], p, target["pos"], AgentCover.eye_of_contact(target), ex
			)
			amb["cover"] = tactics.object_label(piece)
			return amb
	return {}


## `p` annotated as a place to fight `target` from (with its route's exposure to the target), or
## null when the route there passes a known hostile or a hostile would catch the NPC in the open on
## the way or once there.
func _safe_spot(
	tactics: RefCounted,
	ctx: Dictionary,
	target: Dictionary,
	p: Vector2,
	ex: Array,
) -> Variant:
	var path: PackedVector2Array = tactics._route(ctx, p)
	if tactics._route_crosses(
		path,
		ctx["hostiles"],
	) != "" or tactics._watched_in_open(ctx, p, path) != "":
		return null
	var a: Dictionary = tactics._annotate(ctx, target, p, ex, path)
	a["route_exposed"] = tactics._route_exposed(ctx, path, target["pos"])
	return a
