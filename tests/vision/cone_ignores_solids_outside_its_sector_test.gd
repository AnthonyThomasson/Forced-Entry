extends GameTest
## V1 cost (`docs/player-vision.md`): the cone is rebuilt for a blocker that moves, turns or changes
## where the cone's rays can pass: in the sector the viewer looks along or the bubble round it,
## each grown by the blocker's own extent. A solid moved every frame behind the viewer, in its
## reach but outside both, is in no ray: it forces no rebuild but the backstop's. One moved in the
## cone forces one each frame. Through both the cone is the reference cone's, every frame, vertex
## for vertex (`tests/_vision/cone_checker.gd`).

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Checker := preload("res://tests/_vision/cone_checker.gd")
## The spec's backstop (V1): the most physics frames between two rebuilds.
const REBUILD_EVERY := 10
const ARENA := Rect2(0, 0, 6000, 600)
const EYE_AT := Vector2(3000, 300)
## Behind the eye (west of it, the viewer faces east) and in its cone.
const BEHIND_AT := Vector2(2400, 300)
const AHEAD_AT := Vector2(3600, 250)
const SOLID_SIZE := Vector2(14, 60)
const FRAMES := 60
const STEP := 1.0


func describe() -> Dictionary:
	return {
		"name": "The view's cone is not rebuilt for a solid moving behind the viewer",
		"description": "A solid moved every frame 600 px behind the viewer forces no rebuild but "
			+ "the backstop's; one moved in the cone forces one a frame; the cone equals the "
			+ "reference cone's throughout.",
		"tags": ["vision", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA)
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	s.actor(&"eye", &"puppet", EYE_AT)
	s.view(&"eye")


func run(t: TestContext) -> void:
	var view := Probe.view(t)
	if not t.require(view != null, "the world has a view"):
		return
	var eye := t.actor(&"eye")
	if not t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the viewer faces east"):
		return
	var behind := _solid_at(t.world, BEHIND_AT)
	var ahead := _solid_at(t.world, AHEAD_AT)
	await t.frames(30)
	var checker := Checker.new(view, eye)
	t.world.add_child(checker)
	var before := view.rebuilds()
	await _creep(t, behind, BEHIND_AT)
	var rebuilds := view.rebuilds() - before
	t.check(
		behind.position.distance_to(BEHIND_AT) >= STEP * (FRAMES - 1)
		and (behind.position - EYE_AT).length() < view.viewer().sight()["view_distance"],
		"premise: the solid behind the viewer moved and stayed in the reach",
	)
	t.check(
		rebuilds <= int(ceilf(float(FRAMES) / REBUILD_EVERY)) + 2,
		"a solid moved each frame behind the viewer forces no rebuild but the backstop's (%d of %d)"
			% [rebuilds, FRAMES],
	)
	before = view.rebuilds()
	await _creep(t, ahead, AHEAD_AT)
	rebuilds = view.rebuilds() - before
	t.check(
		rebuilds >= FRAMES - 2,
		"a solid moved every frame in the cone forces a rebuild each (%d in %d)" % [
			rebuilds,
			FRAMES,
		],
	)
	t.check(checker.wrong() == 0, "the cone equals the reference cone's: %s" % checker.report())


## Move `body` a step further from `from` every frame, for `FRAMES` frames.
func _creep(t: TestContext, body: Node2D, from: Vector2) -> void:
	for i in FRAMES:
		body.position = from + Vector2(0.0, STEP * i)
		await t.frames(1)


## A solid with a shape, standing at `at` in the world.
func _solid_at(world: Node, at: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.SOLID
	body.position = at
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SOLID_SIZE
	shape.shape = rect
	body.add_child(shape)
	world.add_child(body)
	return body
