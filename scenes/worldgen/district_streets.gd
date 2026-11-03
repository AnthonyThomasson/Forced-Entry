class_name DistrictStreets
## World Generation domain: a district's street grid. Its floors (a sidewalk round each block, the
## roads between the junctions and the junctions themselves) are laid through FloorFactory from
## `GeneralCatalog.STREET`, as a lone house's street ring is: no sound surface, on the street light
## layer, one tile grid shared so slab joints meet. Each carries its marks (seeded per piece).

## What a sidewalk is strewn with, `[catalogue key, weight]`.
const CLUTTER := [
	["vending_machine", 1.0],
	["street_bench", 1.5],
	["street_bin", 2.0],
	["drain_grate", 1.5],
	["litter", 2.0],
]


## Lay the street floors of `layout` (`DistrictLayout.compute`) under `root`, shifted by `delta`:
## `[{ kind, role, rect, node, block }]`, `rect` in world space.
static func build(layout: Dictionary, delta: Vector2, root: Node2D, district_seed: int) -> Array:
	var origin: Vector2 = (layout["extent"] as Rect2).position + delta
	var out: Array = []
	var pieces: Array = layout["streets"]
	for i in pieces.size():
		var piece: Dictionary = pieces[i]
		var rect := DistrictLayout.shifted(piece["rect"], delta)
		var definition: Dictionary = GeneralCatalog.STREET[
			"sidewalk" if piece["kind"] == "sidewalk" else "asphalt"
		].duplicate(true)
		definition["marks"] = {
			"seed": hash([district_seed, "street", i]),
			"edges": piece["edges"],
			"lane": piece["lane"],
			"crossings": piece["crossings"],
			"glyphs": piece["glyphs"],
		}
		definition["tile_from"] = origin
		var node := FloorFactory.spawn(
			rect,
			definition,
			"%s %d" % [(piece["role"] as String).capitalize(), i],
			root,
		)
		out.append({
			"kind": piece["kind"],
			"role": piece["role"],
			"rect": rect,
			"node": node,
			"block": piece["block"],
		})
	return out


## The street lamps along the four sides of every block's sidewalk (StreetLamps, every other one a
## neon sign), their rows kept `lamp_corner_inset` from the corners, clear of the doorway zones of
## every tower and of the crossings and their landings (`taken.zones`, `taken.landings`). A lamp
## that would break either rule is dropped. Each side draws from an RNG of its own (`_sides`).
## Under a `Street Lamps` node of `root`; returns `[{ pos, node, size }]` (`StreetLamps.place`).
static func lamps(
	pavements: Array,
	taken: DistrictKeepouts,
	root: Node2D,
	district_seed: int,
) -> Array:
	var holder := Node2D.new()
	holder.name = "Street Lamps"
	root.add_child(holder)
	var out: Array = []
	for side: Dictionary in _sides(pavements, "lamps", district_seed):
		out.append_array(
			StreetLamps.place(holder, side["run"], taken.zones, side["rng"], taken.landings),
		)
	return out


## The four sides of every block's sidewalk, block by block in the order of
## `DistrictLayout.BLOCK_SIDES`: `[{ run, rng }]`, `run` the lamp run along the side and `rng` the
## side's own RNG, `hash([seed, part, block, side index])`, `part` "lamps" or "clutter".
static func _sides(pavements: Array, part: String, district_seed: int) -> Array:
	var out: Array = []
	for block in pavements.size():
		for k in DistrictLayout.BLOCK_SIDES.size():
			out.append({
				"run": _run(pavements[block], DistrictLayout.BLOCK_SIDES[k]),
				"rng": DistrictLayout.rng_keyed([district_seed, part, block, k]),
				"block": block,
			})
	return out


## The run of lamp posts along `pavement`'s side `out`, off the corners.
static func _run(pavement: Rect2, out: Vector2) -> Dictionary:
	return StreetLamps.trim(
		StreetLamps.run_along(pavement, out),
		WorldGenDistrictConfig.lamp_corner_inset,
	)


## The sidewalk clutter (grimy steel: `StreetCatalog`) along the four sides of every block's
## sidewalk: a slot about every `clutter_every` px, its piece drawn by `CLUTTER`'s weights,
## `clutter_depth` in from the curb, its front to the street. A piece that would meet anything in
## `taken` (`DistrictKeepouts.clear`) or another piece is dropped, not moved. Each side draws from
## an RNG of its own (`_sides`). Under a `Street Clutter` node of `root`; returns
## `[{ room, key, node, block }]`.
static func clutter(
	pavements: Array,
	taken: DistrictKeepouts,
	root: Node2D,
	district_seed: int,
) -> Array:
	var holder := Node2D.new()
	holder.name = "Street Clutter"
	root.add_child(holder)
	var out: Array = []
	var placed: Array[Rect2] = []
	for side: Dictionary in _sides(pavements, "clutter", district_seed):
		for piece in _slots(side["run"], side["rng"], taken, placed, holder):
			piece["block"] = side["block"]
			out.append(piece)
	return out


## The clutter placed along `run` (a lamp run: its line is `streetlight_curb` in from the curb).
static func _slots(
	run: Dictionary,
	rng: RandomNumberGenerator,
	taken: DistrictKeepouts,
	placed: Array[Rect2],
	holder: Node2D,
) -> Array:
	var out: Array = []
	var from: Vector2 = run["a"]
	var along: Vector2 = (run["b"] - from).normalized()
	var length := from.distance_to(run["b"])
	var t := rng.randf_range(0.0, WorldGenDistrictConfig.clutter_every * 0.5)
	while t < length:
		var key: String = WeightedPick.pick(rng, CLUTTER)
		var spot := _spot(key, from + along * t, run["facing"])
		t += WorldGenDistrictConfig.clutter_every + rng.randf_range(
			-WorldGenDistrictConfig.clutter_jitter,
			WorldGenDistrictConfig.clutter_jitter,
		)
		if not taken.clear(spot["rect"]) or _meets(spot["rect"], placed):
			continue
		placed.append(spot["rect"])
		var node := ObjectFactory.spawn(
			ObjectDefinitions.get_definition(key),
			spot["at"],
			holder,
			{ "facing": run["facing"], "rotated": spot["turned"] },
		)
		out.append({ "room": "", "key": key, "node": node })
	return out


## Where clutter `key` stands for the run point `on` (on the posts' line), its front toward
## `facing`: `{ at, rect, turned }`, the piece `clutter_depth` px in from the curb, its footprint
## turned when it faces east or west.
static func _spot(key: String, on: Vector2, facing: Vector2) -> Dictionary:
	var size: Vector2 = ObjectDefinitions.get_definition(key)["size"]
	var turned := facing.x != 0.0
	size = Vector2(size.y, size.x) if turned else size
	# The posts' line is `streetlight_curb` in from the curb: the clutter stands further in.
	var inward := WorldGenDistrictConfig.clutter_depth - WorldGenStreetConfig.streetlight_curb
	var at := on - facing * inward
	return { "at": at, "rect": Rect2(at - size * 0.5, size), "turned": turned }


## Whether `rect`, grown by `clutter_gap`, meets any of the `placed` clutter.
static func _meets(rect: Rect2, placed: Array[Rect2]) -> bool:
	var spaced := rect.grow(WorldGenDistrictConfig.clutter_gap)
	return placed.any(func(other: Rect2) -> bool: return spaced.intersects(other))
