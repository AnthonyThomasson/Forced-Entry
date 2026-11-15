class_name ShotLayer
extends Node3D
## Projectile domain, the 3D look of the shots in flight and at rest (#193 phase 2,
## `domain-art/meshes.md`): a tracer for each live bullet. Bullets are too many and too short-lived
## for a node and a mesh each, so the layer owns a pool of one batch of streaks (`MeshPool`, one
## draw): it learns of a bullet as it joins the world (`watch`: a child of the world that is a
## `Projectile`), gives it a place, writes the place each frame it flies and gives it back when the
## bullet leaves. A spent casing is a part of a second batch the same way: written each frame of
## its toss and once more where it comes to rest, then never again. Nothing is made while the game
## runs, and the layer does not process while no bullet flies and no casing is tossed.

const Projectile := preload("res://scenes/projectile/projectile.gd")
const Casing := preload("res://scenes/projectile/casing.gd")
## How long (s) past its toss a casing is still written, so its last frame is where it came to rest.
const REST_SLACK := 0.1

## The streaks' pool and the casings'.
var _tracers: MeshPool
var _casings: MeshPool
## The casings still being tossed and how long (s) each has been.
var _flying: Array[Node] = []
var _ages := PackedFloat32Array()


func _init() -> void:
	name = "ShotLayer"
	var mesh := _streak()
	var batch := MeshNodes.batch(mesh, ProjectileMeshConfig.tracer_capacity)
	MeshNodes.glow(batch, ProjectileMeshConfig.tracer_color, ProjectileMeshConfig.tracer_glow)
	_tracers = MeshPool.new(batch)
	add_child(batch)
	var shells := MeshNodes.batch(_shell(), ProjectileMeshConfig.casing_capacity)
	_casings = MeshPool.new(shells)
	add_child(shells)


func _ready() -> void:
	set_process(false)  # a layer with `_process` is made to run: it runs only while a bullet flies


func _process(delta: float) -> void:
	for slot in _tracers.count:
		_place_tracer(slot)
	var i := 0
	while i < _flying.size():
		_ages[i] += delta
		var tossed: Node2D = _flying[i]
		var toss: float = tossed.eject_time
		var done := _ages[i] >= toss + REST_SLACK
		_place_casing(tossed, _ages[i] if not done else INF)
		if done:
			_stop_flying(i)
		else:
			i += 1
	_rest_if_idle()


## Follow the bullets of `world`: those in it now and each as it joins.
func watch(world: Node) -> void:
	world.child_entered_tree.connect(_on_joined)
	world.child_exiting_tree.connect(_on_leaving)
	for child in world.get_children():
		_on_joined(child)


## How many tracers are shown.
func tracer_count() -> int:
	return _tracers.count


## The frame of the tracer in `slot` (3D units: its middle, its turn along the bullet's heading,
## its length scaled by how far its fade has come).
func tracer_frame(slot: int) -> Transform3D:
	return _tracers.frame_at(slot)


## How many casings are shown.
func casing_count() -> int:
	return _casings.count


## The frame of the casing in `slot` (3D units).
func casing_frame(slot: int) -> Transform3D:
	return _casings.frame_at(slot)


## How many casings the batch holds at most.
func casing_capacity() -> int:
	return _casings.capacity()


## The casings' batch node.
func casing_batch() -> MultiMeshInstance3D:
	return _casings.node


## A bullet or a casing joined the world: it gets a place, written at once.
func _on_joined(node: Node) -> void:
	var script: Variant = node.get_script()
	if script == Projectile:
		var slot := _tracers.add(node)
		if slot >= 0:
			_place_tracer(slot)
			set_process(true)
	elif script == Casing and _casings.add(node) >= 0:
		_flying.append(node)
		_ages.append(0.0)
		_place_casing(node, 0.0)
		set_process(true)


## A node leaves the world: a bullet or a casing gives its place back.
func _on_leaving(node: Node) -> void:
	var script: Variant = node.get_script()
	if script == Projectile:
		_tracers.remove(node)
	elif script == Casing:
		_casings.remove(node)
		var at := _flying.find(node)
		if at >= 0:
			_stop_flying(at)
	_rest_if_idle()


## The layer runs only while a bullet flies or a casing is tossed.
func _rest_if_idle() -> void:
	set_process(_tracers.count > 0 or not _flying.is_empty())


## The casing at `index` of the tossed ones has come to rest (or is gone).
func _stop_flying(index: int) -> void:
	var last := _flying.size() - 1
	_flying[index] = _flying[last]
	_ages[index] = _ages[last]
	_flying.pop_back()
	_ages.resize(last)


## Write `casing`'s place: where its 2D node is, turned as it is, lifted along its toss's arc
## `age` s into it (INF: lying).
func _place_casing(casing: Node2D, age: float) -> void:
	var lift := 0.0
	var toss: float = casing.eject_time
	if age < toss:
		var along := age / toss
		lift = ProjectileMeshConfig.casing_arc * 4.0 * along * (1.0 - along)
	var at := casing.global_position
	var frame := Transform3D(
		Basis(Vector3.UP, -casing.global_rotation), Vector3(at.x, lift, at.y) * RenderConfig.unit
	)
	_casings.place(_casings.slot_of(casing), frame)


## Write the tracer in `slot`: its tip on its bullet, its streak behind along the heading, at the
## bullet's height, shortened over the last stretch of the bullet's range.
func _place_tracer(slot: int) -> void:
	var bullet: Node2D = _tracers.owner_at(slot)
	var heading: Vector2 = bullet.direction
	var fade := ProjectileMeshConfig.tracer_fade
	var whole := clampf(bullet.range_left() / fade, 0.02, 1.0) if fade > 0.0 else 1.0
	var length := ProjectileMeshConfig.tracer_length * whole
	var middle := bullet.global_position - heading * length * 0.5
	var height := maxf(
		bullet.height * ProjectileMeshConfig.height_scale, ProjectileMeshConfig.tracer_floor
	)
	var turned := Basis(Vector3.UP, PI * 0.5 - heading.angle())
	var frame := Transform3D(
		turned * Basis.from_scale(Vector3(1.0, 1.0, whole)),
		Vector3(middle.x, height, middle.y) * RenderConfig.unit,
	)
	_tracers.place(slot, frame)


## The brass shell every casing shares: a box as long and wide as the 2D art, lying along x.
func _shell() -> Mesh:
	var size := ProjectileMeshConfig.casing_size
	var height := ProjectileMeshConfig.casing_height
	var color := ProjectileMeshConfig.casing_color
	return MeshCache.fetch(
		MeshCache.key("casing", size, color, { "height": height }),
		func() -> Mesh:
			var half := size * 0.5
			var shell := AABB(Vector3(-half.x, 0.0, -half.y), Vector3(size.x, height, size.y))
			return MeshKit.new().box(shell, color).build()
	)


## The streak every tracer shares: a thin bar along z, its middle on the origin.
func _streak() -> Mesh:
	var size := Vector2(ProjectileMeshConfig.tracer_width, ProjectileMeshConfig.tracer_length)
	var color := ProjectileMeshConfig.tracer_color
	return MeshCache.fetch(
		MeshCache.key("tracer", size, color),
		func() -> Mesh:
			var half := size * 0.5
			var bar := AABB(Vector3(-half.x, -half.x, -half.y), Vector3(size.x, size.x, size.y))
			return MeshKit.new().box(bar, color).build()
	)
