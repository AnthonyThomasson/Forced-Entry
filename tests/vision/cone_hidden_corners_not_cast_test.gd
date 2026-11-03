extends GameTest
## V1 cost (`docs/player-vision.md`): the view does not cast a ray to a corner two neighbouring rays
## of the cone's even fan have shown to be hidden. A shared wall between the rooms stands across the
## whole cone and twenty wardrobes (eighty corners) stand in the room behind it, in the cone: each
## corner lies behind a convex shape (the wall's) that two neighbouring fan rays both meet nearer
## than the corner, so the line from the eye to the corner crosses the chord between those hits and
## is blocked, and no ray need be cast to learn it. The cone is still the reference cone's, vertex
## for vertex (`tests/_vision/cone_checker.gd`), and the rays cast to corners (`corner_rays()`) are
## far fewer than the corners in the cone.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Checker := preload("res://tests/_vision/cone_checker.gd")
const EYE_AT := Vector2(250, 250)
## The wardrobes behind the wall, in rows and columns of the kitchen (x 700 to 1200).
const COLUMNS := 4
const ROWS := 5
const FROM := Vector2(790, 70)
const STEP := Vector2(100, 90)
## The most rays that may be cast to corners: the wall's own corners and slack. Casting one to
## every corner of the wardrobes behind it takes more than the wardrobes' eighty.
const MAX_CORNER_RAYS := 40
const FRAMES := 30


func describe() -> Dictionary:
	return {
		"name": "The view casts no ray to a corner hidden behind a shape the fan met",
		"description": "Twenty wardrobes behind a wall in the cone: the cone equals the reference "
			+ "cone's every frame and the rays cast to corners are fewer than the wardrobes' "
			+ "corners.",
		"tags": ["vision"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.layout(Probe.ROOMS, [])
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	for column in COLUMNS:
		for row in ROWS:
			s.object(
				StringName("hidden_%d_%d" % [column, row]),
				"wardrobe",
				FROM + Vector2(STEP.x * column, STEP.y * row),
			)
	s.actor(&"eye", &"puppet", EYE_AT)
	s.view(&"eye")


func run(t: TestContext) -> void:
	var view := Probe.view(t)
	if not t.require(view != null, "the world has a view"):
		return
	var eye := t.actor(&"eye")
	if not t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the viewer faces east"):
		return
	var checker := Checker.new(view, eye)
	t.world.add_child(checker)
	await t.frames(FRAMES)
	t.check(checker.wrong() == 0, "the cone equals the reference cone's: %s" % checker.report())
	t.check(
		not view.cone().is_empty() and view.rebuilds() > 0,
		"premise: the view built a cone (%d rebuilds)" % view.rebuilds(),
	)
	t.check(
		view.corner_rays() <= MAX_CORNER_RAYS,
		"a rebuild casts at most %d rays to corners, with %d wardrobe corners hidden behind the "
			% [MAX_CORNER_RAYS, COLUMNS * ROWS * 4]
		+ "wall (%d cast)" % view.corner_rays(),
	)
