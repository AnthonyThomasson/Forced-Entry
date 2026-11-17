extends GameTest
## The player's view in the 3D render (#193 vision-mask, `docs/player-vision.md` V12): the toon
## shaders read two masks, so the view draws them on request and not every frame. In a world with
## the 3D view and a viewer facing along a hall:
## - the masks are switched on once the first cone is drawn (`ToonMask.mask_active`), the memory
##   covering the floors' bounds, and the live window covers what the camera shows;
## - while the viewer stands still and the world holds still, nothing is drawn (the cone is
##   republished by the view's backstop every few frames, an unchanged one draws nothing);
## - a viewer that walks gets both masks drawn again (the cone is new);
## - a camera that moves out of the live window gets the window laid again about it;
## - the viewer's death lifts the view and the masks are cleared that frame;
## - the view holds only those two viewports, neither rendering every frame, and draws nothing over
##   the world itself (no capture of the world, no screen mask, no composite).
## Pixels are judged in `vision/vision_mask_3d_windowed`; here the masks' wiring and cost.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Ground := preload("res://scenes/vision/view_ground.gd")
const FLOOR := Rect2(0, 0, 1400, 700)
const EYE_AT := Vector2(150, 350)
## The viewer walks this far (px) east, and the camera is moved this far off.
const WALK := 300.0
const FAR := Vector2(6000.0, 350.0)
## A still stretch long enough to cross the view's backstop rebuilds (every 10 frames) several
## times.
const STILL_FRAMES := 60


func describe() -> Dictionary:
	return {
		"name": "The 3D view draws its two masks on request: still when nothing changes",
		"description": "A viewer in a 3D world: the masks switch on after the first cone; a still "
			+ "viewer draws nothing across the backstop's rebuilds; a walk draws both again; "
			+ "the camera leaving the window lays it again; the "
			+ "viewer's death clears the masks; no viewport renders every frame.",
		"tags": ["vision", "render", "3d"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()  # it builds its own rig and camera: the session shows none
	s.arena(FLOOR)
	s.switch(&"vision.enabled", true)
	s.switch(&"nav.rebake", false)
	s.actor(&"eye", &"puppet", EYE_AT)
	s.view(&"eye")


func run(t: TestContext) -> void:
	var view := Probe.view(t)
	if not t.require(view != null and view.ground != null, "premise: a 3D view was built"):
		return
	var ground: Ground = view.ground
	t.check(not ToonMask.mask_active(), "no mask is on before the first cone is drawn")
	if not t.require(
			await t.until(func() -> bool: return ToonMask.mask_active(), 2.0),
			"the masks are switched on once the first cone is drawn",
	):
		return
	t.check(
		ToonMask.memory_world_rect().encloses(FLOOR.grow(-1.0)),
		"the memory covers the floors' bounds (%s)" % ToonMask.memory_world_rect(),
	)
	_no_world_capture(t, view)
	_still_draws_nothing(t, ground, view)
	if not t.require(await _settled(t, ground), "premise: the camera settles on the viewer"):
		return
	await _still(t, ground)
	await _walk(t, ground, view)
	await _camera_leaves_the_window(t, ground)
	_death_clears(t)


## The view is the two masks and nothing that photographs the world: its only viewports are the
## live window and the memory, and neither renders every frame (they draw on request).
func _no_world_capture(t: TestContext, view: PlayerView) -> void:
	var viewports := view.find_children("*", "SubViewport", true, false)
	var names := viewports.map(func(v: Node) -> String: return String(v.name))
	names.sort()
	t.expect_eq(names, ["Live", "Seen"], "the view's viewports are the live window and the memory")
	var always := viewports.filter(
		func(v: SubViewport) -> bool:
			return v.render_target_update_mode == SubViewport.UPDATE_ALWAYS
	)
	t.expect_eq(always.size(), 0, "no viewport of the view renders every frame")
	t.expect_eq(
		view.find_children("*", "CanvasItem", true, false).filter(
			func(n: Node) -> bool: return n.get_parent() == view
		).size(),
		0,
		"and nothing is drawn over the world by the view itself",
	)


## The test camera eases onto the viewer at first and the window follows it: true once no mask has
## been drawn for a stretch.
func _settled(t: TestContext, ground: Ground) -> bool:
	for _try in 10:
		var drawn := ground.counts.duplicate()
		await t.frames(int(STILL_FRAMES * 0.5))
		if ground.counts == drawn:
			return true
	return false


## The view holds a cone drawn at least once, and the window and the memory were each drawn.
func _still_draws_nothing(t: TestContext, ground: Ground, view: PlayerView) -> void:
	t.check(ground.counts["live"] > 0 and ground.counts["seen"] > 0, "premise: both were drawn")
	t.check(view.cone().size() > 2, "premise: the view has a cone")


## A still viewer in a still world: no draw of either mask over many frames, though the view
## published at its backstop several times.
func _still(t: TestContext, ground: Ground) -> void:
	var drawn := ground.counts.duplicate()
	var published: int = Probe.view(t).rebuilds()
	await t.frames(STILL_FRAMES)
	t.check(Probe.view(t).rebuilds() > published, "premise: the view rebuilt meanwhile")
	t.expect_eq(ground.counts["live"], drawn["live"], "a still view draws the live mask no more")
	t.expect_eq(ground.counts["seen"], drawn["seen"], "nor the memory")


## A walk draws both again.
func _walk(t: TestContext, ground: Ground, view: PlayerView) -> void:
	var drawn := ground.counts.duplicate()
	var eye := t.puppet(&"eye")
	eye.walk(Vector2.RIGHT)
	var from: Vector2 = view.viewer().global_position
	if not t.require(
			await t.until(
				func() -> bool: return view.viewer().global_position.x > from.x + WALK, 6.0,
			),
			"premise: the viewer walks",
	):
		return
	eye.walk(Vector2.ZERO)
	t.check(ground.counts["live"] > drawn["live"], "a walk draws the live mask")
	t.check(ground.counts["seen"] > drawn["seen"], "and the memory")


## The camera moves off: the window is laid about where it now looks.
func _camera_leaves_the_window(t: TestContext, ground: Ground) -> void:
	var camera := Camera2D.new()
	camera.position = FAR
	t.world.add_child(camera)
	camera.make_current()
	var laid: int = ground.counts["anchors"]
	await t.frames(3)
	t.check(ground.counts["anchors"] > laid, "the window is laid again when the camera leaves it")
	t.check(ground.window.has_point(FAR), "about where it looks (%s)" % ground.window)
	camera.queue_free()


## The viewer's death lifts the view, and a lifted view leaves no mask on.
func _death_clears(t: TestContext) -> void:
	t.check(ToonMask.mask_active(), "premise: the masks are on")
	var viewer := Probe.view(t).viewer()
	viewer.queue_free()
	await t.frames(2)
	t.check(Probe.view(t) == null, "the view is lifted")
	t.check(not ToonMask.mask_active(), "and no mask is left on the world")
