extends GameTest
## P6 (docs/cover-and-stance.md): a risen body's eye is the risen pose's (`BodyHeights.eye`): a
## ducked viewer 25 px short of a sofa's back sees none of the points of a standing body 350 px
## beyond it (the back is 38 px, its eye 32); once it rises to fire over the sofa its eye (46 px)
## is over the back and the same body is seen (`SightRay`, D9). The other way too: the standing body
## sees none of the ducked viewer behind the sofa, sees it while it is risen over the sofa, and none
## of it again once it has dropped back; its eye follows the rise (`body_posture`), not the stance.

const SOFA_AT := Vector2(400, 250)
const VIEWER_AT := Vector2(350, 250)
const TARGET_AT := Vector2(700, 250)


func describe() -> Dictionary:
	return {
		"name": "A risen body sees over the cover it fires over",
		"description": "A ducked viewer by a sofa sees no point of a standing body beyond it; "
			+ "risen to fire, its eye clears the sofa's back and it sees the body.",
		"tags": ["character", "posture", "rise", "sight", "3d"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.set_static(CharacterRiseConfig, &"rise_time", 0.1)
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
		straight[gun]["automatic"] = true
	s.set_static(GunConfig, &"guns", straight)
	var sofa := WorldGen.object_definition("sofa").duplicate()
	sofa["size"] = Vector2(50, 120)
	s.object(&"sofa", sofa, SOFA_AT, { "facing": Vector2.RIGHT })
	s.actor(&"viewer", &"puppet", VIEWER_AT, { "start_slot": 3, "max_health": 100_000.0 })
	s.actor(&"target", &"puppet", TARGET_AT, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var viewer := t.actor(&"viewer")
	t.require(viewer.movement.set_posture(&"crouch"), "premise: the viewer ducks")
	t.puppet(&"viewer").aim_at(t.actor(&"target"))
	await t.seconds(0.6)
	t.expect_near(
		SightRay.eye_point(viewer).y, BodyHeights.eye(BodyHeights.DUCK), 0.01, "ducked eye"
	)
	t.check(not _sees(t), "ducked, it sees no point of the body beyond the sofa")
	t.puppet(&"viewer").hold_fire(true)
	await t.seconds(0.5)
	t.expect_eq(viewer.movement.body_posture(), BodyHeights.FIRE_OVER, "premise: it has risen")
	t.expect_near(
		SightRay.eye_point(viewer).y, BodyHeights.eye(BodyHeights.FIRE_OVER), 0.01, "risen eye"
	)
	t.check(_sees(t), "risen, its eye is over the sofa's back and it sees the body")
	t.check(_sees_viewer(t), "and the standing body sees the risen one over the sofa")
	t.puppet(&"viewer").hold_fire(false)
	await t.seconds(CharacterRiseConfig.dwell + CharacterRiseConfig.rise_time + 0.6)
	t.expect_eq(viewer.movement.body_posture(), BodyHeights.DUCK, "premise: it has dropped back")
	t.check(not _sees(t), "dropped, it sees no point of the body beyond the sofa again")
	t.check(not _sees_viewer(t), "and the standing body sees none of it behind the sofa")


func _sees(t: TestContext) -> bool:
	var target := t.actor(&"target")
	return SightRay.sees(
		TwinSpace.space_of(target),
		SightRay.eye_point(t.actor(&"viewer")),
		target.global_position,
		SightRay.target_heights(target),
		SightRay.exclude_of(target),
	)


## Whether the standing body's eye sees any point of the viewer.
func _sees_viewer(t: TestContext) -> bool:
	var viewer := t.actor(&"viewer")
	return SightRay.sees(
		TwinSpace.space_of(viewer),
		SightRay.eye_point(t.actor(&"target")),
		viewer.global_position,
		SightRay.target_heights(viewer),
		SightRay.exclude_of(viewer),
	)
