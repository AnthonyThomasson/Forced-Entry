extends GameTest
## V1 cost (`docs/player-vision.md`): the view reads the solid shapes of the sector the eye looks
## along and the bubble round it, not the whole disc of its reach. Sixty wardrobes (two hundred and
## forty corners) stand behind the eye, outside the cone and the bubble, in the reach; none can
## bound the polygon, so the shape read (`corners_read()`) holds far fewer corners than they have,
## and the cone is still the reference cone's vertex for vertex
## (`tests/_vision/cone_checker.gd`), with a wardrobe in front of the eye to bound it.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Checker := preload("res://tests/_vision/cone_checker.gd")
const EYE_AT := Vector2(1500, 250)
## A grid of wardrobes west of the eye (the cone faces east): 10 columns by 6 rows.
const COLUMNS := 10
const ROWS := 6
const FROM := Vector2(300, 60)
const STEP := Vector2(100, 70)
const FRONT_AT := Vector2(1800, 250)
## The most corners the read may hold: the wardrobe in front, the arena's walls and slack. The
## wardrobes behind the eye have 240.
const MAX_CORNERS := 120
const FRAMES := 20


func describe() -> Dictionary:
	return {
		"name": "The view reads only the shapes of its cone and bubble",
		"description": "Sixty wardrobes behind the eye, in its reach: the shape read leaves them "
			+ "out and the cone equals the reference cone's every frame.",
		"tags": ["vision"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 3000, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	for column in COLUMNS:
		for row in ROWS:
			s.object(
				StringName("behind_%d_%d" % [column, row]),
				"wardrobe",
				FROM + Vector2(STEP.x * column, STEP.y * row),
			)
	s.object(&"front", "wardrobe", FRONT_AT)
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
		view.corners_read() > 0 and view.rebuilds() > 0,
		"premise: the view read corners (%d) and built a cone" % view.corners_read(),
	)
	t.check(
		view.corners_read() <= MAX_CORNERS,
		"the shape read holds at most %d corners, the %d wardrobes behind the eye leave it out (%d)"
			% [MAX_CORNERS, COLUMNS * ROWS, view.corners_read()],
	)
