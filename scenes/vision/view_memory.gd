extends Node
## Vision domain (private): what the viewer has seen. Two SubViewports side by side (a viewport
## nested in another makes the engine log an error):
##   capture  shares the main viewport's world, with its size and canvas transform, and leaves
##            `ViewLayers.MOVING` and `OVERLAY` out of its cull mask: the world as drawn without
##            what moves and without the overlays;
##   memory   a world-space picture over the bounds of the floors, `scale` texels per world px,
##            never cleared, which the cone's polygon paints each frame with the capture, so it
##            keeps the world as it was last seen and stays transparent where nothing was seen.
## The memory is never cleared by the engine, so it starts empty by a wipe: a rect over the whole
## memory, drawn under the painter for its first `WIPE_FRAMES` frames, that writes "nothing seen".

## Godot's limit on a texture's side, px.
const MAX_SIDE := 16_384
## Frames the wipe stays drawn, so the memory is empty whatever the engine started it with.
const WIPE_FRAMES := 2
const Fan := preload("res://scenes/vision/view_fan.gd")
const PAINT_SHADER := preload("res://scenes/vision/memory_paint.gdshader")
const WIPE_SHADER := preload("res://scenes/vision/memory_wipe.gdshader")

## The capture of the world as it stands, and the memory (null before `build`).
var capture: SubViewport
var memory: SubViewport
## The painter that paints the cone from the capture into the memory.
var painter: Node2D
## Memory texels per world px: the configured one, less when the bounds are too wide for a texture.
var scale := 1.0
## The world rect the memory covers (the floors' bounds), px.
var bounds := Rect2()
var _wipe: Node2D
var _wipe_frames := 0


## Build the capture and the memory for `bounds` at up to `want` texels per world px, sharing the
## world of `main`. The node must be in the tree.
func build(world_bounds: Rect2, want: float, main: Viewport) -> void:
	bounds = world_bounds
	var longest := maxf(maxf(bounds.size.x, bounds.size.y), 1.0)
	scale = minf(want, float(MAX_SIDE) / longest)
	var texels := (bounds.size * scale - Vector2.ONE * 0.001).ceil()
	memory = _viewport("Memory", Vector2i(texels).clamp(Vector2i.ONE, Vector2i.ONE * MAX_SIDE))
	memory.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	add_child(memory)
	memory.canvas_transform = Transform2D(
		Vector2(scale, 0.0), Vector2(0.0, scale), -bounds.position * scale
	)
	capture = _viewport("Capture", Vector2i(main.get_visible_rect().size).max(Vector2i.ONE))
	capture.world_2d = main.world_2d
	capture.canvas_cull_mask = 0xffffffff & ~(ViewLayers.MOVING | ViewLayers.OVERLAY)
	add_child(capture)
	painter = Fan.new()
	painter.name = "MemoryPainter"
	var paint_material := ShaderMaterial.new()
	paint_material.shader = PAINT_SHADER
	painter.material = paint_material
	painter.texture = capture.get_texture()
	painter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	memory.add_child(painter)
	_wipe = _wipe_node()
	memory.add_child(_wipe)
	_wipe_frames = WIPE_FRAMES


## Whether the memory is still being emptied.
func wiping() -> bool:
	return _wipe_frames > 0


## Follow the camera: the capture takes its canvas transform `cam` and its screen size.
func follow(cam: Transform2D, size: Vector2i) -> void:
	if size != capture.size:
		capture.size = size
	capture.canvas_transform = cam
	if _wipe_frames > 0:
		_wipe_frames -= 1
		_wipe.visible = _wipe_frames > 0


## Paint the `cone` and the `bubble` round `eye` into the memory from the capture, seen by the
## camera `cam` over the capture's `size`.
func paint(
	cone: PackedVector2Array,
	bubble: PackedVector2Array,
	eye: Vector2,
	cam: Transform2D,
) -> void:
	painter.refresh(cone, bubble, eye, cam, Vector2(capture.size))


## A rect over the whole memory, drawn under the painter while the wipe lasts, that writes "nothing
## seen" everywhere.
func _wipe_node() -> Node2D:
	var wipe := Node2D.new()
	wipe.name = "Wipe"
	wipe.z_index = -10
	var material := ShaderMaterial.new()
	material.shader = WIPE_SHADER
	wipe.material = material
	wipe.draw.connect(func() -> void: wipe.draw_rect(bounds, Color.WHITE))
	return wipe


## A transparent, always-updating SubViewport of `px` that takes no input and draws no 3D.
func _viewport(node_name: String, px: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = node_name
	vp.size = px
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return vp
