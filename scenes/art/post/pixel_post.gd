class_name PixelPost
extends RefCounted
## Art domain, the pixel post (`pixel_post_config.gd`; #193 rule 6): the outline pass of the 3D
## picture, a full-screen quad that is a child of the view's `Camera3D` and reads that viewport's
## colour, depth and normals. `attach` builds it, `refresh` pushes the holder's values (the widths
## are in picture pixels: a picture rendered `oversample` times larger takes them that much wider
## so an outline stays as thick on the picture it is averaged down to).

const OUTLINE := preload("res://scenes/art/post/outline.gdshader")
## The name of the quad under the camera.
const NODE := "PixelPostOutline"


## Add the outline quad under `camera` and return it, its material set from the holder.
static func attach(camera: Camera3D, oversample := 1) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var node := MeshInstance3D.new()
	node.name = NODE
	node.mesh = quad
	node.extra_cull_margin = 16_384.0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = OUTLINE
	node.material_override = material
	camera.add_child(node)
	refresh(node, oversample)
	return node


## Push the holder's outline colour, widths and steps into `node`'s material.
static func refresh(node: MeshInstance3D, oversample := 1) -> void:
	var material := node.material_override as ShaderMaterial
	var scale := float(maxi(oversample, 1))
	material.set_shader_parameter(&"outline_color", PixelPostConfig.outline_color)
	material.set_shader_parameter(&"silhouette_px", PixelPostConfig.silhouette_px * scale)
	material.set_shader_parameter(&"crease_px", PixelPostConfig.crease_px * scale)
	material.set_shader_parameter(&"depth_step", PixelPostConfig.depth_step)
	material.set_shader_parameter(&"normal_step", PixelPostConfig.normal_step)
	material.set_shader_parameter(&"crease_gap", PixelPostConfig.crease_gap)
	node.visible = PixelPostConfig.silhouette_px > 0.0 or PixelPostConfig.crease_px > 0.0
