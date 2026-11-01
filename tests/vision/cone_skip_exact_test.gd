extends GameTest
## V1 cost (`docs/player-vision.md`): the view rebuilds its cone only when its output can change,
## and a frame it skips holds exactly the cone a fresh rebuild would give. A checker
## (`tests/_vision/cone_checker.gd`) runs after the view in every physics frame, builds a fresh cone
## from the viewer's place by the reference algorithm and holds the view's polygon to it, vertex for
## vertex. The viewer stands in two rooms joined by doorways, a wooden door, a glass-panel door and
## a hollow one in them, and the test changes what the cone can see in every way the spec lists:
##   - the viewer still, then turning;
##   - a wardrobe and the walls dented again and again (their colliders cut into more shapes);
##   - a wardrobe shoved across the room, and one freed, and one added;
##   - a door swung wide and shut, a glass-panel door's panes shattered, a door knocked down;
##   - in a world of its own, a character that blocks the viewer's sight standing and not crouched
##     changing its posture, and dying.
## And the reach, in a world of its own that counts rebuilds only: a solid moved every frame far
## outside the viewer's reach forces no rebuild, one moved within reach forces one each frame, and
## one that moves from outside into reach is a rebuild in that frame.
## And the rebuilds themselves: a still viewer rebuilds far less often than every frame, and the
## view never goes more than `REBUILD_EVERY` frames without one (the backstop).
##
## It reads (tests/_vision/vision_probe.gd) the `PlayerView`: `cone()`, `bubble()`, `rebuilds()`.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Checker := preload("res://tests/_vision/cone_checker.gd")
const Mover := preload("res://tests/_vision/physics_mover.gd")
## The spec's backstop (V1): the most physics frames between two rebuilds.
const REBUILD_EVERY := 10
const EYE_AT := Vector2(250, 250)
const WARDROBE_AT := Vector2(450, 130)
const SHOVED_AT := Vector2(450, 390)
const ADDED_AT := Vector2(520, 250)
## The doorways in the wall the rooms share (x 700), by `Probe.doorway`.
const GLASS_Y := 110.0
const WOOD_Y := 250.0
const DOWN_Y := 390.0
## The second world: a character at `STANDER_AT` between the viewer and a far wall, whose sight
## looks over only what is lower than `Probe.LOOK_OVER_LOW` (a standing body, 60, blocks it; a
## crouched one, 35, does not).
const OTHER := Vector2(4000, 0)
const OTHER_EYE := Vector2(4100, 300)
const STANDER_AT := Vector2(4300, 300)
const HITS_PER_VOLLEY := 6
## The two solids of `_shape_added_and_moved`: a slab that gains a shape, and a mover that is moved.
const SLAB_AT := Vector2(360, 250)
const MOVER_AT := Vector2(360, 120)
const MOVER_TO := Vector2(360, 200)
const SOLID_SIZE := Vector2(14, 60)
## The reach, in a third world: the viewer faces east; a solid at `FAR_AT` is 3750 px from it (the
## reach is 2520), one at `NEAR_AT` is in its cone. Each is moved for `REACH_FRAMES` frames,
## `REACH_STEP` px a frame, and the far one then arrives at `FAR_ARRIVES`, in the cone.
const REACH_ARENA := Rect2(8000, 0, 600, 600)
const REACH_EYE := Vector2(8100, 300)
const FAR_AT := Vector2(11_850, 300)
const NEAR_AT := Vector2(8400, 250)
const FAR_ARRIVES := Vector2(8350, 350)
## A shape scaled by this many reaches 1500 px from its body: from 3750 px off it is 270 px into
## range.
const WIDE_SCALE := 30.0
const REACH_FRAMES := 60
const REACH_STEP := 1.0
## The frames the dents must change the viewer's cone in, or they proved nothing.
const MIN_DENT_CHANGES := 3

var _t: TestContext


func describe() -> Dictionary:
	return {
		"name": "A skipped cone frame holds the cone a fresh rebuild would give",
		"description": "Through a still and a turning viewer, dents, a shove, a piece freed and "
			+ "added, a door's swing, shattered panes and a fall, a posture change and a death, "
			+ "every frame's polygon equals a fresh rebuild's; a still viewer rebuilds far less "
			+ "often, and never goes more than ten frames without one.",
		"tags": ["vision", "scripted"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.layout(Probe.ROOMS, [
		Probe.doorway(GLASS_Y, "glass", "panes", "glass"),
		Probe.doorway(WOOD_Y, "solid", "plank", "wood"),
		Probe.doorway(DOWN_Y, "hollow", "flush", "hollow"),
	])
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.switch(&"vision.enabled", true)
	s.object(&"wardrobe", "wardrobe", WARDROBE_AT, { "rotated": true })
	s.object(&"shoved", "wardrobe", SHOVED_AT, { "rotated": true })
	s.object(&"freed", "bookshelf", Vector2(300, 60))
	s.actor(&"eye", &"puppet", EYE_AT)
	s.view(&"eye")


func run(t: TestContext) -> void:
	_t = t
	var view := Probe.view(t)
	if not t.require(view != null, "the world has a view"):
		return
	var eye := t.actor(&"eye")
	if not t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the viewer faces east"):
		return
	var checker := Checker.new(view, eye)
	t.world.add_child(checker)
	await _still(t, checker)
	await _turning(t, checker, eye)
	await _dents(t, checker)
	await _shove(t, checker)
	await _freed_and_added(t, checker)
	await _shape_added_and_moved(t, checker)
	await _doors(t, checker)
	_check_whole(t, checker, "the first world")
	checker.queue_free()
	await _posture_and_death(t)
	await _reach(t)


## The viewer stands still: it rebuilds far less often than every frame.
func _still(t: TestContext, checker: Checker) -> void:
	var frames := 60
	var before := checker.view.rebuilds()
	await t.frames(frames)
	var rebuilds := checker.view.rebuilds() - before
	t.check(
		rebuilds <= int(ceilf(float(frames) / REBUILD_EVERY)) + 2,
		"a still viewer rebuilds about every %d frames (%d in %d)"
		% [REBUILD_EVERY, rebuilds, frames],
	)
	t.check(rebuilds >= 1, "a still viewer still rebuilds now and then (%d)" % rebuilds)


## The viewer sweeps its facing across the room: each frame's cone is new, and exact.
func _turning(t: TestContext, checker: Checker, eye: Node2D) -> void:
	var changed := checker.changed
	var before := checker.view.rebuilds()
	for i in 90:
		var angle := lerpf(-0.8, 0.8, float(i) / 89.0)
		t.puppet(&"eye").aim_at(EYE_AT + Vector2.from_angle(angle) * 100.0)
		await t.frames(1)
	t.check(
		checker.changed - changed >= 60,
		"premise: a turning viewer's cone changes (%d frames of 90)" % (checker.changed - changed),
	)
	t.check(
		checker.view.rebuilds() - before >= 60,
		"a turning viewer rebuilds as it turns (%d in 90)" % (checker.view.rebuilds() - before),
	)
	t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the viewer faces east again")


## What the viewer sees is hit again and again, at the places its cone ends on; each hit dents, and
## the collider is cut anew in a frame or two with no move of the body.
func _dents(t: TestContext, checker: Checker) -> void:
	# The pieces are held still, so that a dent re-cuts a collider with no move of its body (a piece
	# hit while free is shoved, and a cone that rebuilds as it moves hides a missed re-cut).
	var pieces: Array[RigidBody2D] = []
	for node in t.world.find_children("*", "RigidBody2D", true, false):
		pieces.append(node)
		node.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		node.freeze = true
	var targets: Array[Node2D] = []
	targets.append_array(pieces)
	for node in t.world.find_children("*", "StaticBody2D", true, false):
		if node.has_method("wall_segments"):
			targets.append(node)
	var shapes := Probe.collision_shapes(targets)
	var changed := checker.changed
	var rng := RandomNumberGenerator.new()
	rng.seed = Probe.HIT_SEED
	for volley in Probe.VOLLEYS:
		for _k in HITS_PER_VOLLEY:
			_strike_seen(checker, rng)
		await t.frames(5)
	await t.frames(5)
	for piece in pieces:
		piece.freeze = false
	t.check(
		Probe.collision_shapes(targets) > shapes,
		"premise: the dents cut the colliders into more shapes (%d, was %d)"
		% [Probe.collision_shapes(targets), shapes],
	)
	t.check(
		checker.changed - changed >= MIN_DENT_CHANGES,
		"premise: the dents change what the viewer sees (%d frames)" % (checker.changed - changed),
	)


## A wardrobe is shoved across the room and comes to rest.
func _shove(t: TestContext, checker: Checker) -> void:
	var piece: RigidBody2D = t.object(&"shoved")
	var at := piece.global_position
	piece.apply_impulse(Vector2(900.0, -400.0) * piece.get_mass() * 0.4)
	await t.frames(120)
	t.check(
		piece.global_position.distance_to(at) > 20.0,
		"premise: the shoved wardrobe moved (%.0f px)" % piece.global_position.distance_to(at),
	)
	var before := checker.view.rebuilds()
	await t.frames(40)
	t.check(
		checker.view.rebuilds() - before <= 4 + 2,
		"the cone is not rebuilt each frame once the shoved wardrobe rests (%d in 40)"
		% (checker.view.rebuilds() - before),
	)


## A bookshelf is freed and a wardrobe added in the cone.
func _freed_and_added(t: TestContext, checker: Checker) -> void:
	var changed := checker.changed
	t.object(&"freed").queue_free()
	await t.frames(15)
	var piece := ObjectFactory.spawn(WorldGen.object_definition("wardrobe"), ADDED_AT, t.world)
	await t.frames(15)
	t.check(is_instance_valid(piece), "premise: the added wardrobe is there")
	t.check(
		checker.changed > changed,
		"premise: adding the wardrobe changes what the viewer sees",
	)
	piece.queue_free()
	await t.frames(15)


## A script gives a solid a shape, and another is moved once from its own physics frame ahead of
## the view (as a door swinging is): a new shape and a move that no signal tells of.
func _shape_added_and_moved(t: TestContext, checker: Checker) -> void:
	var slab := StaticBody2D.new()
	slab.collision_layer = PhysicsLayers.SOLID
	slab.position = SLAB_AT
	t.world.add_child(slab)
	var mover := AnimatableBody2D.new()
	mover.collision_layer = PhysicsLayers.SOLID
	mover.add_child(_solid_shape())
	mover.position = MOVER_AT
	t.world.add_child(mover)
	await t.frames(15)
	var changed := checker.changed
	slab.add_child(_solid_shape())
	await t.frames(15)
	t.check(checker.changed > changed, "premise: the slab's new shape changes what the viewer sees")
	changed = checker.changed
	var hand := Mover.new()
	hand.body = mover
	t.world.add_child(hand)
	hand.arm(MOVER_TO)
	await t.frames(15)
	t.check(checker.changed > changed, "premise: the moved solid changes what the viewer sees")
	slab.queue_free()
	mover.queue_free()
	hand.queue_free()
	await t.frames(15)


## A third world: a solid moved every frame outside the viewer's reach forces no rebuild; one
## within reach does; the far one moved into reach is a rebuild in the frame it arrives.
func _reach(t: TestContext) -> void:
	var s := TestSetup.new()
	s.arena(REACH_ARENA)
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	s.actor(&"eye", &"puppet", REACH_EYE)
	s.view(&"eye")
	var world: Node2D = await Probe.build_world(t, s)
	var view := Probe.views_under(world)[0]
	TestContext.controller_of(world.actors[&"eye"], &"aim_at").aim_at(REACH_EYE + Vector2(100, 0))
	var far := _solid_at(world, FAR_AT)
	var near := _solid_at(world, NEAR_AT)
	await t.frames(30)
	var before := view.rebuilds()
	await _creep(t, far, FAR_AT)
	var rebuilds := view.rebuilds() - before
	t.check(
		far.position.distance_to(FAR_AT) >= REACH_STEP * (REACH_FRAMES - 1),
		"premise: the far solid moved (%.0f px)" % far.position.distance_to(FAR_AT),
	)
	t.check(
		(far.position - REACH_EYE).length() > view.viewer().sight()["view_distance"],
		"premise: the far solid stayed outside the reach",
	)
	t.check(
		rebuilds <= int(ceilf(float(REACH_FRAMES) / REBUILD_EVERY)) + 2,
		"a solid moved every frame far outside the reach forces no rebuild (%d in %d)"
		% [rebuilds, REACH_FRAMES],
	)
	before = view.rebuilds()
	await _creep(t, near, NEAR_AT)
	rebuilds = view.rebuilds() - before
	t.check(
		rebuilds >= REACH_FRAMES - 2,
		"a solid moved every frame within the reach forces a rebuild each frame (%d in %d)"
		% [rebuilds, REACH_FRAMES],
	)
	await _wide(t, world, view)
	await t.frames(15)
	before = view.rebuilds()
	far.position = FAR_ARRIVES
	await t.frames(1)
	t.check(
		view.rebuilds() > before,
		"a solid that moves from outside the reach into it is a rebuild in that frame",
	)
	await Probe.drop_world(t, world)


## A solid whose body is 3750 px off but whose shape is stretched into range counts as within it.
func _wide(t: TestContext, world: Node, view: PlayerView) -> void:
	var wide := _solid_at(world, FAR_AT)
	wide.get_child(0).scale = Vector2(WIDE_SCALE, 1.0)
	await t.frames(15)
	var before := view.rebuilds()
	await _creep(t, wide, FAR_AT)
	var rebuilds := view.rebuilds() - before
	t.check(
		rebuilds >= REACH_FRAMES - 2,
		"a far solid with a stretched shape in range forces a rebuild each frame (%d in %d)"
		% [rebuilds, REACH_FRAMES],
	)
	wide.queue_free()


## Move `body` from `from` along y, `REACH_STEP` px a frame, for `REACH_FRAMES` frames.
func _creep(t: TestContext, body: Node2D, from: Vector2) -> void:
	for i in REACH_FRAMES:
		body.position = from + Vector2(0.0, REACH_STEP * i)
		await t.frames(1)


## A solid with a shape, standing at `at` in the world.
func _solid_at(world: Node, at: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.SOLID
	body.position = at
	body.add_child(_solid_shape())
	world.add_child(body)
	return body


## A solid's shape: `SOLID_SIZE` round its body.
func _solid_shape() -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SOLID_SIZE
	shape.shape = rect
	return shape


## A wooden door swings wide and shut; a glass-panel door's panes shatter; a hollow door is knocked
## down.
func _doors(t: TestContext, checker: Checker) -> void:
	var wood: Node2D = t.object(&"wood")
	var changed := checker.changed
	wood.open_fully(null)
	await t.frames(60)
	t.check(wood.angle() > 45.0, "premise: the door swung open (%.0f degrees)" % wood.angle())
	t.check(checker.changed > changed, "premise: the swing changed what the viewer sees")
	wood.toggle(null)
	await t.frames(60)
	var glass: Node2D = t.object(&"glass")
	glass.take_hit(Probe.hit(glass.global_position, Vector2.LEFT, 8.0))
	await t.frames(10)
	t.check(glass.look.broken, "premise: the glass door's panes shattered")
	var hollow: Node2D = t.object(&"hollow")
	hollow.take_damage(10_000.0)
	await t.frames(20)
	t.check(hollow.is_down(), "premise: the hollow door was knocked down")


## A second world: a character in the viewer's line of sight, whose sight looks over only what is
## lower than a standing body. It crouches and stands again, and dies.
func _posture_and_death(t: TestContext) -> void:
	var s := TestSetup.new()
	s.arena(Rect2(OTHER.x, OTHER.y, 600, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	s.set_static(CharacterVisionConfig, &"see_over_coverage", Probe.LOOK_OVER_LOW)
	s.actor(&"eye", &"puppet", OTHER_EYE)
	s.actor(&"stander", &"puppet", STANDER_AT)
	s.view(&"eye")
	var world: Node2D = await Probe.build_world(t, s)
	var eye: Node2D = world.actors[&"eye"]
	var stander: Node2D = world.actors[&"stander"]
	var view := Probe.views_under(world)[0]
	TestContext.controller_of(eye, &"aim_at").aim_at(OTHER_EYE + Vector2(100, 0))
	await t.frames(5)
	var checker := Checker.new(view, eye)
	world.add_child(checker)
	await t.frames(20)
	var changed := checker.changed
	for posture in [&"crouch", &"stand", &"crouch"]:
		# A change of posture waits out its cooldown: ask until the body holds it.
		if not t.require(
			await t.until(func(): return stander.movement.set_posture(posture), 3.0),
			"the character takes the posture %s" % posture,
		):
			break
		await t.frames(20)
	t.check(
		checker.changed - changed >= 2,
		"premise: the posture changes what the viewer sees (%d changes)"
		% (checker.changed - changed),
	)
	changed = checker.changed
	stander.take_damage(10_000.0)
	await t.frames(90)
	t.check(stander.is_dead, "premise: the character died")
	_check_whole(t, checker, "the posture world")
	checker.queue_free()
	await Probe.drop_world(t, world)


## The checker's whole run: every frame's polygon was the fresh cone's, and no wait was longer than
## the backstop.
func _check_whole(t: TestContext, checker: Checker, where: String) -> void:
	t.check(checker.frames >= 100, "premise: %s: %d frames compared" % [where, checker.frames])
	t.check(
		checker.wrong() == 0,
		"%s: %d frames held a cone other than a fresh rebuild's: %s"
		% [where, checker.wrong(), checker.report()],
	)
	t.check(
		checker.longest_wait <= REBUILD_EVERY,
		"%s: the longest wait between rebuilds is %d frames (at most %d)"
		% [where, checker.longest_wait, REBUILD_EVERY],
	)


## One hit on whatever the viewer sees at a random place its cone ends on: the first solid on the
## line from its eye to there.
func _strike_seen(checker: Checker, rng: RandomNumberGenerator) -> void:
	var cone := checker.view.cone()
	if cone.size() < 2:
		return
	var eye := checker.viewer.global_position
	var end := cone[rng.randi_range(1, cone.size() - 1)]
	var query := PhysicsRayQueryParameters2D.create(eye, eye + (end - eye) * 1.001)
	query.collision_mask = PhysicsLayers.SOLID
	query.exclude = [checker.viewer.get_rid()]
	var found := checker.viewer.get_world_2d().direct_space_state.intersect_ray(query)
	if found.is_empty() or not found["collider"].has_method("take_hit"):
		return
	var damage := rng.randf_range(10.0, 40.0)
	found["collider"].take_hit(Probe.hit(found["position"], found["normal"], damage))
