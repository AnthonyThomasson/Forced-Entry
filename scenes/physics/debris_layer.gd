class_name DebrisLayer
extends "res://scenes/physics/chunked_layer.gd"
## Physics System: the chips that have come to rest, drawn as one layer under a world node instead
## of one node each. A chip (`debris.gd`) is a node only while it flies; as it lands it hands its
## place, turn, colour, size and shape here and frees itself, so a floor strewn with a thousand
## chips costs a few draw calls and no nodes. Chips are grouped in `CHUNK`-px squares
## (`chunked_layer.gd`), and a chunk draws its chips in pages of `PAGE`, oldest first, a canvas item
## each: a chip landing repaints the page it joins and the oldest dropped the page it leaves, not
## the hundreds a struck chair piles into one chunk. The oldest are dropped past
## `Despawner.max_scene_objects`, the same bound the flying chips are tracked against, so the floor
## never accumulates chips without end. A layer draws under whatever is added to its node after it,
## as `BloodDecals` does.

const NODE_NAME := "DebrisLayer"
## Chips a page holds.
const PAGE := 32

## Whether a chunk's chips are drawn by its pages, else all by the chunk in one batch: the same
## triangles in the same order, so the same pixels either way (for tests).
static var paged := true
## Chips drawn by every chunk and page since last reset (for tests).
static var chips_drawn := 0


## The debris layer held by `parent`, or null if none yet.
static func find(parent: Node) -> DebrisLayer:
	return parent.get_node_or_null(NODE_NAME) as DebrisLayer


## The debris layer under `parent` (the node the chips were spawned in), made on first use. Each
## parent has its own layer, freed with it.
static func layer(parent: Node) -> DebrisLayer:
	return _get_or_make(parent, NODE_NAME, DebrisLayer) as DebrisLayer


## A "tri" chip `s` px across, point up, round its centre: the flying chip (`debris_visuals.gd`)
## draws it too, so a chip lands looking as it flew.
static func tri(s: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -s.y * 0.5),
		Vector2(s.x * 0.5, s.y * 0.5),
		Vector2(-s.x * 0.5, s.y * 0.5),
	])


## Draw `chips` on `item` in one triangle array (General's FillBatch), oldest first, each moved to
## its own place and turn: the shapes `debris_visuals.gd` draws (its disc, triangle or rect, both
## convex so added uncut), the same pixels for a fraction of the commands.
static func _draw_chips(item: CanvasItem, chips: Array) -> void:
	chips_drawn += chips.size()
	var to_world := item.get_global_transform().affine_inverse()  # chips are placed in world space
	if not FillBatch.batching:
		_draw_each(item, chips, to_world)
		return
	var batch := FillBatch.new(item)
	for chip in chips:
		var xform := to_world * Transform2D(chip["turn"], chip["at"])
		var color: Color = chip["color"]
		var s: Vector2 = chip["size"]
		match chip["shape"]:
			"circle":
				batch.circle(Vector2.ZERO, s.x * 0.5, color, xform)
			"tri":
				batch.fill_convex(tri(s), color, xform)
			_:  # "rect"
				batch.fill_convex(_rect(s), color, xform)
	batch.flush()


## A "rect" chip `s` px across, round its centre.
static func _rect(s: Vector2) -> PackedVector2Array:
	var h := s * 0.5
	return PackedVector2Array([
		Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y),
	])


## Each chip by its own command, as the batch's would be under the headless display (nothing is
## rendered there, and these cost the least).
static func _draw_each(item: CanvasItem, chips: Array, to_world: Transform2D) -> void:
	for chip in chips:
		item.draw_set_transform_matrix(to_world * Transform2D(chip["turn"], chip["at"]))
		var color: Color = chip["color"]
		var s: Vector2 = chip["size"]
		match chip["shape"]:
			"circle":
				item.draw_circle(Vector2.ZERO, s.x * 0.5, color)
			"tri":
				item.draw_colored_polygon(tri(s), color)
			_:  # "rect"
				item.draw_rect(Rect2(-s * 0.5, s), color)


## Lay a chip to rest at world `at`, turned by `turn` (world radians): `size` px across, `shape`
## ("rect" | "tri" | "circle") in `color`, drawn exactly as the flying chip was.
func rest(at: Vector2, turn: float, color: Color, size: Vector2, shape: String) -> void:
	var chip := {
		"chunk": _chunk_cell(at),
		"at": at,
		"turn": turn,
		"color": color,
		"size": size,
		"shape": shape,
	}
	_add(chip, Despawner.max_scene_objects)


## A chip landed in `cell`: onto its chunk's last page, which alone repaints.
func _mark_added(cell: Vector2i, mark: Dictionary) -> void:
	var chunk := _chunk_node(cell) as DebrisChunk
	_repaint(chunk, chunk.add_chip(mark))


## The oldest chip of `cell` went: off its chunk's first page, which alone repaints (or goes
## when left empty).
func _mark_dropped(cell: Vector2i, mark: Dictionary) -> void:
	var chunk := _chunks.get(cell) as DebrisChunk
	if chunk != null:
		_repaint(chunk, chunk.drop_chip(mark))


## Repaint `page` of `chunk`, or the whole chunk while it draws in one batch.
func _repaint(chunk: DebrisChunk, page: DebrisPage) -> void:
	if not paged:
		chunk.queue_redraw()
	elif page != null:
		page.queue_redraw()


## A draw chunk for this layer's chips in `cell`.
func _make_chunk(cell: Vector2i) -> Node2D:
	var node := DebrisChunk.new()
	node.owner_layer = self
	node.cell = cell
	return node


## One chunk: the layer's chips that fall in its cell, held in its pages (its children, oldest
## first). It draws them all itself only while `paged` is off.
class DebrisChunk:
	extends Node2D

	## The layer whose chips it holds.
	var owner_layer: DebrisLayer
	## Its chunk grid cell.
	var cell := Vector2i.ZERO


	## The pages still holding chips, oldest first.
	var _pages: Array[DebrisPage] = []


	func _draw() -> void:
		if not DebrisLayer.paged:
			DebrisLayer._draw_chips(self, owner_layer.marks_in(cell))


	## File `chip` (the chunk's newest) on the last page, or a new one when that is full, and
	## return that page.
	func add_chip(chip: Dictionary) -> DebrisPage:
		if _pages.is_empty() or _pages[-1].chips.size() >= PAGE:
			var page := DebrisPage.new()
			add_child(page)
			_pages.append(page)
		_pages[-1].chips.append(chip)
		return _pages[-1]


	## Take `chip` (the chunk's oldest) off the first page holding it and return that page, or null
	## once it is left empty and freed.
	func drop_chip(chip: Dictionary) -> DebrisPage:
		for page in _pages:
			if page.chips.has(chip):
				page.chips.erase(chip)
				if not page.chips.is_empty():
					return page
				_pages.erase(page)
				page.queue_free()
				return null
		return null


## One page of a chunk: up to `PAGE` of its chips, drawn while `paged` is on.
class DebrisPage:
	extends Node2D

	## Its chips, oldest first.
	var chips: Array = []

	func _draw() -> void:
		if DebrisLayer.paged:
			DebrisLayer._draw_chips(self, chips)
