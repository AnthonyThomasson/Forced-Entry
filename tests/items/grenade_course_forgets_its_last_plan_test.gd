extends GameTest
## What a `GrenadeCourse` remembers of a plan (`GrenadeCourse.made`: the arcs and what their lobs
## struck) is that plan's alone: `GrenadeArc.plan` forgets it first, so a course asked a second
## question, another aim, answers it as a course never asked before. Asked over a bare floor (no
## space), where only the aim tells the two questions apart.

const FROM := Vector2(300, 300)
const FIRST_AIM := Vector2(600, 300)
const SECOND_AIM := Vector2(300, 400)


func describe() -> Dictionary:
	return {
		"name": "A course planned twice forgets the first plan",
		"description": "A grenade course is planned east, then south and shorter: the second "
			+ "launch is the one a fresh course gives.",
		"tags": ["grenade", "throw", "lob", "item", "3d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 600))


func run(t: TestContext) -> void:
	var reused := _course(FIRST_AIM)
	var first := GrenadeArc.plan(reused)
	reused.to = SECOND_AIM
	var second := GrenadeArc.plan(reused)
	var fresh := GrenadeArc.plan(_course(SECOND_AIM))
	t.require(first.direction != fresh.direction, "premise: the two aims are thrown differently")
	t.check(
		second.direction == fresh.direction,
		"thrown the second aim's way: %s, a fresh course %s" % [second.direction, fresh.direction],
	)
	t.check(
		second.speed == fresh.speed and second.rise == fresh.rise,
		"at its speed and rise: %s %s, a fresh course %s %s" % [
			second.speed, second.rise, fresh.speed, fresh.rise,
		],
	)
	t.check(second.touchdown == fresh.touchdown, "touching down where a fresh course does")


func _course(to: Vector2) -> GrenadeCourse:
	var course := GrenadeCourse.new()
	course.from = FROM
	course.release = BodyHeights.release(&"stand")
	course.to = to
	course.row = GrenadeConfig.row(&"frag")
	return course
