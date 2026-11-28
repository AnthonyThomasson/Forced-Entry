extends GameTest
## G3: a grenade leaves the hand at the height of the pose its thrower is in
## (`CharacterMovement.body_posture()`, `BodyHeights.release`): about 72 px standing, 55 px ducked,
## so the first sight of a stun thrown ducked is lower than of one thrown standing, by what the
## two release heights differ.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const STAND_AT := Vector2(100, 150)
const DUCK_AT := Vector2(100, 350)
const AIM_FROM := 300.0
## How far the first sighting (a frame after the release) may be from the release height's
## underside.
const SLACK := 8.0


func describe() -> Dictionary:
	return {
		"name": "A grenade leaves the hand at its thrower's pose's height",
		"description": "A standing and a ducked thrower each lob a stun 300 px: the first "
			+ "sighting is at the release height of the posture, the ducked one lower.",
		"tags": ["grenade", "release", "posture", "item", "3d"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 500))
	s.switch(&"nav.rebake", false)
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	s.actor(&"stander", &"puppet", STAND_AT, { "max_health": 100_000.0 })
	s.actor(&"ducker", &"puppet", DUCK_AT, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var stander := t.actor(&"stander")
	var ducker := t.actor(&"ducker")
	Probe.arm(stander, 1, 0)
	Probe.arm(ducker, 1, 0)
	t.require(ducker.movement.set_posture(&"crouch"), "premise: the thrower ducks")
	t.expect_eq(ducker.movement.body_posture(), BodyHeights.DUCK, "premise: its pose is the duck")
	var stood := await _first_altitude(t, &"stander", STAND_AT)
	await t.seconds(2.5)
	var ducked := await _first_altitude(t, &"ducker", DUCK_AT)
	var stand_rel := BodyHeights.release(BodyHeights.STAND) - GrenadeConfig.radius
	var duck_rel := BodyHeights.release(BodyHeights.DUCK) - GrenadeConfig.radius
	t.expect_near(stood, stand_rel, SLACK, "standing: it leaves at the standing release height")
	t.expect_near(ducked, duck_rel, SLACK, "ducked: it leaves at the ducked release height")
	t.check(ducked < stood - 8.0, "the ducked grenade leaves lower (%.0f < %.0f)" % [ducked, stood])


## The altitude of the first sighting of a stun thrown from `from` 300 px along +x.
func _first_altitude(t: TestContext, who: StringName, from: Vector2) -> float:
	await Probe.throw_at(t, who, Probe.STUN, from + Vector2(AIM_FROM, 0.0))
	var flight := await Probe.track(t, 1.0)
	return float(flight[0]["altitude"]) if not flight.is_empty() else -1.0
