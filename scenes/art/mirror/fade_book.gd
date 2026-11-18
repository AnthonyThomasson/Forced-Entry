class_name FadeBook
extends RefCounted
## Art domain, what the wall fade looks after (`wall_fade.gd`): the meshes it is told of, the units
## they are made of, and how those units come and go. A mesh is `watch`ed with the key of its body
## (its instance id) and taught to the fade from the next frame it is in the tree (`admit`): a mesh
## with a signal `segment_replaced(index, part)` and a method `segments() -> Dictionary` (index ->
## instance) is a wall, one unit per segment (`WallMesh`); any other mesh is one unit of every
## `GeometryInstance3D` under it. A unit that stands under `WallFadeConfig.tall_height` is not kept.
## A mesh that says `hangs_on_wall` (a stain, a menu board: a `FurnitureRig`) is a hung unit: it is
## in no grid cell and fades with the wall unit it hangs on (`WallFadeConfig.hang_pad`), looked for
## each frame until found, else after `hang_frames` frames it is a unit of its own. A mesh leaving
## the tree takes its units out of the grid, and the fade they had is kept a few frames for the mesh
## that takes their place (a piece built again, by its key).

## How many units are kept.
var count := 0
var _grid: FadeGrid
## The fade's list of units that are not whole (shared with it: the book puts a unit back on it).
var _listed: Array[FadeUnit]
## Key -> the units of the mesh watched under it, by index.
var _units: Dictionary = {}
## Meshes waiting for the frame they are in the tree (`[mesh, key, movable]`).
var _pending: Array = []
## The fade a freed mesh's units had, by key and index, and until which tick it is kept.
var _carry: Dictionary = {}
var _carry_until := 0
var _tick := 0
## The hung units still without a wall, each `[unit, frames waited]`.
var _hanging: Array = []


func _init(grid: FadeGrid, listed: Array[FadeUnit]) -> void:
	_grid = grid
	_listed = listed


## Look after `mesh`, the 3D mesh of the body `key`: from the next `admit` it is in the tree.
## `movable` for a piece that can be shoved or swung.
func watch(mesh: Node3D, key: int, movable: bool) -> void:
	_pending.append([mesh, key, movable])


## The unit of segment `index` of the mesh watched under `key` (a piece is index 0), or null.
func unit_of(key: int, index := 0) -> FadeUnit:
	return (_units.get(key, {}) as Dictionary).get(index)


## Teach the fade the meshes that came into the tree since the last call, and forget the carried
## fades nobody took up.
func admit() -> void:
	_tick += 1
	if not _carry.is_empty() and _tick > _carry_until:
		_carry.clear()
	_find_walls()
	var i := 0
	while i < _pending.size():
		var entry: Array = _pending[i]
		var mesh: Variant = entry[0]
		if not is_instance_valid(mesh):
			_pending.remove_at(i)
		elif (mesh as Node3D).is_inside_tree():
			_pending.remove_at(i)
			_register(mesh as Node3D, entry[1], entry[2])
		else:
			i += 1


## Teach it what `mesh` (the mesh of the body `key`) is made of: a wall's segments, or one piece.
func _register(mesh: Node3D, key: int, movable: bool) -> void:
	var units := {}
	var wall := mesh.has_signal(&"segment_replaced") and mesh.has_method(&"segments")
	if wall:
		var parts: Dictionary = mesh.call(&"segments")
		for index: int in parts:
			var unit := _part_unit(parts[index], key, index)
			if unit != null:
				units[index] = unit
		mesh.connect(&"segment_replaced", _on_segment_replaced.bind(key))
	else:
		var hangs: bool = mesh.get(&"hangs_on_wall") == true
		var unit := _piece_unit(mesh, key, movable and not hangs, hangs)
		if unit != null:
			units[0] = unit
	if units.is_empty() and not wall:
		return
	_units[key] = units
	mesh.tree_exiting.connect(_forget.bind(key), CONNECT_ONE_SHOT)
	var carried: Dictionary = _carry.get(key, {})
	for index: int in units:
		if carried.has(index):
			_resume(units[index], carried[index])
	_carry.erase(key)


## A wall's segment `part`: one unit (the segment's box; the instances it carries on its face, a
## wear decal, fade with it), or null when it is too low to hide anyone.
func _part_unit(part: MeshInstance3D, key: int, index: int) -> FadeUnit:
	var instances: Array[GeometryInstance3D] = [part]
	for child in part.get_children():
		if child is GeometryInstance3D:
			instances.append(child)
	var unit := _filed(FadeUnit.make(part, instances, part.get_aabb(), false))
	if unit != null:
		unit.hold.key = key
		unit.hold.index = index
		unit.hang.wall = true
	return unit


## A whole piece: every instance under `mesh` (and it, if it shows one) fades together; a `hangs`
## piece is a hung unit.
func _piece_unit(mesh: Node3D, key: int, movable: bool, hangs := false) -> FadeUnit:
	var instances: Array[GeometryInstance3D] = []
	var bounds := AABB()
	var inverse := mesh.global_transform.affine_inverse()
	var nodes := mesh.find_children("*", "GeometryInstance3D", true, false)
	if mesh is GeometryInstance3D:
		nodes.append(mesh)
	for node: Node in nodes:
		var part := node as GeometryInstance3D
		var local: AABB = inverse * part.global_transform * part.get_aabb()
		bounds = local if instances.is_empty() else bounds.merge(local)
		instances.append(part)
	if instances.is_empty():
		return null
	var unit := FadeUnit.make(mesh, instances, bounds, movable)
	unit.hold.key = key
	if hangs:
		unit.hang.hung = true
		count += 1
		_hanging.append([unit, 0])
		return unit
	return _filed(unit)


## File `unit` in the grid; null for one too low to matter.
func _filed(unit: FadeUnit) -> FadeUnit:
	if unit.box.top < WallFadeConfig.tall_height * RenderConfig.unit:
		return null
	count += 1
	_grid.file(unit)
	return unit


## Take `unit` out of the grid and off the list of those the fade steps; the pieces hung on it look
## for another wall unless `rehome` is false (the caller gives them a new one).
func _unfile(unit: FadeUnit, rehome := true) -> void:
	count -= 1
	unit.hold.release()
	_grid.unfile(unit)
	_leave_walls(unit, rehome)
	if unit.listed:
		unit.listed = false
		_listed.erase(unit)


## `Segment<index>` of a wall was rebuilt, `part` its new instance: the fade the old one had goes
## on the new one at once, so a hit segment is not whole for a frame.
func _on_segment_replaced(index: int, part: MeshInstance3D, key: int) -> void:
	var units: Dictionary = _units.get(key, {})
	var old: FadeUnit = units.get(index)
	var unit := _part_unit(part, key, index)
	var hung: Array[FadeUnit] = []
	if old != null:
		hung.assign(old.hang.followers)
		_unfile(old, false)
	if unit == null:
		units.erase(index)
		return
	units[index] = unit
	for piece in hung:
		piece.hang.hosts.append(unit)
		unit.hang.followers.append(piece)
	if old != null and old.faded > 0.0:
		unit.hit_frame = old.hit_frame
		_resume(unit, old.faded)


## Put `unit` back at `faded` of the way (a segment rebuilt, a piece built again): listed so the
## fade steps it, and written now.
func _resume(unit: FadeUnit, faded: float) -> void:
	unit.faded = faded
	if not unit.listed:
		unit.listed = true
		_listed.append(unit)
	unit.apply()


## Every unit stops being held faded: the fade is going, and its meshes may stay (a view rebuilt
## over live bodies).
func release_all() -> void:
	for units: Dictionary in _units.values():
		for unit: FadeUnit in units.values():
			unit.hold.release()


## The mesh of `key` leaves the tree: its units go, and what they had faded is kept for a few
## frames for the mesh that takes its place.
func _forget(key: int) -> void:
	var units: Dictionary = _units.get(key, {})
	var carried := {}
	for index: int in units:
		var unit: FadeUnit = units[index]
		if unit.faded > 0.0:
			carried[index] = unit.faded
		_unfile(unit)
	_units.erase(key)
	if not carried.is_empty():
		_carry[key] = carried
		_carry_until = _tick + 3


## Give each hung unit still without a wall a look for one: the wall units in the cell of the middle
## of its back whose footprint, grown `hang_pad`, holds that point. One that waited `hang_frames`
## frames is a unit of its own, filed in the grid like any tall piece.
func _find_walls() -> void:
	var i := 0
	while i < _hanging.size():
		var entry: Array = _hanging[i]
		var unit: FadeUnit = entry[0]
		if _attach(unit):
			_hanging.remove_at(i)
			continue
		entry[1] += 1
		if entry[1] >= WallFadeConfig.hang_frames:
			_hanging.remove_at(i)
			unit.hang.hung = false
			if unit.box.top >= WallFadeConfig.tall_height * RenderConfig.unit:
				_grid.file(unit)
			continue
		i += 1


## Make `unit` follow the wall units that hold its back; whether there were any.
func _attach(unit: FadeUnit) -> bool:
	var point := unit.box.centre
	var pad := WallFadeConfig.hang_pad * RenderConfig.unit
	var hosts: Array[FadeUnit] = []
	for host: FadeUnit in _grid.at(_grid.cell_of(point.x), _grid.cell_of(point.y)):
		if host.hang.wall and host.box.entry(point, Vector2.RIGHT, pad) == 0.0:
			hosts.append(host)
	if hosts.is_empty():
		return false
	unit.hang.hosts = hosts
	for host in hosts:
		host.hang.followers.append(unit)
	return true


## `unit` goes: a hung one stops following its walls (and stops looking for one), a wall's hung
## pieces are left without it (and look for another when `rehome`).
func _leave_walls(unit: FadeUnit, rehome: bool) -> void:
	for host in unit.hang.hosts:
		host.hang.followers.erase(unit)
	unit.hang.hosts.clear()
	for i in range(_hanging.size() - 1, -1, -1):
		if _hanging[i][0] == unit:
			_hanging.remove_at(i)
	for piece in unit.hang.followers:
		piece.hang.hosts.erase(unit)
		if rehome and piece.hang.hosts.is_empty() and piece.hang.hung:
			_hanging.append([piece, 0])
	unit.hang.followers.clear()
