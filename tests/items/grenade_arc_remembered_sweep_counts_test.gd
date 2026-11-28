extends GameTest
## `GrenadeArc.work` is the price the AI's throw-spot search is charged by, not the casts made: a
## lob a plan has already swept is answered from its memory (`Arc.struck`) and still counts one
## (docs/grenades.md), so a plan that remembers more costs the AI no less. Asked of one lob of one
## arc, twice, in a twin space.

const HAND := Vector2(80, 200)
const AIM := Vector2(500, 200)


func describe() -> Dictionary:
	return {
		"name": "A sweep a plan remembers still counts as work",
		"description": "One lob of one arc is asked twice: the second answer comes from the "
			+ "plan's memory and the planner's work rises by two in all.",
		"tags": ["grenade", "throw", "lob", "item", "3d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))


func run(t: TestContext) -> void:
	await t.frames(3)
	var course := GrenadeCourse.new()
	course.from = HAND
	course.to = AIM
	course.release = BodyHeights.release(BodyHeights.STAND)
	course.row = GrenadeConfig.row(&"frag")
	course.space = t.world.twin_space().space()
	var query := GrenadeArc._sweep(course)
	var arc := GrenadeArc._arc(course, course.release)
	var reach := GrenadeArc._reach(course, arc)
	var before := GrenadeArc.work
	var first: Variant = GrenadeArc._strike(course, query, arc, reach)
	t.require(arc.struck.has(reach), "premise: the plan remembers what the lob struck")
	var second: Variant = GrenadeArc._strike(course, query, arc, reach)
	t.check(second == first, "the remembered answer: %s, swept %s" % [second, first])
	var counted := GrenadeArc.work - before
	t.check(counted == 2, "asked twice, the work rises by 2: %d" % counted)
