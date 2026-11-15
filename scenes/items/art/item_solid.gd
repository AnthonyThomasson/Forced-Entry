class_name ItemSolid
extends RefCounted

## A pixel is drawn when its alpha is over this.
const OPAQUE := 0.5

## Items domain, private to the item meshes (`gun_mesh.gd`, `grenade_mesh.gd`, `spoon_art.gd`;
## #193): a solid raised from a flat picture's silhouette. The 2D painters' art is the item's look,
## so the 3D item is its coverage (the pixels the painter drew) lifted to a height, and the art is
## projected straight down onto it (`MeshNodes.textured`): seen from above the mesh IS the 2D art.
##
## A picture is read as runs: per pixel row, the stretches of drawn pixels (`rows`). Rows that
## repeat the same runs at the same height are one box (`slab`), so a rectangular part costs one
## box, not a box a row.
##
## The frame is the picture's, turned to 3D: pixel `(x, y)` is at `origin + (x, y) * cell` in the
## (x, z) plane, `cell` px a pixel (the painting's scale: art px over picture px).

## The drawn pixels by row: one `PackedInt32Array` of `[from, to)` pairs per row.
var runs: Array = []
## Where the picture's top-left corner is in the mesh's (x, z) plane (px).
var origin := Vector2.ZERO
## How many px a picture pixel is.
var cell := 1.0


## The solid of `image` laid in the frame `rect` (px, in the mesh's frame: where the picture's
## whole footprint lies), its drawn pixels read as runs.
static func of(image: Image, rect: Rect2) -> ItemSolid:
	var solid := ItemSolid.new()
	solid.runs = rows(image)
	solid.origin = rect.position
	solid.cell = rect.size.x / float(image.get_width())
	return solid


## The solid of the pixels of `image` that differ from `other` (the same size), in this one's frame:
## what one painting added over the other (a grenade's lever).
func added(image: Image, other: Image) -> ItemSolid:
	var solid := ItemSolid.new()
	solid.origin = origin
	solid.cell = cell
	for y in image.get_height():
		var pairs := PackedInt32Array()
		var start := -1
		for x in image.get_width():
			var differs := image.get_pixel(x, y) != other.get_pixel(x, y)
			if differs and start < 0:
				start = x
			elif not differs and start >= 0:
				pairs.append_array([start, x])
				start = -1
		if start >= 0:
			pairs.append_array([start, image.get_width()])
		solid.runs.append(pairs)
	return solid


## The drawn pixels of `image` by row: an array with one `PackedInt32Array` per row of `[from, to)`
## pairs (x of the first drawn pixel, x past the last of a stretch).
static func rows(image: Image) -> Array:
	var picture := image
	if picture.get_format() != Image.FORMAT_RGBA8:
		picture = image.duplicate()
		picture.convert(Image.FORMAT_RGBA8)
	var data := picture.get_data()
	var width := picture.get_width()
	var out: Array = []
	for y in picture.get_height():
		var pairs := PackedInt32Array()
		var start := -1
		for x in width:
			var drawn := float(data[(y * width + x) * 4 + 3]) / 255.0 > OPAQUE
			if drawn and start < 0:
				start = x
			elif not drawn and start >= 0:
				pairs.append_array([start, x])
				start = -1
		if start >= 0:
			pairs.append_array([start, width])
		out.append(pairs)
	return out


## Add a box to `kit` for each stretch of rows that repeats the same runs at the same height, from
## picture row `from` up to (not including) `to`. `height` is a `Callable(row) -> float` (px); a
## box rises from `base`. The colour is white: the art multiplies it.
func slab(kit: MeshKit, base: float, height: Callable, from := 0, to := -1) -> void:
	var last := runs.size() if to < 0 else mini(to, runs.size())
	var start := from
	while start < last:
		var tall: float = height.call(start)
		var end := start + 1
		while end < last and runs[end] == runs[start] and is_equal_approx(height.call(end), tall):
			end += 1
		if tall > 0.0:
			_boxes(kit, runs[start], Vector2(start, end), Vector2(base, tall))
		start = end


## The widest span of the drawn pixels over rows `from` to `to`, as `Vector2(first x, past the last
## x)` in picture pixels; `Vector2.ZERO` when nothing is drawn there.
func extent(from := 0, to := -1) -> Vector2:
	var last := runs.size() if to < 0 else mini(to, runs.size())
	var low := INF
	var high := -INF
	for y in range(from, last):
		var pairs: PackedInt32Array = runs[y]
		if not pairs.is_empty():
			low = minf(low, pairs[0])
			high = maxf(high, pairs[pairs.size() - 1])
	return Vector2.ZERO if low > high else Vector2(low, high)


## A round bar over rows `from` to the last, standing on `base`: a cylinder along z as wide as the
## art there (`kit.sides` flat faces round).
func bar(kit: MeshKit, base: float, from: int) -> void:
	var span := extent(from)
	if span == Vector2.ZERO:
		return
	var radius := (span.y - span.x) * cell * 0.5
	var middle := origin.x + (span.x + span.y) * 0.5 * cell
	kit.pose(
		Transform3D(
			Basis(Vector3.RIGHT, PI * 0.5),
			Vector3(middle, base + radius, origin.y + from * cell),
		)
	)
	kit.cylinder(Vector3.ZERO, radius, (runs.size() - from) * cell, Color.WHITE)
	kit.pose(Transform3D.IDENTITY)


## The boxes of one stretch's `pairs` over picture rows `rows` (from, past the last), `lift` (base,
## height).
func _boxes(kit: MeshKit, pairs: PackedInt32Array, span: Vector2, lift: Vector2) -> void:
	for k in range(0, pairs.size(), 2):
		kit.box(
			AABB(
				Vector3(origin.x + pairs[k] * cell, lift.x, origin.y + span.x * cell),
				Vector3((pairs[k + 1] - pairs[k]) * cell, lift.y, (span.y - span.x) * cell),
			),
			Color.WHITE,
		)
