extends GameTest
## A ducked character that rises over its cover to fire (`CharacterRise`, D7) is as tall in the twin
## space (`CharacterTwin`, #194 chars3d-a) as the pose it rose to: crouched 36 px, risen to the
## fire-over pose that pose's head top, dropped back 36 again.

const Probe := preload("res://tests/_general/twin_probe.gd")
const AT := Vector2(300, 250)
const CHARACTERS := PhysicsLayers.TWIN_CHARACTER


func describe() -> Dictionary:
	return {
		"name": "A character's twin is as tall as the pose it rose to",
		"description": "Crouched the twin is the duck's head top; risen to the fire-over pose, its "
			+ "pose's; dropped back, the duck's again.",
		"tags": ["twins", "3d", "heights", "posture", "rise", "character"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 500))
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	s.actor(&"puppet", &"puppet", AT)


func run(t: TestContext) -> void:
	await t.frames(3)
	var body := t.actor(&"puppet")
	t.require(body.movement.set_posture(&"crouch"), "premise: it can crouch")
	await t.frames(3)
	var duck := BodyHeights.head_top(BodyHeights.DUCK)
	var over := BodyHeights.head_top(BodyHeights.FIRE_OVER)
	t.require(over > duck + 1.0, "premise: the fire-over pose is taller than the duck")
	t.expect_near(Probe.top_at(t, AT, CHARACTERS), duck, 0.5, "crouched it is the duck's height")
	body.weapon.rise.rise_to(BodyHeights.FIRE_OVER)
	await t.frames(3)
	t.expect_near(Probe.top_at(t, AT, CHARACTERS), over, 0.5, "risen it is the fire-over pose's")
	body.weapon.rise.drop()
	await t.frames(3)
	t.expect_near(Probe.top_at(t, AT, CHARACTERS), duck, 0.5, "dropped back it is the duck's again")
