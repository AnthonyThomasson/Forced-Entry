extends GameTest
## A body frozen when it is twinned is followed once it is unfrozen (interface 29: the note of the
## twins job, kept by #194 furn3d): an anchored post (frozen, a static twin that is not read each
## frame) is later unfrozen and shoved; its twin follows it where it goes, and the post is no
## longer the body a ray finds where it stood.

const Probe := preload("res://tests/_general/twin_probe.gd")
const AT := Vector2(300, 250)
## An anchored solid post: it never moves while it is anchored (the streetlight's kind of piece).
const POST := {
	"name": "Post", "shape": "circle", "size": Vector2(28, 28), "color": Color(0.32, 0.33, 0.36),
	"material": "metal", "weight": 6, "penetration": 85, "anchored": true,
}


func describe() -> Dictionary:
	return {
		"name": "A body unfrozen after it is twinned is followed by its twin",
		"description": "An anchored post is twinned frozen; unfrozen and shoved along, its twin "
			+ "ends up where the post does, not where it was placed.",
		"tags": ["twins", "3d", "freeze"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 500))
	s.object(&"post", POST, AT)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var post := t.object(&"post") as RigidBody2D
	var twin := Probe.twins(t).twin_of(post)
	if not t.require(twin != null, "premise: the frozen post is twinned"):
		return
	post.freeze = false
	post.gravity_scale = 0.0
	post.linear_damp = 3.0
	post.apply_impulse(Vector2(3000.0, 0.0))
	await t.seconds(1.0)
	t.require(post.global_position.x > AT.x + 40.0, "premise: it moved (%s)" % post.global_position)
	var plan := PlanSpace.plan_of(twin.global_position)
	t.check(
		plan.distance_to(post.global_position) < 1.0,
		"its twin is where it went (%s, the post at %s)" % [
			plan.round(),
			post.global_position.round(),
		],
	)
