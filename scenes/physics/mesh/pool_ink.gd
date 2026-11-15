class_name PoolInk
extends RefCounted
## Physics domain, a dead body's bleed-out pool in the 3D render (#193 phase 2;
## `domain-physics/meshes.md`): a decal on the floor (`MeshNodes.decal`) showing the pool's fill
## field as the 2D draws it, the field the flood-fill claims and the front sweeps through (blurred
## by `BloodPoolVisuals`, the same function), cut at `PhysicsInkConfig.pool_threshold` into two
## tones (the rim, and the deep blood) and a third for blood that has soaked into a porous floor.
## The picture is made at `PhysicsInkConfig.pool_upscale` times the flow cell's resolution from
## the field smoothed between its cells, so the edge is as fine as the pixel art allows, and is
## built again at most every `PhysicsInkConfig.pool_interval` s while the pool grows or soaks (the
## 2D pool tells it by marking itself stale), in place while the pool's box is the same size. A pool
## that has settled is not built again. A pool lives as long as its 2D node.

const Visuals := preload("res://scenes/physics/blood/blood_pool_visuals.gd")

## How many pictures were built (a test reads it: a settled pool builds none).
var builds := 0
var _parent: Node3D
## The pools by their 2D node's instance id: a `Record`.
var _pools := {}
## Seconds since the pools were last built.
var _since := 0.0


## Decals under `parent` (the 3D world's frame).
func _init(parent: Node3D) -> void:
	_parent = parent


## How many pools lie, and how many wait to be built.
func count() -> int:
	return _pools.size()


## How many pools wait to be built again.
func waiting() -> int:
	var n := 0
	for record: Record in _pools.values():
		n += 1 if record.stale else 0
	return n


## The decal of the pool whose 2D node is `pool` (null before it is first built).
func decal_of(pool: Node2D) -> MeshInstance3D:
	var record: Record = _pools.get(pool.get_instance_id())
	return record.decal if record != null else null


## The picture of the pool whose 2D node is `pool` (null before it is first built): what its decal
## shows.
func picture_of(pool: Node2D) -> Image:
	var record: Record = _pools.get(pool.get_instance_id())
	return record.image if record != null else null


## A 2D pool began: it lies as long as its node does.
func pool_made(pool: Node2D) -> void:
	var record := Record.new()
	record.id = pool.get_instance_id()
	record.node = pool
	record.stale = true
	_pools[record.id] = record
	pool.tree_exiting.connect(_pool_gone.bind(record))


## A 2D pool's fill changed: its picture is built again within the interval.
func pool_changed(pool: Node2D) -> void:
	var record: Record = _pools.get(pool.get_instance_id())
	if record != null:
		record.stale = true


## Build the pictures that are out of date, if the interval has passed. True while one waits.
func process(delta: float) -> bool:
	_since += delta
	if _since < PhysicsInkConfig.pool_interval:
		return waiting() > 0
	_since = 0.0
	for record: Record in _pools.values():
		if record.stale:
			record.stale = false
			_build(record)
	return false


## A 2D pool left the world.
func _pool_gone(record: Record) -> void:
	_pools.erase(record.id)
	if is_instance_valid(record.decal):
		record.decal.queue_free()


## Build `record`'s picture from its pool's flow: the decal over the box of cells it covers.
func _build(record: Record) -> void:
	var pool: Node2D = record.node
	var flow: BloodFlow = pool.flow
	if flow == null or flow.cells.is_empty():
		return
	var covered: Array = flow.cells.keys() + flow.trail.keys()
	var box := Visuals.field_box(covered)
	var image := _picture(Visuals.field_bytes(flow, covered, box), box.size)
	builds += 1
	record.image = image
	if record.decal != null and record.box == box:
		(record.decal.get_meta(&"texture") as ImageTexture).update(image)
		return
	if record.decal != null:
		record.decal.queue_free()
	record.decal = _lay(pool.global_position, box, image)
	record.box = box


## A decal showing `image` over the cells `box` of a pool at `origin`.
func _lay(origin: Vector2, box: Rect2i, image: Image) -> MeshInstance3D:
	var texture := ImageTexture.create_from_image(image)
	var cell := BloodPoolConfig.flow_cell_size
	var centre := origin + (Vector2(box.position) + Vector2(box.size) * 0.5) * cell
	var frame := MeshNodes.surface_frame(Vector3(centre.x, 0.0, centre.y))
	var decal := MeshNodes.decal(
		Vector2(box.size) * cell, frame, texture, Color.WHITE, PhysicsInkConfig.pool_layer
	)
	decal.set_meta(&"texture", texture)
	decal.name = "Pool"
	_parent.add_child(decal)
	return decal


## The picture of a field (RG8: red the fill, green how far it has soaked in, `cells` across and
## down) at `PhysicsInkConfig.pool_upscale` pixels a cell: each pixel the field smoothed between
## the cells' middles, in the rim tone, the deep tone or the soaked one where the blood lies and
## clear where it does not.
func _picture(field: PackedByteArray, cells: Vector2i) -> Image:
	var scale := maxi(PhysicsInkConfig.pool_upscale, 1)
	var size := cells * scale
	var deep := BloodConfig.color
	var rim := deep.darkened(BloodPoolConfig.flow_edge_darken)
	var soaked := deep.darkened(1.0 - PhysicsInkConfig.pool_soaked)
	var bytes := PackedByteArray()
	bytes.resize(size.x * size.y * 4)
	for y in size.y:
		for x in size.x:
			var at := Vector2((x + 0.5) / scale - 0.5, (y + 0.5) / scale - 0.5)
			var fill := _sample(field, cells, at, 0)
			if fill < PhysicsInkConfig.pool_threshold:
				continue
			var tone := deep if fill >= PhysicsInkConfig.pool_deep else rim
			if _sample(field, cells, at, 1) >= 0.5:
				tone = soaked
			var i := (y * size.x + x) * 4
			bytes[i] = int(tone.r * 255.0)
			bytes[i + 1] = int(tone.g * 255.0)
			bytes[i + 2] = int(tone.b * 255.0)
			bytes[i + 3] = 255
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)


## The channel `channel` of the field at `at` (in cells, the first cell's middle at 0), smoothed
## between the four cells round it; cells off the edge are empty.
func _sample(field: PackedByteArray, cells: Vector2i, at: Vector2, channel: int) -> float:
	var x0 := int(floor(at.x))
	var y0 := int(floor(at.y))
	var fx := at.x - x0
	var fy := at.y - y0
	var top := lerpf(
		_cell(field, cells, x0, y0, channel),
		_cell(field, cells, x0 + 1, y0, channel),
		fx,
	)
	var bottom := lerpf(
		_cell(field, cells, x0, y0 + 1, channel), _cell(field, cells, x0 + 1, y0 + 1, channel), fx,
	)
	return lerpf(top, bottom, fy)


## The channel of the cell `x`, `y` as 0..1 (0 off the edge).
func _cell(field: PackedByteArray, cells: Vector2i, x: int, y: int, channel: int) -> float:
	if x < 0 or y < 0 or x >= cells.x or y >= cells.y:
		return 0.0
	return float(field[(y * cells.x + x) * 2 + channel]) / 255.0


## One pool's book-keeping: its 2D node, whether its picture is out of date, its decal, the
## picture and the box of cells it covers.
class Record:
	extends RefCounted

	var id := 0
	var node: Node2D
	var stale := false
	var decal: MeshInstance3D
	var image: Image
	var box := Rect2i()
