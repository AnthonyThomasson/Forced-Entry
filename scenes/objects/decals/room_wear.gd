extends Node2D
## One room's wear (Objects domain), built by WearFactory: the damage of a run-down room placed in
## the world, never in its repeating floor or wall tile, so no mark shows up twice. World-Gen says
## where wear gathers (a few clusters, each by a wall, a corner or a piece of furniture, seeded);
## this node decides what each cluster is: 1-3 floor marks round its centre that follow the room's
## floor (planks break along a plank row, tiles go missing on the tile grid, carpet wears bald,
## concrete cracks and takes oil) and, for a cluster by a wall, often a mark on that wall's free
## stretch (peeling plaster, a water stain, a hairline crack, a run of stapled cable). Drawn by two
## decal layers (decal_layer.gd): the floor marks on the floor's rung (`FloorWear`), the wall marks
## on the walls' (`WallWear`); built after the house's floors and walls, so each draws over them.
## One per room, so it is lit like that room's floor. Draw-only. Tuning: ObjectArtWearConfig.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
const DecalLayer = preload("res://scenes/objects/decals/decal_layer.gd")
const FloorPainter = preload("res://scenes/objects/art/floor_painter.gd")

## `FloorWear`: the floor marks.
var _floor_layer: Node2D
## `WallWear`: the wall marks.
var _wall_layer: Node2D


## Build the wear of the room `rect` (in the parent's space; this node sits at its corner) on the
## floor `floor_definition` (its `color` and `art_opts.pattern`) inside walls `wall_thickness`
## thick, one cluster per `clusters` entry (`{ pos, wall, seed }`: its centre and the free stretch
## of wall it is by, `[a, b]` or empty, in the parent's space); returns this node.
func setup(
	rect: Rect2,
	floor_definition: Dictionary,
	wall_thickness: float,
	clusters: Array,
) -> Node2D:
	position = rect.position
	_floor_layer = DecalLayer.new().setup("FloorWear", ObjectArtLayerConfig.floor_z_index)
	_wall_layer = DecalLayer.new().setup("WallWear", DrawLayers.STANDING)
	add_child(_floor_layer)
	add_child(_wall_layer)
	var room := Rect2(Vector2.ZERO, rect.size)
	var inner := room.grow(-(wall_thickness * 0.5 + ObjectArtWearConfig.inset))
	var pattern := _pattern_of(floor_definition)
	var placed: Array[Rect2] = []
	for cluster: Dictionary in clusters:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(cluster.get("seed", 0))
		var at: Vector2 = (cluster["pos"] as Vector2) - rect.position
		if (ObjectArtWearConfig.floor_kinds.has(pattern)
				and inner.size.x >= 40.0
				and inner.size.y >= 40.0):
			_floor_marks(rng, at, inner, floor_definition, placed)
		var wall: Array = cluster.get("wall", [])
		if wall.size() == 2 and rng.randf() < ObjectArtWearConfig.wall_chance:
			_wall_mark(
				rng,
				(wall[0] as Vector2) - rect.position,
				(wall[1] as Vector2) - rect.position,
				at,
				wall_thickness,
			)
	return self


# --- Floor ----------------------------------------------------------------------------------------


## The pattern of the floor `floor_definition` (its `art_opts.pattern`, planks by default).
static func _pattern_of(floor_definition: Dictionary) -> String:
	return String((floor_definition.get("art_opts", {}) as Dictionary).get("pattern", "planks"))


## 1-3 marks of the floor `floor_definition` (its pattern, tinted from its drawn colour) round `at`,
## inside `inner`, clear of the marks already `placed`.
func _floor_marks(
	rng: RandomNumberGenerator,
	at: Vector2,
	inner: Rect2,
	floor_definition: Dictionary,
	placed: Array[Rect2],
) -> void:
	var pattern := _pattern_of(floor_definition)
	var tone := ObjectArt.drawn_color(floor_definition.get("color", Color.GRAY))
	var marks := (1
			if rng.randf() < ObjectArtWearConfig.one_chance
			else (2 if rng.randf() < ObjectArtWearConfig.two_chance else 3))
	for m in marks:
		var spread := ObjectArtWearConfig.spread
		var offset := (Vector2.ZERO
				if m == 0
				else Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(spread.x, spread.y))
		var kind: String = WeightedPick.pick(rng, ObjectArtWearConfig.floor_kinds[pattern])
		var mark := _floor_mark(kind, at + offset, pattern, rng)
		if mark.is_empty():
			continue
		var r := _fit(mark["rect"], inner, mark["step"])
		var crowded := func(q: Rect2) -> bool: return q.grow(ObjectArtWearConfig.gap).intersects(r)
		if not inner.encloses(r) or placed.any(crowded):
			continue
		placed.append(r)
		var opts: Dictionary = mark["opts"]
		opts["kind"] = kind
		opts["v"] = rng.randi_range(0, ObjectArtWearConfig.variants - 1)
		_floor_layer.add(ObjectArt.texture("wear", r.size, tone, mark["facing"], opts), r)


## A floor mark of `kind` near `p` on a floor of `pattern` whose tile starts at this node's origin:
## `{ rect, step, facing, opts }` (the rect, how it may be moved to fit (whole rows or cells for a
## grid-bound mark, a pixel for a free one), the turn its art is drawn at, the painter's grid
## options), or `{}` for a kind it does not know.
static func _floor_mark(
	kind: String,
	p: Vector2,
	pattern: String,
	rng: RandomNumberGenerator,
) -> Dictionary:
	match kind:
		"plank_gap":
			return _plank_gap(p, rng)
		"strip_gap":
			return _strip_gap(p, rng)
		"missing_cells":
			return _missing_cells(p, pattern, rng)
	if not ObjectArtWearConfig.sizes.has(kind):
		return {}
	return _free_mark(kind, p, rng)


## A plank gap near `p`: one or two plank rows broken out along a row.
static func _plank_gap(p: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var px := ArtCanvasConfig.pixel_size
	var row_h := FloorPainter.row_px()
	var rows := 1 if rng.randf() < 0.7 else 2
	var length := roundf(rng.randf_range(20, 56) / px)
	var row := floori(p.y / (row_h * px))
	var r := Rect2(
		roundf(p.x / px - length * 0.5) * px,
		(row * row_h + 1) * px,
		length * px,
		(rows * row_h - 1) * px,
	)
	return {
		"rect": r,
		"step": Vector2(px, row_h * px),
		"facing": Vector2.DOWN,
		"opts": { "row_h": row_h, "rows": rows },
	}


## A parquet gap near `p`: one strip of a basket-weave square (strips across in one square, along in
## the next), or two side by side.
static func _strip_gap(p: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var px := ArtCanvasConfig.pixel_size
	var cell := ObjectArtFloorConfig.parquet_px / px
	var strip := FloorPainter.parquet_strip()
	var g := Vector2i(floori(p.x / (cell * px)), floori(p.y / (cell * px)))
	var s := rng.randi_range(0, int(cell / strip) - 1)
	var n := 1 if rng.randf() < 0.6 or s == int(cell / strip) - 1 else 2
	var cell_o := Vector2(g) * cell * px
	var r := (Rect2(cell_o + Vector2(0, s * strip * px), Vector2(cell, strip * n) * px)
			if (g.x + g.y) % 2 == 0
			else Rect2(cell_o + Vector2(s * strip * px, 0), Vector2(strip * n, cell) * px))
	return {
		"rect": r,
		"step": Vector2(cell, cell) * px,
		"facing": Vector2.DOWN,
		"opts": {},
	}


## Tiles knocked out of a block of the tile (or `mosaic`) grid near `p`.
static func _missing_cells(p: Vector2, pattern: String, rng: RandomNumberGenerator) -> Dictionary:
	var px := ArtCanvasConfig.pixel_size
	var cell := FloorPainter.cell_px(pattern)
	var most := 3 if pattern == "mosaic" else 2
	var n := Vector2i(rng.randi_range(1, most), rng.randi_range(1, most))
	var g := Vector2i(floori(p.x / (cell * px)), floori(p.y / (cell * px)))
	var r := Rect2(Vector2(g * cell) * px, Vector2(n * cell + Vector2i.ONE) * px)
	return {
		"rect": r,
		"step": Vector2(cell, cell) * px,
		"facing": Vector2.DOWN,
		"opts": { "cell": cell, "nx": n.x, "ny": n.y },
	}


## A free mark of `kind` (one ObjectArtWearConfig.sizes knows) centred near `p`, of a size within
## its bounds, turned a random quarter.
static func _free_mark(kind: String, p: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var px := ArtCanvasConfig.pixel_size
	var lo: Vector2 = ObjectArtWearConfig.sizes[kind][0]
	var hi: Vector2 = ObjectArtWearConfig.sizes[kind][1]
	var size := ((Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y)) / 2.0).round()
			* 2.0)
	var turned := rng.randf() < 0.5
	var foot := Vector2(size.y, size.x) if turned else size
	var facing: Vector2 = ([Vector2.LEFT, Vector2.RIGHT][rng.randi_range(0, 1)]
			if turned
			else [Vector2.DOWN, Vector2.UP][rng.randi_range(0, 1)])
	return {
		"rect": Rect2(((p - foot * 0.5) / px).round() * px, foot),
		"step": Vector2(px, px),
		"facing": facing,
		"opts": {},
	}


## `r` moved inside `inner` in whole `step`s (a grid-bound mark keeps to its grid), as far as it
## fits.
static func _fit(r: Rect2, inner: Rect2, step: Vector2) -> Rect2:
	var shift := Vector2.ZERO
	for axis in 2:
		if r.position[axis] < inner.position[axis]:
			shift[axis] = ceilf((inner.position[axis] - r.position[axis]) / step[axis]) * step[axis]
		elif r.end[axis] > inner.end[axis]:
			shift[axis] = -ceilf((r.end[axis] - inner.end[axis]) / step[axis]) * step[axis]
	return Rect2(r.position + shift, r.size)


# --- Wall -----------------------------------------------------------------------------------------


## One wall mark on the stretch `a`-`b` (the wall's centre line, this node's frame) `thickness`
## thick, as near `at`'s place along it as it fits.
func _wall_mark(
	rng: RandomNumberGenerator,
	from: Vector2,
	to: Vector2,
	at: Vector2,
	thickness: float,
) -> void:
	var a := from.min(to)  # A wall runs along x or y: walk it from its lower end.
	var length := a.distance_to(from.max(to))
	var kind: String = WeightedPick.pick(rng, ObjectArtWearConfig.wall_kinds)
	var span: Vector2 = ObjectArtWearConfig.wall_lengths[kind]
	var mark := roundf(minf(rng.randf_range(span.x, span.y), length - 8.0))
	if mark < span.x:
		return
	var dir := (from.max(to) - a) / length
	var s := roundf(clampf((at - a).dot(dir) - mark * 0.5, 4.0, length - 4.0 - mark))
	var r := _wall_rect(a + dir * s, dir, mark, thickness)
	# The art runs along its canvas's length, turned onto a wall along y.
	var facing := Vector2.DOWN if absf(dir.x) > 0.5 else Vector2.RIGHT
	var opts := { "kind": kind, "v": rng.randi_range(0, ObjectArtWearConfig.variants - 1) }
	_wall_layer.add(
		ObjectArt.texture("wear", r.size, ObjectArtWearConfig.plaster_color, facing, opts),
		r,
	)


## The rect of a wall mark `mark` px long from `start` on a wall running along `dir`, `thickness`
## thick about its centre line.
static func _wall_rect(start: Vector2, dir: Vector2, mark: float, thickness: float) -> Rect2:
	if absf(dir.x) > 0.5:
		return Rect2(start - Vector2(0, thickness * 0.5), Vector2(mark, thickness))
	return Rect2(start - Vector2(thickness * 0.5, 0), Vector2(thickness, mark))
