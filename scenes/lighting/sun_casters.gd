extends Node
## Lighting domain: keeps what cannot shadow a street spot out of the sun's shadow pass. The sun
## lights only the street (the sky mask: the street's floors less the houses, `ToonLight.set_sky`),
## so a mesh whose shadow falls on no such spot changes no pixel by casting. Such a mesh is moved
## from render layer 1 to `LightingCostConfig.sun_indoor_layer`, which the sun's
## `shadow_caster_mask` leaves out; the camera and every other light see that layer as any other.
##
## Only a mesh that is known to stay where it is is judged: one on a static twin
## (`StaticBody3D`), one on a body a script drives (`AnimatableBody3D`, a standing door's leaf:
## looked at every frame, judged again when it moved), one on a rigid body that sleeps (it casts
## again the frame it wakes: every held body is asked each frame, since a script's
## `sleeping = false` signals nothing), and one the mesh carrier placed itself (a `proxies_of`
## ancestor, read duck-typed: a non-solid piece). Everything else always casts. A static or
## sleeping mesh a script moves is found by a look at a few of them each frame
## (`LightingCostConfig.sun_recheck`).

## The bit of the layer a mesh casts on by default.
const CASTING := 1

## The sun whose pass is thinned.
var _sun: DirectionalLight3D
## The street's rects, grown by the margin, and the houses' (2D px): where the sun reaches.
var _streets: Array[Rect2] = []
var _houses: Array[Rect2] = []
## How far a shadow falls over the floor for each px of height above it, and its direction.
var _fall := Vector2.ZERO
## The meshes judged, by instance id: `{ mesh, at: Transform3D, body: RigidBody3D or null }`.
var _held: Dictionary = {}
## The rigid bodies holding a judged mesh, whether each slept at the last look (0 or 1) and the
## ids of its meshes, by the same place; `_places` is each body's place by its instance id.
var _bodies: Array = []
var _asleep := PackedByteArray()
var _carried: Array[Array] = []
var _places: Dictionary = {}
## The ids of the judged meshes a script drives, looked at every frame (a set).
var _driven: Dictionary = {}
## The meshes that joined the tree and are judged on the next frame, by instance id.
var _joined: Dictionary = {}
## The ids still to be looked at in this round of the re-check.
var _round: Array = []


func _process(_delta: float) -> void:
	settle()
	_wake()
	_follow_driven()
	_recheck()


## Judge every mesh of the sun's world, now and as it joins: `streets` and `houses` are the world
## rects (2D px) the sky mask paints white and then black, `travel` the way the sunlight goes.
func watch(
	sun: DirectionalLight3D, streets: Array[Rect2], houses: Array[Rect2], travel: Vector3
) -> void:
	_sun = sun
	var margin := LightingCostConfig.sun_caster_margin
	for street in streets:
		_streets.append(street.grow(margin))
	_houses = houses
	_fall = Vector2(travel.x, travel.z) / maxf(-travel.y, 0.001)
	sun.shadow_caster_mask = 0xffffffff & ~_indoor_bit()
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		_on_node_added(node)
	settle()


## Judge the meshes that joined since the last frame.
func settle() -> void:
	if _joined.is_empty():
		return
	var batch := _joined.values()
	_joined = {}
	var world := _sun.get_world_3d()
	for mesh: Variant in batch:
		if not is_instance_valid(mesh) or not (mesh as Node3D).is_inside_tree():
			continue
		if (mesh as Node3D).get_world_3d() == world:
			_take(mesh)


## Whether the sunlight on a mesh spanning `box` (3D units) can fall on a street spot: its
## footprint swept along the fall of its top, grown by the margin, holds a point of a street that
## no house covers.
func reaches_street(box: AABB) -> bool:
	var unit := RenderConfig.unit
	var margin := LightingCostConfig.sun_caster_margin
	var foot := Rect2(
		Vector2(box.position.x, box.position.z) / unit, Vector2(box.size.x, box.size.z) / unit
	)
	var thrown := _fall * maxf(box.end.y / unit + margin, 0.0)
	var swept := foot.merge(Rect2(foot.position + thrown, foot.size)).grow(margin)
	var open: Array[Rect2] = []
	for street in _streets:
		if street.intersects(swept):
			open.append(street.intersection(swept))
	for house in _houses:
		if open.is_empty():
			break
		open = _less(open, house)
	return not open.is_empty()


## How many meshes `body` is followed with (a test reads it).
func carried(body: RigidBody3D) -> int:
	var place: Variant = _places.get(body.get_instance_id())
	return 0 if place == null else _carried[place].size()


## `rects` with `cut` taken out of each.
static func _less(rects: Array[Rect2], cut: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for rect in rects:
		if not rect.intersects(cut):
			out.append(rect)
			continue
		var held := rect.intersection(cut)
		var above := held.position.y - rect.position.y
		var below := rect.end.y - held.end.y
		var left := held.position.x - rect.position.x
		var right := rect.end.x - held.end.x
		if above > 0.0:
			out.append(Rect2(rect.position, Vector2(rect.size.x, above)))
		if below > 0.0:
			out.append(Rect2(rect.position.x, held.end.y, rect.size.x, below))
		if left > 0.0:
			out.append(Rect2(rect.position.x, held.position.y, left, held.size.y))
		if right > 0.0:
			out.append(Rect2(held.end.x, held.position.y, right, held.size.y))
	return out


## The bit of the layer the sun casts nothing from.
static func _indoor_bit() -> int:
	return 1 << (LightingCostConfig.sun_indoor_layer - 1)


## A mesh joined the tree: judged on the next frame, when its transform, mesh and world are set.
func _on_node_added(node: Node) -> void:
	if node is MeshInstance3D:
		_joined[node.get_instance_id()] = node


## Judge `mesh` by what holds it, and remember it when it may be left out.
func _take(mesh: MeshInstance3D) -> void:
	var id := mesh.get_instance_id()
	_held.erase(id)
	_cast(mesh, true)
	var holder := mesh.get_parent()
	while holder != null and not (holder is CollisionObject3D or holder.has_method(&"proxies_of")):
		holder = holder.get_parent()
	var body := holder as RigidBody3D
	if holder == null or (holder is CollisionObject3D and body == null
			and not holder is StaticBody3D):
		return
	if body != null:
		_follow(body, id)
	if holder is AnimatableBody3D:
		_driven[id] = true
	var row := { "mesh": mesh, "body": body, "at": mesh.global_transform }
	_held[id] = row
	_judge(row)


## Ask `body` each frame whether it sleeps, for the mesh `id` on it.
func _follow(body: RigidBody3D, id: int) -> void:
	var key := body.get_instance_id()
	if not _places.has(key):
		_places[key] = _bodies.size()
		_bodies.append(body)
		_asleep.append(int(body.sleeping))
		_carried.append([])
	var meshes: Array = _carried[_places[key]]
	if not meshes.has(id):
		meshes.append(id)


## Judge again the meshes of every body that woke or fell asleep, dropping those no longer held (a
## dented body's mesh is built again); a freed body is forgotten.
func _wake() -> void:
	var at := _bodies.size() - 1
	while at >= 0:
		var body: Variant = _bodies[at]
		if not is_instance_valid(body):
			_forget(at)
		elif int((body as RigidBody3D).sleeping) != _asleep[at]:
			_asleep[at] = int((body as RigidBody3D).sleeping)
			var meshes: Array = _carried[at]
			for i in range(meshes.size() - 1, -1, -1):
				var row: Variant = _held.get(meshes[i])
				if row == null or not is_instance_valid(row["mesh"]):
					_held.erase(meshes[i])
					meshes.remove_at(i)
				elif is_same(row["body"], body):
					_judge(row)
		at -= 1


## Drop the body at place `at`, the last taking its place.
func _forget(at: int) -> void:
	var last := _bodies.size() - 1
	for key: int in _places:
		if _places[key] == at:
			_places.erase(key)
			break
	if at != last:
		for key: int in _places:
			if _places[key] == last:
				_places[key] = at
				break
		_bodies[at] = _bodies[last]
		_asleep[at] = _asleep[last]
		_carried[at] = _carried[last]
	_bodies.resize(last)
	_asleep.resize(last)
	_carried.resize(last)


## Cast or leave out a held mesh by where it stands now; one on an awake body casts.
func _judge(row: Dictionary) -> void:
	var mesh: MeshInstance3D = row["mesh"]
	var body: RigidBody3D = row["body"]
	if not mesh.is_inside_tree():
		return
	row["at"] = mesh.global_transform
	if body != null and not body.sleeping:
		_cast(mesh, true)
		return
	_cast(mesh, reaches_street(mesh.global_transform * mesh.get_aabb()))


## Look at every mesh a script drives.
func _follow_driven() -> void:
	for id: int in _driven.keys():
		if not _look(id):
			_driven.erase(id)


## Look at a few held meshes.
func _recheck() -> void:
	if _round.is_empty():
		_round = _held.keys()
	for i in mini(LightingCostConfig.sun_recheck, _round.size()):
		_look(_round.pop_back())


## Judge held mesh `id` again if it moved; false once it is freed or no longer held.
func _look(id: int) -> bool:
	var row: Variant = _held.get(id)
	if row == null:
		return false
	if not is_instance_valid(row["mesh"]):
		_held.erase(id)
		return false
	var mesh: MeshInstance3D = row["mesh"]
	if mesh.is_inside_tree() and mesh.global_transform != row["at"]:
		_judge(row)
	return true


## Put `mesh` on the layer the sun casts from, or on the one it leaves out.
func _cast(mesh: MeshInstance3D, casting: bool) -> void:
	var bit := _indoor_bit()
	var layers := (
		(mesh.layers & ~bit) | CASTING if casting else (mesh.layers & ~CASTING) | bit
	)
	if layers != mesh.layers:
		mesh.layers = layers
