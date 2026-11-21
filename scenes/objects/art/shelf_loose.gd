extends RefCounted
## Objects domain, what an open shelf holds when it is emptied (`docs/stacked-items.md` SI13,
## decision D21): the books, the boxes (and the odd paint tin) or the pairs of shoes that
## `shelf_mesh.gd` and `shelf_painter.gd` used to build into the shelf, as rows for loose items to
## stand where they stood (`PieceCarries`). The pieces are picked by a generator seeded from the
## look (the footprint, the contents, the boards), so every shelf of one look carries the same
## things, and they are the ones the old mesh drew: the same walk along each board, the same sizes
## and gaps.
## A row is `{ key, at, size, lift, height, color }`: the item's catalogue key, its centre from the
## shelf's centre in the canonical frame (x across, the front toward +y), its footprint, the board's
## top it stands on and how tall it is. A run of books (`RUN` at most, side by side on one board) is
## one item whose `spines` (`[[x, width, height, colour]]`, x from the run's left) the mesh draws: a
## bookshelf's hundred books would be a hundred bodies; a run is the few that move together.

const ShelfMesh = preload("res://scenes/objects/art/shelf_mesh.gd")
## The most books in one run.
const RUN := 6
## How likely a place on a board of boxes is a paint tin, its largest radius and its height (px).
const TIN_CHANCE := 0.3
const TIN_RADIUS := 5.0
const TIN_HEIGHT := 8.0


## The rows of the shelf `spec` (art "shelf", `art_opts.loose`): `[]` for a shelf with no contents.
static func rows(spec: FurnitureSpec) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var height := ShelfMesh.height_of(spec)
	var levels := ShelfMesh.levels_of(height)
	var board := ObjectMeshStorageConfig.shelf_board
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([spec.size, ShelfMesh.contents_of(spec), levels])
	var gap := (height - board) / (levels - 1)
	for k in levels - 1:
		_board(spec, rng, gap * k + board, gap - board, out)
	return out


## The things on the board whose top is `at`, `room` px below the next board.
static func _board(
	spec: FurnitureSpec,
	rng: RandomNumberGenerator,
	at: float,
	room: float,
	out: Array[Dictionary],
) -> void:
	var side := ShelfMesh.HULL  # inside the sides the body has, not the thinner ones drawn
	var x := side + 0.5
	var end := spec.size.x - side - 0.5
	var kind := ShelfMesh.contents_of(spec)
	var first := out.size()
	while x < end - 1.0:
		match kind:
			"books":
				x = _book(spec, rng, Vector3(x, at, room), end, out)
			"boxes":
				x = _box(spec, rng, Vector3(x, at, room), end, out)
			_:
				x = _shoes(spec, rng, Vector3(x, at, room), end, out)
	if kind == "books":
		_runs(first, out)


## The books of one board (`out` from `first`) as runs of at most `RUN`, side by side.
static func _runs(first: int, out: Array[Dictionary]) -> void:
	var books := out.slice(first)
	out.resize(first)
	for start in range(0, books.size(), RUN):
		out.append(_run(books.slice(start, start + RUN)))


## One item for the `books` (rows) side by side: as wide as they are together, as tall as the
## tallest, its `spines` each book's x from the run's left, width, height and colour.
static func _run(books: Array) -> Dictionary:
	var left := INF
	var right := -INF
	var high := 0.0
	for book: Dictionary in books:
		var half: float = (book["size"] as Vector2).x * 0.5
		left = minf(left, (book["at"] as Vector2).x - half)
		right = maxf(right, (book["at"] as Vector2).x + half)
		high = maxf(high, book["height"])
	var spines: Array = []
	for book: Dictionary in books:
		var width: float = (book["size"] as Vector2).x
		var from: float = (book["at"] as Vector2).x - width * 0.5 - left
		spines.append([from, width, book["height"], book["color"]])
	var lead: Dictionary = books[0]
	return {
		"key": "book_stood",
		"at": Vector2((left + right) * 0.5, (lead["at"] as Vector2).y),
		"size": Vector2(roundf(right - left), (lead["size"] as Vector2).y),
		"lift": lead["lift"],
		"height": high,
		"color": lead["color"],
		"spines": spines,
	}


## A row for the area `area` (px from the back-left corner), `rise` its (lift, height) in px.
static func _row(
	spec: FurnitureSpec,
	key: String,
	area: Rect2,
	rise: Vector2,
	colour: Color,
) -> Dictionary:
	return {
		"key": key,
		"at": area.get_center() - spec.size * 0.5,
		"size": area.size.round(),
		"lift": rise.x,
		"height": rise.y,
		"color": colour,
	}


## A book at `at.x` on the board `at.y` high with `at.z` px of room above it; the x past it.
static func _book(
	spec: FurnitureSpec,
	rng: RandomNumberGenerator,
	at: Vector3,
	end: float,
	out: Array[Dictionary],
) -> float:
	var bw := minf(rng.randf_range(2.0, 4.0), end - at.x)
	if rng.randf() < 0.1:
		return at.x + rng.randf_range(1.0, 3.0)
	var area := Rect2(at.x, ShelfMesh.HULL + 0.5, bw, spec.size.y * 0.6)
	var high := at.z * rng.randf_range(0.6, 0.95)
	out.append(_row(spec, "book_stood", area, Vector2(at.y, high), _pick(rng, "books")))
	return at.x + bw


## A cardboard box (placed like `_book`); the x past it.
static func _box(
	spec: FurnitureSpec,
	rng: RandomNumberGenerator,
	at: Vector3,
	end: float,
	out: Array[Dictionary],
) -> float:
	if rng.randf() < TIN_CHANCE:
		return _tin(spec, rng, at, end, out)
	var bw := minf(rng.randf_range(0.22, 0.34) * spec.size.x, end - at.x)
	var area := Rect2(at.x, ShelfMesh.HULL + 0.5, bw, spec.size.y - ShelfMesh.HULL - 2.5)
	var high := at.z * rng.randf_range(0.5, 0.8)
	out.append(_row(spec, "box", area, Vector2(at.y, high), ObjectArtStorageConfig.shelf_box_color))
	return at.x + bw + 1.0


## The odd paint tin of a board of boxes (the old painter's: as wide as the board's depth allows,
## at most 5 px a side of radius, against the back); the x past it.
static func _tin(
	spec: FurnitureSpec,
	rng: RandomNumberGenerator,
	at: Vector3,
	end: float,
	out: Array[Dictionary],
) -> float:
	var depth := (spec.size.y - ShelfMesh.HULL - 2.5) * rng.randf_range(0.6, 0.95)
	var rad := minf(maxf(1.0, floorf(depth * 0.5)), minf(TIN_RADIUS, (end - at.x) * 0.5))
	var area := Rect2(at.x, ShelfMesh.HULL + 1.5, rad * 2.0, rad * 2.0)
	var colour: Color = ObjectArtDecorConfig.prop_colors["metal"]
	out.append(_row(spec, "paint_tin", area, Vector2(at.y, minf(at.z * 0.8, TIN_HEIGHT)), colour))
	return at.x + rad * 2.0 + 2.0


## A pair of shoes (placed like `_book`); the x past it.
static func _shoes(
	spec: FurnitureSpec,
	rng: RandomNumberGenerator,
	at: Vector3,
	end: float,
	out: Array[Dictionary],
) -> float:
	var pw := minf(11.0, end - at.x)
	var area := Rect2(at.x, spec.size.y * 0.25, pw, spec.size.y * 0.55)
	out.append(_row(spec, "shoes", area, Vector2(at.y, minf(at.z * 0.4, 6.0)), _pick(rng, "shoes")))
	return at.x + pw + rng.randf_range(1.0, 3.0)


## A colour of `list` of `ObjectArtDecorConfig.prop_colors`, picked by `rng`.
static func _pick(rng: RandomNumberGenerator, list: String) -> Color:
	var colours: Array = ObjectArtDecorConfig.prop_colors[list]
	return colours[rng.randi_range(0, colours.size() - 1)]
