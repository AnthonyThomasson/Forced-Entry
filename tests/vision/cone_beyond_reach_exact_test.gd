extends GameTest
## V1 (`docs/player-vision.md`): a corner beyond the view distance adds no ray to the cone,
## whichever shape it belongs to. A thin wall lies across the reach: it touches the view distance's
## disc outside the cone (60 degrees from the facing, the cone's half width is 55) and runs on out
## of
## the disc to a corner inside the cone's angle, 2700 px from the eye. And a wardrobe stands just
## outside the reach, within the few pixels past it that a shape query of the cone's sector reads.
## The view's polygon is the reference cone's, vertex for vertex, in every frame
## (`tests/_vision/cone_checker.gd`).

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Checker := preload("res://tests/_vision/cone_checker.gd")
const EYE_AT := Vector2(500, 300)
## The wall's two ends, from the eye: inside the disc at 60 degrees, beyond it at 50 degrees.
const WALL_FROM := Vector2(2500, 0)
const WALL_TO := Vector2(2700, 0)
const WALL_FROM_ANGLE := 60.0
const WALL_TO_ANGLE := 50.0
const WALL_WIDTH := 6.0
## A wardrobe this far from the eye (the reach is 2520), on the facing.
const BAND := 2524.0
const FRAMES := 20


func describe() -> Dictionary:
	return {
		"name": "The view's cone ignores corners beyond the view distance, as the reference's",
		"description": "A wall that touches the view distance's disc outside the cone and runs "
			+ "on to a corner beyond it inside the cone's angle, and a wardrobe just past the "
			+ "reach: the polygon is the reference cone's every frame.",
		"tags": ["vision"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(-3000, -3000, 8000, 8000), { "walls": false })
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	s.object(&"band", "wardrobe", EYE_AT + Vector2(BAND, 0.0), { "rotated": true })
	s.actor(&"eye", &"puppet", EYE_AT)
	s.view(&"eye")


func run(t: TestContext) -> void:
	var view := Probe.view(t)
	if not t.require(view != null, "the world has a view"):
		return
	var eye := t.actor(&"eye")
	if not t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the viewer faces east"):
		return
	var from := EYE_AT + Vector2.from_angle(deg_to_rad(WALL_FROM_ANGLE)) * WALL_FROM.x
	var to := EYE_AT + Vector2.from_angle(deg_to_rad(WALL_TO_ANGLE)) * WALL_TO.x
	_wall(t.world, from, to)
	await t.frames(5)
	var checker := Checker.new(view, eye)
	t.world.add_child(checker)
	await t.frames(FRAMES)
	t.check(checker.wrong() == 0, "the cone equals the reference cone's: %s" % checker.report())
	t.check(
		not view.cone().is_empty() and checker.frames >= FRAMES,
		"premise: the view built a cone and the checker compared it (%d frames)" % checker.frames,
	)


## A thin solid wall from `from` to `to`.
func _wall(world: Node, from: Vector2, to: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.SOLID
	body.position = (from + to) * 0.5
	body.rotation = (to - from).angle()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(from.distance_to(to), WALL_WIDTH)
	shape.shape = rect
	body.add_child(shape)
	world.add_child(body)
