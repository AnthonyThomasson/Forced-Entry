extends RefCounted
## AI PERCEPTION sub-domain — THROW: the geometry of a grenade. Pure queries over the physics space
## (through the vision sense's ray helpers) and the navigation map: whether a point is inside a
## grenade's danger zone, where the nearest safe spot is and how to reach it before the fuse runs
## out, and whether a lob can fly from one point to another. It returns DATA only and holds no
## policy. Its callers: the evade reflex (`agent_grenades.gd`, docs/grenades.md G16), the snapshot's
## `grenade_throws` group (the GRENADE tactic, G17) and the bang entry (G18), which ask the same
## questions of a grenade they are about to throw.
##
## **Cover** is the blast's own rule (G7), asked of the Projectile System (`Explosion.shields`,
## `Explosion.first_stop`): a wall always stops the line from the burst, a piece of furniture stops
## it when its `coverage` is above the height of the body, and the other characters stop nothing. A
## standing body and a crouched one have the heights the character reports (`learn_body`,
## `docs/cover-and-stance.md`; the current posture is read off the character's own surface). So a
## couch (45) shields a crouched body and not a standing one, a wall or a wardrobe both.
##
## **The danger zone** of a frag is a clear line to the burst within its blast radius plus
## `evade_margin`; of a stun, a clear line within its flash radius. A **safe spot** is out of the
## burst's line (a wall or tall piece between: "round a corner"), or behind furniture that shields a
## crouched body (the NPC crouches there), or outside the zone altogether.

## How far (px) past the zone's edge a spot counts as outside it, so a body arriving a step short is
## not back inside.
const OUTSIDE_SLACK := 30.0
## The stamina (fraction of a full bar) below which the NPC is taken to walk and not run, and the
## share of its running speed it counts on (the route has corners and it must turn: it plans to be
## in place with room to spare).
const RUN_STAMINA := 0.3
const RUN_RELIABILITY := 0.85
## Seconds before the burst the NPC should be in place (it must also turn and crouch).
const ARRIVE_MARGIN := 0.4
## How far (px) a candidate may be pulled by navmesh snapping before it is dropped.
const SNAP_TOLERANCE := 40.0
## Candidates: the circle beyond the zone and the shadows behind what stands near the burst
## (directions each), how far (px) behind an obstacle a shadow spot is put, and the rings round the
## NPC (radii, directions).
const CIRCLE_DIRECTIONS := 24
const SHADOW_DIRECTIONS := 24
const SHADOW_STEPS := [32.0, 72.0]
## The shadow behind a piece also gets a spot right against its far face: the ray back from this far
## (px) past the hit finds that face, and a body stands this far (px) off it.
const FAR_PROBE := 160.0
const FAR_STEP := 20.0
## A cover spot must also be shielded this far (px) to either side of it.
const COVER_MARGIN := 10.0
const RING_RADII := [60.0, 120.0, 180.0, 240.0, 300.0]
const RING_DIRECTIONS := 12
## What a lob clears over the whole way (px, the `coverage` scale): the height a grenade leaves the
## hand at. A piece of furniture above it is struck near the thrower; the arc rises over the middle,
## so this is the safe reading.
const LOB_CLEARANCE := 50.0
## Where a grenade leaves a thrower that stands facing its aim: its throwing hand
## (`Character.inventory.throw_release_offset`, learned with the grenades it carries), held off a
## wall the way the character's own hand is, `HAND_RADIUS` px short of it. A lob is clear only when
## the band `LOB_MARGIN` px either side of the line from there is clear the whole way (the grenade's
## own body and the hand's sway): a line from the thrower's centre that grazes a jamb by a pixel, or
## a line that clears it by less than the grenade's width, is a grenade that strikes it.
const HAND_RADIUS := 3.0
const LOB_MARGIN := 8.0
## How far (px) from a spot it walks to a thrower may end up (the walk's own arrival:
## `Combat.THROW_SPOT_REACH`, the entry's `SLOT_REACH`): a throw from a spot it walks to is judged
## from there and from this far off it either way (`throw_clear_on_arrival`).
const ARRIVAL_SLACK := 6.0
## How far (px) inside a grenade's range a thrower stands to let it go (`reach_of`): one that
## drifted a step past it closes in on its spot before it throws, and a throw spot is chosen within
## it.
const REACH_SLACK := 15.0
## The inventory slot of each kind of grenade (Items: `ItemRegistry`).
const SLOTS := { &"frag": ItemRegistry.FRAG_SLOT, &"stun": ItemRegistry.STUN_SLOT }
## A spot's verdict in `escape`: not judged yet, out of the zone or shielded standing, shielded only
## crouched, or neither.
const UNJUDGED := -1
const SAFE_STANDING := 0
const SAFE_CROUCHED := 1
const NOT_SAFE := 2

# --- What every NPC fleeing one burst shares ------------------------------------------------------

## An evade wave is several NPCs planning their escape from one grenade on one physics frame
## (docs/grenades.md G16), and most of `escape`'s work depends on the burst alone: the candidates
## round it (`_around`: about 50 rays), where each candidate lies on the navmesh and each spot's
## verdict (the blast's lines, `Explosion.shields`). That work is done once and shared for the rest
## of the physics frame. Inside one the space and the map hold still for these queries: furniture
## moves in the physics step, a dented collider is rebuilt deferred, the navigation map syncs after
## the frame's callbacks, and the characters are excluded. So what is shared is what each NPC would
## work out itself, and the spot it picks is the same. Outside a physics frame
## (`Engine.is_in_physics_frame()` false: the step may have run since) nothing is kept.
static var _shared_frame := -1
## [space, burst, kind, out_r, reach, stand height, crouch height, excluded rid ids] -> { around:
## `_around`, judged: spot -> verdict }. A grenade that moved, or an NPC whose heights, margin or
## exclusions differ, has its own entry.
static var _bursts := {}
## Navigation map -> { candidate -> its spot on the navmesh }.
static var _snaps := {}

## The perception's sight sense; owner of the ray queries.
var vision: RefCounted
## How far past a frag's blast radius its danger zone reaches (px).
var evade_margin: float = 120.0
## Kind -> what the NPC knows of that grenade (`Character.inventory.throw_stats`,
## `ThrownGrenade.throw_stats`); see `learn`.
var _stats := {}
## The height of a standing body on the coverage scale (`CharacterMovement.posture_coverage`); tall
## until it is learned.
var _stand := 100.0
## The same for a crouched one.
var _crouch := 100.0
## Where a grenade leaves the NPC's hand, in its frame (`Character.inventory.throw_release_offset`:
## x ahead, y to its right); the centre until learned.
var _release := Vector2.ZERO
## The NPC's body (`bind`): the grenades it carries, its heights and its pace.
var _character: Node


## Hand in the NPC's body. Called once by `AgentPerception.bind()`.
func bind(character: Node) -> void:
	_character = character


# --- The grenades it carries ----------------------------------------------------------------------


## How many grenades of `kind` `character` carries (`Character.inventory.item_count`).
static func count(character: Node, kind: StringName) -> int:
	return int(character.inventory.item_count(SLOTS[kind]))


## The kinds `character` carries, a frag first: `[&"frag", &"stun"]` less those it has none of.
static func carried(character: Node) -> Array:
	return SLOTS.keys().filter(func(k): return count(character, k) > 0)


## Learn a grenade's numbers (`{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind
## }`): off one it carries or one it sees fly. The AI keeps no copy of the tuning; what it knows of
## a kind is what a grenade of that kind last told it, and stays known after the last one is thrown.
func learn(stats: Dictionary) -> void:
	if not stats.is_empty():
		_stats[stats["kind"]] = stats


## Learn the numbers of every grenade the NPC carries (`Character.inventory.throw_stats`), and where
## one leaves its hand (`Character.inventory.throw_release_offset`).
func learn_carried() -> void:
	for slot: int in SLOTS.values():
		var stats: Dictionary = _character.inventory.throw_stats(slot)
		learn(stats)
		if not stats.is_empty():
			_release = _character.inventory.throw_release_offset(slot)


## Learn the heights of a standing and of a crouched body off the NPC's own
## (`CharacterMovement.posture_coverage`), the figures furniture is measured against.
func learn_body() -> void:
	_stand = _character.movement.posture_coverage(&"stand")
	_crouch = _character.movement.posture_coverage(&"crouch")


## The height of a standing body on the coverage scale.
func stand_height() -> float:
	return _stand


## The height of a crouched body.
func crouch_height() -> float:
	return _crouch


## How far (px) a throw of `kind` first comes down; 0 for a kind it has never met.
func range_of(kind: StringName) -> float:
	return float(_stats.get(kind, {}).get("max_range", 0.0))


## How far (px) from its spot a thrower stands to let a grenade of `kind` go: its range less
## `REACH_SLACK`.
func reach_of(kind: StringName) -> float:
	return maxf(range_of(kind) - REACH_SLACK, 0.0)


## The blast radius of a frag, the flash radius of a stun; 0 for a kind it has never met.
func radius_of(kind: StringName) -> float:
	return float(_stats.get(kind, {}).get("danger_radius", 0.0))


## The longest (s) a stun of `kind` blinds anyone; 0 for a frag, and for a kind it has never met.
func max_blind_of(kind: StringName) -> float:
	return float(_stats.get(kind, {}).get("max_blind", 0.0))


## Seconds from release to the burst; 0 for a kind it has never met.
func fuse_of(kind: StringName) -> float:
	return float(_stats.get(kind, {}).get("fuse", 0.0))


# --- The danger zone ------------------------------------------------------------------------------


## How far (px) from a burst of `kind` whose danger `radius` is given the danger zone reaches: a
## frag's blast radius and the margin, a stun's flash radius.
func zone_radius(kind: StringName, radius: float) -> float:
	return radius + evade_margin if kind == &"frag" else radius


## Whether a body `height` tall at `p` is inside the danger zone of grenade `threat` (its kind, its
## danger radius and where it bursts; the fuse is not read): within the zone's reach and not
## shielded from the burst. `exclude` holds the characters' rids (bodies stop nothing).
func in_zone(
	space: PhysicsDirectSpaceState2D,
	threat: GrenadeThreat,
	p: Vector2,
	height: float,
	exclude: Array,
) -> bool:
	return (p.distance_to(threat.burst) <= zone_radius(threat.kind, threat.radius)
			and not shielded(
				space, threat.burst, p, _cover_rule(height, exclude, cover_reach(threat.kind))
			))


## Whether something between `burst` and `p` shields a body at `p` by `cover` (its height, the rids
## the line passes through, the reach): a wall, or furniture taller than the body, by the blast's
## own rule (`Explosion.shields`). With a finite reach (a stun's flash, `cover_reach`) a piece of
## furniture only stops the line when `p` is within that many px of it, on the burst's side.
func shielded(
	space: PhysicsDirectSpaceState2D,
	burst: Vector2,
	p: Vector2,
	cover: CoverRule,
) -> bool:
	return Explosion.shields(space, burst, p, cover)


## How near (px) a body must be to furniture for it to shield it from a burst of `kind`: a stun's
## `flash_cover_reach`, any distance (INF) for a frag's blast, and for a kind it has never met.
func cover_reach(kind: StringName) -> float:
	return float(_stats.get(kind, {}).get("flash_cover_reach", INF))


# --- The escape -----------------------------------------------------------------------------------


## The nearest (by route) safe spot the `runner` (at `from`, walking `speed` px/s) can reach before
## the grenade `threat` (its `kind`, danger `radius`, at `burst`) goes off in `fuse_left` s:
## `{ spot, crouch, route }` (`crouch`: it is behind furniture that shields a crouched body only),
## or `{ spot: Vector2.INF }` when there is none in time. Candidates are the circle just outside the
## zone, the shadows behind whatever stands round the burst and a ring round the NPC; each is
## snapped onto the navmesh and judged by the shielding rule, every one that passes is routed (a
## straight line says nothing: a spot just behind a wall can be a house away by walking) and the
## shortest route that is in time wins. What depends on the burst alone (the candidates round it,
## each candidate's spot on the navmesh, each spot's verdict) is shared with every NPC that asks
## about the same burst on the same physics frame (`_shared_burst`); the routes are the NPC's own.
func escape(
	space: PhysicsDirectSpaceState2D,
	map: RID,
	threat: GrenadeThreat,
	runner: GrenadeRunner,
	exclude: Array,
) -> Dictionary:
	var from := runner.from
	var out_r := zone_radius(threat.kind, threat.radius) + OUTSIDE_SLACK
	var standing := _cover_rule(_stand, exclude, cover_reach(threat.kind))
	# Candidates often repeat (the standing and the crouching probe meet the same wall) and snap
	# onto the same spot, so each point is snapped, each spot judged and each route measured once:
	# the same answers, in the same order.
	var shared := _shared_burst(space, threat.burst, out_r, exclude, threat.kind)
	var on_mesh: Dictionary = _shared_snaps(map)  # candidate -> its spot on the navmesh
	# spot -> NOT_SAFE, or whether it is safe only crouched
	var judged: Dictionary = shared["judged"]
	var spots: Array = []
	for p in [from] + shared["around"] + _ring(from):
		var q: Vector2 = on_mesh.get(p, Vector2.INF)
		if q == Vector2.INF:
			q = NavBuilder.snap(map, p)
			on_mesh[p] = q
		if q.distance_to(p) > SNAP_TOLERANCE:
			continue
		var verdict: int = judged.get(q, UNJUDGED)
		if verdict == UNJUDGED:
			verdict = _judge(space, threat, q, standing)
			judged[q] = verdict
		if verdict != NOT_SAFE:
			spots.append({ "spot": q, "crouch": verdict == SAFE_CROUCHED })
	return _nearest_in_time(
		map,
		from,
		spots,
		maxf(threat.fuse_left - ARRIVE_MARGIN, 0.0) * runner.speed,
	)


## The verdict on spot `q` for the grenade `threat`, judged with the `standing` body's cover rule:
## `SAFE_STANDING` outside the zone or shielded standing, `SAFE_CROUCHED` shielded only crouched,
## else `NOT_SAFE`.
func _judge(
	space: PhysicsDirectSpaceState2D,
	threat: GrenadeThreat,
	q: Vector2,
	standing: CoverRule,
) -> int:
	if (q.distance_to(threat.burst) >= zone_radius(threat.kind, threat.radius) + OUTSIDE_SLACK
			or _covered(space, threat.burst, q, standing)):
		return SAFE_STANDING
	var crouched := _cover_rule(_crouch, standing.exclude, standing.cover_reach)
	return SAFE_CROUCHED if _covered(space, threat.burst, q, crouched) else NOT_SAFE


## Of `spots` (`{ spot, crouch }`, safe ones), the one with the shortest route from `from` on
## navigation `map` that is at most `allowed` px long: `{ spot, crouch, route }`, or
## `{ spot: Vector2.INF }` when none is. Each spot's route is measured once.
static func _nearest_in_time(map: RID, from: Vector2, spots: Array, allowed: float) -> Dictionary:
	var best := { "spot": Vector2.INF, "crouch": false, "route": INF }
	var routes := {}  # spot -> its route's length
	for s: Dictionary in spots:
		var length: float = routes.get(s["spot"], -1.0)
		if length < 0.0:
			length = NavBuilder.path_length(NavBuilder.route(map, from, s["spot"]))
			routes[s["spot"]] = length
		if length <= allowed and length < best["route"]:
			best = { "spot": s["spot"], "crouch": s["crouch"], "route": length }
	return best


## The cover rule of a body `height` tall on lines through the rids `exclude` (bodies stop nothing),
## furniture counting within `reach` px of the body (`cover_reach`).
static func _cover_rule(height: float, exclude: Array, reach: float) -> CoverRule:
	var cover := CoverRule.new()
	cover.height = height
	cover.exclude = exclude
	cover.cover_reach = reach
	return cover


## The work shared on this physics frame for a burst at `burst` judged with the zone `out_r` and
## this NPC's heights: `{ around, judged }` (`judged` filled as spots are judged), made now when no
## NPC has asked yet, and fresh outside a physics frame.
func _shared_burst(
	space: PhysicsDirectSpaceState2D,
	burst: Vector2,
	out_r: float,
	exclude: Array,
	kind: StringName,
) -> Dictionary:
	var keep := _this_frame()
	var key: Array = ([space, burst, kind, out_r, cover_reach(kind), _stand, _crouch, _ids(exclude)]
			if keep
			else [])
	var entry: Dictionary = _bursts.get(key, {}) if keep else {}
	if entry.is_empty():
		entry = { "around": _around(space, burst, out_r, exclude, kind), "judged": {} }
		if keep:
			_bursts[key] = entry
	return entry


## The candidates snapped onto navigation `map` on this physics frame (filled as they are snapped),
## or a fresh dictionary outside one.
static func _shared_snaps(map: RID) -> Dictionary:
	if not _this_frame():
		return {}
	if not _snaps.has(map):
		_snaps[map] = {}
	return _snaps[map]


## Whether this runs inside a physics frame, what is shared then being that frame's (dropped when a
## new one began).
static func _this_frame() -> bool:
	if not Engine.is_in_physics_frame():
		return false
	var frame := Engine.get_physics_frames()
	if frame != _shared_frame:
		_shared_frame = frame
		_bursts.clear()
		_snaps.clear()
	return true


## The ids of `rids`, sorted: the set of bodies a line passes through, whatever order the caller
## listed them in.
static func _ids(rids: Array) -> Array:
	var ids: Array = rids.map(func(r: RID) -> int: return r.get_id())
	ids.sort()
	return ids


## Whether a body at `p` is shielded from `burst` by the `cover` rule (its height, the rids the line
## passes through, the reach) with room to spare: also `COVER_MARGIN` px to either side of the line,
## so a spot on the edge of a shadow (and a body that stops a step short of it) is not taken for
## one.
func _covered(
	space: PhysicsDirectSpaceState2D,
	burst: Vector2,
	p: Vector2,
	cover: CoverRule,
) -> bool:
	var side := (p - burst).normalized().orthogonal() * COVER_MARGIN
	return (shielded(space, burst, p, cover)
			and shielded(space, burst, p + side, cover)
			and shielded(space, burst, p - side, cover))


## The candidate spots for an escape (unsnapped, unjudged): where the NPC stands (already behind
## cover that shields a crouched body, it need not move), the circle just outside the zone of the
## grenade `threat`, the shadows behind the obstacles a ray from its burst meets, and a ring round
## `from`. `exclude` holds the characters' rids.
func _candidates(
	space: PhysicsDirectSpaceState2D,
	threat: GrenadeThreat,
	from: Vector2,
	exclude: Array,
) -> Array:
	var out_r := zone_radius(threat.kind, threat.radius) + OUTSIDE_SLACK
	return [from] + _around(space, threat.burst, out_r, exclude, threat.kind) + _ring(from)


## The candidates that depend on the burst alone: the circle `out_r` round it and the shadows behind
## the obstacles a ray from it meets.
func _around(
	space: PhysicsDirectSpaceState2D,
	burst: Vector2,
	out_r: float,
	exclude: Array,
	kind: StringName,
) -> Array:
	var out: Array = []
	for i in CIRCLE_DIRECTIONS:
		out.append(burst + Vector2.from_angle(TAU * i / CIRCLE_DIRECTIONS) * out_r)
	for i in SHADOW_DIRECTIONS:
		var dir := Vector2.from_angle(TAU * i / SHADOW_DIRECTIONS)
		for height in [_crouch, _stand]:
			var hit := Explosion.first_stop(space, burst, burst + dir * out_r, height, exclude)
			if hit.is_empty():
				continue
			for step: float in SHADOW_STEPS:
				out.append((hit["position"] as Vector2) + dir * step)
			if kind != &"stun":
				continue
			var far := _far_face(space, hit["position"], dir, exclude)
			if not far.is_empty():
				# Right against the piece's far face: the cover a flash respects.
				out.append((far["position"] as Vector2) + dir * FAR_STEP)
	return out


## The far face of what a ray from a burst along `dir` met at `at`: the ray back from `FAR_PROBE` px
## past it, or {} when nothing is there.
func _far_face(
	space: PhysicsDirectSpaceState2D,
	at: Vector2,
	dir: Vector2,
	exclude: Array,
) -> Dictionary:
	return vision.raycast(space, at + dir * FAR_PROBE, at, exclude)


## The candidates round the NPC at `from`: `RING_RADII` x `RING_DIRECTIONS`.
func _ring(from: Vector2) -> Array:
	var out: Array = []
	for radius: float in RING_RADII:
		for i in RING_DIRECTIONS:
			out.append(from + Vector2.from_angle(TAU * i / RING_DIRECTIONS) * radius)
	return out


## The speed (px/s) the NPC counts on to cover ground when it runs for it (`RUN_RELIABILITY` of
## `CharacterMovement.run_speed`), or its walk (`CharacterMovement.walk_speed`) once its stamina is
## low.
func run_speed() -> float:
	return (_character.movement.run_speed() * RUN_RELIABILITY
			if _character.movement.stamina_fraction() > RUN_STAMINA
			else _character.movement.walk_speed())


# --- The lob --------------------------------------------------------------------------------------


## Whether a thrower standing at `at` can lob a grenade onto `to`: within `max_range` of it, and the
## lob from its hand is clear (`throw_clear`). `exclude` holds the characters' rids.
func can_lob(
	space: PhysicsDirectSpaceState2D,
	at: Vector2,
	to: Vector2,
	max_range: float,
	exclude: Array,
) -> bool:
	return at.distance_to(to) <= max_range and throw_clear(space, at, to, exclude)


## Whether the lob a thrower standing at `at` throws onto `to` flies clear, whatever the distance:
## the band `LOB_MARGIN` px either side of the line from where the grenade leaves its hand
## (`release_point`) to `to`, its middle and both edges.
func throw_clear(
	space: PhysicsDirectSpaceState2D,
	at: Vector2,
	to: Vector2,
	exclude: Array,
) -> bool:
	var hand := release_point(space, at, to, exclude)
	var side := (to - hand).normalized().orthogonal() * LOB_MARGIN
	for lateral: Vector2 in [Vector2.ZERO, side, -side]:
		if not lob_clear(space, hand + lateral, to + lateral, exclude):
			return false
	return true


## Whether the lob onto `to` is clear for a thrower that walks to `at`: from `at` and from
## `ARRIVAL_SLACK` px off it in each of the four directions, where the walk may end (a spot clear
## only to the pixel is a jamb struck by a thrower that stops a stride's sliver short).
func throw_clear_on_arrival(
	space: PhysicsDirectSpaceState2D,
	at: Vector2,
	to: Vector2,
	exclude: Array,
) -> bool:
	if not throw_clear(space, at, to, exclude):
		return false
	for off: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		if not throw_clear(space, at + off * ARRIVAL_SLACK, to, exclude):
			return false
	return true


## Where a grenade thrown onto `to` leaves a thrower standing at `at`: its throwing hand (the
## learned release offset, as it faces `to`), or, with a wall or solid piece closer than that, the
## hand held against it, as the character's own hand is.
func release_point(
	space: PhysicsDirectSpaceState2D,
	at: Vector2,
	to: Vector2,
	exclude: Array,
) -> Vector2:
	var toward := (to - at).normalized()
	if toward == Vector2.ZERO or _release == Vector2.ZERO:
		return at
	var hand := at + toward * _release.x + toward.rotated(PI * 0.5) * _release.y
	var hit: Dictionary = vision.raycast(space, at, hand, exclude)
	if hit.is_empty():
		return hand
	return (hit["position"] as Vector2) - (hand - at).normalized() * HAND_RADIUS


## Whether nothing stops a lob on the straight line from `from` to `to`, low furniture included (no
## wall or piece taller than `LOB_CLEARANCE`), whatever the distance.
func lob_clear(
	space: PhysicsDirectSpaceState2D,
	from: Vector2,
	to: Vector2,
	exclude: Array,
) -> bool:
	return not shielded(space, from, to, _cover_rule(LOB_CLEARANCE, exclude, INF))
