extends GameTest
## V11 (`docs/player-vision.md`): a character whose drawn reach (a 60 px disc round it) lies wholly
## outside the cone and bubble is not repainted while it stays there; its pose, aim, hands,
## footsteps and ragdoll keep running (gameplay reads those, never the drawing). The frame any of
## its reach enters the cone it is repainted before it is drawn. A dead body at rest keeps its last
## drawing (it is remembered). With the view lifted, or none, everything is repainted as today.
##
## In an arena the viewer (a puppet, `PlayerView.watch`ed by the test) stands facing east and a
## walker walks to and fro behind its left shoulder, outside the cone. The walker's repaint count
## (`Visuals.redraws`, the count of times its standing body was drawn) is read frame by frame:
##   - with no view yet it repaints nearly every frame (the premise: it is on screen and moving);
##   - with the view, flat while the walker is wholly outside;
##   - walking into the cone, it repaints on the frame after the first frame its disc reaches the
##     cone (the repaint of a frame is counted at the next physics frame, as `offscreen_body_is_not_
##     drawn` counts);
##   - a body that died in the cone and settled keeps its drawing, node shown and remembered, once
##     the viewer turns away;
##   - a second walker outside repaints again once the viewer dies and the view is lifted.
## And in two worlds built from one declaration, one viewed and one not, a walker out of view that
## a shooter out of view shoots is hit the same way (the same hits, at the same places, for the same
## damage): the pose and aim a hit is read off keep running unseen.
##
## It reads (tests/_vision/vision_probe.gd) the `PlayerView`: `sees(point)`.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const EYE_AT := Vector2(700, 350)
## The walker's lane, behind the viewer's left shoulder; it walks along it between these.
const LANE_Y := 190.0
const LANE_WEST := 580.0
const LANE_EAST := 860.0
## How far east along the lane the walker is still wholly outside the cone.
const LANE_HIDDEN_EAST := 700.0
## The walker's drawn reach (V11), px. A disc of 50 is surely reached, one of 70 surely not.
const REACH := 60.0
const SURELY_IN := 50.0
const SURELY_OUT := 70.0
const RING := 16
const WINDOW := 40
## The second walker's lane, below the viewer.
const OTHER_AT := Vector2(580, 480)
## The third, which dies outside the cone and bleeds out there.
const FALLEN_AT := Vector2(650, 500)
## Twin worlds: the viewer, the walker and the shooter, away from the session's arena.
const TWIN_EYE := Vector2(3700, 350)
const TWIN_WALKER := Vector2(3580, 210)
const TWIN_SHOOTER := Vector2(3600, 520)
## The test camera frames the session's world; a twin world is framed by a camera of its own.
const TWIN_ZOOM := 0.4


func describe() -> Dictionary:
	return {
		"name": "A character wholly out of the cone is not repainted",
		"description": "A walker outside the cone stops repainting and its pose runs on (a hit "
			+ "lands as without the view); walking in it repaints the frame after its reach "
			+ "enters; a settled body keeps its drawing; with the view lifted it repaints.",
		"tags": ["vision", "draw", "scripted"],
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	s.actor(&"eye", &"puppet", EYE_AT, { "start_slot": 1 })
	s.actor(&"walker", &"puppet", Vector2(LANE_WEST, LANE_Y), { "start_slot": 1 })
	s.actor(&"other", &"puppet", OTHER_AT, { "start_slot": 1 })
	s.actor(&"fallen", &"puppet", FALLEN_AT, { "start_slot": 1 })
	s.camera_follow([&"eye"])


func run(t: TestContext) -> void:
	var walker := t.puppet(&"walker")
	var eye := t.actor(&"eye")
	# The premise, before any view: a walker on screen repaints nearly every frame.
	await t.seconds(0.5)
	walker.walk_to(Vector2(LANE_EAST, LANE_Y))
	await t.frames(3)
	var free := await _repaints(t, &"walker", WINDOW)
	t.require(
		free >= WINDOW * 0.8,
		"premise: with no view the walker repaints nearly every frame (%d in %d)" % [free, WINDOW],
	)
	walker.walk_to(Vector2(LANE_WEST, LANE_Y))
	await t.until(
		func() -> bool: return t.actor(&"walker").global_position.x < LANE_WEST + 20.0,
		20.0,
	)

	# The view of the viewer, facing east.
	var view := PlayerView.watch(t.world, eye)
	if not t.require(view != null, "the view is built"):
		return
	if not t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the viewer faces east"):
		return
	await t.frames(3)
	await _outside(t, view)
	await _walking_in(t, view)
	await _settled_body(t, view)
	await _unseen_pool(t, view)
	await _lifted(t, view)
	await _hit_the_same(t)


## The walker, out of the cone, walks to and fro: its repaints stay flat.
func _outside(t: TestContext, view: PlayerView) -> void:
	var walker := t.puppet(&"walker")
	var other := t.puppet(&"other")
	var wide := Vector2(LANE_HIDDEN_EAST, LANE_Y)
	t.require(
		not _reaches(view, t.actor(&"walker").global_position, SURELY_OUT),
		"premise: the walker starts wholly outside the cone",
	)
	walker.walk_to(wide)
	other.walk_to(OTHER_AT + Vector2(120, 20))
	await t.frames(3)
	var walker_paints := await _repaints(t, &"walker", WINDOW)
	var other_paints := await _repaints(t, &"other", WINDOW)
	t.require(
		not _reaches(view, t.actor(&"walker").global_position, SURELY_OUT),
		"premise: the walker is still wholly outside the cone",
	)
	t.check(walker_paints == 0, "the walker outside the cone is not repainted (%d)" % walker_paints)
	t.check(other_paints == 0, "the other outside the cone is not repainted (%d)" % other_paints)
	var moved: float = t.actor(&"walker").global_position.distance_to(Vector2(LANE_WEST, LANE_Y))
	t.check(moved > 100.0, "premise: it walked on meanwhile, unseen (%.0f px)" % moved)


## The walker walks east along its lane into the cone: flat until its disc reaches the cone, and
## repainted the frame after the first frame it does.
func _walking_in(t: TestContext, view: PlayerView) -> void:
	var walker := t.puppet(&"walker")
	var body: Node2D = t.actor(&"walker")
	walker.walk_to(Vector2(LANE_EAST, LANE_Y))
	var pending := true  # a catch-up repaint is owed once the disc reaches the cone
	var reached_at := -1
	var last := _redraws(t, &"walker")
	var last_state := ""
	for frame in 600:
		await t.frames(1)
		var now := _redraws(t, &"walker")
		var at := body.global_position
		# What this resume shows came of the previous frame's state.
		if last_state == "out":
			t.check(now == last, "frame %d: wholly outside, not repainted" % frame)
		elif last_state == "in":
			if pending:
				t.check(
					now > last,
					"frame %d: its reach entered the cone and it was repainted" % frame,
				)
			pending = false
			if reached_at < 0:
				reached_at = frame
		elif now > last:
			pending = false  # the disc grazed the edge and was repainted on the way: fine
		last = now
		last_state = _state(view, at)
		if reached_at >= 0 and frame > reached_at + 5:
			break
	t.check(reached_at >= 0, "the walker's reach entered the cone and it was repainted for it")
	t.check(_state(view, body.global_position) == "in", "premise: it ended up in the cone")


## A body that died in the cone and settled is remembered where it lies (`WORLD`) and keeps its
## drawing, its node shown, when the viewer turns away.
func _settled_body(t: TestContext, view: PlayerView) -> void:
	var body: Node2D = t.actor(&"walker")
	var visuals: Node2D = body.get_node("Visuals")
	body.take_damage(1000.0)
	var settled := await t.until(
		func() -> bool: return body.visibility_layer == Probe.WORLD, 15.0
	)
	if not t.require(settled, "premise: the dead body settles (at rest, remembered)"):
		return
	await t.frames(5)
	var drawn: Array = visuals.drawn_art()
	t.require(not drawn.is_empty(), "premise: the body at rest has a drawing")
	var eye := t.actor(&"eye")
	t.require(await Probe.place(t, eye, EYE_AT, Vector2.LEFT), "the viewer turns west")
	await t.frames(30)
	t.require(
		not _reaches(view, body.global_position, SURELY_OUT),
		"premise: the dead body is now wholly outside the cone",
	)
	t.check(visuals.visible, "the dead body outside the cone is still shown")
	t.check(visuals.drawn_art() == drawn, "the dead body outside the cone keeps its drawing")
	t.check(body.visibility_layer == Probe.WORLD, "the dead body outside is still remembered")


## A body that dies wholly outside the cone bleeds a pool there: the pool keeps flowing, unseen, and
## is not redrawn while it stays wholly outside; the viewer turns to it and it is drawn at once.
func _unseen_pool(t: TestContext, view: PlayerView) -> void:
	var eye := t.actor(&"eye")
	t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the viewer faces east")
	var fallen: Node2D = t.actor(&"fallen")
	fallen.take_damage(1000.0)
	var pool := await _pool_near(t, fallen.global_position)
	if not t.require(pool != null, "premise: the body bleeds a pool"):
		return
	var visuals: Node2D = pool.get_node("BloodPoolVisuals")
	# A node is drawn once as it enters the tree: the count to hold flat is what it is after that.
	await t.frames(3)
	var drawn: int = visuals.redraws
	var cells: int = pool.flow.cells.size()
	await t.seconds(2.0)
	var extent: Rect2i = pool.flow.extent()
	var reach := Vector2(extent.size).length() * BloodPoolConfig.flow_cell_size * 0.5
	t.require(
		not _reaches(view, pool.global_position, reach + 20.0),
		"premise: the pool lies wholly outside the cone (%s, reaching %.0f px)" % [extent, reach],
	)
	t.check(
		pool.flow.cells.size() > cells,
		"the pool flows on unseen (%d cells, was %d)" % [pool.flow.cells.size(), cells],
	)
	t.check(
		visuals.redraws == drawn,
		"the pool outside the cone is not redrawn (%d, was %d)" % [visuals.redraws, drawn],
	)
	t.require(await Probe.place(t, eye, EYE_AT, Vector2.DOWN), "the viewer turns to face south")
	await t.frames(3)
	t.check(
		visuals.redraws > 0,
		"the pool is drawn once the cone reaches it (%d)" % visuals.redraws,
	)


## The pool bleeding out nearest `at`, once it exists (null when none appears).
func _pool_near(t: TestContext, at: Vector2) -> Node2D:
	await t.until(func() -> bool: return _pools_near(t, at).size() > 0, 15.0)
	var found := _pools_near(t, at)
	return found[0] if not found.is_empty() else null


## The blood pools within 80 px of `at`.
func _pools_near(t: TestContext, at: Vector2) -> Array:
	return t.world.find_children("BloodPool*", "Node2D", true, false).filter(
		func(n: Node) -> bool: return "flow" in n and n.global_position.distance_to(at) < 80.0
	)


## The viewer dies, the view is lifted: the other walker, wholly outside until then, repaints as
## before any view.
func _lifted(t: TestContext, view: PlayerView) -> void:
	var other := t.puppet(&"other")
	t.require(await Probe.place(t, t.actor(&"eye"), EYE_AT, Vector2.RIGHT), "the viewer faces east")
	other.walk_to(OTHER_AT)
	await t.frames(3)
	var before := await _repaints(t, &"other", WINDOW)
	t.require(
		before == 0,
		"premise: the other is not repainted while the view stands (%d)" % before,
	)
	t.actor(&"eye").take_damage(1000.0)
	await t.frames(2)
	t.require(not is_instance_valid(view) or view.is_queued_for_deletion(), "premise: view lifted")
	other.walk_to(OTHER_AT + Vector2(120, 20))
	await t.frames(3)
	var after := await _repaints(t, &"other", WINDOW)
	t.check(
		after >= WINDOW * 0.8,
		"with the view lifted the other repaints as before (%d in %d)" % [after, WINDOW],
	)


## The same scripted shots at a walker out of the cone, one world with the view and one without:
## the same hits, at the same places, for the same damage.
func _hit_the_same(t: TestContext) -> void:
	var plain := await _twin(t, false)
	var viewed := await _twin(t, true)
	t.require(
		viewed["hidden_paints"] == 0,
		"premise: the viewed walker was not repainted meanwhile (%d)" % viewed["hidden_paints"],
	)
	t.require(
		plain["hidden_paints"] > 0,
		"premise: the unviewed walker was repainted meanwhile (%d)" % plain["hidden_paints"],
	)
	for i in mini(plain["shots"].size(), viewed["shots"].size()):
		var a: Dictionary = plain["shots"][i]
		var b: Dictionary = viewed["shots"][i]
		t.require(not a["hit"].is_empty(), "premise: shot %d hits the unviewed walker" % i)
		t.check(not b["hit"].is_empty(), "shot %d hits the viewed walker too" % i)
		if a["hit"].is_empty() or b["hit"].is_empty():
			continue
		t.check(
			(a["hit"]["position"] as Vector2).distance_to(b["hit"]["position"]) < 3.0,
			"shot %d lands at the same place (%s unviewed, %s viewed)"
			% [i, a["hit"]["position"], b["hit"]["position"]],
		)
		t.check(
			absf(a["lost"] - b["lost"]) < 0.01,
			"shot %d costs the same health (%.2f, %.2f)" % [i, a["lost"], b["lost"]],
		)
		t.check(
			absf(angle_difference(a["torso"], b["torso"])) < 0.02,
			"shot %d finds the shoulders turned the same way (%.3f, %.3f)"
			% [i, a["torso"], b["torso"]],
		)


## One world, the view of the viewer or none: the walker walks out of the cone and is shot at; what
## the hits were and how often the walker was repainted meanwhile.
func _twin(t: TestContext, viewed: bool) -> Dictionary:
	var s := TestSetup.new()
	s.arena(Rect2(3000, 0, 1400, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.switch(&"vision.enabled", viewed)
	s.switch(&"projectile.flyover", false)
	# A round strikes at one height, so the zone it strikes is the same every run.
	OutfitProbe.pin_height(s)
	s.actor(&"eye", &"puppet", TWIN_EYE, { "start_slot": 1 })
	s.actor(&"walker", &"puppet", TWIN_WALKER, { "start_slot": 1, "max_health": 100_000.0 })
	s.actor(&"shooter", &"puppet", TWIN_SHOOTER, { "start_slot": 3 })
	s.view(&"eye")
	var world: Node2D = await Probe.build_world(t, s)
	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE * TWIN_ZOOM
	camera.position = TWIN_EYE
	world.add_child(camera)
	camera.make_current()
	var out := { "shots": [], "hidden_paints": 0 }
	var walker: Node2D = world.actors[&"walker"]
	var visuals: Node2D = walker.get_node("Visuals")
	await t.seconds(0.5)
	# The viewer looks east, away from both.
	_puppet_of(world, &"eye").aim_at(TWIN_EYE + Vector2(300, 0))
	await t.seconds(0.5)
	var views := Probe.views_under(world)
	if not t.require(
		views.size() == (1 if viewed else 0),
		"premise: the %s world has %d view(s)" % ["viewed" if viewed else "unviewed", views.size()],
	):
		await Probe.drop_world(t, world)
		return out
	var before: int = visuals.redraws
	_puppet_of(world, &"walker").walk_to(TWIN_WALKER + Vector2(40, 30))
	await t.seconds(2.0)
	_puppet_of(world, &"shooter").aim_at(walker)
	await t.seconds(0.5)
	out["hidden_paints"] = visuals.redraws - before
	if viewed:
		t.check(
			not _reaches(views[0], walker.global_position, SURELY_OUT),
			"premise: the walker is wholly outside the viewer's cone",
		)
	out["shots"] = await _shoot(t, world)
	await Probe.drop_world(t, world)
	return out


## Three shots from the shooter at the walker. For each: the `hit` that struck the walker (its place
## and damage, empty when none did), the health it cost and the angle its shoulders were turned to
## (which sets the side a round strikes).
func _shoot(t: TestContext, world: Node2D) -> Array:
	var walker: Node2D = world.actors[&"walker"]
	var shots: Array = []
	var struck: Array = []
	var listener := func(topic: StringName, data: Dictionary) -> void:
		if topic == &"hit" and data.get("victim") == walker:
			struck.append({ "position": data["position"], "damage": data["damage"] })
	EventBus.posted.connect(listener)
	for _shot in 3:
		var health: float = walker.health
		struck.clear()
		_puppet_of(world, &"shooter").shoot()
		await t.seconds(0.6)
		shots.append(
			{
				"hit": struck[0] if not struck.is_empty() else {},
				"lost": health - walker.health,
				"torso": walker.anatomy.pose.torso_angle,
			},
		)
	EventBus.posted.disconnect(listener)
	return shots


func _puppet_of(world: Node2D, id: StringName) -> Node:
	return TestContext.controller_of(world.actors[id], &"walk_to")


## Whether any part of a disc of `radius` round `at` is seen: the centre or one of `RING` points.
func _reaches(view: PlayerView, at: Vector2, radius: float) -> bool:
	if view.sees(at):
		return true
	for i in RING:
		if view.sees(at + Vector2.from_angle(float(i) / RING * TAU) * radius):
			return true
	return false


## "in" when the disc surely inside reach touches the cone, "out" when the surely-outside one does
## not, else "between".
func _state(view: PlayerView, at: Vector2) -> String:
	if _reaches(view, at, SURELY_IN):
		return "in"
	return "between" if _reaches(view, at, SURELY_OUT) else "out"


func _redraws(t: TestContext, id: StringName) -> int:
	return t.actor(id).get_node("Visuals").redraws


## Repaints of `id` over the next `frames` frames.
func _repaints(t: TestContext, id: StringName, frames: int) -> int:
	var before := _redraws(t, id)
	await t.frames(frames)
	return _redraws(t, id) - before
