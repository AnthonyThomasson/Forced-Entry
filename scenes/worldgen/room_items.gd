class_name RoomItems
## World Generation domain: places a room's small items (`docs/stacked-items.md` SI9): a few on a
## flat top (tableware on tables and counters, books, lamps and monitors on desks
## and shelves) and, in a storage room, garage or office, boxes and crates stacked two or three
## high on the floor. What goes where is data (`ItemsCatalog.TOPS`, `TOPS_BY_ART`, `FLOOR`), how
## many and how likely is `WorldGenItemConfig`. Each is built through `ObjectFactory.spawn_on` (a
## free body resting on its base, `docs/stacked-items.md` SI2).
## Every room draws from an RNG of its own, `hash([run seed, room key, "items"])`, and runs after
## the furniture, the clutter and the neon: the items never shift a seed's layout, doors or
## dressing. Nothing here is added to `RoomSite.solids`, so the wear goes where it went.
## An item goes only where its whole footprint fits: on a flat top (not against a backsplash), on
## a piece of a stack at least as big as it (a crate on a crate, a box on a box or a crate, never a
## crate on a box), a hair off centre by no more than the margin that leaves (`_jitter`): an item
## that overhangs what it stands on topples at the start.

## The most (px) an item set on another of its kind on a top, and one in a floor stack, is put off
## the centre of what it stands on (cut to what the footprints leave).
const JITTER_TOP := 1.0
const JITTER_STACK := 1.5


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
		out.append_array(carry(piece["node"], piece["definition"], site.items, site.room["key"]))
		out.append_array(_on_top(site, piece, rng))
	out.append_array(_floor_stacks(site, rng))
	return out


## The items an emptied piece carries (`PieceCarries`: a shelf's books, a crate stack's crates, a
## pallet's wrapped boxes, a hotplate's plate and pan; decision D21) set where it used to draw them:
## `base` (a furniture node) from its catalogue `definition`, each under `parent`, as
## `[{ room, key, node, on, carried }]` like `place`'s (`carried` true: an emptied piece's own).
## Nothing for a piece that carries nothing.
static func carry(base: Node2D, definition: Dictionary, parent: Node, room: String) -> Array:
	var out: Array = []
	if base == null or not PieceCarries.carries(definition):
		return out
	var facing: Variant = (base.get(&"look") as Object).get(&"facing")
	for row: Dictionary in PieceCarries.rows(definition, base):
		var item := PieceCarries.patched(
			ObjectDefinitions.get_definition(row["key"]),
			row["patch"],
		)
		var opts := {
			"rotated": row["rotated"],
			"facing": facing if facing is Vector2 else Vector2.DOWN,
			"name": row["key"],
		}
		if not row["on_top"]:
			opts["rest_at"] = row["lift"]
		var node := ObjectFactory.spawn_on(
			item, base, (row["at"] as Vector2) - base.position, parent, opts
		)
		out.append({ "room": room, "key": row["key"], "node": node, "on": base, "carried": true })
	return out


## The items on the top of `piece` (`{ key, definition, node }`): none, or 1 to `top_max` with
## `top_chance`, each of its catalogue row's kinds (`ItemsCatalog.options_for`), kept inside the
## top.
static func _on_top(site: RoomSite, piece: Dictionary, rng: RandomNumberGenerator) -> Array:
	var base: Node2D = piece["node"]
	var options := ItemsCatalog.options_for(piece["key"], piece["definition"])
	if options.is_empty() or base == null or rng.randf() >= WorldGenItemConfig.top_chance:
		return []
	var flat := ObjectFactory.flat_top(base)
	var top := {
		"base": base,
		"rect": (flat["top"] as Rect2).grow(-WorldGenItemConfig.edge),
		"raised": flat["raised"],
		"laid": [] as Array[Rect2],
	}
	var out: Array = []
	for _i in rng.randi_range(1, WorldGenItemConfig.top_max):
		out.append_array(_one_on(site, top, WeightedPick.pick(rng, options), rng))
	return out


## One item `key` on `top` (`{ base, rect, raised, laid }`): `[]` when no try finds it a place, else
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
		var jitter := _jitter(rng, JITTER_TOP, foot, foot)
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


## A point for a footprint `foot` inside `top`'s rect, off what it has `laid` and its `raised`
## parts; (INF, INF) when no try fits.
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


## Whether `rect` is on an item already `laid` on `top` (`WorldGenItemConfig.spacing` apart), on a
## part that stands higher than the top (a counter's backsplash: an item set against it leans).
static func _crowded(top: Dictionary, rect: Rect2) -> bool:
	var spacing := WorldGenItemConfig.spacing
	for other: Rect2 in top["laid"]:
		if other.grow(spacing).intersects(rect):
			return true
	for lip: Rect2 in top["raised"]:
		if lip.grow(spacing).intersects(rect):
			return true
	return false


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
		out.append_array(_on_stack(site, bottom, rule, rng))
	return out


## What goes on the floor stack whose bottom is `bottom`, 1 or 2 more (`rule.high`), each of a kind
## of `rule.top` that fits inside the one under it (none when no kind does), a hair off centre.
static func _on_stack(
	site: RoomSite,
	bottom: Dictionary,
	rule: Dictionary,
	rng: RandomNumberGenerator,
) -> Array:
	var high: Vector2i = rule["high"]
	var under := _size_of(bottom["key"])
	var off := Vector2.ZERO
	var out: Array = []
	for _n in rng.randi_range(high.x, high.y) - 1:
		var options := ItemsCatalog.fitting(rule["top"], under)
		if options.is_empty():
			break
		var key: String = WeightedPick.pick(rng, options)
		off += _jitter(rng, JITTER_STACK, _size_of(key), under)
		out.append(_stack_on(site, bottom, key, off))
		under = _size_of(key)
	return out


## One more item `key` on the floor stack whose bottom is `bottom`, `off` (px) from its centre.
static func _stack_on(site: RoomSite, bottom: Dictionary, key: String, off: Vector2) -> Dictionary:
	var base: Node2D = bottom["node"]
	var opts := { "rotated": false, "facing": Vector2.DOWN, "name": key }
	return _set_on(site, base, ObjectDefinitions.get_definition(key), base.position + off, opts)


## The footprint (px) of catalogue piece `key`.
static func _size_of(key: String) -> Vector2:
	return ObjectDefinitions.get_definition(key)["size"]


## A random offset of an item of footprint `own` on one of footprint `under`: at most `limit` px
## along an axis and at most what keeps `own` inside `under` (nothing for two of one size), so the
## item never overhangs what it stands on.
static func _jitter(
	rng: RandomNumberGenerator,
	limit: float,
	own: Vector2,
	under: Vector2,
) -> Vector2:
	var room := ((under - own) * 0.5).max(Vector2.ZERO).min(Vector2(limit, limit))
	return Vector2(rng.randf_range(-1.0, 1.0) * room.x, rng.randf_range(-1.0, 1.0) * room.y)


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
