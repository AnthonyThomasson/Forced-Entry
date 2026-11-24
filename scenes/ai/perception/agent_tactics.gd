extends RefCounted
## AI PERCEPTION sub-domain — TACTICS: the combat geometry an NPC reads off what it knows. Pure
## queries over known contacts, the physics space (via the vision sense's ray helpers) and the
## navigation map (Navigation interface 9): where it could flank a target from, which spots give a
## clear shot or cover, how to close in, where to fall back to — each candidate annotated with the
## facts a tactical choice turns on (clear shot, cover, route length and exposure, which ally
## already holds a side, which other hostile would see it, which hostile the route passes). It
## returns DATA only; the perception turns that into the words Von reads. It holds no policy and
## never decides. Firing and throw spots are screened: a spot whose route passes a known hostile
## is not a place to fight from at all (firing spots also when a hostile would catch the NPC in the
## open).
##
## A target's FLANKS are measured in its own frame: its front is where it was last seen facing (when
## recent), else the side facing this NPC. Left/right are the target's own left/right.

const AgentCover := preload("res://scenes/ai/perception/agent_cover.gd")
const ThrowSpots := preload("res://scenes/ai/perception/throw_spots.gd")
const FireSpots := preload("res://scenes/ai/perception/fire_spots.gd")
## The flanking sides offered, as degrees off the target's front (screen space, +y down).
const SIDES := { "left": -90.0, "right": 90.0, "rear": 180.0 }
## How far (px) a sampled point may be pulled by navmesh snapping before it counts as unreachable.
const SNAP_TOLERANCE := 48.0
## Points sampled along a route to judge whether the target can see it.
const ROUTE_SAMPLES := 8
## A place a walk ends within this (px of walking) of where the NPC stands is where it stands: the
## walk is over the moment it begins (a stride, twice the walk's own arrival distance), and the
## unchanged situation would offer it again. No retreat nor walk toward the shots (LOCATE, the
## "where the shots came from" lead: `where_it_stands`) goes to one.
const STRIDE := 32.0
## A place closer than this (px) to a character the NPC knows of is taken (a body's footprint): a
## walk there is held short of the body.
const TAKEN := 32.0
## How far (px) from an ally lies the spot beside it that the NPC falls back to: a body clear of it
## (the stack's spacing).
const BESIDE_ALLY := 44.0
## How far past `route_clearance` a flank route is bent round the target it would pass (B2), as
## factors of it: the first that clears is taken.
const BENT_CLEARANCES := [1.15, 1.6, 2.2]
## What (px of walk) a bent route that crosses an ally's line of fire costs more than one that does
## not.
const BENT_LANE_COST := 1000.0
## The snapshot cache's buckets of kept fire lines (by target), standing and ducked.
const LINES := "fire_lines"
const DUCKED_LINES := "fire_lines_ducked"

## The perception's sight sense; owner of the ray queries.
var vision: RefCounted
## Where to throw a grenade from (`throw_spots.gd`): the part reads this geometry at each call.
var throws := ThrowSpots.new()
## Where to fight a hostile from (`fire_spots.gd`): the part reads this geometry at each call.
var fire_spots := FireSpots.new()
# --- Config fields the perception's apply_config() sets from the NPC's tuning (`NpcTuning`: the
# `tactics` topic's of the same name, `shoot_range` and the ring off `combat`, `still_speed` off
# `context`; `throw_spot_walk` off `grenades` is `throws.spot_walk`).
## Distance (px) from the target a flanking spot is sought at.
var flank_distance: float
## Angular spread (degrees) sampled around each side's bearing.
var flank_arc: float
## An ally this close to the target holds the side it stands on.
var flank_ally_radius: float
## Pistol range (px): a spot beyond it gives no shot.
var shoot_range: float
## Radius (px) of the ring of nearby candidate fighting spots.
var combat_ring_radius: float
## Points sampled on that ring.
var combat_ring_count: int
## Speed (px/s) under which a contact counts as standing still.
var still_speed: float
## A route coming this close (px) to a known hostile passes it.
var route_clearance: float
## Full cone (degrees) around a hostile's front in which it is looking.
var watch_arc: float
## Distances (px) from a target at which firing spots are sampled.
var fire_spot_distances: Array[float]
## Actual route and `_cover_near` queries made by this geometry object (reuse observables).
var route_queries := 0
var cover_queries := 0


# --- Ray + nav primitives --------------------------------------------------------------------


## Whether the straight line `a`→`b` is blocked by a wall or solid object.
func blocked(space: PhysicsDirectSpaceState3D, a: Vector2, b: Vector2, exclude: Array) -> bool:
	return vision.blocked(space, a, b, exclude)


## The first solid object on `a`→`b`, or null when the line is clear.
func blocker(space: PhysicsDirectSpaceState3D, a: Vector2, b: Vector2, exclude: Array) -> Object:
	return vision.raycast(space, a, b, exclude).get("collider")


## Whether a round from `a` cannot reach the body at `b` (`target`, null for a standing one; a
## `posture` of `BodyHeights.DUCK` judges a ducked body, the one that takes cover there): the real
## line of fire, from a standing muzzle (`AgentVision.fire_stop_from`), over what is low and stopped
## by what is tall. What every fire, exposure and hiding judgment asks, where `blocked` is a wall's
## plain line (where a walk may go). Asked once per snapshot for the same line: candidates are
## annotated, ringed and watched again from the same points (a hit is counted in the tally).
func _shot_blocked(
	ctx: Dictionary,
	a: Vector2,
	b: Vector2,
	target: Variant = null,
	posture: StringName = BodyHeights.NONE,
) -> bool:
	var name := LINES if posture == BodyHeights.NONE else DUCKED_LINES
	var bucket := _cache_bucket(ctx, name)
	var who: int = target.get_instance_id() if is_instance_valid(target) else 0
	if not bucket.has(who):
		bucket[who] = {}
	var lines: Dictionary = bucket[who]
	var key := Vector4(a.x, a.y, b.x, b.y)
	if lines.has(key):
		_count_hit(ctx, name)
		return lines[key]
	var blocked_here := _shot_blocked_in(ctx["space"], a, b, target, posture)
	if ctx.has("tactics_cache"):
		lines[key] = blocked_here
	return blocked_here


## `_shot_blocked` for a caller with only a space (no snapshot to keep the answer in).
func _shot_blocked_in(
	space: PhysicsDirectSpaceState3D,
	a: Vector2,
	b: Vector2,
	target: Variant = null,
	posture: StringName = BodyHeights.NONE,
) -> bool:
	return not vision.fire_stop_from(space, a, b, target as Node2D, posture).is_empty()


## Count one answer the snapshot's cache kept in the bucket `name` (`tactics_cache["hits"]`).
func _count_hit(ctx: Dictionary, name: String) -> void:
	var root: Variant = ctx.get("tactics_cache")
	if root == null:
		return
	var hits: Dictionary = root.get("hits", {})
	hits[name] = hits.get(name, 0) + 1
	root["hits"] = hits


## A readable name for a blocking object: a furniture piece's own name ("fridge"), a character's
## name, else "wall" — walls are named after their room, which would read as a place ("behind the
## kitchen").
func object_label(obj: Object) -> String:
	if obj == null:
		return ""
	var named = obj.get("object_name")
	if named is String and named != "":
		return named.to_lower()
	if obj is Node and obj.is_in_group(&"characters"):
		return str(obj.get("name")).to_lower()
	return "wall"


## Whether most of a route lies in the open from `threat` (a clear line from it to most samples).
## With a `front` (the threat's facing, radians) a sample also has to lie inside its view cone
## (`watch_arc`): a route behind the threat's back is not in its view, however clear the line.
## Without one, only the line counts.
func _route_exposed(
	ctx: Dictionary,
	path: PackedVector2Array,
	threat: Vector2,
	front := NAN,
) -> bool:
	var total := NavBuilder.path_length(path)
	if total <= 0.0:
		return false
	var half := deg_to_rad(watch_arc) * 0.5
	var seen := 0
	var missed := 0
	for i in ROUTE_SAMPLES:
		var sample := _along(path, total * (i + 1) / (ROUTE_SAMPLES + 1))
		var in_sight := ((is_nan(front) or _looking_at(threat, front, sample, half))
				and not _shot_blocked(ctx, threat, sample))
		seen += 1 if in_sight else 0
		missed += 0 if in_sight else 1
		# Settled once more than half are seen, or too few are left to be.
		if seen * 2 > ROUTE_SAMPLES:
			return true
		if (ROUTE_SAMPLES - missed) * 2 <= ROUTE_SAMPLES:
			return false
	return false


## The point `dist` px along a route.
func _along(path: PackedVector2Array, dist: float) -> Vector2:
	for i in range(1, path.size()):
		var seg := path[i - 1].distance_to(path[i])
		if dist <= seg:
			return path[i - 1].lerp(path[i], dist / seg if seg > 0.0 else 0.0)
		dist -= seg
	return path[path.size() - 1]


# --- Frames and sides ------------------------------------------------------------------------


## The target's front bearing (radians): its last-seen facing when `use_facing`, else toward
## `self_pos`.
func front_angle(target: Dictionary, self_pos: Vector2, use_facing: bool) -> float:
	var facing: Vector2 = target.get("facing", Vector2.ZERO)
	if use_facing and facing != Vector2.ZERO:
		return facing.angle()
	return (self_pos - (target["pos"] as Vector2)).angle()


## Which side of a target at `target_pos` (front bearing `front`) the point `p` is on:
## "front" / "left" / "right" / "rear".
func side_of(target_pos: Vector2, front: float, p: Vector2) -> String:
	var d := angle_difference(front, (p - target_pos).angle())
	if absf(d) <= PI * 0.25:
		return "front"
	if absf(d) >= PI * 0.75:
		return "rear"
	return "left" if d < 0.0 else "right"


# --- Spot classification ---------------------------------------------------------------------


## Points on a ring of `radius` (`combat_ring_count` of them) around `self_pos` classified against
## the target `tgt` (`{ pos, node }`, a contact's, `node` optional): `fire` (a clear line to it) and
## `cover` (shielded by a cover-grade object). Points walled off from the NPC are dropped. Both
## lists nearest-first.
func combat_spots(
	space: PhysicsDirectSpaceState3D,
	self_pos: Vector2,
	tgt: Dictionary,
	exclude: Array,
	radius: float,
) -> Dictionary:
	var tgt_pos: Vector2 = tgt["pos"]
	var fire: Array = []
	var cover: Array = []
	for i in combat_ring_count:
		var p := self_pos + Vector2.RIGHT.rotated(TAU * i / combat_ring_count) * radius
		if blocked(space, self_pos, p, exclude):
			continue
		if not _shot_blocked_in(space, p, tgt_pos, tgt.get("node")):
			fire.append(p)
		if vision.hiding_piece(
			space,
			p,
			tgt_pos,
			AgentCover.eye_of_contact(tgt),
			exclude,
		) != null:
			cover.append(p)
	fire.sort_custom(
		func(a, b): return a.distance_squared_to(self_pos) < b.distance_squared_to(self_pos),
	)
	cover.sort_custom(
		func(a, b): return a.distance_squared_to(self_pos) < b.distance_squared_to(self_pos),
	)
	return { "fire": fire, "cover": cover }


## The piece that hides a ducked body at `p`, or a clear step from it, from `threat`
## (`AgentVision.hiding_piece`, from an eye `eye` px up), or "" when none does.
func _cover_near(
	space: PhysicsDirectSpaceState3D,
	p: Vector2,
	threat: Vector2,
	exclude: Array,
	eye := -1.0,
) -> String:
	for i in 9:
		var q := p if i == 0 else p + Vector2.RIGHT.rotated(TAU * i / 8.0) * 36.0
		if i > 0 and blocked(space, p, q, exclude):
			continue  # A step into a piece or through a wall is no step.
		var piece: Object = vision.hiding_piece(space, q, threat, eye, exclude)
		if piece != null:
			return object_label(piece)
	return ""


## `_cover_near` for a point and hostile (`node`, whose posture sets the eye the line starts at; a
## standing one's for none), reused when the same candidate is annotated again or another target's
## watch test asks it. Nothing leaves the snapshot. In a world with twin space the answer does not
## depend on `ex` (a body is no cover), so it is not part of the key there.
func cover_cached(
	ctx: Dictionary,
	p: Vector2,
	threat: Vector2,
	ex: Array,
	node: Variant = null,
) -> String:
	var eye := AgentCover.eye_of(node)
	var bucket := _cache_bucket(ctx, "cover")
	var twinned: bool = ctx["space"] != null
	var group: Variant = ex
	if twinned:
		group = eye
	if not bucket.has(group):
		bucket[group] = {}
	var kept: Dictionary = bucket[group]
	var key := Vector4(p.x, p.y, threat.x, threat.y)
	if kept.has(key):
		_count_hit(ctx, "cover")
		return kept[key]
	cover_queries += 1
	kept[key] = _cover_near(ctx["space"], p, threat, ex, eye)
	return kept[key]


## Names of the known hostiles other than `skip_id` with a clear line to `p` within shooting reach.
func exposed_to(
	ctx: Dictionary,
	p: Vector2,
	hostiles: Array,
	skip_id: int,
) -> Array:
	var out: Array = []
	for h in hostiles:
		if h["id"] == skip_id or (h["pos"] as Vector2).distance_to(p) > shoot_range * 1.5:
			continue
		if not _shot_blocked(ctx, h["pos"], p):
			out.append(h["name"])
	return out


## The ally (perceived, or via a radio callout) holding side `side` of a target, or "".
func side_holder(
	target: Dictionary,
	front: float,
	side: String,
	allies: Array,
	callouts: Array,
) -> String:
	var tpos: Vector2 = target["pos"]
	for a in allies:
		if ((a["pos"] as Vector2).distance_to(tpos) <= flank_ally_radius
				and side_of(tpos, front, a["pos"]) == side):
			return a["name"]
	for c in callouts:
		var point: Vector2 = c.get("point", Vector2.INF)
		if (point != Vector2.INF
				and point.distance_to(tpos) <= flank_ally_radius
				and side_of(tpos, front, point) == side):
			return "%s (radio)" % c.get("name", "an ally")
	return ""


## The ally whose line of fire on the target passes close to `p`, or that the route `path` to `p`
## crosses, or "". Walking across a friend's line of fire is as bad as standing in it.
func _ally_lane(
	p: Vector2,
	target_pos: Vector2,
	allies: Array,
	path := PackedVector2Array(),
) -> String:
	for a in allies:
		var apos: Vector2 = a["pos"]
		if apos.distance_to(target_pos) > flank_ally_radius:
			continue
		if Geometry2D.get_closest_point_to_segment(p, apos, target_pos).distance_to(p) < 40.0:
			return a["name"]
		for i in range(1, path.size()):
			if (Geometry2D.segment_intersects_segment(path[i - 1], path[i], apos, target_pos)
					!= null):
				return a["name"]
	return ""


# --- Route safety ----------------------------------------------------------------------------


## The first known hostile a route passes, or "": its last-known position lies within
## `route_clearance` of the route AND nearer than the route's start already is, so walking away from
## someone close by is not passing them.
func _route_crosses(path: PackedVector2Array, hostiles: Array) -> String:
	if path.size() < 2:
		return ""
	for h in hostiles:
		var hpos: Vector2 = h["pos"]
		var closest := INF
		for i in range(1, path.size()):
			closest = minf(
				closest,
				Geometry2D.get_closest_point_to_segment(hpos, path[i - 1], path[i]).distance_to(
					hpos,
				),
			)
		if closest < route_clearance and closest < path[0].distance_to(hpos) - 1.0:
			return h["name"]
	return ""


## The walk to the flank point `p` of `target` as B2, B3 and the exposure read it, and the one the
## NPC is sent on: `{ path, via }`. The plain `path` (no `via`: `Vector2.INF`), unless that passes
## the target and no other hostile, then the route bent round the target (`_bent_route`) when one
## clears every hostile; the goal walks by its `via` first, so the route checked is the route
## walked.
func _flank_walk(
	ctx: Dictionary,
	target: Dictionary,
	path: PackedVector2Array,
	p: Vector2,
) -> Dictionary:
	var others: Array = ctx["hostiles"].filter(
		func(h: Dictionary) -> bool: return h["id"] != target["id"])
	if _route_crosses(path, [target]) == "" or _route_crosses(path, others) != "":
		return { "path": path, "via": Vector2.INF }
	var bent := _bent_route(ctx, target, p)
	return bent if not bent.is_empty() else { "path": path, "via": Vector2.INF }


## The shortest walk from the NPC to `p` round `hostile` that passes no known hostile, or {}:
## `{ path, via }`, through a waypoint beside the hostile (to either side, at `BENT_CLEARANCES`
## times `route_clearance` off it, the smallest that works). One that crosses no ally's line of fire
## to the hostile is preferred.
func _bent_route(ctx: Dictionary, hostile: Dictionary, p: Vector2) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var hpos: Vector2 = hostile["pos"]
	var line := p - self_pos
	if line.length() < 1.0:
		return {}
	var beside := line.orthogonal().normalized()
	for factor in BENT_CLEARANCES:
		var best := {}
		var best_cost := INF
		for way in [1.0, -1.0]:
			var raw: Vector2 = hpos + beside * way * route_clearance * factor
			var via := NavBuilder.snap(ctx["map"], raw)
			if via.distance_to(raw) > SNAP_TOLERANCE:
				continue
			var bent := _route(ctx, via)
			route_queries += 1
			bent.append_array(NavBuilder.route(ctx["map"], via, p).slice(1))
			if (bent[bent.size() - 1].distance_to(p) > SNAP_TOLERANCE
					or _route_crosses(bent, ctx["hostiles"]) != ""):
				continue
			var cost := NavBuilder.path_length(bent)
			if _ally_lane(p, hpos, ctx["allies"], bent) != "":
				cost += BENT_LANE_COST
			if cost < best_cost:
				best = { "path": bent, "via": via }
				best_cost = cost
		if not best.is_empty():
			return best
	return {}


## The known hostile that would catch the NPC in the open, or "": one looking toward `p` (within
## `watch_arc` of its front, from `ctx.fronts`) with a clear line to it in reach and no cover within
## a step of `p` against it. With a `path`, also one looking along the route there while the NPC is
## now hidden or covered from it, when most of that route is open to it — stepping out of cover
## under its eye.
func _watched_in_open(
	ctx: Dictionary,
	p: Vector2,
	path: PackedVector2Array = PackedVector2Array(),
) -> String:
	var self_pos: Vector2 = ctx["self_pos"]
	var half := deg_to_rad(watch_arc) * 0.5
	var fronts: Dictionary = ctx.get("fronts", {})
	for h in ctx["hostiles"]:
		var hpos: Vector2 = h["pos"]
		# Unknown facing counts as facing this NPC, the safe assumption.
		var front: float = fronts.get(h["id"], (self_pos - hpos).angle())
		var ex: Array = ctx["exclude"] + body_rid(h)
		if (_looking_at(hpos, front, p, half)
				and hpos.distance_to(p) <= shoot_range * 1.5
				and not _shot_blocked(ctx, hpos, p)
				and cover_cached(ctx, p, hpos, ex, AgentCover.viewer_of(h)) == ""):
			return h["name"]
		if path.size() >= 2 and _eyes_route(ctx, h, front, path, ex):
			return h["name"]
	return ""


## Whether hostile `h` (facing `front`) looks along the route `path` while this NPC is now hidden or
## covered from it, with most of that route open to it. `ex` holds the rids the rays pass through.
func _eyes_route(
	ctx: Dictionary,
	h: Dictionary,
	front: float,
	path: PackedVector2Array,
	ex: Array,
) -> bool:
	var hpos: Vector2 = h["pos"]
	var mid := _along(path, NavBuilder.path_length(path) * 0.5)
	return (_looking_at(hpos, front, mid, deg_to_rad(watch_arc) * 0.5)
			and _covered_from(ctx, h, ex)
			and _route_exposed(ctx, path, hpos))


## Whether this NPC is hidden or covered from hostile `h` where it stands. That does not depend on
## the spot judged, so it is worked out once per hostile for the whole snapshot
## (`ctx.covered_from`) rather than for every candidate spot.
func _covered_from(ctx: Dictionary, h: Dictionary, ex: Array) -> bool:
	var covered_from: Dictionary = ctx.get("covered_from", {})
	if covered_from.has(h["id"]):
		return covered_from[h["id"]]
	var hpos: Vector2 = h["pos"]
	var self_pos: Vector2 = ctx["self_pos"]
	var covered: bool = (_shot_blocked(ctx, hpos, self_pos)
			or cover_cached(ctx, self_pos, hpos, ex, AgentCover.viewer_of(h)) != "")
	covered_from[h["id"]] = covered
	return covered


## Whether a hostile at `hpos` facing `front` is looking toward `p` (within `half` radians).
func _looking_at(hpos: Vector2, front: float, p: Vector2, half: float) -> bool:
	return absf(angle_difference(front, (p - hpos).angle())) <= half


# --- Candidate positions ---------------------------------------------------------------------


## The flanking spots around `target` (one per side, excluding the side this NPC is already on),
## each annotated — `crosses` names a known hostile the route there passes. `ctx` = { space, map,
## self_pos, exclude, hostiles, allies, callouts, fronts, covered_from }.
func flank_sides(ctx: Dictionary, target: Dictionary, front: float) -> Array:
	var out: Array = []
	for side in flank_sides_to_try(ctx, target, front):
		var a: Variant = flank_side(ctx, target, front, side)
		if a != null:
			out.append(a)
	return out


## The sides `flank_sides` tries, in order: every side of the target but the one this NPC is on.
func flank_sides_to_try(ctx: Dictionary, target: Dictionary, front: float) -> Array:
	var own_side := side_of(target["pos"], front, ctx["self_pos"])
	return SIDES.keys().filter(func(side): return side != own_side)


## The flanking spot on `side` of `target`, annotated (see `flank_sides`), or null when the side has
## no reachable point.
func flank_side(ctx: Dictionary, target: Dictionary, front: float, side: String) -> Variant:
	var tpos: Vector2 = target["pos"]
	var ex: Array = ctx["exclude"] + body_rid(target)
	var p = _flank_point(ctx, tpos, front, side, target.get("node"))
	if p == null:
		return null
	var walk := _flank_walk(ctx, target, _route(ctx, p), p)
	var path: PackedVector2Array = walk["path"]
	var vel: Vector2 = target.get("vel", Vector2.ZERO)
	# What standing at the side's point gives (as for every candidate), then the flank's own.
	var a := { "side": side, "via": walk["via"] }
	a.merge(_annotate(ctx, target, p, ex, path))
	a.merge({
		"route_exposed": _route_exposed(ctx, path, tpos, front),
		"crosses": _route_crosses(path, ctx["hostiles"]),
		"held_by": side_holder(target, front, side, ctx["allies"], ctx["callouts"]),
		"heading_toward": vel.length() >= still_speed
			and absf(vel.angle_to(p - tpos)) < PI / 3.0,
		"ally_lane": _ally_lane(p, tpos, ctx["allies"], path),
	}, true)
	return a


## A reachable point on `side` of a target: sampled across `flank_arc` at full then shorter range,
## preferring one with a clear shot. Null when the side has no reachable point.
func _flank_point(
	ctx: Dictionary,
	tpos: Vector2,
	front: float,
	side: String,
	node: Variant,
) -> Variant:
	var base := front + deg_to_rad(SIDES[side])
	var fallback = null
	for dist in [flank_distance, flank_distance * 0.65]:
		for k in [0.0, -0.5, 0.5]:
			var raw: Vector2 = tpos + Vector2.from_angle(base + deg_to_rad(flank_arc) * k) * dist
			var p := NavBuilder.snap(ctx["map"], raw)
			if p.distance_to(raw) > SNAP_TOLERANCE or side_of(tpos, front, p) != side:
				continue
			if not _shot_blocked(ctx, p, tpos, node):
				return p
			if fallback == null:
				fallback = p
	return fallback


## A named bucket of the context's snapshot-scoped cache, or an unretained dictionary for a plain
## computation with no `tactics_cache`.
func _cache_bucket(ctx: Dictionary, name: String) -> Dictionary:
	if not ctx.has("tactics_cache"):
		return {}
	var root: Dictionary = ctx["tactics_cache"]
	if not root.has(name):
		root[name] = {}
	return root[name]


## What this snapshot already worked out under `key` in the bucket `name` of its cache, or null:
## null too for a plain computation (no `tactics_cache`), which works everything out. A hit is
## counted in `tactics_cache["hits"][name]` (what was kept in all is the bucket's size).
func recall(ctx: Dictionary, name: String, key: Variant) -> Variant:
	var root: Variant = ctx.get("tactics_cache")
	if root == null or not root.has(name):
		return null
	var kept: Variant = root[name].get(key)
	if kept != null:
		var hits: Dictionary = root["hits"]
		hits[name] = hits.get(name, 0) + 1
	return kept


## `value` worked out for `key` in the bucket `name`, kept for the snapshot's later asks
## (`recall`); returns `value`.
func remember(ctx: Dictionary, name: String, key: Variant, value: Variant) -> Variant:
	var root: Variant = ctx.get("tactics_cache")
	if root != null:
		if not root.has(name):
			root[name] = {}
			root["hits"] = root.get("hits", {})
		root[name][key] = value
	return value


## `p` snapped onto the navmesh, asked once a snapshot (throw candidates and room centres repeat).
func snap(ctx: Dictionary, p: Vector2) -> Vector2:
	var kept: Variant = recall(ctx, "snaps", p)
	if kept != null:
		return kept
	return remember(ctx, "snaps", p, NavBuilder.snap(ctx["map"], p))


## The route from the frozen NPC position to `p`, shared by every target analysis in this snapshot.
func _route(ctx: Dictionary, p: Vector2) -> PackedVector2Array:
	var cache := _cache_bucket(ctx, "routes")
	if not cache.has(p):
		route_queries += 1
		cache[p] = NavBuilder.route(ctx["map"], ctx["self_pos"], p)
	return cache[p]


## The walk to `point` (`route`: `{ path, len, detour }`, else the plain route with no detour) as
## `{ route_len, detour }`, or {} when it does not qualify: it must end within 12 px of the point,
## be at most `max_len` long and pass no known hostile (the throw spots' walk, `throw_spots.gd`).
func walk_leg(ctx: Dictionary, point: Vector2, route: Callable, max_len: float) -> Dictionary:
	var way: Dictionary = route.call(point) if route.is_valid() else {}
	if way.is_empty():
		var plain := _route(ctx, point)
		way = { "path": plain, "len": NavBuilder.path_length(plain), "detour": false }
	var path: PackedVector2Array = way["path"]
	var length: float = way["len"]
	if (length > max_len
			or path.is_empty()
			or path[path.size() - 1].distance_to(point) > 12.0
			or _route_crosses(path, ctx["hostiles"]) != ""):
		return {}
	return { "route_len": length, "detour": bool(way.get("detour", false)) }


## Ways to close in on `target`: points part-way along the route to it (with any cover there) and
## its last-known position itself.
func advance_positions(ctx: Dictionary, target: Dictionary) -> Array:
	var tpos: Vector2 = target["pos"]
	var ex: Array = ctx["exclude"] + body_rid(target)
	var path := _route(ctx, tpos)
	var total := NavBuilder.path_length(path)
	var out: Array = []
	if total > 160.0:
		for frac in [0.5, 0.75]:
			var p := NavBuilder.snap(ctx["map"], _along(path, total * frac))
			var a := _annotate(ctx, target, p, ex)
			a["fraction"] = frac
			out.append(a)
	var rush := _annotate(ctx, target, NavBuilder.snap(ctx["map"], tpos), ex)
	rush["rush"] = true
	rush["route_exposed"] = _route_exposed(ctx, path, tpos)
	out.append(rush)
	return out


## Places to fall back to from `threats` (world points): known room centres, cover spots nearby, and
## a spot beside each nearby ally — each annotated with whether it is hidden from every threat,
## cover, route and the ally it lies toward. Each is the point on the navmesh a walk there ends at,
## judged there. A retreat takes the NPC out of sight of every threat when it stands in sight of
## one, else farther (by a `STRIDE`) from the nearest; one taken by a character it knows of
## (`TAKEN`) or where it already stands (`STRIDE`) is no place to fall back to.
func retreat_positions(ctx: Dictionary, threats: Array, rooms: Array) -> Array:
	var self_pos: Vector2 = ctx["self_pos"]
	var here_gap := _nearest_gap(self_pos, threats)
	# Rays toward a threat end on the hostile's own body — it must not count as what hides a spot.
	var ex: Array = ctx["exclude"].duplicate()
	for h in ctx["hostiles"]:
		ex += body_rid(h)
	var here_hidden := _hidden_from(ctx, threats, self_pos)
	var bodies: Array = (ctx["allies"] + ctx["hostiles"]).map(func(c): return c["pos"])
	var out: Array = []
	for c in _retreat_candidates(ctx, threats, rooms, ex):
		var p: Vector2 = c["point"]
		if bodies.any(func(b): return p.distance_to(b) < TAKEN):
			continue  # Taken: the walk would be held short of the body on it.
		var hidden := _hidden_from(ctx, threats, p)
		var farther := _nearest_gap(p, threats) >= here_gap + STRIDE
		if not farther and (not hidden or here_hidden):
			continue  # Neither out of sight (from in it) nor farther away: not a retreat.
		if _annotate_retreat(ctx, c, threats, ex, hidden):
			out.append(c)
	return out


## The places a retreat from `threats` weighs, each `{ point, room }` (and `ally` for a spot beside
## one): the centre of every known room the NPC is not in, then, with a threat, the cover spots on
## the ring round the NPC (`combat_ring_radius` x2) against the nearest and a spot beside each ally.
func _retreat_candidates(ctx: Dictionary, threats: Array, rooms: Array, ex: Array) -> Array:
	var self_pos: Vector2 = ctx["self_pos"]
	var candidates: Array = []
	for room in rooms:
		var rect: Rect2 = room["rect"]
		if rect.has_point(self_pos):
			continue
		candidates.append({
			"point": snap(ctx, rect.get_center()),
			"room": str(room.get("type", "room")).replace("_", " "),
		})
	if threats.is_empty():
		return candidates
	var nearest: Vector2 = threats[0]
	for p in fire_spots._self_cover_spots(
		self, ctx, { "pos": nearest }, ex, combat_ring_radius * 2.0
	):
		# A ring point off the navmesh is walked to its edge.
		candidates.append({ "point": NavBuilder.snap(ctx["map"], p), "room": "" })
	for a in ctx["allies"]:
		var spot := _beside(ctx, a["pos"], nearest)
		if spot != Vector2.INF:
			candidates.append({ "point": spot, "room": "", "ally": a["name"] })
	return candidates


## Whether a body at `p` is hidden from every one of `threats` (a wall or solid piece between), true
## with none. The body is a ducked one: a retreat takes cover there, so a piece low enough to shoot
## over a standing body but tall enough to hide a crouched one counts.
func _hidden_from(ctx: Dictionary, threats: Array, p: Vector2) -> bool:
	for t in threats:
		if not _shot_blocked(ctx, t, p, null, BodyHeights.DUCK):
			return false
	return true


## Annotate retreat candidate `c` (`hidden` from every threat or not) with its `hidden`, `cover`
## against the nearest of `threats`, `route_len` and `route_exposed`; false, leaving it as it was,
## when the walk there is under a `STRIDE` (where the NPC stands: the walk would be over before it
## began).
func _annotate_retreat(
	ctx: Dictionary,
	c: Dictionary,
	threats: Array,
	ex: Array,
	hidden: bool,
) -> bool:
	var path := _route(ctx, c["point"])
	var route_len := NavBuilder.path_length(path)
	if route_len < STRIDE:
		return false
	var cover := ""
	if not threats.is_empty():
		cover = cover_cached(ctx, c["point"], threats[0], ex)
	c["hidden"] = hidden
	c["cover"] = cover
	c["route_len"] = route_len
	c["route_exposed"] = (not threats.is_empty()
			and _route_exposed(ctx, path, threats[0]))
	return true


## Whether a walk from where the NPC stands to `p` is over the moment it begins: the point on the
## navmesh it ends at is within a `STRIDE` of walking (cheap straight-line test first).
func where_it_stands(ctx: Dictionary, p: Vector2) -> bool:
	var self_pos: Vector2 = ctx["self_pos"]
	var q := NavBuilder.snap(ctx["map"], p)
	return (self_pos.distance_to(q) < STRIDE
			and NavBuilder.path_length(_route(ctx, q)) < STRIDE)


## The spot beside the ally at `ally` that the NPC falls back to: `BESIDE_ALLY` px behind it from
## `threat` (the ally between the NPC and the threat), else to one side of it; open floor (the
## navmesh does not pull it) with no wall between it and the ally. INF when there is none.
func _beside(ctx: Dictionary, ally: Vector2, threat: Vector2) -> Vector2:
	var away := (ally - threat).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	for turn in [0.0, PI * 0.5, -PI * 0.5]:
		var p: Vector2 = ally + away.rotated(turn) * BESIDE_ALLY
		var q := NavBuilder.snap(ctx["map"], p)
		if q.distance_to(p) <= 3.0 and not blocked(ctx["space"], ally, q, ctx["exclude"]):
			return q
	return Vector2.INF


## The facts about standing at `p` to fight `target`: clear shot, cover, route length, exposure.
## `path` is the route there when the caller already has it.
func _annotate(
	ctx: Dictionary,
	target: Dictionary,
	p: Vector2,
	ex: Array,
	path := PackedVector2Array(),
) -> Dictionary:
	var tpos: Vector2 = target["pos"]
	if path.is_empty():
		path = _route(ctx, p)
	return {
		"point": p,
		"clear_shot": not _shot_blocked(ctx, p, tpos, target.get("node")),
		"cover": cover_cached(ctx, p, tpos, ex, AgentCover.viewer_of(target)),
		"route_len": NavBuilder.path_length(path),
		"route_exposed": false,
		"exposed_to": exposed_to(ctx, p, ctx["hostiles"], target["id"]),
	}


## Distance from `p` to the nearest of `threats` (INF with none).
func _nearest_gap(p: Vector2, threats: Array) -> float:
	var best := INF
	for t in threats:
		best = minf(best, p.distance_to(t))
	return best


## The contact's twin rid as a one-element array, for excluding it from a ray (empty when it is
## gone or has no twin).
func body_rid(contact: Dictionary) -> Array:
	return AgentCover.rids_of(contact)
