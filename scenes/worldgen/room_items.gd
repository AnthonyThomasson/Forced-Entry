class_name RoomItems
## World Generation domain: places a room's small items (#194 stack-b, D20, `docs/stacked-items.md`
## SI9): a few on a flat top (tableware on tables and counters, books, lamps and monitors on desks
## and shelves) and, in a storage room, garage or office, boxes and crates stacked two or three
## high on the floor. What goes where is data (`ItemsCatalog.TOPS`, `TOPS_BY_ART`, `FLOOR`), how
## many and how likely is `WorldGenItemConfig`. Each is built through `ObjectFactory.spawn_on` (a
## free body resting on its base, `docs/stacked-items.md` SI2).
## Every room draws from an RNG of its own, `hash([run seed, room key, "items"])`, and runs after
## the
## furniture, the clutter and the neon: the items never shift a seed's layout, doors or dressing.
## Nothing here is added to `RoomSite.solids`, so the wear goes where it went.

## How far (px) an item's edge stays from a painted prop's centre.
const PROP_CLEAR := 4.0


## The items a generated `house` placed as `[{ room, key, node, on }]`: `room` the room's key, `key`
## the item's catalogue key, `node` the item (a free body resting on its base) and `on` the piece it
## rests on (null for the bottom of a floor stack on the floor). Empty for a null house, a hand-laid
## layout or a house built with `worldgen.items` off. (A test read, interface 1.)
static func placed_in(house: Node2D) -> Array:
	if house == null:
		return []
	return house.get_meta("items", [])


## Place `site`'s items under `site.items` (the furniture is built, in `site.pieces`): returns
## `[{ room, key, node, on }]` (`placed_in`). Nothing when `WorldGenItemConfig.enabled` is off.
static func place(site: RoomSite) -> Array:
	if not WorldGenItemConfig.enabled or site.items == null:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([site.run_seed, site.room["key"], "items"])
	var out: Array = []
	for piece: Dictionary in site.pieces:
		out.append_array(_on_top(site, piece, rng))
	out.append_array(_floor_stacks(site, rng))
	return out


## The items on the top of `piece` (`{ key, definition, node }`): none, or 1 to `top_max` with
## `top_chance`, each of its catalogue row's kinds (`ItemsCatalog.options_for`), kept inside the top
## and off the props its art paints.
static func _on_top(site: RoomSite, piece: Dictionary, rng: RandomNumberGenerator) -> Array:
	var base: Node2D = piece["node"]
	var options := ItemsCatalog.options_for(piece["key"], piece["definition"])
	if options.is_empty() or base == null or rng.randf() >= WorldGenItemConfig.top_chance:
		return []
	var top := {
		"base": base,
		"rect": Rect2(base.position - base.size * 0.5, base.size).grow(-WorldGenItemConfig.edge),
		"props": _prop_points(base),
		"laid": [] as Array[Rect2],
	}
	var out: Array = []
	for _i in rng.randi_range(1, WorldGenItemConfig.top_max):
		out.append_array(_one_on(site, top, WeightedPick.pick(rng, options), rng))
	return out


## One item `key` on `top` (`{ base, rect, props, laid }`): `[]` when no try finds it a place, else
## it, and a second on it now and then when it is a plate or a book.
static func _one_on(
	site: RoomSite,
	top: Dictionary,
	key: String,
	rng: RandomNumberGenerator,
) -> Array:
	var definition := ObjectDefinitions.get_definition(key)
	var facing := _facing_of(top["base"], key, rng)
	var rotated := facing.x != 0.0
	var foot: Vector2 = definition["size"]
	foot = Vector2(foot.y, foot.x) if rotated else foot
	var at := _spot_on(top, foot, rng)
	if at.x == INF:
		return []
	(top["laid"] as Array[Rect2]).append(Rect2(at - foot * 0.5, foot))
	var opts := { "rotated": rotated, "facing": facing, "name": key }
	var out: Array = [_set_on(site, top["base"], definition, at, opts)]
	if key in ItemsCatalog.STACKS_ON_TOPS and rng.randf() < WorldGenItemConfig.stack_chance:
		var jitter := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		out.append(_set_on(site, top["base"], definition, at + jitter, opts))
	return out


## `definition` set on `base` at plan point `at` (the furniture node's space): the item's entry.
static func _set_on(
	site: RoomSite,
	base: Node2D,
	definition: Dictionary,
	at: Vector2,
	opts: Dictionary,
) -> Dictionary:
	var node := ObjectFactory.spawn_on(definition, base, at - base.position, site.items, opts)
	return { "room": site.room["key"], "key": opts["name"], "node": node, "on": base }


## Which way the item `key` on `base` faces: a monitor the way its desk does (toward the one who
## sits there), the rest any of the four.
static func _facing_of(base: Node2D, key: String, rng: RandomNumberGenerator) -> Vector2:
	var drawn: Vector2 = [
		Vector2.DOWN,
		Vector2.UP,
		Vector2.LEFT,
		Vector2.RIGHT,
	][rng.randi_range(0, 3)]
	if key != "monitor":
		return drawn
	var look: Variant = base.get(&"look")
	var face: Variant = (look as Object).get(&"facing") if look is Object else null
	return face if face is Vector2 else Vector2.DOWN


## A point for a footprint `foot` inside `top`'s rect, off what it has `laid` and its `props`;
## (INF, INF) when no try fits.
static func _spot_on(top: Dictionary, foot: Vector2, rng: RandomNumberGenerator) -> Vector2:
	var area: Rect2 = top["rect"]
	var span := area.size - foot
	if span.x < 0.0 or span.y < 0.0:
		return Vector2.INF
	for _try in WorldGenItemConfig.tries:
		var at := area.position + foot * 0.5 + Vector2(rng.randf() * span.x, rng.randf() * span.y)
		var rect := Rect2(at - foot * 0.5, foot)
		if not _crowded(top, rect):
			return at
	return Vector2.INF


## Whether `rect` is on an item already `laid` on `top` (`WorldGenItemConfig.spacing` apart) or on a
## prop the painter draws there.
static func _crowded(top: Dictionary, rect: Rect2) -> bool:
	var spacing := WorldGenItemConfig.spacing
	for other: Rect2 in top["laid"]:
		if other.grow(spacing).intersects(rect):
			return true
	for point: Vector2 in top["props"]:
		if rect.grow(PROP_CLEAR).has_point(point):
			return true
	return false


## Where the painter draws props on `base` (the `art_opts.props` `at` fractions of its footprint,
## turned the way the piece faces), in the furniture node's space.
static func _prop_points(base: Node2D) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var look: Variant = base.get(&"look")
	if not look is Object:
		return out
	var opts: Variant = (look as Object).get(&"art_opts")
	if not opts is Dictionary or not (opts as Dictionary).has("props"):
		return out
	var face: Variant = (look as Object).get(&"facing")
	var toward: Vector2 = face if face is Vector2 else Vector2.DOWN
	var turns := roundi(Vector2.DOWN.angle_to(toward) / (PI * 0.5))
	var canonical: Vector2 = base.size
	if posmod(turns, 2) == 1:
		canonical = Vector2(canonical.y, canonical.x)
	for prop: Dictionary in (opts as Dictionary)["props"]:
		var unit: Vector2 = prop.get("at", Vector2(0.5, 0.5))
		var from_centre := ((unit - Vector2(0.5, 0.5)) * canonical).rotated(turns * PI * 0.5)
		out.append(base.position + from_centre)
	return out


## The floor stacks of `site`'s room type (`ItemsCatalog.FLOOR`): 1 or more stacks of 2 to 3 boxes
## and crates at the walls and corners, clear of the furniture, the doorways and each other.
static func _floor_stacks(site: RoomSite, rng: RandomNumberGenerator) -> Array:
	var rule: Dictionary = ItemsCatalog.FLOOR.get(site.room["type"], {})
	if rule.is_empty() or rng.randf() >= float(rule["chance"]):
		return []
	var count: Vector2i = rule["count"]
	var laid: Array[Rect2] = []
	var out: Array = []
	for _i in rng.randi_range(count.x, count.y):
		var bottom := _stack_bottom(site, WeightedPick.pick(rng, rule["base"]), laid, rng)
		if bottom.is_empty():
			continue
		out.append(bottom)
		var high: Vector2i = rule["high"]
		for _n in rng.randi_range(high.x, high.y) - 1:
			out.append(_stack_on(site, bottom, WeightedPick.pick(rng, rule["top"]), rng))
	return out


## One more item `key` on the floor stack whose bottom is `bottom`, a hair off its centre.
static func _stack_on(
	site: RoomSite,
	bottom: Dictionary,
	key: String,
	rng: RandomNumberGenerator,
) -> Dictionary:
	var jitter := Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
	var base: Node2D = bottom["node"]
	var opts := { "rotated": false, "facing": Vector2.DOWN, "name": key }
	return _set_on(site, base, ObjectDefinitions.get_definition(key), base.position + jitter, opts)


## The bottom of a floor stack of catalogue piece `key` on the floor, by a wall or in a corner,
## clear of the furniture, the doorway boxes and the stacks `laid`: its entry, or {} when no try
## finds a spot.
static func _stack_bottom(
	site: RoomSite,
	key: String,
	laid: Array[Rect2],
	rng: RandomNumberGenerator,
) -> Dictionary:
	var definition := ObjectDefinitions.get_definition(key)
	var inner := RoomDresser.inner_of(site)
	var solids := RoomDresser.solids_of(site)
	var foot: Vector2 = definition["size"]
	var clear := WorldGenItemConfig.floor_clear
	for _try in WorldGenItemConfig.tries:
		var found := RoomDresser.anchor(rng, inner, solids)
		var p: Vector2 = (found["p"] as Vector2).clamp(
			inner.position + foot * 0.5,
			inner.end - foot * 0.5,
		)
		var r := Rect2(p - foot * 0.5, foot)
		if (not found["by_wall"]
				or not inner.encloses(r)
				or solids.any(func(s: Rect2) -> bool: return s.grow(clear).intersects(r))
				or laid.any(func(q: Rect2) -> bool: return q.grow(clear).intersects(r))
				or site.blocked.any(func(b: Rect2) -> bool: return b.grow(clear).intersects(r))
				or not RoomDresser.near_anchor(p, site.room["rect"], solids)):
			continue
		laid.append(r)
		var opts := { "rotated": false, "facing": Vector2.DOWN, "name": key }
		var node := ObjectFactory.spawn(definition, p, site.items, opts)
		return { "room": site.room["key"], "key": key, "node": node, "on": null }
	return {}
