extends GameTest
## V1 (`docs/player-vision.md`): the view's cone follows the sight rule. Two rooms joined by a
## doorway, a wardrobe (tall) and a coffee table (low) in the first, and a puppet eye turned to set
## its facing: a point over the table and inside the cone is in the polygon; a point behind the
## wardrobe, one beyond the wall, one behind the eye past 48 px are not; one within 48 px behind it
## is; and the cone turns with the eye.
##
## It reads (tests/_vision/vision_probe.gd) the `PlayerView` of the world: `cone()`, `sees(point)`.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const EYE_AT := Vector2(150, 300)
## From the eye to the wardrobe's centre: points on this line, farther out, are behind it.
const WARDROBE_LINE := Vector2(300, -170)


func describe() -> Dictionary:
	return {
		"name": "The view's cone follows the sight rule",
		"description": "A point over a low table is seen; points behind a tall wardrobe, beyond a "
			+ "wall and behind the eye past its bubble are not; the cone turns with the facing.",
		"tags": ["vision"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	Probe.building(s, EYE_AT)
	s.set_static(VisionConfig, &"enabled", true)


func run(t: TestContext) -> void:
	var eye := t.actor(&"eye")
	PlayerView.watch(t.world, eye)
	var view := Probe.view(t)
	if not t.require(view != null, "the world has a view"):
		return
	if not t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the eye faces east"):
		return
	t.check(view.cone().size() >= 3, "the cone is a polygon")
	# Over the low table, and beyond it, in the cone.
	t.check(view.sees(Vector2(330, 300)), "a point over the table is seen")
	t.check(view.sees(Vector2(480, 300)), "a point beyond the table is seen")
	t.check(view.sees(Vector2(600, 200)), "a clear point in the cone is seen")
	# Behind the wardrobe, on the line from the eye through it.
	t.check(not view.sees(EYE_AT + WARDROBE_LINE * 1.4), "a point behind the wardrobe is not seen")
	t.check(
		not view.sees(EYE_AT + WARDROBE_LINE * 1.6),
		"a point farther behind the wardrobe is not seen",
	)
	t.check(view.sees(EYE_AT + WARDROBE_LINE * 0.6), "a point before the wardrobe is seen")
	# Through the doorway (y 200 to 300 in the shared wall) and beyond the wall.
	t.check(view.sees(Vector2(900, 250)), "a point beyond the doorway, on a clear line, is seen")
	t.check(not view.sees(Vector2(900, 420)), "a point beyond the wall is not seen")
	# Behind the eye: the bubble is 48 px.
	t.check(not view.sees(EYE_AT + Vector2(-100, 0)), "a point 100 px behind the eye is not seen")
	t.check(view.sees(EYE_AT + Vector2(-40, 0)), "a point 40 px behind the eye is seen")
	t.check(not view.sees(EYE_AT + Vector2(-60, 0)), "a point 60 px behind the eye is not seen")
	# Turned north, the cone follows: the room's far end north is seen, the south is not.
	if not t.require(await Probe.place(t, eye, EYE_AT, Vector2.UP), "the eye turns north"):
		return
	t.check(view.sees(EYE_AT + Vector2(0, -200)), "facing north, a point 200 px north is seen")
	t.check(
		not view.sees(EYE_AT + Vector2(0, 150)),
		"facing north, a point 150 px south is not seen",
	)
	t.check(not view.sees(Vector2(480, 300)), "facing north, a point east is not seen")
