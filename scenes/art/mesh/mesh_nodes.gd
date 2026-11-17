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


## A mesh (or a node already showing one) wearing the 2D painters' art: `texture` projected straight
## down onto the model, `rect` (px, in the mesh's own frame: the footprint the art covers, e.g. a
## piece's `Rect2(-size / 2, size)`) the part of the model plane the whole texture spans (the
## texel is the picture's pixel when the texture is `rect.size / ArtCanvasConfig.pixel_size`
## wide). The ONE entry every domain calls for a textured mesh.
##   * `thing` is a `Mesh` (a new node, shared toon rules as `instance`) or a `MeshInstance3D` /
##     `MultiMeshInstance3D` (its material and `uv_rect` are set; a tint it was given and its shadow
##     setting stay unless `opts` names them; a node never tinted is white, not the toon's grey
##     default, which would darken the art).
##   * `opts`: `tint` (the instance's `base_color`, white by default on a new node), `casts_shadow`
##     (true by default on a new node), `tiled` (the art repeats across the model: a floor tile,
##     a road strip; `rect` is then one tile), `cutout` (a clear texel draws nothing: a sprite laid
##     over a solid).
## A top face (normal up) shows the art, a side face the art's edge texels stretched and darkened
## (`toon_tex.gdshader` documents the rule); a clear texel shows the mesh's vertex colour. A null
## texture leaves the shared toon material (a plain mesh). Instance uniforms cannot be samplers, so
## a material is one per texture and tiling (`ToonMaterial.textured`, weakly cached): many nodes of
## one texture share it, a node holds it.
static func textured(
	thing: Object,
	texture: Texture2D,
	rect: Rect2,
	opts := {},
) -> GeometryInstance3D:
	var node: GeometryInstance3D
	if thing is Mesh:
		node = instance(thing, opts.get("tint", Color.WHITE), opts.get("casts_shadow", true))
	else:
		node = thing as GeometryInstance3D
		if opts.has("tint"):
			base_color(node, opts["tint"])
		elif not node.get_instance_shader_parameter(&"base_color") is Color:
			base_color(node, Color.WHITE)
		if opts.has("casts_shadow"):
			node.cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if opts["casts_shadow"]
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)
	if texture == null:
		node.material_override = ToonMaterial.shared()
		return node
	node.material_override = ToonMaterial.textured(
		texture,
		opts.get("tiled", false),
		opts.get("cutout", false),
	)
	var unit := RenderConfig.unit
	node.set_instance_shader_parameter(
		&"uv_rect",
		Vector4(
			rect.position.x * unit,
			rect.position.y * unit,
			rect.size.x * unit,
			rect.size.y * unit,
		),
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
## `x`, `z` smallest, its top toward `-z`); facing sideways the texture stands upright and reads
## left to right seen from outside, on any of a wall's four facings.
static func surface_frame(at: Vector3, normal := Vector3.UP, spin := 0.0) -> Transform3D:
	var up := normal.normalized()
	# The texture's top (local -z) runs up a wall, so a texture reads upright and left to right
	# from outside; on a floor or ceiling, which has no up, it runs toward -z.
	var rise := Vector3.UP - up * up.dot(Vector3.UP)
	var back := Vector3.BACK if rise.length_squared() < 0.0001 else -rise.normalized()
	var turned := Basis(up.cross(back), up, back).rotated(up, spin)
	return Transform3D(turned, at)


## A decal: a flat quad of `size` px laid on a surface at `frame` (`surface_frame`), showing
## `texture` (its alpha cuts the quad: a crack, a stain, a stencil; null is a plain patch) times
## `tint`. It floats `MeshKitConfig.decal_lift` px off the surface so it never fights it, and
## `layer * MeshKitConfig.decal_layer_step` more (`layer` a float: decals of one surface that
## overlap take layers apart, the one drawn later the higher, so none shares a depth); lit as the
## toon material lights, casting no shadow.
static func decal(size: Vector2, frame: Transform3D, texture: Texture2D = null,
		tint := Color.WHITE, layer := 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _quad(size)
	node.material_override = ToonMaterial.decal(texture)
	node.set_instance_shader_parameter(&"base_color", tint)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.basis = frame.basis
	var lift := MeshKitConfig.decal_lift + layer * MeshKitConfig.decal_layer_step
	node.position = (frame.origin + frame.basis.y * lift) * RenderConfig.unit
	return node


## A drop shadow: a flat round patch `radius` px across its half, `lift` px over the floor at the
## node's own origin (so it follows what it is a child of), `strength` dark (an alpha: the floor
## shows through; `ToonMaterial.shade`). Not lit and not cast, so it is as short as it is drawn,
## whatever the lights are; for a thing that moves, `moving` makes the player's view hide it with
## the thing.
static func shade(radius: float, strength: float, lift := 1.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _quad(Vector2(radius, radius) * 2.0)
	node.material_override = ToonMaterial.shade()
	node.set_instance_shader_parameter(&"strength", strength)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = Vector3(0.0, lift * RenderConfig.unit, 0.0)
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


## A batch of `count` copies of `mesh` in one draw (a `MultiMeshInstance3D` in the shared toon
## material, tinted `tint`, casting no shadow unless `casts_shadow`): for many small short-lived
## things (casings, sparks, debris) where a node each is too dear. None shows until `batch_show`;
## `batch_place` puts one by index (a pool: a spawn takes the next index, a retired one is
## overwritten), `batch_show` says how many, from the first, are drawn. With `colored` each part
## has a colour of its own (`batch_color`), times the batch's `tint` and the mesh's own colours.
static func batch(mesh: Mesh, count: int, tint := Color.WHITE,
		casts_shadow := false, colored := false) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = colored
	multi.mesh = mesh
	multi.instance_count = count
	multi.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	node.material_override = ToonMaterial.shared()
	node.set_instance_shader_parameter(&"base_color", tint)
	node.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if casts_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	return node


## Part `index` of `batch` placed at `at` (2D `x`, height, 2D `y`, px) turned `yaw` radians about up
## (as `place`).
static func batch_place(node: MultiMeshInstance3D, index: int, at: Vector3, yaw := 0.0) -> void:
	node.multimesh.set_instance_transform(index, part_frame(at, yaw))


## Part `index` of a `colored` batch tinted `color` (the art's sRGB colour, as a face's is).
static func batch_color(node: MultiMeshInstance3D, index: int, color: Color) -> void:
	node.multimesh.set_instance_color(index, color.srgb_to_linear())


## The frame (3D units, in the frame of its parent) of a part at `at` (px) turned `yaw` about up:
## what `place` gives a node and `batch_place` a part of a batch.
static func part_frame(at: Vector3, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), at * RenderConfig.unit)


## The first `shown` parts of `batch` are drawn (at most all it holds).
static func batch_show(node: MultiMeshInstance3D, shown: int) -> void:
	node.multimesh.visible_instance_count = clampi(shown, 0, node.multimesh.instance_count)


## `node` tinted `color`: the instance's base colour, times the mesh's own colours (white leaves
## them; black shows only a glow, `glow`). Any toon node or decal.
static func base_color(node: GeometryInstance3D, color: Color) -> void:
	node.set_instance_shader_parameter(&"base_color", color)


## `node` shown `amount` of the way (1 whole, 0 gone): a dither of the pixels the picture's own
## size, so a wall between the camera and the player thins out instead of blending. Any toon node
## or decal; 1 costs a branch the shader never takes.
static func fade(node: GeometryInstance3D, amount: float) -> void:
	node.set_instance_shader_parameter(&"fade", clampf(amount, 0.0, 1.0))


## `node` glowing `color` (times `strength`) whatever the light: a lamp's shade, a screen, a muzzle
## flash; black or a strength of 0 is no glow. Dimmed by the vision mask like the rest.
static func glow(node: GeometryInstance3D, color: Color, strength := 1.0) -> void:
	node.set_instance_shader_parameter(&"emissive", Color(color.r, color.g, color.b, strength))


## `node` (a part of a character) outlined by its silhouette only: the pixel post draws no crease
## on it, so a body's faceted limbs, a pixel or two wide, keep their colours. Any toon node.
static func figure(node: GeometryInstance3D, on := true) -> void:
	node.set_instance_shader_parameter(&"figure", 1.0 if on else 0.0)


## `node` and every mesh under it (a character's parts, a thing's lids) marked as a thing that
## moves (`on`) or one that stays: the player's view draws a moving thing only inside the cone it
## sees now and a still one wherever it was ever seen (`ToonMask`). Any toon node or decal; a
## batch marks all its parts at once.
static func moving(node: Node, on := true) -> void:
	node.set_meta(&"moving", on)
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).set_instance_shader_parameter(
			&"moving", 1.0 if on else 0.0
		)
	var joined := _on_joined.bind(node)
	if on and not node.child_entered_tree.is_connected(joined):
		node.child_entered_tree.connect(joined)
	for child in node.get_children():
		moving(child, on)


## A part added under a marked node (a dent patch, a new outfit piece) takes the mark of its parent.
static func _on_joined(child: Node, parent: Node) -> void:
	if is_instance_valid(parent) and parent.get_meta(&"moving", false):
		moving(child, true)
