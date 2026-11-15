class_name MeshNodes
extends RefCounted
## Art domain, the 3D mesh kit's node helpers (interface 12): the `MeshInstance3D` a built mesh is
## shown by, and the places a mesh's parts go, in the art's px (the one `RenderConfig.unit`
## conversion is the kit's, so a builder never multiplies by it).


## A node showing `mesh` in the shared toon material (`ToonMaterial.shared`), tinted `tint` (the
## instance's `base_color`, white: the mesh's own colours), casting a shadow unless `casts_shadow`
## is off.
static func instance(mesh: Mesh, tint := Color.WHITE, casts_shadow := true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = ToonMaterial.shared()
	node.set_instance_shader_parameter(&"base_color", tint)
	node.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if casts_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	return node


## `node` placed at `at` (2D `x`, height, 2D `y`, all px) and turned `yaw` radians about the up axis
## (a 2D turn clockwise on the y-down screen is `-angle`: pass the 2D angle negated as the mirror
## does), in the frame of its parent.
static func place(node: Node3D, at: Vector3, yaw := 0.0) -> void:
	node.position = at * RenderConfig.unit
	node.rotation.y = yaw


## The frame (px, in the frame of the surface's owner) of a spot on a surface: at `at`, facing
## `normal` (up for a floor or a table top, sideways for a wall) and turned `spin` radians about the
## normal. What `decal` is laid by. Facing up it is the identity (a texture's top-left corner at
## `x`, `z` smallest, its top toward `-z`); facing sideways the texture stands upright.
static func surface_frame(at: Vector3, normal := Vector3.UP, spin := 0.0) -> Transform3D:
	var up := normal.normalized()
	var toward := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var right := (toward - up * up.dot(toward)).normalized()
	var turned := Basis(right, up, right.cross(up)).rotated(up, spin)
	return Transform3D(turned, at)


## A decal: a flat quad of `size` px laid on a surface at `frame` (`surface_frame`), showing
## `texture` (its alpha cuts the quad: a crack, a stain, a stencil; null is a plain patch) times
## `tint`. It floats `MeshKitConfig.decal_lift` px off the surface so it never fights it, lit as the
## toon material lights, casting no shadow.
static func decal(size: Vector2, frame: Transform3D, texture: Texture2D = null,
		tint := Color.WHITE) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _quad(size)
	node.material_override = ToonMaterial.decal(texture)
	node.set_instance_shader_parameter(&"base_color", tint)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.basis = frame.basis
	node.position = (frame.origin + frame.basis.y * MeshKitConfig.decal_lift) * RenderConfig.unit
	return node


## The quad of `size` px (a 3D mesh in the XZ plane facing up, with uvs) every decal of that size
## shares.
static func _quad(size: Vector2) -> Mesh:
	return MeshCache.fetch(MeshCache.key("decal", size, Color.WHITE), func() -> Mesh:
		var half := size * 0.5 * RenderConfig.unit
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
			Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y),
			Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y),
		])
		var up := Vector3.UP
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([up, up, up, up])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
		])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
	)
