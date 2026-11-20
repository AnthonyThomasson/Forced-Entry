extends GameTest
## A piece that stays where it is when it is twinned is followed once a script moves it (interface
## 29: the note of the twins job, kept by #194 furn3d and del2d-c4): an anchored post (a plan handle
## with a static twin that is not read each frame, only looked at slowly) is later moved along by a
## script (no 2D physics step moves it: it has no 2D body); its twin follows it where it goes.

const Probe := preload("res://tests/_general/twin_probe.gd")
const AT := Vector2(300, 250)
## How the post is moved: this many frames, this far (px) a frame.
const SHOVE_FRAMES := 30
const SHOVE_STEP := Vector2(2.0, 0.0)
## An anchored solid post: it never moves while it is anchored (the streetlight's kind of piece).
const POST := {
	"name": "Post", "shape": "circle", "size": Vector2(28, 28), "color": Color(0.32, 0.33, 0.36),
	"material": "metal", "weight": 6, "penetration": 85, "anchored": true,
}


func describe() -> Dictionary:
	return {
		"name": "A static piece a script moves after it is twinned is followed by its twin",
		"description": "An anchored post is twinned static; moved along by a script, its twin "
			+ "ends up where the post does, not where it was placed.",
		"tags": ["twins", "3d", "static"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 500))
	s.object(&"post", POST, AT)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var post := t.object(&"post")
	var twin := Probe.twins(t).twin_of(post)
	if not t.require(twin != null, "premise: the post is twinned"):
		return
	for i in SHOVE_FRAMES:  # a script moves it
		post.global_position += SHOVE_STEP
		await t.frames(1)
	await t.frames(2)  # the twin is a frame behind a script's move
	t.require(post.global_position.x > AT.x + 40.0, "premise: it moved (%s)" % post.global_position)
	var plan := PlanSpace.plan_of(twin.global_position)
	t.check(
		plan.distance_to(post.global_position) < 1.0,
		"its twin is where it went (%s, the post at %s)" % [
			plan.round(),
			post.global_position.round(),
		],
	)
