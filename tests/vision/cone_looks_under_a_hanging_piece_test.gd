extends GameTest
## V1 (`docs/player-vision.md`): a piece that hangs above the eye is looked under. A mirror hangs
## from 46 px to 80 px above the floor: a standing eye (69 px) meets it and the cone stops there; a
## ducked eye (32 px) is under it and the cone goes on past it, and standing up closes it again.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const EYE_AT := Vector2(150, 300)
const MIRROR_AT := Vector2(400, 300)
## A point behind the mirror, on the line from the eye through its centre.
const BEHIND := Vector2(470, 300)


func describe() -> Dictionary:
	return {
		"name": "The player's cone passes under a piece that hangs above the eye",
		"description": "A mirror hangs from 46 to 80 px: a standing eye does not see past it, a "
			+ "ducked one does, and standing up again closes the cone behind it.",
		"tags": ["vision", "heights", "posture", "3d"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"vision.enabled", true)
	s.object(&"mirror", "mirror", MIRROR_AT, { "facing": Vector2.RIGHT })
	s.actor(&"eye", &"puppet", EYE_AT)
	s.view(&"eye")


func run(t: TestContext) -> void:
	var eye := t.actor(&"eye")
	var view := Probe.view(t)
	if not t.require(view != null, "the world has a view"):
		return
	if not t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the eye faces east"):
		return
	t.check(not view.sees(BEHIND), "standing (69 px), a point behind the mirror is not seen")
	t.require(eye.movement.set_posture(&"crouch"), "premise: the viewer can duck")
	await t.frames(5)
	t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the ducked eye faces east")
	t.check(view.sees(BEHIND), "ducked (32 px), a point behind the mirror is seen under it")
	t.require(
		await t.until(func(): return eye.movement.set_posture(&"stand"), 3.0),
		"premise: the viewer stands up",
	)
	await t.frames(5)
	t.require(await Probe.place(t, eye, EYE_AT, Vector2.RIGHT), "the eye stands and faces east")
	t.check(not view.sees(BEHIND), "standing again, the point behind the mirror is not seen")
