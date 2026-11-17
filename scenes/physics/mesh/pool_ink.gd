class_name PoolInk
extends RefCounted
## Physics domain, a dead body's bleed-out pool in the 3D render (#193 phase 2;
## `domain-physics/meshes.md`): a decal on the floor (`MeshNodes.decal`) showing the pool's fill
## field as the 2D draws it, the field the flood-fill claims and the front sweeps through (blurred
## by `BloodPoolField`, the same function), cut at `PhysicsInkConfig.pool_threshold` into two
## tones (the rim, and the deep blood) and a third for blood that has soaked into a porous floor.
## The picture is the field scaled up `PhysicsInkConfig.pool_upscale` times with the engine's own
## bilinear resize, so the edge is as fine as the pixel art allows, then cut into tones. A pool
## that grows or soaks tells it (the 2D pool marks itself stale) and is built again at most every
## `PhysicsInkConfig.pool_interval` s, and **at most one pool a frame**, the ones waiting taking
## turns, so a volley of bleeding pools never builds together; in place while the pool's box is the
## same size. A pool that has settled is not built again. Every pool's decal is the one unit quad
## (`MeshNodes.decal` of one px, scaled to the box), so the mesh cache does not grow with the sizes
## a pool passes through. A pool lives as long as its 2D node.

## How many pictures were built (a test reads it: a settled pool builds none).
var builds := 0
var _parent: Node3D
## The pools by their 2D node's instance id (a `Record`), in the order they took turns, and which
## one is next.
var _pools := {}
var _order: Array[Record] = []
var _next := 0
## How many pools wait to be built, and the seconds the pools have been going (their turns are
## told apart by it).
var _stale := 0
var _clock := 0.0
## The ground the pools lie on (the road a kerb lower).
var _world: FxWorld


## Decals under `parent` (the 3D world's frame), over the ground of `world`.
func _init(parent: Node3D, world: FxWorld) -> void:
	_parent = parent
	_world = world


## How many pools lie.
func count() -> int:
	return _pools.size()


## How many pools wait to be built again.
func waiting() -> int:
	return _stale


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
	_pools[record.id] = record
	_order.append(record)
	_wait(record)
	pool.tree_exiting.connect(_pool_gone.bind(record))


## A 2D pool's fill changed: its picture is built again within the interval.
func pool_changed(pool: Node2D) -> void:
	var record: Record = _pools.get(pool.get_instance_id())
	if record != null:
		_wait(record)


## Build the next pool that waits and whose interval has passed (at most one). True while any waits.
func process(delta: float) -> bool:
	_clock += delta
	if _stale == 0:
		return false
	var turns := _order.size()
	for i in turns:
		var at := (_next + i) % turns
		var record := _order[at]
		if record.stale and _clock - record.last >= PhysicsInkConfig.pool_interval:
			_next = (at + 1) % turns
			_settle(record)
			record.last = _clock
			_build(record)
			break
	return _stale > 0


## `record` waits to be built.
func _wait(record: Record) -> void:
	if not record.stale:
		record.stale = true
		_stale += 1


## `record` no longer waits.
func _settle(record: Record) -> void:
	if record.stale:
		record.stale = false
		_stale -= 1


## A 2D pool left the world.
func _pool_gone(record: Record) -> void:
	_settle(record)
	_pools.erase(record.id)
	_order.erase(record)
	if is_instance_valid(record.decal):
		record.decal.queue_free()


## Build `record`'s picture from its pool's flow: the decal over the box of cells it covers.
func _build(record: Record) -> void:
	var pool: Node2D = record.node
	var flow: BloodFlow = pool.flow
	if flow == null or flow.cells.is_empty():
		return
	var covered: Array = flow.cells.keys() + flow.trail.keys()
	var box := BloodPoolField.field_box(covered)
	var image := _picture(BloodPoolField.field_bytes(flow, covered, box), box.size)
	builds += 1
	record.image = image
	if is_instance_valid(record.decal) and record.box == box:
		(record.decal.get_meta(&"texture") as ImageTexture).update(image)
		return
	if is_instance_valid(record.decal):
		record.decal.queue_free()
	record.decal = _lay(pool.global_position, box, image)
	record.box = box


## A decal showing `image` over the cells `box` of a pool at `origin`: the one unit quad, scaled.
func _lay(origin: Vector2, box: Rect2i, image: Image) -> MeshInstance3D:
	var texture := ImageTexture.create_from_image(image)
	var cell := BloodPoolConfig.flow_cell_size
	var size := Vector2(box.size) * cell
	var centre := origin + (Vector2(box.position) + Vector2(box.size) * 0.5) * cell
	var frame := MeshNodes.surface_frame(Vector3(centre.x, _world.ground_at(centre), centre.y))
	var decal := MeshNodes.decal(
		Vector2.ONE,
		frame,
		texture,
		Color.WHITE,
		PhysicsInkConfig.pool_layer,
	)
	decal.basis = decal.basis * Basis.from_scale(Vector3(size.x, 1.0, size.y))
	decal.set_meta(&"texture", texture)
	decal.name = "Pool"
	_parent.add_child(decal)
	return decal


## The field's bytes (RG8) scaled up bilinearly from `cells` to `size`.
func _smooth(field: PackedByteArray, cells: Vector2i, size: Vector2i) -> PackedByteArray:
	var image := Image.create_from_data(cells.x, cells.y, false, Image.FORMAT_RG8, field)
	image.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	return image.get_data()


## The pool's three tones: the rim, the deep blood and the soaked-in.
func _tones() -> Array[Color]:
	var deep := BloodConfig.color
	return [
		deep.darkened(BloodPoolConfig.flow_edge_darken), deep,
		deep.darkened(1.0 - PhysicsInkConfig.pool_soaked),
	]


## The picture of a field (RG8: red the fill, green how far it has soaked in, `cells` across and
## down) at `PhysicsInkConfig.pool_upscale` pixels a cell: the field scaled up bilinearly, then each
## pixel in the rim tone, the deep tone or the soaked one where the blood lies and clear where it
## does not.
func _picture(field: PackedByteArray, cells: Vector2i) -> Image:
	var scale := maxi(PhysicsInkConfig.pool_upscale, 1)
	var size := cells * scale
	var levels := _smooth(field, cells, size)
	var tones := _tones()
	var edge := int(PhysicsInkConfig.pool_threshold * 255.0)
	var thick := int(PhysicsInkConfig.pool_deep * 255.0)
	var bytes := PackedByteArray()
	bytes.resize(size.x * size.y * 4)
	for p in size.x * size.y:
		var fill := levels[p * 2]
		if fill < edge:
			continue
		var tone := tones[1] if fill >= thick else tones[0]
		if levels[p * 2 + 1] >= 128:
			tone = tones[2]
		bytes[p * 4] = int(tone.r * 255.0)
		bytes[p * 4 + 1] = int(tone.g * 255.0)
		bytes[p * 4 + 2] = int(tone.b * 255.0)
		bytes[p * 4 + 3] = 255
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)


## One pool's book-keeping: its 2D node, whether its picture is out of date and when it was last
## built, its decal, the picture and the box of cells it covers.
class Record:
	extends RefCounted

	var id := 0
	var node: Node2D
	var stale := false
	var last := -1000.0
	var decal: MeshInstance3D
	var image: Image
	var box := Rect2i()
