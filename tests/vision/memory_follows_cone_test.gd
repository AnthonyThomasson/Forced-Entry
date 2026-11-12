extends GameTest
## V3 and V4 (`docs/player-vision.md`): what the viewer has seen is kept, and drawn where it sees
## no more. The memory is a picture of the world over the bounds of its floors, `memory_scale`
## texels per world px, which is never cleared and starts empty; each frame the cone's polygon
## paints it from the capture, a copy of the world as drawn without what moves (`ViewLayers.MOVING`
## and `OVERLAY` left out of its cull mask); the mask is the cone as a screen picture, feathered
## over `VisionConfig.feather` px; and the composite, drawn over the world at `DrawLayers.VISION`
## and out of the capture, carries the look of `VisionConfig`.
##
## A headless run has no pixels, so it reads what the parts are told: sizes, transforms, cull masks,
## the polygon the painters hold and the texture they draw it with, the composite's rung and
## parameters (tests/_vision/vision_probe.gd). The pixels are checked in a window by hand.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const EYE_AT := Vector2(200, 300)
## The floors the layout makes are its rooms: the living room and the kitchen, 1200 x 500.
const BOUNDS := Rect2(0, 0, 1200, 500)
## The spec's feather (V4), screen px.
const FEATHER := 16.0
const EPS := 0.001


func describe() -> Dictionary:
	return {
		"name": "The memory follows the cone",
		"description": "The memory covers the floors' bounds, is never cleared and starts empty; "
			+ "its painter paints the cone from the capture, which leaves out what moves; the "
			+ "composite is drawn at the view's rung with the look and feather of the config.",
		"tags": ["vision"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Probe.building(s, EYE_AT)
	s.switch(&"vision.enabled", true)


func run(t: TestContext) -> void:
	var eye := t.actor(&"eye")
	# Built here, so the first frames of the memory are watched.
	var view := PlayerView.watch(t.world, eye)
	if not t.require(view != null, "the view is built"):
		return
	if not t.require(view.memory() != null and view.capture() != null, "the memory and capture"):
		return
	t.check(view.wiping(), "the memory starts being emptied")
	if not t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the eye faces east"):
		return
	await t.frames(3)
	t.check(not view.wiping(), "the memory is emptied once, not every frame")
	_memory(t, view)
	_capture(t, view)
	_painter(t, view)
	_mask(t, view)
	_composite(t, view)
	# Never cleared: turn and walk, the memory is not emptied again, and the painter follows the
	# cone to where the viewer is now.
	await Probe.place(t, eye, Vector2(900, 250), Vector2.LEFT)
	await t.frames(3)
	var points: PackedVector2Array = view.painter().points()
	var missed := 0
	for corner in view.cone():
		if points.find(corner) < 0:
			missed += 1
	t.check(
		view.cone().size() >= 3 and missed == 0,
		"the painter paints the cone where the viewer now stands (%d missing)" % missed,
	)
	t.check(not view.wiping(), "the memory is not emptied again after the viewer moves")
	t.check(
		view.memory().render_target_clear_mode == SubViewport.CLEAR_MODE_NEVER,
		"the memory is still never cleared",
	)


func _memory(t: TestContext, view: PlayerView) -> void:
	var memory := view.memory()
	var scale := VisionConfig.memory_scale
	t.check(is_equal_approx(view.memory_scale(), scale), "the memory is at the configured scale")
	t.check(
		memory.size == Vector2i(BOUNDS.size * scale),
		"the memory covers the floors' bounds: %s px" % [memory.size],
	)
	t.check(
		memory.render_target_clear_mode == SubViewport.CLEAR_MODE_NEVER,
		"the memory is never cleared",
	)
	var at: Vector2 = memory.canvas_transform * BOUNDS.position
	var far: Vector2 = memory.canvas_transform * BOUNDS.end
	t.check(at.is_zero_approx(), "the bounds' corner is the memory's first texel (%s)" % [at])
	t.check(
		far.is_equal_approx(Vector2(memory.size)),
		"the bounds' far corner is its last (%s)" % [far],
	)


func _capture(t: TestContext, view: PlayerView) -> void:
	var capture := view.capture()
	var main := t.world.get_viewport()
	t.check(capture.world_2d == main.world_2d, "the capture shares the world")
	t.check(capture.size == Vector2i(main.get_visible_rect().size), "the capture is screen sized")
	t.check(
		capture.canvas_transform.is_equal_approx(main.get_canvas_transform()),
		"the capture sees what the camera sees",
	)
	t.check(capture.canvas_cull_mask & ViewLayers.WORLD != 0, "the capture draws the world")
	t.check(capture.canvas_cull_mask & ViewLayers.MOVING == 0, "the capture leaves out what moves")
	t.check(capture.canvas_cull_mask & ViewLayers.OVERLAY == 0, "the capture leaves out overlays")


func _painter(t: TestContext, view: PlayerView) -> void:
	var painter := view.painter()
	var cone := view.cone()
	if not t.require(painter != null and cone.size() >= 3, "the memory has a painter and a cone"):
		return
	t.check(painter.get_parent() == view.memory(), "the painter draws into the memory")
	t.check(painter.texture == view.capture().get_texture(), "the painter paints the capture")
	# The capture is the screen; the cone reaches past it, and a place not on it was not seen.
	var paint := painter.material as ShaderMaterial
	t.check(
		paint != null and paint.shader.code.contains("discard"),
		"what lies off the capture is not painted into the memory",
	)
	var points: PackedVector2Array = painter.points()
	var uvs: PackedVector2Array = painter.uvs()
	t.check(uvs.size() == points.size(), "every point of the polygon has a texture coordinate")
	var size: Vector2 = t.world.get_viewport().get_visible_rect().size
	var missed := 0
	var off := 0
	for corner in cone:
		var k := points.find(corner)
		if k < 0:
			missed += 1
		elif not uvs[k].is_equal_approx(Pointer.screen_of(t.world, corner) / size):
			off += 1
	t.check(missed == 0, "the painter holds the cone's polygon (%d of %d missing)" % [
		missed, cone.size(),
	])
	t.check(off == 0, "each corner is textured where it is on the capture (%d off)" % off)


func _mask(t: TestContext, view: PlayerView) -> void:
	var mask := view.mask()
	var painter := view.mask_painter()
	if not t.require(mask != null and painter != null, "the view has a mask"):
		return
	var main := t.world.get_viewport()
	t.check(mask.size == Vector2i(main.get_visible_rect().size), "the mask is screen sized")
	t.check(painter.get_parent() == mask, "the mask painter draws into the mask")
	t.check(painter.points().size() >= 3, "the mask draws the cone's polygon")
	var reach: float = FEATHER / Pointer.screen_transform(t.world).get_scale().x
	var shifts: PackedVector2Array = painter.offsets
	var widest := 0.0
	for shift in shifts:
		widest = maxf(widest, shift.length())
	t.check(shifts.size() > 8, "the edge is drawn blurred (%d copies)" % shifts.size())
	t.check(widest <= reach + EPS, "the blur stays within the feather (%.2f of %.2f)" % [
		widest, reach,
	])
	t.check(widest >= reach * 0.9, "the blur reaches the feather (%.2f of %.2f)" % [widest, reach])


func _composite(t: TestContext, view: PlayerView) -> void:
	var composite := view.composite()
	if not t.require(composite != null, "the view has a composite"):
		return
	t.check(composite.z_index == DrawLayers.VISION, "the composite is drawn at the view's rung")
	t.check(not composite.z_as_relative, "the rung is absolute")
	t.check(
		composite.visibility_layer == ViewLayers.OVERLAY,
		"the composite is out of the capture's cull mask",
	)
	var material := composite.material as ShaderMaterial
	if not t.require(material != null, "the composite has a shader"):
		return
	t.check(material.shader.code.contains("unshaded"), "the composite is unshaded")
	var look := {
		"grey": VisionConfig.grey,
		"contrast": VisionConfig.contrast,
		"pivot": VisionConfig.pivot,
		"brightness": VisionConfig.brightness,
		"tint": VisionConfig.tint,
	}
	for key in look:
		t.check(
			material.get_shader_parameter(key) == look[key],
			"the composite carries the config's %s" % key,
		)
	t.check(material.get_shader_parameter("soft") == 1.0, "the composite blends the feather")
	t.check(
		material.get_shader_parameter("memory") == view.memory().get_texture(),
		"the composite reads the memory",
	)
	t.check(
		material.get_shader_parameter("cone_mask") == view.mask().get_texture(),
		"the composite reads the mask",
	)
	t.check(
		material.get_shader_parameter("memory_origin") == BOUNDS.position,
		"the memory starts at the bounds' corner",
	)
	t.check(
		is_equal_approx(material.get_shader_parameter("memory_scale"), view.memory_scale()),
		"the composite knows the memory's scale",
	)
	t.check(
		material.get_shader_parameter("memory_size") == Vector2(view.memory().size),
		"the composite knows the memory's size",
	)
