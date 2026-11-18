extends GameTest
## V1 (`docs/player-vision.md`): the cone is a floor-plan polygon in which only a piece taller than
## the viewer's eye blocks the line of sight (#194 D9). A standing eye (69 px) sees over a table
## (31 px), a kitchen counter (38 px) and a coffee table (22 px) and not over a wardrobe (87 px or
## more); the same eye ducked (32 px) is stopped by the counter and still looks over the coffee
## table. A car (47 px at the belt) is looked over standing and blocks ducked. Standing up again
## opens the cone again.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const EYE_AT := Vector2(150, 300)
const COUNTER_AT := Vector2(400, 300)
const WARDROBE_AT := Vector2(300, 150)
const COFFEE_AT := Vector2(300, 450)
## One point behind each piece, on the line from the eye through its centre.
const BEHIND_COUNTER := Vector2(520, 300)
const BEHIND_WARDROBE := Vector2(375, 75)
const BEHIND_COFFEE := Vector2(375, 525)
const CAR_AT := Vector2(700, 100)
const BEHIND_CAR := Vector2(800, 63)


func describe() -> Dictionary:
	return {
		"name": "The player's cone is blocked by what stands taller than the eye",
		"description": "Standing, the cone passes over a kitchen counter and a coffee table and is "
			+ "stopped by a wardrobe; ducked, it is stopped by the counter and a car and passes "
			+ "over the coffee table; standing again reopens it.",
		"tags": ["vision", "heights", "posture", "3d"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	s.object(&"counter", "kitchen_counter", COUNTER_AT)
	s.object(&"wardrobe", "wardrobe", WARDROBE_AT)
	s.object(&"coffee", "coffee_table", COFFEE_AT)
	s.vehicle(&"car", &"car", CAR_AT)
	s.actor(&"eye", &"puppet", EYE_AT)
	s.view(&"eye")


func run(t: TestContext) -> void:
	var eye := t.actor(&"eye")
	var view := Probe.view(t)
	if not t.require(view != null, "the world has a view"):
		return
	if not t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the eye faces east"):
		return
	t.check(view.sees(BEHIND_COUNTER), "standing, a point behind the counter is seen over it")
	t.check(view.sees(BEHIND_COFFEE), "standing, a point behind the coffee table is seen over it")
	t.check(not view.sees(BEHIND_WARDROBE), "a point behind the wardrobe is not seen")
	t.check(view.sees(BEHIND_CAR), "standing, a point behind a car is seen over it")
	t.require(eye.movement.set_posture(&"crouch"), "premise: the viewer can duck")
	await t.frames(5)
	t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the ducked eye faces east")
	t.check(not view.sees(BEHIND_COUNTER), "ducked, a point behind the counter is not seen")
	t.check(view.sees(BEHIND_COFFEE), "ducked, a point behind the coffee table is still seen")
	t.check(not view.sees(BEHIND_CAR), "ducked, a point behind a car is not seen")
	t.check(view.sees(Vector2(330, 300)), "ducked, the room before the counter is seen")
	t.require(
		await t.until(func(): return eye.movement.set_posture(&"stand"), 3.0),
		"premise: the viewer stands up",
	)
	await t.frames(5)
	t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the eye stands and faces east")
	t.check(view.sees(BEHIND_COUNTER), "standing again, the point behind the counter is seen")
