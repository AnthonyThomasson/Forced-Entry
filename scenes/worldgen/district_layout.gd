class_name DistrictLayout
## World Generation domain: the geometry of a downtown district, worked out before anything is
## built (pure data from a seed, so a seed reproduces it). A 3 x 3 grid of blocks, one tower each:
## the centre block's tower is the house (the forced plan, else a tower plan), the rest draw tower
## plans only. Each tower is turned by the seed so its front door faces one of its block's four
## streets, and stands against that edge of its block, so its front wall sits on that street's
## sidewalk. Each column of blocks is as wide as its widest tower, each row as deep as its deepest;
## asphalt runs between and round the blocks, with a sidewalk round each block, and one ring of
## shells stands past the outer street. Every part draws from its own RNG, `hash([seed, part,
## block])`. Positions are in the layout's own frame (the top-left of the outer street at the
## origin); DistrictSpawner shifts them so the house's front door lands on the entrance.

const GRID := 3
const HOUSE_BLOCK := 4
## Where a plan's front faces after 0, 1, 2 and 3 quarter turns (`HouseSpawner`'s turn).
const FACINGS := [Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2.RIGHT]
## The four sides, in the order marks seed their RNGs.
const SIDES := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]


## The layout of the district of `district_seed` with `force_plan` ("" for none) in the centre:
## `{ blocks, streets, shells, extent }`.
##   blocks:  per block 0 to 8 (row by row) `{ block, plan, turn, outward, tower_seed, size, front,
##            area, corner }`: its plan, its quarter turns and the way its front faces, the seed of
##            its build, its footprint, the front door from that footprint's top-left, the block's
##            tower area (the sidewalk is outside it) and the footprint's top-left.
##   streets: `{ kind, role, rect, block, edges, lane, crossings, glyphs }` per floor, none larger
##            than `tile_max` on a side: a tile of a block's sidewalk (`kind` `sidewalk`, `block`
##            its index; those wholly under the tower are left out), of a road segment between two
##            junctions or a junction (`kind` `street`, `role` `road` or `junction`, `block` -1). A
##            road tile at a junction carries that arm's `crossings` and lane `glyphs` (the marks
##            street_marks.gd lays).
##   landings: the rects no lamp or clutter may stand in: each crossing and the sidewalk at both
##            ends of it.
##   shells:  the rect of each of the 16 shells.
##   extent:  the rect of the streets (the shells stand past it).
static func compute(district_seed: int, force_plan: String) -> Dictionary:
	var blocks: Array = []
	for block in GRID * GRID:
		blocks.append(_block(district_seed, force_plan, block))
	var across := _axis(_lengths(blocks, true))
	var down := _axis(_lengths(blocks, false))
	for block: Dictionary in blocks:
		_place(block, district_seed, across, down)
	var tiles := _tiles(_streets(across, down), blocks, district_seed)
	return {
		"blocks": blocks,
		"streets": tiles,
		"landings": _landings(tiles),
		"shells": _shells(across, down),
		"extent": Rect2(0.0, 0.0, across["length"], down["length"]),
	}


## Block `block`'s plan, turn and footprint (not yet placed).
static func _block(district_seed: int, force_plan: String, block: int) -> Dictionary:
	var plans := TowerDefinitions.get_all()
	var rng := _rng(district_seed, "plan", block)
	var drawn: String = plans[rng.randi() % plans.size()]
	var plan := force_plan if block == HOUSE_BLOCK and force_plan != "" else drawn
	var turn := _rng(district_seed, "facing", block).randi() % 4
	var tower_seed := hash([district_seed, "tower", block])
	var foot := HouseSpawner.footprint(plan, tower_seed, turn)
	return {
		"block": block,
		"plan": plan,
		"turn": turn,
		"outward": FACINGS[turn],
		"tower_seed": tower_seed,
		"size": foot["size"],
		"front": foot["front"],
	}


## The RNG of `part` for `block`: `hash([seed, part, block])`.
static func _rng(district_seed: int, part: String, block: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([district_seed, part, block])
	return rng


## The length of each of the three tracks along x (`across`) or y: the largest footprint in it.
static func _lengths(blocks: Array, across: bool) -> Array:
	var lengths: Array = [0.0, 0.0, 0.0]
	for block: Dictionary in blocks:
		var track: int = block["block"] % GRID if across else block["block"] / GRID
		var size: Vector2 = block["size"]
		lengths[track] = maxf(lengths[track], size.x if across else size.y)
	return lengths


## One axis of the grid: the start of each of its four roads and three block pavements, and its
## total length. A road is `street_width` across, a pavement its track plus a sidewalk each side.
static func _axis(lengths: Array) -> Dictionary:
	var road := WorldGenDistrictConfig.street_width
	var side := WorldGenDistrictConfig.sidewalk
	var roads: Array = []
	var pavements: Array = []
	var at := 0.0
	for track in GRID:
		roads.append(at)
		at += road
		pavements.append(at)
		at += lengths[track] + side * 2.0
	roads.append(at)
	return { "roads": roads, "pavements": pavements, "lengths": lengths, "length": at + road }


## Give `block` its area and its tower's top-left corner: against the edge of the area its front
## faces, anywhere along the other.
static func _place(
	block: Dictionary,
	district_seed: int,
	across: Dictionary,
	down: Dictionary,
) -> void:
	var side := WorldGenDistrictConfig.sidewalk
	var col: int = block["block"] % GRID
	var row: int = block["block"] / GRID
	var area := Rect2(
		across["pavements"][col] + side,
		down["pavements"][row] + side,
		across["lengths"][col],
		down["lengths"][row],
	)
	var size: Vector2 = block["size"]
	var slack := area.size - size
	var rng := _rng(district_seed, "place", block["block"])
	var corner := area.position + Vector2(rng.randf() * slack.x, rng.randf() * slack.y)
	var out: Vector2 = block["outward"]
	if out.y > 0.0:
		corner.y = area.end.y - size.y
	elif out.y < 0.0:
		corner.y = area.position.y
	elif out.x > 0.0:
		corner.x = area.end.x - size.x
	else:
		corner.x = area.position.x
	block["area"] = area
	block["corner"] = corner


## The street floors: a sidewalk round each block, the sixteen junctions, then the road segments
## between them (along x, then along y).
static func _streets(across: Dictionary, down: Dictionary) -> Array:
	var side := WorldGenDistrictConfig.sidewalk
	var road := WorldGenDistrictConfig.street_width
	var streets: Array = []
	for row in GRID:
		for col in GRID:
			var rect := Rect2(
				across["pavements"][col],
				down["pavements"][row],
				across["lengths"][col] + side * 2.0,
				down["lengths"][row] + side * 2.0,
			)
			var curbs := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
			streets.append(_piece("sidewalk", "block", rect, row * GRID + col, curbs))
	for j in GRID + 1:
		for i in GRID + 1:
			var rect := Rect2(across["roads"][i], down["roads"][j], road, road)
			streets.append(_piece("street", "junction", rect, -1, []))
	streets.append_array(_roads(across, down, true))
	streets.append_array(_roads(down, across, false))
	return streets


## The road segments lying along an axis: along `along` (one per block pavement of it) on each of
## the four roads of `other`, a gutter on each side a sidewalk lies. `horizontal`: along x.
static func _roads(along: Dictionary, other: Dictionary, horizontal: bool) -> Array:
	var side := WorldGenDistrictConfig.sidewalk
	var road := WorldGenDistrictConfig.street_width
	var before := Vector2.UP if horizontal else Vector2.LEFT
	var roads: Array = []
	for k in GRID + 1:
		for n in GRID:
			var start: float = along["pavements"][n]
			var length: float = along["lengths"][n] + side * 2.0
			var rect := (
				Rect2(start, other["roads"][k], length, road)
				if horizontal
				else Rect2(other["roads"][k], start, road, length)
			)
			roads.append(_piece("street", "road", rect, -1, _gutters(k, GRID, before, -before)))
	return roads


## A street piece: `edges` are the sides a curb (sidewalk) or gutter (road) runs along.
static func _piece(kind: String, role: String, rect: Rect2, block: int, edges: Array) -> Dictionary:
	return {
		"kind": kind,
		"role": role,
		"rect": rect,
		"block": block,
		"edges": edges,
		"lane": role == "road",
		"crossings": [],
		"glyphs": [],
	}


## `pieces` cut into floors of at most `tile_max` on a side. A sidewalk tile keeps the curbs of the
## sides it lies on and is left out when the tower of its block covers it; a road tile at a junction
## takes that arm's crossing and lane glyph.
static func _tiles(pieces: Array, blocks: Array, district_seed: int) -> Array:
	var tiles: Array = []
	for piece: Dictionary in pieces:
		var rect: Rect2 = piece["rect"]
		var counts := Vector2i(
			maxi(1, ceili(rect.size.x / WorldGenDistrictConfig.tile_max)),
			maxi(1, ceili(rect.size.y / WorldGenDistrictConfig.tile_max)),
		)
		for ty in counts.y:
			for tx in counts.x:
				var tile := piece.duplicate(true)
				tile["rect"] = Rect2(
					rect.position + rect.size * Vector2(tx, ty) / Vector2(counts),
					rect.size / Vector2(counts),
				)
				if _under_tower(tile, blocks):
					continue
				tile["edges"] = _kept_edges(piece["edges"], Vector2i(tx, ty), counts)
				_mark(tile, Vector2i(tx, ty), counts, district_seed, tiles.size())
				tiles.append(tile)
	return tiles


## Whether the sidewalk `tile` lies wholly under the tower of its block.
static func _under_tower(tile: Dictionary, blocks: Array) -> bool:
	if tile["kind"] != "sidewalk":
		return false
	var block: Dictionary = blocks[tile["block"]]
	return Rect2(block["corner"], block["size"]).grow(1.0).encloses(tile["rect"])


## The sides of `edges` (of a whole piece) that tile `at` of `counts` lies on.
static func _kept_edges(edges: Array, at: Vector2i, counts: Vector2i) -> Array:
	var kept: Array = []
	for side: Vector2 in edges:
		var on_edge := (
			(side == Vector2.LEFT and at.x == 0)
			or (side == Vector2.RIGHT and at.x == counts.x - 1)
			or (side == Vector2.UP and at.y == 0)
			or (side == Vector2.DOWN and at.y == counts.y - 1)
		)
		if on_edge:
			kept.append(side)
	return kept


## Give the road tile `at` of `counts` the crossing and lane glyph of each junction it ends at.
static func _mark(
	tile: Dictionary,
	at: Vector2i,
	counts: Vector2i,
	district_seed: int,
	index: int,
) -> void:
	if tile["role"] != "road":
		return
	var rect: Rect2 = tile["rect"]
	var sides: Array[Vector2] = []
	if rect.size.x > rect.size.y:
		if at.x == 0:
			sides.append(Vector2.LEFT)
		if at.x == counts.x - 1:
			sides.append(Vector2.RIGHT)
	else:
		if at.y == 0:
			sides.append(Vector2.UP)
		if at.y == counts.y - 1:
			sides.append(Vector2.DOWN)
	var reach := WorldGenDistrictConfig.crossing_reach
	for side: Vector2 in sides:
		var rng := _rng(district_seed, "glyph", index * 4 + SIDES.find(side))
		tile["crossings"].append({ "side": side, "reach": reach })
		tile["glyphs"].append({
			"side": side,
			"from": reach + WorldGenDistrictConfig.glyph_gap,
			"length": WorldGenDistrictConfig.glyph_length,
			"text": "%02d" % rng.randi_range(7, 49),
		})


## The rects of the crossings of `tiles`, each stretched across the sidewalks at its ends.
static func _landings(tiles: Array) -> Array:
	var side := WorldGenDistrictConfig.sidewalk
	var landings: Array = []
	for tile: Dictionary in tiles:
		for crossing: Dictionary in tile["crossings"]:
			var dir: Vector2 = crossing["side"]
			var zone := _end_strip(tile["rect"], dir, crossing["reach"])
			landings.append(
				zone.grow_individual(side, 0, side, 0)
				if dir.x == 0.0
				else zone.grow_individual(0, side, 0, side)
			)
	return landings


## The strip `reach` px deep along the end of `rect` at `side`, the whole way across it.
static func _end_strip(rect: Rect2, side: Vector2, reach: float) -> Rect2:
	match side:
		Vector2.UP:
			return Rect2(rect.position, Vector2(rect.size.x, reach))
		Vector2.DOWN:
			return Rect2(Vector2(rect.position.x, rect.end.y - reach), Vector2(rect.size.x, reach))
		Vector2.LEFT:
			return Rect2(rect.position, Vector2(reach, rect.size.y))
	return Rect2(Vector2(rect.end.x - reach, rect.position.y), Vector2(reach, rect.size.y))


## The gutters of a road at road index `k` of `count` + 1 along its axis: a sidewalk lies on its
## `before` side unless it is the first road, on its `after` side unless it is the last.
static func _gutters(k: int, count: int, before: Vector2, after: Vector2) -> Array:
	var edges: Array = []
	if k > 0:
		edges.append(before)
	if k < count:
		edges.append(after)
	return edges


## The sixteen shells: the ring of cells of a 5 x 5 grid round the 3 x 3 blocks, the middle three
## on each side split at the centre of the roads between blocks and the corners `shell_depth`
## square, each shrunk by half the gap on every side.
static func _shells(across: Dictionary, down: Dictionary) -> Array:
	var depth := WorldGenDistrictConfig.shell_depth
	var xs := _cuts(across, depth)
	var ys := _cuts(down, depth)
	var half := WorldGenDistrictConfig.shell_gap * 0.5
	var shells: Array = []
	for row in 5:
		for col in 5:
			if row in [1, 2, 3] and col in [1, 2, 3]:
				continue
			shells.append(Rect2(
				xs[col] + half,
				ys[row] + half,
				xs[col + 1] - xs[col] - half * 2.0,
				ys[row + 1] - ys[row] - half * 2.0,
			))
	return shells


## The six cuts of an axis into the cells of the shell ring: the outer ends `depth` past the
## streets, the streets' ends and the centres of the two roads between blocks.
static func _cuts(axis: Dictionary, depth: float) -> Array:
	var road := WorldGenDistrictConfig.street_width
	return [
		-depth,
		0.0,
		axis["roads"][1] + road * 0.5,
		axis["roads"][2] + road * 0.5,
		axis["length"],
		axis["length"] + depth,
	]
