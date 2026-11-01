extends Node2D
## Vision domain (private): the layer drawn over the world, at `DrawLayers.VISION` in the world's
## own canvas (so the overlays above it, at `DrawLayers.OVERLAY`, keep their colours). It is a
## polygon over the whole screen whose shader (`view_composite.gdshader`, unshaded) cuts the live
## world out where the mask says inside, and draws the memory in the look of `VisionConfig`
## elsewhere. Its visibility bit is `ViewLayers.OVERLAY`, which the capture leaves out, so the
## capture never photographs the composite.

const SHADER := preload("res://scenes/vision/view_composite.gdshader")

## The shader the polygon is drawn with, and the screen's four corners in the world.
var _material := ShaderMaterial.new()
var _screen := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])


func _init() -> void:
	name = "Composite"
	top_level = true
	z_index = DrawLayers.VISION
	z_as_relative = false
	visibility_layer = ViewLayers.OVERLAY
	_material.shader = SHADER
	material = _material


func _draw() -> void:
	draw_colored_polygon(_screen, Color.WHITE)


## Read the `memory` and the `mask` texture; the memory covers `bounds` at `texels` per world
## px and is `size` texels; the look and the feather come from `VisionConfig`.
func build(
	memory: Texture2D, mask: Texture2D, bounds: Rect2, texels: float, size: Vector2i
) -> void:
	_material.set_shader_parameter("memory", memory)
	_material.set_shader_parameter("cone_mask", mask)
	_material.set_shader_parameter("memory_origin", bounds.position)
	_material.set_shader_parameter("memory_scale", texels)
	_material.set_shader_parameter("memory_size", Vector2(size))
	_material.set_shader_parameter("grey", VisionConfig.grey)
	_material.set_shader_parameter("contrast", VisionConfig.contrast)
	_material.set_shader_parameter("pivot", VisionConfig.pivot)
	_material.set_shader_parameter("brightness", VisionConfig.brightness)
	_material.set_shader_parameter("tint", VisionConfig.tint)
	_material.set_shader_parameter("soft", 1.0 if VisionConfig.feather > 0.0 else 0.0)


## Follow the camera: cover the screen of `size` px seen through the canvas transform `cam`, and
## give the shader the matrix that maps a screen point back to the world.
func follow(cam: Transform2D, size: Vector2i) -> void:
	var inverse := cam.affine_inverse()
	var corners := Vector2(size)
	_screen[0] = inverse * Vector2.ZERO
	_screen[1] = inverse * Vector2(corners.x, 0.0)
	_screen[2] = inverse * corners
	_screen[3] = inverse * Vector2(0.0, corners.y)
	_material.set_shader_parameter("view_size", corners)
	_material.set_shader_parameter("inv_x", inverse.x)
	_material.set_shader_parameter("inv_y", inverse.y)
	_material.set_shader_parameter("inv_o", inverse.origin)
	queue_redraw()
