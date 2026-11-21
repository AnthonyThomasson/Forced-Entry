extends GameTest
## The test camera frames the world's actors (the midpoint of those alive, zoomed to fit them): an
## actor parked far off the stage (as `ai/stack/rally_held_fights_stack_side` parks its defender at
## (-6000, -6000)) is not framed, or the view would zoom out to empty ground and centre between
## the room and nowhere. With the actor back on the stage it is framed again.

## Where an actor is parked off the stage (px).
const OFFSTAGE := Vector2(-6000, -6000)
## How near (px) the camera's centre must be to the actor left on the stage.
const NEAR := 150.0


func describe() -> Dictionary:
	return {
		"name": "The camera does not frame an actor parked off the stage",
		"description": "Two actors in a room are framed; one parked 6000 px away leaves the camera "
			+ "on the other, no further out; put back, both are framed again.",
		"tags": ["camera", "zoom", "framing"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.lock_interaction([&"camera"])  # a person's wheel or camera keys would change what is measured
	s.arena(Rect2(0, 0, 1000, 640))
	s.actor(&"a", &"puppet", Vector2(300, 300))
	s.actor(&"b", &"puppet", Vector2(700, 300))


func run(t: TestContext) -> void:
	var cam: Camera2D = t.world.get_viewport().get_camera_2d()
	if not t.require(cam != null, "premise: the test has a camera"):
		return
	await t.seconds(2.0)
	var both := cam.zoom.x
	t.expect_near(cam.global_position.x, 500.0, NEAR, "both framed: centred between them")
	var b := t.actor(&"b")
	b.global_position = OFFSTAGE
	await t.seconds(2.0)
	t.check(
		cam.global_position.distance_to(t.actor(&"a").global_position) < NEAR,
		"the camera is on the actor left on the stage (at %s)" % cam.global_position,
	)
	t.check(
		cam.zoom.x >= both,
		"the view does not zoom out for the parked one (zoom %.2f, was %.2f)" % [cam.zoom.x, both],
	)
	b.global_position = Vector2(700, 300)
	await t.seconds(2.0)
	t.expect_near(cam.global_position.x, 500.0, NEAR, "back on the stage: framed again")
