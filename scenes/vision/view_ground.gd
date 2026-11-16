extends Node
## Vision domain (private): the player's view in the 3D render (#193 phase 3). The 3D scene is lit
## and drawn as it is; what the player sees of it is two textures the toon shaders read through
## global uniforms (`ToonMask`, `toon_common.gdshaderinc`), by a surface's own ground position:
##   live   a window of the world about the camera, `VisionGroundConfig.live_side` texels square,
##          holding the cone the player sees now (1) with its edge feathered as the 2D mask's is
##          (a disc of shifted copies, added up); it is laid again when the camera drifts out of
##          it or the zoom changes, and redrawn only then and when a cone is published;
##   seen   the whole floor's bounds at a few px a texel, never cleared, to which each published
##          cone's polygon adds 1: where the player has ever seen. It is the world as it stands
##          that is drawn dimmed there, not a picture of it.
## A viewport is drawn once on request (`UPDATE_ONCE`), never every frame, and the 2D world's
## capture is not made at all in this mode. The masks are switched on `settle_frames` after the
## first cone is painted.

const Mask := preload("res://scenes/vision/view_mask.gd")
const Fan := preload("res://scenes/vision/view_fan.gd")

## The live window's viewport, the memory's, and the painters that draw the cone into them.
var live: SubViewport
var seen: SubViewport
var live_painter: Node2D
var seen_painter: Node2D
## The world rect (px) the live window covers, and the memory covers.
var window := Rect2()
var seen_bounds := Rect2()
## Memory texels per world px (less than asked when the floors are too wide).
var seen_texels := 1.0
## How many times each was asked to draw (`live`, `seen`) and the window was laid (`anchors`): what
## a test reads to show that nothing draws while nothing changed.
var counts := { "live": 0, "seen": 0, "anchors": 0 }
## Whether the masks are switched on (`ToonMask.set_mask` called and not cleared).
var on := false
var _half := 0.0
var _centre := Vector2.ZERO
var _zoom := 0.0
var _shifts := PackedVector2Array()
var _settle := -1
## The cone last drawn: a published cone the same as it is no news (the view's backstop republishes
## an unchanged one every few frames) and draws nothing.
var _drawn: Array[PackedVector2Array] = []


## Build the two viewports, the memory over `floor_bounds`. The node must be in the tree.
func build(floor_bounds: Rect2) -> void:
	seen_bounds = floor_bounds
	var longest := maxf(maxf(floor_bounds.size.x, floor_bounds.size.y), 1.0)
	seen_texels = minf(VisionGroundConfig.seen_scale, VisionGroundConfig.seen_max_side / longest)
	var texels := Vector2i((floor_bounds.size * seen_texels).ceil())
	seen = _viewport("Seen", texels.clamp(Vector2i.ONE, Vector2i.ONE * 16_384))
	seen.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	add_child(seen)
	seen.canvas_transform = Transform2D(
		Vector2(seen_texels, 0.0), Vector2(0.0, seen_texels), -floor_bounds.position * seen_texels
	)
	seen_painter = Fan.new()
	seen_painter.name = "SeenPainter"
	seen.add_child(seen_painter)
	var side := maxi(VisionGroundConfig.live_side, 8)
	live = _viewport("Live", Vector2i(side, side))
	add_child(live)
	live_painter = Fan.new()
	live_painter.name = "LivePainter"
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	live_painter.material = add
	var feathered := VisionConfig.feather > 0.0
	live_painter.color = (
		Color(Mask.TAP_VALUE, Mask.TAP_VALUE, Mask.TAP_VALUE) if feathered else Color.WHITE
	)
	_shifts.resize(Mask.TAPS if feathered else 1)
	_shifts.fill(Vector2.ZERO)
	live_painter.offsets = _shifts
	live.add_child(live_painter)


## Keep the live window about what `node`'s viewport shows (the camera's view, the world seen
## through `Pointer`), and count the masks on once the first cone has settled. Cheap when nothing
## drifted: a circle round the screen and one compare.
func follow(node: Node) -> void:
	if live == null:
		return
	var to_screen := Pointer.screen_transform(node)
	var zoom := to_screen.x.length()
	if zoom <= 0.0001:
		return
	var back := to_screen.affine_inverse()
	var size := node.get_viewport().get_visible_rect().size
	var centre := back * (size * 0.5)
	var radius := 0.0
	for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]:
		radius = maxf(radius, ((back * corner) - centre).length())
	var want := maxf(radius, 1.0) * VisionGroundConfig.window_margin
	if (
		_half <= 0.0
		or (centre - _centre).length() + radius > _half
		or _half > want * VisionGroundConfig.window_slack
	):
		_anchor(centre, want)
	if absf(zoom - _zoom) > 0.0005:
		_zoom = zoom
		_feather_to(zoom)
		_ask(live)
		counts["live"] += 1
	_tick_settle()


## A cone was published: the polygons the player sees now, drawn into both masks.
func publish(cone: PackedVector2Array, bubble: PackedVector2Array, eye: Vector2) -> void:
	if live == null:
		return
	if not on and _settle < 0:
		_settle = VisionGroundConfig.settle_frames
	if _drawn.size() == 3 and _drawn[0] == cone and _drawn[1] == bubble and _drawn[2][0] == eye:
		return
	_drawn = [cone.duplicate(), bubble.duplicate(), PackedVector2Array([eye])]
	live_painter.refresh(cone, bubble, eye, Transform2D.IDENTITY, Vector2.ONE)
	seen_painter.refresh(cone, bubble, eye, Transform2D.IDENTITY, Vector2.ONE)
	_ask(live)
	_ask(seen)
	counts["live"] += 1
	counts["seen"] += 1


## Show the whole world again: the masks are cleared (the viewer died, the view was disabled).
func suspend() -> void:
	if on:
		ToonMask.clear()
	on = false
	_settle = -1


## The window is laid on `centre`, `half` px each way, and the live viewport follows it.
func _anchor(centre: Vector2, half: float) -> void:
	_centre = centre
	_half = half
	window = Rect2(centre - Vector2(half, half), Vector2(half, half) * 2.0)
	var texels := float(live.size.x) / (half * 2.0)
	live.canvas_transform = Transform2D(
		Vector2(texels, 0.0), Vector2(0.0, texels), -window.position * texels
	)
	_feather_to(_zoom)
	if on:
		ToonMask.move_mask(window)
	_ask(live)
	counts["live"] += 1
	counts["anchors"] += 1


## The feather's taps: a disc `VisionConfig.feather` screen px wide at `zoom`, in world px.
func _feather_to(zoom: float) -> void:
	if VisionConfig.feather <= 0.0 or zoom <= 0.0:
		return
	for i in Mask.TAPS:
		var radius := VisionConfig.feather * sqrt((float(i) + 0.5) / float(Mask.TAPS)) / zoom
		_shifts[i] = Vector2.from_angle(float(i) * Mask.GOLDEN_ANGLE) * radius
	live_painter.queue_redraw()


## Count down to switching the masks on.
func _tick_settle() -> void:
	if _settle < 0:
		return
	_settle -= 1
	if _settle > 0 or on:
		return
	_settle = -1
	on = true
	ToonMask.set_mask(live.get_texture(), window, VisionGroundConfig.unseen_brightness)
	ToonMask.set_memory(
		seen.get_texture(), seen_bounds, VisionConfig.grey, VisionConfig.brightness,
		VisionConfig.tint,
	)


## Draw `viewport` once, next frame.
func _ask(viewport: SubViewport) -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## A transparent viewport of `px` that is drawn on request, takes no input and draws no 3D.
func _viewport(node_name: String, px: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = node_name
	vp.size = px
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	return vp
