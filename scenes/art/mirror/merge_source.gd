class_name MergeSource
extends RefCounted
## Art domain, one mesh's vertices as a chunk takes them (`merge_chunk.gd`): every surface's
## triangles laid out one vertex a corner, read from the mesh once and shared by every member that
## shows it (kept while the mesh lives).

const STRIDE := 4

## Instance id of a mesh -> `[weakref(mesh), source or null]`.
static var _read: Dictionary = {}
## The size at which the next new mesh first forgets the freed ones.
static var _prune_at := 256

## Positions, normals and colours (white where the mesh has none), its uvs (zero without), each
## vertex's model (x, z), and its model normal as four floats.
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var across := PackedVector2Array()
var model_normals := PackedFloat32Array()


## The source of `mesh`, or null for a mesh a chunk cannot take (not triangles, or empty).
static func of(mesh: Mesh) -> MergeSource:
	var id := mesh.get_instance_id()
	var held: Variant = _read.get(id)
	if held != null and (held[0] as WeakRef).get_ref() == mesh:
		return held[1]
	if _read.size() >= _prune_at:
		for key: int in _read.keys():
			if (_read[key][0] as WeakRef).get_ref() == null:
				_read.erase(key)
		_prune_at = maxi(256, _read.size() * 2)
	var made := _from(mesh)
	_read[id] = [weakref(mesh), made]
	return made


## Drop every source read: the cache holds instances of its own script, which would otherwise
## keep it, and what it reaches, alive at the engine's exit.
static func clear() -> void:
	_read.clear()


## `mesh`'s triangles read and laid out.
static func _from(mesh: Mesh) -> MergeSource:
	var out := MergeSource.new()
	for surface in mesh.get_surface_count():
		var array_mesh := mesh as ArrayMesh
		if (
			array_mesh != null
			and array_mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES
		):
			return null
		out._add(mesh.surface_get_arrays(surface))
	if out.vertices.is_empty():
		return null
	out._derive()
	return out


## Append a surface's `arrays`, an indexed one corner by corner.
func _add(arrays: Array) -> void:
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var facing: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tints := PackedColorArray()
	if arrays[Mesh.ARRAY_COLOR] != null:
		tints = arrays[Mesh.ARRAY_COLOR]
	if tints.size() != points.size():
		tints.resize(points.size())
		tints.fill(Color.WHITE)
	var laid := PackedVector2Array()
	if arrays[Mesh.ARRAY_TEX_UV] != null:
		laid = arrays[Mesh.ARRAY_TEX_UV]
	laid.resize(points.size())
	var order := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		order = arrays[Mesh.ARRAY_INDEX]
	if order.is_empty():
		vertices.append_array(points)
		normals.append_array(facing)
		colors.append_array(tints)
		uvs.append_array(laid)
		return
	for i in order:
		vertices.append(points[i])
		normals.append(facing[i])
		colors.append(tints[i])
		uvs.append(laid[i])


## What the shader reads of a vertex in its own mesh's frame.
func _derive() -> void:
	across.resize(vertices.size())
	model_normals.resize(vertices.size() * STRIDE)
	for i in vertices.size():
		across[i] = Vector2(vertices[i].x, vertices[i].z)
		model_normals[i * STRIDE] = normals[i].x
		model_normals[i * STRIDE + 1] = normals[i].y
		model_normals[i * STRIDE + 2] = normals[i].z
		model_normals[i * STRIDE + 3] = 0.0
