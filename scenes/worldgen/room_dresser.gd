class_name RoomDresser
## World Generation domain: dresses a furnished room the run-down way, placing what the Objects
## domain then draws. Where things gather is World-Gen's: a corner, along a wall, just beside a
## piece of furniture (`anchor`), never in a doorway.
##   - Clutter: 0-2 walk-over pieces a room (no key twice) from its recipe's `clutter`
##     (`[key, weight]` pairs; default GeneralCatalog.CLUTTER), each a catalogue piece spawned
##     through ObjectFactory, its own size and detail variant, the long ones lying along the edge
##     they hug.
##   - A neon tube along the foot of one wall in about every other room (GeneralCatalog `neon_tube`,
##     cyan or magenta).
##   - Wear: 0-3 clusters a room (more in a big one), each handed to the Objects domain's
##     WearFactory with the free stretch of wall it is by, which decides and draws its marks on the
##     floor and that wall.
## Every room draws from RNGs of its own, seeded by the run's seed and the room's key, so dressing
## never shifts the shared RNG: a seed keeps its furniture layout. Tuning: WorldGenConfig.dress_* /
## wear_* / clutter_* / neon_tube_*.

## How an anchor is drawn: a corner, ...
const _CORNER_CHANCE := 0.3
## ... else (below this) along a wall, else beside a piece of furniture.
const _WALL_CHANCE := 0.7


## Strew `site`'s clutter and maybe its neon tube under its furniture node (rects in the house's
## space): `clutter` its recipe's `[key, weight]` pairs, kept clear of its solid furniture and the
## doorway clearance boxes. Returns the clutter placed: `[{ key, node }]`.
static func strew(site: RoomSite, clutter: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([site.run_seed, site.room["key"], "clutter"])
	var out: Array = []
	var count := _clutter_count(rng)
	var kinds := clutter.duplicate()
	## The clutter footprints laid so far.
	var placed: Array = []
	for _i in count:
		if kinds.is_empty():
			break
		var key: String = WeightedPick.pick(rng, kinds)
		kinds = kinds.filter(func(row: Array) -> bool: return row[0] != key)
		var definition := _clutter_definition(key, rng)
		if definition.is_empty():
			continue
		var laid := _lay_clutter(site, definition, key, rng, placed)
		if not laid.is_empty():
			out.append(laid)
	_neon_tube(site, _here(site) + placed)
	return out


## How many clutter pieces a room gets: none, one or two.
static func _clutter_count(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	return (0
			if roll < WorldGenConfig.clutter_none_chance
			else (2 if roll >= 1.0 - WorldGenConfig.clutter_two_chance else 1))


## The catalogue piece `key` as clutter: its own size (`WorldGenConfig.clutter_scale`) and detail
## variant `v`; {} for an unknown key.
static func _clutter_definition(key: String, rng: RandomNumberGenerator) -> Dictionary:
	var definition := ObjectDefinitions.get_definition(key).duplicate(true)
	if definition.is_empty():
		push_error("RoomDresser: unknown clutter '%s'" % key)
		return definition
	var scale := WorldGenConfig.clutter_scale
	definition["size"] = (((definition["size"] as Vector2) * rng.randf_range(scale.x, scale.y)
			/ 2.0).round() * 2.0)
	definition["art_opts"] = (definition.get("art_opts", {}) as Dictionary).merged(
		{ "v": rng.randi_range(0, 5) },
		true,
	)
	return definition


## Lay one clutter piece of `definition` (catalogue key `key`) in `site`'s room at an anchor, a long
## one along the edge it hugs, off its solid furniture, the doorway boxes and the clutter `placed`
## so far (its footprint appended there). Returns `{ key, node }`, or {} when no try found a spot.
static func _lay_clutter(
	site: RoomSite,
	definition: Dictionary,
	key: String,
	rng: RandomNumberGenerator,
	placed: Array,
) -> Dictionary:
	var rect: Rect2 = site.room["rect"]
	var inner := _inner(site)
	var here := _here(site)
	var size: Vector2 = definition["size"]
	var long := size.x >= size.y * 2.0
	for _try in WorldGenConfig.dress_tries:
		var at := anchor(rng, inner, here)
		var rotated: bool = (at["along"] == Vector2.DOWN) if long else rng.randf() < 0.5
		var foot := Vector2(size.y, size.x) if rotated else size
		var p: Vector2 = (at["p"] as Vector2).clamp(
			inner.position + foot * 0.5,
			inner.end - foot * 0.5,
		)
		var r := Rect2(p - foot * 0.5, foot)
		if (not inner.encloses(r)
				or here.any(func(s: Rect2) -> bool: return s.grow(2.0).intersects(r))
				or placed.any(func(q: Rect2) -> bool: return q.grow(10.0).intersects(r))
				or site.blocked.any(func(b: Rect2) -> bool: return b.intersects(r))
				or not near_anchor(p, rect, here)):
			continue
		placed.append(r)
		var opts := { "rotated": rotated, "facing": _clutter_facing(rotated, rng), "name": key }
		return { "key": key, "node": ObjectFactory.spawn(definition, p, site.furniture, opts) }
	return {}


## Which way a clutter piece faces: either way along its length.
static func _clutter_facing(rotated: bool, rng: RandomNumberGenerator) -> Vector2:
	return ([Vector2.LEFT, Vector2.RIGHT][rng.randi_range(0, 1)]
			if rotated
			else [Vector2.DOWN, Vector2.UP][rng.randi_range(0, 1)])


## Where `site`'s dressing may lie: its room's rect inset from the walls by
## `WorldGenConfig.dress_inset`.
static func _inner(site: RoomSite) -> Rect2:
	var rect: Rect2 = site.room["rect"]
	return rect.grow(-(site.wall_thickness * 0.5 + WorldGenConfig.dress_inset))


## The footprints of `site`'s solid furniture within its room.
static func _here(site: RoomSite) -> Array:
	var rect: Rect2 = site.room["rect"]
	return site.solids.filter(func(s: Rect2) -> bool: return s.intersects(rect))


## Lay `site`'s wear (its room's rect in `parent`'s space) on its floor `floor_definition`: 0-3
## clusters by walls, corners and its solid furniture, each with the free stretch of wall it is by
## (not across a doorway: `doors` `{ pos, width }`), built by the Objects domain's WearFactory under
## `parent`. Returns the clusters, `[{ pos, layer }]` (`layer` the room's wear node), or `[]` for a
## room left bare.
static func wear(site: RoomSite, floor_definition: Dictionary, doors: Array, parent: Node) -> Array:
	var rect: Rect2 = site.room["rect"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([site.run_seed, site.room["key"], "wear"])
	var clusters := _wear_clusters(site, rng, _wear_count(rect, rng), doors)
	if clusters.is_empty():
		return []
	var plan := WearPlan.new()
	plan.floor_definition = floor_definition
	plan.wall_thickness = site.wall_thickness
	plan.clusters = clusters
	var layer := WearFactory.spawn(
		rect,
		plan,
		(site.room["key"] as String).capitalize() + " Wear",
		parent,
	)
	return clusters.map(
		func(c: Dictionary) -> Dictionary: return { "pos": c["pos"], "layer": layer },
	)


## How many wear clusters a room of `rect` gets: none or one, and one more per
## `WorldGenConfig.wear_more_area` it is bigger than, each by `wear_more_chance`.
static func _wear_count(rect: Rect2, rng: RandomNumberGenerator) -> int:
	var count := 0 if rng.randf() < WorldGenConfig.wear_bare_chance else 1
	for area: float in WorldGenConfig.wear_more_area:
		if rect.get_area() > area and rng.randf() < WorldGenConfig.wear_more_chance:
			count += 1
	return count


## Up to `count` wear clusters for `site`'s room, each at an anchor near a wall or its furniture:
## `{ pos, wall, seed }`, `wall` the free stretch of wall it is by (cut short of `doors`) or `[]`.
static func _wear_clusters(
	site: RoomSite,
	rng: RandomNumberGenerator,
	count: int,
	doors: Array,
) -> Array:
	var rect: Rect2 = site.room["rect"]
	var inner := _inner(site)
	var here := _here(site)
	var clusters: Array = []
	for _c in count:
		for _try in WorldGenConfig.dress_tries:
			var at := anchor(rng, inner, here)
			var p: Vector2 = at["p"]
			if not near_anchor(p, rect, here):
				continue
			var stretch: Array = _wall_stretch(p, rect, doors) if at["by_wall"] else []
			clusters.append({ "pos": p, "wall": stretch, "seed": rng.randi() })
			break
	return clusters


## A spot of `inner` where wear and clutter gather: a corner, along a wall, or just beside one of
## `solids`. Returns `{ p, along, by_wall }`: the point, the direction of the edge it hugs, and
## whether that edge is a wall.
static func anchor(rng: RandomNumberGenerator, inner: Rect2, solids: Array) -> Dictionary:
	var roll := rng.randf()
	var at: Dictionary
	if roll < _CORNER_CHANCE:
		at = _corner_anchor(rng, inner)
	elif roll < _WALL_CHANCE or solids.is_empty():
		at = _wall_anchor(rng, inner)
	else:
		at = _furniture_anchor(rng, solids)
	at["p"] = (at["p"] as Vector2).clamp(inner.position, inner.end)
	return at


## An anchor near one of `inner`'s corners, hugging either of its edges.
static func _corner_anchor(rng: RandomNumberGenerator, inner: Rect2) -> Dictionary:
	var corner := Vector2(
		inner.position.x if rng.randf() < 0.5 else inner.end.x,
		inner.position.y if rng.randf() < 0.5 else inner.end.y,
	)
	var inward := (inner.get_center() - corner).sign()
	var reach := WorldGenConfig.dress_reach
	var p := (corner
			+ inward
				* Vector2(rng.randf_range(reach.x, reach.y), rng.randf_range(reach.x, reach.y)))
	var along := Vector2.RIGHT if rng.randf() < 0.5 else Vector2.DOWN
	return { "p": p, "along": along, "by_wall": true }


## An anchor along one of `inner`'s walls, a little in from it.
static func _wall_anchor(rng: RandomNumberGenerator, inner: Rect2) -> Dictionary:
	var side := rng.randi_range(0, 3)
	var t := rng.randf_range(0.08, 0.92)
	var inset := rng.randf_range(WorldGenConfig.dress_reach.x, WorldGenConfig.dress_reach.y)
	var p := _wall_point(inner, side, t, inset)
	return { "p": p, "along": Vector2.RIGHT if side < 2 else Vector2.DOWN, "by_wall": true }


## An anchor just beside one of `solids`, a gap out from one of its sides.
static func _furniture_anchor(rng: RandomNumberGenerator, solids: Array) -> Dictionary:
	var s: Rect2 = solids[rng.randi_range(0, solids.size() - 1)]
	var side := rng.randi_range(0, 3)
	var gap := rng.randf_range(
		WorldGenConfig.dress_furniture_gap.x,
		WorldGenConfig.dress_furniture_gap.y,
	)
	var p: Vector2
	match side:
		0:
			p = Vector2(rng.randf_range(s.position.x, s.end.x), s.position.y - gap)
		1:
			p = Vector2(rng.randf_range(s.position.x, s.end.x), s.end.y + gap)
		2:
			p = Vector2(s.position.x - gap, rng.randf_range(s.position.y, s.end.y))
		_:
			p = Vector2(s.end.x + gap, rng.randf_range(s.position.y, s.end.y))
	return { "p": p, "along": Vector2.RIGHT if side < 2 else Vector2.DOWN, "by_wall": false }


## The point `t` (0..1) along wall `side` of `rect` (0 top, 1 bottom, 2 left, 3 right), `inset` px
## in from it.
static func _wall_point(rect: Rect2, side: int, t: float, inset: float) -> Vector2:
	match side:
		0:
			return Vector2(rect.position.x + rect.size.x * t, rect.position.y + inset)
		1:
			return Vector2(rect.position.x + rect.size.x * t, rect.end.y - inset)
		2:
			return Vector2(rect.position.x + inset, rect.position.y + rect.size.y * t)
		_:
			return Vector2(rect.end.x - inset, rect.position.y + rect.size.y * t)


## Whether `p` lies within WorldGenConfig.dress_near of a wall line of `rect` or of one of `solids`:
## where dressing belongs.
static func near_anchor(p: Vector2, rect: Rect2, solids: Array) -> bool:
	var near := WorldGenConfig.dress_near
	var to_x := minf(p.x - rect.position.x, rect.end.x - p.x)
	var to_y := minf(p.y - rect.position.y, rect.end.y - p.y)
	if minf(to_x, to_y) <= near:
		return true
	return solids.any(func(s: Rect2) -> bool:
		var d := Vector2(
			maxf(0.0, maxf(s.position.x - p.x, p.x - s.end.x)),
			maxf(0.0, maxf(s.position.y - p.y, p.y - s.end.y)),
		)
		return d.length() <= near)


## The free stretch of `rect`'s wall nearest `p` that `p` lies beside, `[a, b]` along the wall's
## centre line, cut short of every doorway in `doors` (`{ pos, width }`) on it; `[]` when `p` faces
## a doorway.
static func _wall_stretch(p: Vector2, rect: Rect2, doors: Array) -> Array:
	var wall := _nearest_wall(p, rect)
	var along: float = wall["along"]
	var lo := 0.0
	var hi: float = wall["length"]
	for door: Dictionary in doors:
		var span := _door_span(door, wall, rect)
		if span.is_empty():
			continue
		if along >= span[0] and along <= span[1]:
			return []
		if span[1] <= along:
			lo = maxf(lo, span[1])
		else:
			hi = minf(hi, span[0])
	var dir := Vector2.RIGHT if wall["horizontal"] else Vector2.DOWN
	var start: Vector2 = wall["start"]
	return [start + dir * lo, start + dir * hi]


## The wall of `rect` nearest `p`: `{ horizontal, line, start, length, along }`, whether it runs
## across, the x or y of its centre line, where it starts, how long it is and how far along it `p`
## lies.
static func _nearest_wall(p: Vector2, rect: Rect2) -> Dictionary:
	# 0 top, 1 bottom, 2 left, 3 right.
	var gaps := [p.y - rect.position.y, rect.end.y - p.y, p.x - rect.position.x, rect.end.x - p.x]
	var side := gaps.find(gaps.min())
	var horizontal := side < 2
	var line := ((rect.position.y if side == 0 else rect.end.y)
			if horizontal
			else (rect.position.x if side == 2 else rect.end.x))
	return {
		"horizontal": horizontal,
		"line": line,
		"start": Vector2(rect.position.x, line) if horizontal else Vector2(line, rect.position.y),
		"length": rect.size.x if horizontal else rect.size.y,
		"along": (p.x - rect.position.x) if horizontal else (p.y - rect.position.y),
	}


## The stretch `[a, b]` along `wall` (`_nearest_wall` of `rect`) that `door` (`{ pos, width }`)
## takes, its jambs (`WorldGenConfig.dress_jamb`) included; `[]` when the door is not on that wall.
static func _door_span(door: Dictionary, wall: Dictionary, rect: Rect2) -> Array:
	var horizontal: bool = wall["horizontal"]
	var at: Vector2 = door["pos"]
	if not is_equal_approx(at.y if horizontal else at.x, wall["line"]):
		return []
	var offset := (at.x - rect.position.x) if horizontal else (at.y - rect.position.y)
	if offset <= 0.0 or offset >= wall["length"]:
		return []
	return [
		offset - float(door["width"]) * 0.5 - WorldGenConfig.dress_jamb,
		offset + float(door["width"]) * 0.5 + WorldGenConfig.dress_jamb,
	]


## A neon tube along the foot of one of `site`'s walls (WorldGenConfig.neon_tube_chance of rooms),
## under its furniture node, clear of `taken` and its doorway boxes; its own RNG, so it never shifts
## the clutter's draws.
static func _neon_tube(site: RoomSite, taken: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([site.run_seed, site.room["key"], "neon"])
	if rng.randf() >= WorldGenConfig.neon_tube_chance:
		return
	var rect: Rect2 = site.room["rect"]
	var definition := ObjectDefinitions.get_definition("neon_tube").duplicate(true)
	var size: Vector2 = definition["size"]
	var inset := site.wall_thickness * 0.5 + size.y * 0.5 + 1.0
	for _try in WorldGenConfig.dress_tries:
		var side := rng.randi_range(0, 3)
		var p := _wall_point(rect, side, rng.randf_range(0.2, 0.8), inset)
		var rotated := side >= 2
		var foot := Vector2(size.y, size.x) if rotated else size
		var r := Rect2(p - foot * 0.5, foot)
		if (site.blocked.any(
					func(b: Rect2) -> bool: return b.grow(WorldGenConfig.dress_jamb).intersects(r)
				)
				or taken.any(func(s: Rect2) -> bool: return s.grow(2.0).intersects(r))):
			continue
		definition["art_opts"] = (definition.get("art_opts", {}) as Dictionary).merged(
			{ "tone": "cyan" if rng.randf() < 0.5 else "magenta" },
			true,
		)
		# A turned tube's art is turned with it, so its painter still draws along the canvas's
		# length.
		ObjectFactory.spawn(
			definition,
			p,
			site.furniture,
			{
				"rotated": rotated,
				"facing": Vector2.RIGHT if rotated else Vector2.DOWN,
				"name": "neon_tube",
			},
		)
		return
