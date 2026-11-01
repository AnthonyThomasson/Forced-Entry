extends GameTest
## V1 (`docs/player-vision.md`): the view's cone follows the sight rule. Two rooms joined by a
## doorway, a wardrobe (tall) and a coffee table (low) in the first, and a puppet eye turned to set
## its facing: a point over the table and inside the cone is in the polygon; a point behind the
## wardrobe, one beyond the wall, one behind the eye past 48 px are not; one within 48 px behind it
## is; and the cone turns with the eye. Three more doorways hold a door each (V1, "Doors follow the
## same rule"): beyond a shut solid door is not seen, beyond a shut glass-panel door is, through
## an ajar door's gap is, and beyond a door knocked down is.
##
## It reads (tests/_vision/vision_probe.gd) the `PlayerView` of the world: `cone()`, `sees(point)`.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const EYE_AT := Vector2(150, 300)
## From the eye to the wardrobe's centre: points on this line, farther out, are behind it.
const WARDROBE_LINE := Vector2(300, -170)
## The doors, in the wall the rooms share (x 700) clear of the open doorway: where each hangs
## (`y`), and the eye's place 100 px before it, facing east at the point `BEYOND` px past it.
const GLASS_Y := 60.0
const HOLLOW_Y := 140.0
const WOOD_Y := 460.0
const EYE_BEFORE := 600.0
const BEYOND := 900.0


func describe() -> Dictionary:
	return {
		"name": "The view's cone follows the sight rule",
		"description": "A point over a low table is seen; points behind a tall wardrobe, beyond a "
			+ "wall and behind the eye past its bubble are not; the cone turns with the facing.",
		"tags": ["vision"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	Probe.building(s, EYE_AT, [
		Probe.DOOR,
		Probe.doorway(GLASS_Y, "glass", "panes", "glass"),
		Probe.doorway(HOLLOW_Y, "hollow", "flush", "hollow"),
		Probe.doorway(WOOD_Y, "solid", "plank", "wood"),
	])
	s.switch(&"physics.debris", false)
	s.switch(&"vision.enabled", true)
	s.view(&"eye")


func run(t: TestContext) -> void:
	var eye := t.actor(&"eye")
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
	await _doors(t, view, eye)


## Doors (V1): the eye stands before each door in turn, facing east, and the point beyond it is
## looked for. A shut solid door hides it, a shut glass-panel door does not, a solid door swung open
## shows it through the gap and hides it again shut, and a hollow door knocked down does not hide
## it.
func _doors(t: TestContext, view: PlayerView, eye: Node2D) -> void:
	var wood: Node2D = t.object(&"wood")
	var hollow: Node2D = t.object(&"hollow")
	t.check(
		not await _sees_beyond(t, view, eye, WOOD_Y),
		"beyond a shut solid door is not seen",
	)
	t.check(
		await _sees_before(t, view, eye, WOOD_Y),
		"the room before the shut solid door is seen",
	)
	t.check(
		await _sees_beyond(t, view, eye, GLASS_Y),
		"beyond a shut glass-panel door is seen",
	)
	t.check(
		not await _sees_beyond(t, view, eye, HOLLOW_Y),
		"beyond a shut hollow door is not seen",
	)
	wood.open_fully(null)
	await t.frames(60)
	t.check(wood.angle() > 45.0, "premise: the solid door swung open (%.0f degrees)" % wood.angle())
	t.check(
		await _sees_beyond(t, view, eye, WOOD_Y),
		"through an ajar door's gap is seen",
	)
	wood.toggle(null)
	await t.frames(60)
	t.check(
		not await _sees_beyond(t, view, eye, WOOD_Y),
		"beyond the solid door shut again is not seen",
	)
	hollow.take_damage(10_000.0)
	await t.frames(20)
	t.check(hollow.is_down(), "premise: the hollow door was knocked down")
	t.check(
		await _sees_beyond(t, view, eye, HOLLOW_Y),
		"beyond a door knocked down is seen",
	)


## Whether the point `BEYOND` px east, at height `y`, is seen by the eye standing before the door
## there.
func _sees_beyond(t: TestContext, view: PlayerView, eye: Node2D, y: float) -> bool:
	await Probe.place(t, eye, Vector2(EYE_BEFORE, y), Vector2.RIGHT)
	await t.frames(5)
	return view.sees(Vector2(BEYOND, y))


## Whether a point 30 px before the door, in the eye's own room, is seen.
func _sees_before(t: TestContext, view: PlayerView, eye: Node2D, y: float) -> bool:
	await Probe.place(t, eye, Vector2(EYE_BEFORE, y), Vector2.RIGHT)
	await t.frames(5)
	return view.sees(Vector2(Probe.DOOR["pos"].x - 30.0, y))
