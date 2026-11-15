class_name InkChunk
extends MeshInstance3D
## Physics domain, the marks of one 128 px square of the 3D floor (`InkFx`) as one mesh, so a floor
## strewn with blood costs a draw or two and not one a mark. The mesh is built again, from the
## marks' own triangles, when one is added, dropped, painted or grown (the owner asks for it once a
## frame at most); a chunk with no mark has no mesh.

## The marks it shows, oldest first.
var marks: Array[InkMark] = []


func _init() -> void:
	mesh = ArrayMesh.new()
	material_override = ToonMaterial.shared()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	MeshNodes.base_color(self, Color.WHITE)


## Build the mesh again from the marks.
func rebuild() -> void:
	var arrays := mesh as ArrayMesh
	arrays.clear_surfaces()
	var points := PackedVector3Array()
	var tones := PackedColorArray()
	for mark in marks:
		points.append_array(mark.verts)
		tones.append_array(mark.colors)
	if points.is_empty():
		return
	var up := PackedVector3Array()
	up.resize(points.size())
	up.fill(Vector3.UP)
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = points
	surface[Mesh.ARRAY_NORMAL] = up
	surface[Mesh.ARRAY_COLOR] = tones
	arrays.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
