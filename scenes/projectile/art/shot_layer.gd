class_name ShotLayer
extends Node3D
## Projectile domain, the 3D look of the shots in flight and at rest
## (`domain-art/meshes.md`): a tracer for each live bullet. Bullets are too many and too short-lived
## for a node and a mesh each, so the layer owns a pool of one batch of streaks (`MeshPool`, one
## draw): it learns of a bullet as it joins the world (`watch`: a child of the world that is a
## `Projectile`), gives it a place, writes the place each frame it flies and gives it back when the
## bullet leaves. A spent casing is a part of a second batch the same way: written each frame of
## its flight (it flies in the twin 3D space and says how high it is, `Casing.altitude()`) and once
## more where it comes to rest, on the floor or on a piece's top, then never again. Nothing is made
## while the game runs, and the layer does not process while no bullet flies and no casing is in the
## air. The tracers'
## pool is `ProjectileMeshConfig.tracer_capacity`, the casings' is what the `Despawner` keeps of
## them (read when the layer is made): one that finds its pool full is not shown, and the layer
## says so once.

const Projectile := preload("res://scenes/projectile/projectile.gd")
const Casing := preload("res://scenes/projectile/casing.gd")
## How far round a casing in the air (px) the cone must reach for it to be drawn.
const TOSS_REACH := 8.0

## The streaks' pool and the casings'.
var _tracers: MeshPool
var _casings: MeshPool
## The casings still in flight.
var _flying: Array[Node] = []
## The casings the player's view has had in its cone (instance id -> true), and those lying that it
## has not yet: a casing is drawn once seen, where it lies, and not before.
var _seen: Dictionary = {}
var _waiting: Array[Node] = []
## The seen area's version the waiting casings were last checked against.
var _checked := -1
## Whether the layer has said a pool was full (the tracers', then the casings').
var _said_full := [false, false]


func _init() -> void:
	name = "ShotLayer"
	var mesh := _streak()
	var batch := MeshNodes.batch(mesh, ProjectileMeshConfig.tracer_capacity)
	MeshNodes.glow(batch, ProjectileMeshConfig.tracer_color, ProjectileMeshConfig.tracer_glow)
	MeshNodes.moving(batch)  # a bullet in flight is drawn only inside the cone the player sees
	_tracers = MeshPool.new(batch)
	add_child(batch)
	var shells := MeshNodes.batch(_shell(), maxi(Despawner.max_scene_objects, 1))
	_casings = MeshPool.new(shells)
	add_child(shells)


func _ready() -> void:
	set_process(false)  # a layer with `_process` is made to run: it runs only while a bullet flies


func _process(_delta: float) -> void:
	for slot in _tracers.count:
		_place_tracer(slot)
	var i := 0
	while i < _flying.size():
		var tossed: Node2D = _flying[i]
		_place_casing(tossed)
		if tossed.is_resting():
			_stop_flying(i)
		else:
			i += 1
	if _checked != SeenArea.version():  # a lying one waits for the cone: asked of a new cone only
		_checked = SeenArea.version()
		for w in range(_waiting.size() - 1, -1, -1):
			_place_casing(_waiting[w])
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


## The tracers' batch node.
func tracer_batch() -> MultiMeshInstance3D:
	return _tracers.node


## A bullet or a casing joined the world: it gets a place, written at once.
func _on_joined(node: Node) -> void:
	var script: Variant = node.get_script()
	if script == Projectile:
		var slot := _tracers.add(node)
		if slot < 0:
			_say_full(0, "tracers", _tracers.capacity())
			return
		_place_tracer(slot)  # a bullet is not ready yet: only its place and heading count
		set_process(true)
	elif script == Casing:
		if _casings.add(node) < 0:
			_say_full(1, "casings", _casings.capacity())
			return
		_flying.append(node)
		_place_casing(node)
		set_process(true)


## A node leaves the world: a bullet or a casing gives its place back.
func _on_leaving(node: Node) -> void:
	var script: Variant = node.get_script()
	if script == Projectile:
		_tracers.remove(node)
	elif script == Casing:
		_casings.remove(node)
		_seen.erase(node.get_instance_id())
		_waiting.erase(node)
		var at := _flying.find(node)
		if at >= 0:
			_stop_flying(at)
	_rest_if_idle()


## Say once that pool `which` (0 tracers, 1 casings) of `size` places is full.
func _say_full(which: int, what: String, size: int) -> void:
	if not _said_full[which]:
		_said_full[which] = true
		GameLog.say("ShotLayer: all %d %s places are taken, the rest are not shown" % [size, what])


## The layer runs only while a bullet flies or a casing is in the air.
func _rest_if_idle() -> void:
	set_process(_tracers.count > 0 or not _flying.is_empty() or not _waiting.is_empty())


## The casing at `index` of the flying ones has come to rest (or is gone).
func _stop_flying(index: int) -> void:
	_flying[index] = _flying[_flying.size() - 1]
	_flying.pop_back()


## Write `casing`'s place: where its 2D node is, turned as it is, at the height it flies or lies.
func _place_casing(casing: Node2D) -> void:
	var at := casing.global_position
	var frame := Transform3D(
		Basis(Vector3.UP, -casing.global_rotation),
		Vector3(at.x, casing.altitude(), at.y) * RenderConfig.unit,
	)
	if not _drawn(casing, at, casing.is_resting()):
		frame = Transform3D(Basis.from_scale(Vector3.ZERO), frame.origin)
	_casings.place(_casings.slot_of(casing), frame)


## Whether the player's view lets `casing` at `at` be drawn (`lying`: it rests): one in the air only
## inside the cone, one lying once the cone has reached it (it is then remembered where it lies).
## With no view, always. A lying one not yet seen waits, checked each frame.
func _drawn(casing: Node, at: Vector2, lying: bool) -> bool:
	if not SeenArea.active():
		_waiting.erase(casing)
		return true
	var id := casing.get_instance_id()
	var shown := true
	if SeenArea.reaches(at, TOSS_REACH):
		_seen[id] = true
	elif not lying or not _seen.has(id):
		shown = false
		if not lying:
			_seen.erase(id)  # one that flies out of the cone is to be seen again where it lands
	if lying:
		if shown:
			_waiting.erase(casing)
		elif not _waiting.has(casing):
			_waiting.append(casing)
	return shown


## Write the tracer in `slot`: its tip on its bullet, its streak behind along the heading, at the
## bullet's height, shortened over the last stretch of the bullet's range.
func _place_tracer(slot: int) -> void:
	var bullet: Node2D = _tracers.owner_at(slot)
	if bullet == null:
		return
	var heading: Vector2 = bullet.direction
	var fade := ProjectileMeshConfig.tracer_fade
	var whole := clampf(bullet.range_left() / fade, 0.02, 1.0) if fade > 0.0 else 1.0
	var length := ProjectileMeshConfig.tracer_length * whole
	var middle := bullet.global_position - heading * length * 0.5
	var height := _tracer_height(bullet)
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


## How high (px) `bullet`'s tracer flies: the bullet's own height, never lower than `tracer_floor`
## (it climbs or falls with its line).
func _tracer_height(bullet: Node2D) -> float:
	return maxf(bullet.height, ProjectileMeshConfig.tracer_floor)


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
