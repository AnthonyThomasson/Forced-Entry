extends GameTest
## V3 and V4 (`docs/player-vision.md`), in the 3D render: what the viewer has seen is kept, and the
## shaders read two masks. The seen mask (the memory) is a picture over the bounds of the floors,
## `seen_scale` texels per world px, which gains and is never cleared and starts empty; each
## published cone's polygon is drawn into it; the live mask is a square window of the world about
## the camera (`live_side` texels) holding the cone, its edge feathered over `VisionConfig.feather`
## screen px by a disc of shifted copies.
##
## A headless run has no pixels, so it reads what the parts are told: sizes, transforms, clear
## modes, the polygons the painters hold, the blur's reach, and what `ToonMask` was given
## (tests/_vision/vision_probe.gd). The look (grey, dim, black unseen) and the cut are pixels, read
## in `vision/vision_mask_3d_windowed`.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const EYE_AT := Vector2(200, 300)
## The floors the layout makes are its rooms: the living room and the kitchen, 1200 x 500.
const BOUNDS := Rect2(0, 0, 1200, 500)
## The spec's seen mask (V12): texels per world px, and the live window's side in texels.
const SEEN_SCALE := 0.5
const LIVE_SIDE := 768
## The spec's feather (V4), screen px.
const FEATHER := 16.0
const EPS := 0.001


func describe() -> Dictionary:
	return {
		"name": "The memory follows the cone",
		"description": "The seen mask covers the floors' bounds at its scale, is never cleared and "
			+ "starts empty; each cone published is drawn into it and the live window; the live "
			+ "mask's edge is blurred within the feather.",
		"tags": ["vision", "render", "3d"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Probe.building(s, EYE_AT)
	s.switch(&"vision.enabled", true)


func run(t: TestContext) -> void:
	var eye := t.actor(&"eye")
	# Built here, so the first frames of the memory are watched.
	var view := PlayerView.watch(t.world, eye)
	if not t.require(view != null and view.ground != null, "the 3D view is built"):
		return
	var ground := view.ground
	t.check(ground.counts["seen"] == 0, "the memory starts empty: nothing is drawn into it yet")
	t.check(not ToonMask.mask_active(), "and no mask is on before the first cone")
	if not t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the eye faces east"):
		return
	await t.frames(3)
	t.check(ToonMask.mask_active(), "the masks are on once the first cone is drawn")
	_memory(t, ground)
	_painters(t, view)
	_live(t, ground)
	# Never cleared: turn and walk, and the memory gains the cone where the viewer now stands.
	var drawn: int = ground.counts["seen"]
	await Probe.place(t, eye, Vector2(900, 250), Vector2.LEFT)
	await t.frames(3)
	t.check(ground.counts["seen"] > drawn, "the memory draws the cone where the viewer now stands")
	var points: PackedVector2Array = ground.seen_painter.points()
	var missed := 0
	for corner in view.cone():
		if points.find(corner) < 0:
			missed += 1
	t.check(
		view.cone().size() >= 3 and missed == 0,
		"its polygon is that cone (%d missing)" % missed,
	)
	t.check(
		ground.seen.render_target_clear_mode == SubViewport.CLEAR_MODE_ONCE,
		"the memory is still cleared once and never again",
	)


func _memory(t: TestContext, ground: Node) -> void:
	var seen: SubViewport = ground.seen
	t.check(is_equal_approx(ground.seen_texels, SEEN_SCALE), "the memory is at the spec's scale")
	t.check(
		seen.size == Vector2i((BOUNDS.size * SEEN_SCALE).ceil()),
		"the memory covers the floors' bounds: %s texels" % [seen.size],
	)
	t.check(
		seen.render_target_clear_mode == SubViewport.CLEAR_MODE_ONCE,
		"the memory is emptied once, not every frame",
	)
	var at: Vector2 = seen.canvas_transform * BOUNDS.position
	var far: Vector2 = seen.canvas_transform * BOUNDS.end
	t.check(at.is_zero_approx(), "the bounds' corner is the memory's first texel (%s)" % [at])
	t.check(
		far.is_equal_approx(Vector2(seen.size)),
		"the bounds' far corner is its last (%s)" % [far],
	)
	t.check(
		ToonMask.memory_world_rect().is_equal_approx(BOUNDS),
		"the shaders are told it covers the bounds (%s)" % [ToonMask.memory_world_rect()],
	)


## Both painters draw the cone's polygon and the bubble's, in vertex colour (no 2D capture).
func _painters(t: TestContext, view: PlayerView) -> void:
	var cone := view.cone()
	if not t.require(cone.size() >= 3, "the view has a cone"):
		return
	for named: String in ["seen_painter", "live_painter"]:
		var painter: Node2D = view.ground.get(named)
		var points: PackedVector2Array = painter.points()
		var missed := 0
		for corner in cone:
			if points.find(corner) < 0:
				missed += 1
		t.check(missed == 0, "%s holds the cone's polygon (%d of %d missing)" % [
			named, missed, cone.size(),
		])
		for corner in view.bubble():
			if points.find(corner) < 0:
				missed += 1
		t.check(missed == 0, "%s holds the bubble's too (%d missing)" % [named, missed])
		t.check(painter.get_parent() is SubViewport, "%s draws into a viewport" % named)


## The live window: its texels, where it lies, and an edge blurred within the feather.
func _live(t: TestContext, ground: Node) -> void:
	var live: SubViewport = ground.live
	t.check(
		live.size == Vector2i(LIVE_SIDE, LIVE_SIDE),
		"the live window is %d texels square" % LIVE_SIDE,
	)
	t.check(ground.window.size.x > 0.0, "and lies over a part of the world (%s)" % ground.window)
	t.check(
		ToonMask.mask_world_rect().is_equal_approx(ground.window),
		"the shaders are told where it lies",
	)
	var reach: float = FEATHER / Pointer.screen_transform(t.world).get_scale().x
	var widest := 0.0
	for shift: Vector2 in ground.live_painter.offsets:
		widest = maxf(widest, shift.length())
	t.check(
		ground.live_painter.offsets.size() > 8,
		"the edge is drawn blurred (%d copies)" % ground.live_painter.offsets.size(),
	)
	t.check(
		widest <= reach + EPS,
		"the blur stays within the feather (%.2f of %.2f)" % [widest, reach],
	)
	t.check(widest >= reach * 0.9, "the blur reaches the feather (%.2f of %.2f)" % [widest, reach])
