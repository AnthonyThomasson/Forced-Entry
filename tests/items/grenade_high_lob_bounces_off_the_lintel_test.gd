extends GameTest
## G3, a lob too high for a doorway: thrown on the highest arc (peaking at 90 px) through a doorway
## 150 px from the thrower, a stun is above the door's 84 px where it passes and strikes the
## lintel (the doorway's head, up to the wall's top), bounces back and comes to rest on the
## thrower's side of the wall. The same throw on the arc the planner chooses goes through
## (`grenade_flies_under_the_lintel`).

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const WALL_X := 400.0
const FROM := Vector2(250, 400)
const AIM := Vector2(770, 400)
## The highest a lob peaks (`GrenadeConfig.max_apex`, a little under the ceiling).
const HIGH := 90.0
const LINTEL := 84.0


func describe() -> Dictionary:
	return {
		"name": "A high lob into a doorway strikes the lintel and bounces back",
		"description": "A stun thrown on the highest arc at a point beyond a doorway hits the "
			+ "doorway's lintel in the air and ends up on the thrower's side of the wall.",
		"tags": ["grenade", "lob", "doorway", "lintel", "bounce", "item", "3d"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 800) },
		{ "key": "east", "type": "kitchen", "rect": Rect2(400, 0, 400, 800) },
	], [{ "pos": Vector2(WALL_X, 400), "width": 80.0 }])
	s.switch(&"nav.rebake", false)
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	await t.frames(3)
	var throw := GrenadeThrow.new()
	throw.kind = &"stun"
	throw.from = FROM + Vector2(16, 0)
	throw.release = BodyHeights.release(BodyHeights.STAND)
	throw.to = AIM
	throw.thrower = thrower
	throw.apex = HIGH
	ThrownGrenade.spawn(throw, thrower.world_root())
	var flight := await Probe.track(t, 4.0)
	if not t.require(not flight.is_empty(), "a grenade flew"):
		return
	var struck_at := -1.0
	for i in range(1, flight.size()):
		var was: float = flight[i - 1]["at"].x
		var now: float = flight[i]["at"].x
		if was > now and struck_at < 0.0:
			struck_at = float(flight[i - 1]["altitude"])
	t.require(struck_at >= 0.0, "premise: the grenade turned back")
	t.check(
		struck_at > LINTEL - GrenadeConfig.radius,
		"it struck the lintel in the air (%.0f px up, the lintel from %.0f)" % [struck_at, LINTEL],
	)
	var rest: Vector2 = flight.back()["at"]
	t.check(rest.x < WALL_X, "and came to rest on the thrower's side (x %.0f)" % rest.x)
