class_name StreetLamps
## World Generation domain: the street lamps along a sidewalk and the door rule that keeps them
## clear of doorways, shared by a lone house's street ring (`HouseSpawner`) and a district's
## sidewalks (`DistrictSpawner`). A lamp stands `streetlight_curb` px in from the curb with its arm
## out over the road, one about every `streetlight_every` px, jittered; every other one is a neon
## `street_sign`. A lamp any part of which (post square or overhang) would stand by a front or exit
## doorway (`door_zones`) is dropped, not moved. Tuning: `WorldGenStreetConfig`.


## The run of posts along `rect`'s `out` edge (the curb: `out` is a unit axis direction, the way to
## the road): `{ a, b, facing }`, the posts' line from `a` to `b` (the whole edge,
## `streetlight_curb` px in from it) and the way their arms point.
static func run_along(rect: Rect2, out: Vector2) -> Dictionary:
	var curb := WorldGenStreetConfig.streetlight_curb
	var a: Vector2
	var b: Vector2
	if out.y != 0.0:
		var y := rect.end.y - curb if out.y > 0.0 else rect.position.y + curb
		a = Vector2(rect.position.x, y)
		b = Vector2(rect.end.x, y)
	else:
		var x := rect.end.x - curb if out.x > 0.0 else rect.position.x + curb
		a = Vector2(x, rect.position.y)
		b = Vector2(x, rect.end.y)
	return { "a": a, "b": b, "facing": out }


## The lamps along `run` (`run_along`), spawned under `holder` through ObjectFactory (`streetlight`
## and, every other one, `street_sign`): the row centred on the run, about one every
## `streetlight_every` px, each jittered along it by up to `streetlight_jitter`. Those that stand
## clear of every zone of `zones` (`door_zones`) are kept; `rng` draws a jitter and a neon colour
## for each, kept or not. A lamp whose post meets a rect of `keepouts` is dropped as well (a
## district's crossings). Returns `[{ pos, node }]`, `pos` in WORLD space.
static func place(
	holder: Node2D,
	run: Dictionary,
	zones: Array,
	rng: RandomNumberGenerator,
	keepouts: Array = [],
) -> Array:
	var out: Array = []
	var spots := _spots(run, rng)
	for i: int in spots.size():
		var definition := ObjectDefinitions.get_definition("street_sign"
				if i % 2 == 1
				else "streetlight")
		var at: Vector2 = spots[i]["at"]
		var rects := extent(definition, at, run["facing"])
		if not clear_of_doors(rects, zones) or _meets(rects[0], keepouts):
			continue
		var node := ObjectFactory.spawn(
			definition,
			at,
			holder,
			{ "facing": run["facing"], "neon": spots[i]["neon"] if i % 2 == 1 else "" },
		)
		out.append({ "pos": holder.to_global(at), "node": node })
	return out


## Whether `rect` meets some rect of `keepouts`.
static func _meets(rect: Rect2, keepouts: Array) -> bool:
	return keepouts.any(func(keepout: Rect2) -> bool: return rect.intersects(keepout))


## `run` shortened by `inset` px at each end (a run too short to keep one is returned as it is).
static func trim(run: Dictionary, inset: float) -> Dictionary:
	var from: Vector2 = run["a"]
	var to: Vector2 = run["b"]
	if from.distance_to(to) <= inset * 2.0:
		return run
	var along := (to - from).normalized()
	return { "a": from + along * inset, "b": to - along * inset, "facing": run["facing"] }


## The lamps' spots along `run`, `[{ at, neon }]`: the row centred on it, one about every
## `streetlight_every` px, each jittered along it, with a neon colour drawn from `rng` (the jitter,
## then the colour, for each spot).
static func _spots(run: Dictionary, rng: RandomNumberGenerator) -> Array:
	var from: Vector2 = run["a"]
	var along: Vector2 = (run["b"] - from).normalized()
	var length: float = from.distance_to(run["b"])
	var every := WorldGenStreetConfig.streetlight_every
	var count := maxi(1, int(length / every))
	var first := (length - (count - 1) * every) * 0.5
	var spots: Array = []
	for i: int in count:
		var jitter := rng.randf_range(
			-WorldGenStreetConfig.streetlight_jitter,
			WorldGenStreetConfig.streetlight_jitter,
		)
		spots.append({
			"at": from + along * (first + i * every + jitter),
			"neon": "cyan" if rng.randf() < 0.5 else "magenta",
		})
	return spots


## Where a lamp of `definition` at `at` with its arm out along `facing` stands: its post's bounding
## square and its overhang.
static func extent(definition: Dictionary, at: Vector2, facing: Vector2) -> Array:
	var size: Vector2 = definition["size"]
	var rects: Array = [Rect2(at - size * 0.5, size)]
	var overhang: Dictionary = definition.get("overhang", {})
	if not overhang.is_empty():
		var canonical: Vector2 = overhang["size"]
		var drawn := (Vector2(canonical.y, canonical.x)
				if absf(facing.x) > absf(facing.y)
				else canonical)
		rects.append(Rect2(at + facing * float(overhang["reach"]) - drawn * 0.5, drawn))
	return rects


## The no-lamp zone of each front or exit doorway of `openings` (`{ pos, width, front?, exit? }` on
## the walls of `rooms`, one frame throughout): `{ pos, strip }`, its centre and the strip straight
## out of it (its width plus `streetlight_door_strip_margin` each side,
## `streetlight_door_strip_reach` out from the wall of its room it lies on). A district joins the
## zones of every tower.
static func door_zones(rooms: Array, openings: Array) -> Array:
	var zones: Array = []
	for opening in openings:
		if not (opening.get("front", false) or opening.get("exit", false)):
			continue
		var p: Vector2 = opening["pos"]
		var outward := HouseSpawner.outward_on(rooms, opening)
		if outward.size() != 1:
			continue
		var out: Vector2 = outward[0]
		var half: float = (
			opening["width"] * 0.5 + WorldGenStreetConfig.streetlight_door_strip_margin
		)
		var across := Vector2(out.y, out.x).abs()
		var strip := Rect2(p - across * half, Vector2.ZERO).expand(p + across * half
				+ out * WorldGenStreetConfig.streetlight_door_strip_reach)
		zones.append({ "pos": p, "strip": strip })
	return zones


## Whether every rect of `rects` keeps `streetlight_door_clear` from each zone's doorway and out of
## its strip.
static func clear_of_doors(rects: Array, zones: Array) -> bool:
	for zone: Dictionary in zones:
		var p: Vector2 = zone["pos"]
		for rect: Rect2 in rects:
			if (p.distance_to(p.clamp(rect.position, rect.end))
					< WorldGenStreetConfig.streetlight_door_clear):
				return false
			if rect.intersects(zone["strip"]):
				return false
	return true
