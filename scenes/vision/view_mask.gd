extends Node
## Vision domain (private): the cone as a screen picture, for the composite to cut by. A
## screen-sized SubViewport with the camera's canvas transform that draws the view's polygon: once
## for a hard edge, or for a feathered one as the average of a disc of shifted copies, `TAPS` of
## them each adding `TAP_VALUE` (8/255 x 32 = 1), so the value falls from 1 inside to 0 a feather
## width outside.

## Copies of the polygon a feathered mask averages, and the value each adds.
const TAPS := 32
const TAP_VALUE := 8.0 / 255.0
const GOLDEN_ANGLE := 2.399963
const Fan := preload("res://scenes/vision/view_fan.gd")

## The mask (null before `build`) and the painter that draws into it.
var mask: SubViewport
var painter: Node2D
var _feather := 0.0
var _shifts := PackedVector2Array()


## Build the mask, as big as `main`'s screen, feathered `feather` px (screen; 0 = a hard edge).
## The node must be in the tree.
func build(main: Viewport, feather: float) -> void:
	_feather = maxf(feather, 0.0)
	mask = SubViewport.new()
	mask.name = "Mask"
	mask.size = Vector2i(main.get_visible_rect().size).max(Vector2i.ONE)
	mask.transparent_bg = true
	mask.disable_3d = true
	mask.gui_disable_input = true
	mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(mask)
	painter = Fan.new()
	painter.name = "MaskPainter"
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	painter.material = add
	painter.color = Color(TAP_VALUE, TAP_VALUE, TAP_VALUE) if _feather > 0.0 else Color.WHITE
	mask.add_child(painter)
	_shifts.resize(TAPS if _feather > 0.0 else 1)
	_shifts.fill(Vector2.ZERO)
	painter.offsets = _shifts


## Follow the camera: the mask takes its canvas transform `cam` and its screen size.
func follow(cam: Transform2D, size: Vector2i) -> void:
	if size != mask.size:
		mask.size = size
	mask.canvas_transform = cam
	if _feather <= 0.0:
		return
	var zoom := cam.get_scale().x
	for i in TAPS:
		var radius := _feather * sqrt((float(i) + 0.5) / float(TAPS)) / zoom
		_shifts[i] = Vector2.from_angle(float(i) * GOLDEN_ANGLE) * radius


## Draw the `cone` and the `bubble` round `eye`.
func paint(cone: PackedVector2Array, bubble: PackedVector2Array, eye: Vector2) -> void:
	painter.refresh(cone, bubble, eye, Transform2D.IDENTITY, Vector2.ONE)
