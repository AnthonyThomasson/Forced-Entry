class_name MergeChunk
extends RefCounted
## Art domain, one chunk of `StillMerge`: the meshes of its members in one `ArrayMesh` of world
## coordinates, drawn by one rendering-server instance (no node: nothing that walks the tree finds
## it). The mesh is built once and never again: a member leaves by having its vertices drawn to a
## point, and returns by having them written back. (World coordinates: an origin at the chunk's own
## square rounds the corners further from where each mesh's own transform put them.)

## Bytes a vertex position takes in the mesh's vertex buffer.
const POSITION_BYTES := 12

## The meshes it holds, the one surface they are laid into and its rendering-server instance.
var members: Array[MergeMember] = []
var mesh := ArrayMesh.new()
var instance := RID()
## Whether it casts shadows.
var casts := false
## What its instance was given, setter's name -> value: the server tells none of it back (a test).
var given := {}
## The positions as built, to write a member back.
var _positions := PackedVector3Array()


## A chunk of `joining` (each `joins` now) in `scenario`, casting as `cast` says on the render
## layers `layers`; each member is told its place in it.
static func make(
	joining: Array[MergeMember], scenario: RID, cast: int, layers: int
) -> MergeChunk:
	var chunk := MergeChunk.new()
	chunk.members = joining
	chunk.casts = cast != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk._build()
	chunk.instance = RenderingServer.instance_create2(chunk.mesh.get_rid(), scenario)
	var material := ToonMaterial.merged().get_rid()
	chunk._give(RenderingServer.instance_set_transform, Transform3D())
	chunk._give(RenderingServer.instance_geometry_set_material_override, material)
	chunk._give(RenderingServer.instance_geometry_set_cast_shadows_setting, cast)
	chunk._give(RenderingServer.instance_set_layer_mask, layers)
	return chunk


## Draw `member`'s vertices (`on`) or none of them.
func show_member(member: MergeMember, on: bool) -> void:
	var part := _positions.slice(member.first, member.first + member.count)
	if not on:
		part.fill(part[0])
	mesh.surface_update_vertex_region(0, member.first * POSITION_BYTES, part.to_byte_array())


## Have every light that reaches the chunk draw its shadow again: it cached one of other vertices
## and nothing else tells it.
func recast() -> void:
	if casts and instance.is_valid():
		RenderingServer.instance_set_visible(instance, false)
		RenderingServer.instance_set_visible(instance, true)


## Free the instance and let go of the members (each holds its chunk, so neither would be freed):
## the chunk draws nothing from then on.
func free_instance() -> void:
	members.clear()
	if instance.is_valid():
		RenderingServer.free_rid(instance)
		instance = RID()


## Set the instance up by the server's `setter`, and record it (`given`).
func _give(setter: Callable, value: Variant) -> void:
	setter.call(instance, value)
	given[setter.get_method()] = value


## The members' meshes laid into one surface, each where its node stands.
func _build() -> void:
	var laid := Layout.new()
	for member in members:
		member.first = laid.vertices.size()
		laid.add(member)
		member.count = laid.vertices.size() - member.first
	_positions = laid.vertices
	var full := Mesh.ARRAY_CUSTOM_RGBA_FLOAT
	var flags := (
		(full << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (full << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		| (full << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) | (full << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)
	)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, laid.arrays(), [], {}, flags)


## The vertex arrays of a chunk, filled one member at a time (what each holds:
## `toon_merged.gdshader`).
class Layout:
	extends RefCounted

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	## The member's kind and figure.
	var kinds := PackedVector2Array()
	## `uv_rect`, `atlas_rect`, the linear colour and the model normal, four floats a vertex.
	var rects := PackedFloat32Array()
	var places := PackedFloat32Array()
	var tints := PackedFloat32Array()
	var model := PackedFloat32Array()

	## Append `member`'s mesh where its node stands.
	func add(member: MergeMember) -> void:
		var source := MergeSource.of(member.node.mesh)
		var frame := member.node.global_transform
		var count := source.vertices.size()
		vertices.append_array(frame * source.vertices)
		var turned := Transform3D(frame.basis.inverse().transposed(), Vector3.ZERO)
		normals.append_array(turned * source.normals)
		colors.append_array(source.colors)
		uv.append_array(source.uvs if member.kind >= MergeMember.DECAL else source.across)
		model.append_array(source.model_normals)
		_add_params(member, count)

	## The arrays as `ArrayMesh.add_surface_from_arrays` takes them.
	func arrays() -> Array:
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = vertices
		out[Mesh.ARRAY_NORMAL] = normals
		out[Mesh.ARRAY_COLOR] = colors
		out[Mesh.ARRAY_TEX_UV] = uv
		out[Mesh.ARRAY_TEX_UV2] = kinds
		out[Mesh.ARRAY_CUSTOM0] = rects
		out[Mesh.ARRAY_CUSTOM1] = places
		out[Mesh.ARRAY_CUSTOM2] = tints
		out[Mesh.ARRAY_CUSTOM3] = model
		return out

	## What is the same on each of `member`'s `count` vertices.
	func _add_params(member: MergeMember, count: int) -> void:
		var pair := PackedVector2Array([Vector2(member.kind, member.look[5])])
		kinds.append_array(_fill2(pair, count))
		rects.append_array(_fill4(MergeMember.vector_of(member.node, &"uv_rect"), count))
		var place := MergeMember.vector_of(member.node, &"atlas_rect")
		if member.kind == MergeMember.DECAL:
			place = ToonAtlas.slot(member.art)
		places.append_array(_fill4(place, count))
		var linear := (member.look[4] as Color).srgb_to_linear()
		tints.append_array(_fill4(Vector4(linear.r, linear.g, linear.b, linear.a), count))

	## `pair` repeated to `length` entries.
	static func _fill2(pair: PackedVector2Array, length: int) -> PackedVector2Array:
		var out := pair.duplicate()
		while out.size() < length:
			out.append_array(out)
		out.resize(length)
		return out

	## The four floats of `value` repeated `length` times.
	static func _fill4(value: Vector4, length: int) -> PackedFloat32Array:
		var out := PackedFloat32Array([value.x, value.y, value.z, value.w])
		while out.size() < length * 4:
			out.append_array(out)
		out.resize(length * 4)
		return out
