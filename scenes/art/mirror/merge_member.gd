class_name MergeMember
extends RefCounted
## Art domain, one still mesh a chunk of `StillMerge` may hold: what about it a chunk can show
## (`kind_of`, `joins`), the look it was merged with (`look_of`: everything that changes its
## pixels) and where its vertices lie in the chunk. A member whose look is that one again is the
## chunk's to draw; one that differs draws itself.

## The kinds of `toon_merged.gdshader` (its UV2.x): plain toon, textured (+1 tiled, +2 cut-out),
## a decal and a decal with no picture.
const PLAIN := 0
const TEXTURED := 1
const DECAL := 5
const BLANK_DECAL := 6
## The toon materials' own default colour of an instance never tinted.
const UNTINTED := Color(0.7, 0.7, 0.7, 1.0)

## The mesh node it stands for.
var node: MeshInstance3D
## The node's instance id (`node` may be freed) and the chunk it is merged in.
var key := 0
var chunk: MergeChunk
## Its first vertex in the chunk and how many it has.
var first := 0
var count := 0
## Where it stood, its render layers and how it looked when merged (`look_of`).
var at := Transform3D()
var layers := 0
var look: Array = []
## Whether the chunk draws it now, and whether it left its place (hidden, moved, casting another
## way) since it was last the chunk's, so the lights' cached shadows are stale when it returns.
var in_chunk := false
var strayed := false
## The painted art it wears (held so the atlas keeps its place), and its kind.
var art: Texture2D
var kind := PLAIN
## The node that tells of its moves.
var watch: Node


## The kind a chunk shows `mesh_node` as, or -1: one whose material a chunk cannot stand in for.
static func kind_of(mesh_node: MeshInstance3D) -> int:
	var material := mesh_node.material_override as ShaderMaterial
	if material == null:
		return -1
	if material.shader == ToonMaterial.SHADER:
		return PLAIN
	if material.shader == ToonMaterial.TEX_SHADER:
		return _textured_kind(material)
	if material.shader == ToonMaterial.DECAL_SHADER:
		return _decal_kind(material)
	return -1


## A textured material's kind: only one that reads the atlas.
static func _textured_kind(material: ShaderMaterial) -> int:
	if material.get_shader_parameter(&"atlased") != true:
		return -1
	return (
		TEXTURED + int(material.get_shader_parameter(&"tiled") == true)
		+ 2 * int(material.get_shader_parameter(&"cutout") == true)
	)


## A decal material's kind: blank, or one whose picture the atlas takes.
static func _decal_kind(material: ShaderMaterial) -> int:
	var texture: Texture2D = material.get_shader_parameter(&"albedo_texture")
	if texture == null:
		return BLANK_DECAL
	return DECAL if ToonAtlas.fits(texture) else -1


## Whether `mesh_node` is a mesh a chunk could ever hold: what never changes for the better.
static func suits(mesh_node: MeshInstance3D) -> bool:
	if mesh_node.mesh == null or kind_of(mesh_node) < 0 or mesh_node.material_overlay != null:
		return false
	if mesh_node.has_meta(MeshNodes.GLOWS):
		return false
	if mesh_node.transparency > 0.0 or mesh_node.visibility_range_end > 0.0:
		return false
	return MergeSource.of(mesh_node.mesh) != null


## Whether `mesh_node` may join a chunk as it is now: shown, casting plainly, whole, still, never
## given a glow, unmirrored, and on no rigid body that is awake.
static func joins(mesh_node: MeshInstance3D) -> bool:
	if not mesh_node.is_inside_tree() or not mesh_node.is_visible_in_tree():
		return false
	if mesh_node.cast_shadow > GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
		return false
	if _param(mesh_node, &"fade", 1.0) < 1.0 or _param(mesh_node, &"moving", 0.0) > 0.0:
		return false
	if mesh_node.has_meta(MeshNodes.GLOWS):
		return false
	if mesh_node.global_transform.basis.determinant() <= 0.0:
		return false
	var holder: Node = mesh_node.get_parent()
	while holder != null and not holder is CollisionObject3D:
		holder = holder.get_parent()
	return not holder is RigidBody3D or (holder as RigidBody3D).sleeping


## Everything about `mesh_node` besides its place that its pixels come from.
static func look_of(mesh_node: MeshInstance3D) -> Array:
	return [
		mesh_node.is_visible_in_tree(),
		mesh_node.mesh,
		mesh_node.material_override,
		mesh_node.cast_shadow,
		colour_of(mesh_node),
		_param(mesh_node, &"figure", 0.0),
		mesh_node.has_meta(MeshNodes.GLOWS),
		_param(mesh_node, &"fade", 1.0),
		_param(mesh_node, &"moving", 0.0),
		vector_of(mesh_node, &"uv_rect"),
		vector_of(mesh_node, &"atlas_rect"),
	]


## The instance colour `mesh_node` is drawn in (sRGB): its `base_color`, else its shader's default.
static func colour_of(mesh_node: MeshInstance3D) -> Color:
	var set_to: Variant = mesh_node.get_instance_shader_parameter(&"base_color")
	if set_to is Color:
		return set_to
	var material := mesh_node.material_override as ShaderMaterial
	var decal := material != null and material.shader == ToonMaterial.DECAL_SHADER
	return Color.WHITE if decal else UNTINTED


## The `vec4` instance uniform `name` of `mesh_node`, the shaders' default when never set.
static func vector_of(mesh_node: MeshInstance3D, name: StringName) -> Vector4:
	var set_to: Variant = mesh_node.get_instance_shader_parameter(name)
	return set_to if set_to is Vector4 else Vector4(0.0, 0.0, 1.0, 1.0)


## The number of the instance uniform `name`, `unset` when never set.
static func _param(mesh_node: MeshInstance3D, name: StringName, unset: float) -> float:
	var set_to: Variant = mesh_node.get_instance_shader_parameter(name)
	return float(set_to) if set_to != null else unset


## Whether the node still stands where it was merged: in the tree, not moved, on the same render
## layers.
func in_place() -> bool:
	return (
		is_instance_valid(node) and node.is_inside_tree() and node.global_transform == at
		and node.layers == layers
	)


## Whether the node draws, where it was merged, what the chunk's cached shadows hold: shown and
## casting as it did.
func casts_as_merged() -> bool:
	return in_place() and node.is_visible_in_tree() and node.cast_shadow == look[3]
