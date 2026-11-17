extends GameTest
## A character's twin (`CharacterTwin`, interface 29, `BodyHeights`): an upright capsule as wide as
## the body's circle and as tall as the posture it is in: a standing one 74 px, a crouched one 36
## (the duck's head top, 0.85 m). A ray at 50 px strikes it standing and passes over it crouched;
## one at 30 px strikes it either way. It stands where the body walks (a puppet walks 100 px and its
## twin ends under it), and once the body dies (its layer 0) no ray finds it.

const Probe := preload("res://tests/_general/twin_probe.gd")
const AT := Vector2(300, 250)
const FROM := Vector2(300, 250 - 80)
const TO := Vector2(300, 250 + 80)
## The standing and the ducked head tops (px).
const STAND := 74.0
const DUCK := 36.0
const CHARACTERS := PhysicsLayers.TWIN_CHARACTER


func describe() -> Dictionary:
	return {
		"name": "A character's twin is a capsule as tall as its posture, and follows it",
		"description": "Standing, a ray dropped on the puppet lands at 74 px and a level ray at 50 "
			+ "px strikes it; crouched, the top is 36 px and the 50 px ray passes over, the 30 px "
			+ "one strikes; the twin follows a walk; a dead body has no twin to hit.",
		"tags": ["twins", "3d", "heights", "posture", "character"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.actor(&"puppet", &"puppet", AT)


func run(t: TestContext) -> void:
	await t.frames(3)
	var body := t.actor(&"puppet")
	var hit := Probe.down(t, AT, CHARACTERS)
	t.check(hit.get("owner") == body, "a ray dropped on the puppet finds it")
	t.expect_near(Probe.top_at(t, AT, CHARACTERS), STAND, 0.5, "standing it is 74 px tall")
	t.check(not Probe.level(t, FROM, TO, 50.0, CHARACTERS).is_empty(), "a ray at 50 px strikes it")
	t.require(body.movement.set_posture(&"crouch"), "premise: it can crouch")
	await t.frames(3)
	t.expect_near(Probe.top_at(t, AT, CHARACTERS), DUCK, 0.5, "crouched it is 36 px tall")
	t.check(Probe.level(t, FROM, TO, 50.0, CHARACTERS).is_empty(), "a ray at 50 px passes over it")
	t.check(not Probe.level(t, FROM, TO, 30.0, CHARACTERS).is_empty(), "a ray at 30 px strikes it")
	await _walk(t, body)
	await _dead(t, body)


## The puppet walks 100 px east: its twin is under it.
func _walk(t: TestContext, body: Node2D) -> void:
	t.puppet(&"puppet").walk_to(AT + Vector2(100, 0))
	await t.until(func() -> bool: return t.puppet(&"puppet").has_arrived(), 6.0)
	await t.frames(3)
	var plan := PlanSpace.plan_of(t.world.twin_space().twin_of(body).global_position)
	t.check(plan.distance_to(body.global_position) < 0.5, "the twin stands where it walked to")
	t.check(body.global_position.distance_to(AT) > 50.0, "premise: it walked")


## The body dies: its twin is on no layer.
func _dead(t: TestContext, body: Node2D) -> void:
	var at := body.global_position
	body.take_damage(100_000.0)
	await t.frames(3)
	var miss := Probe.level(t, at - Vector2(0, 80), at + Vector2(0, 80), 30.0, CHARACTERS)
	t.require(body.is_dead, "premise: it died")
	t.check(miss.is_empty(), "no ray finds a dead character's twin")
