extends GameTest
## G3: a throw that a tall piece across the line stops at every height its arcs cross it at is
## judged blocked from the one strike of the highest arc, not from sweeping every arc and every
## farther lob (`GrenadeArc._spanned`: level casts at the lowest and the highest height an arc is
## at there find the one body). A wardrobe (78 px, under the highest lob's 90) standing a short way
## before the aim is struck by every arc, because they are already coming down at it; the same
## wardrobe far from the aim is flown over, and a desk (31 px) never stops the throw.

const ROOM := Rect2(0, 0, 700, 400)
## The lane of the blocked lob: the thrower, the wardrobe and the aim, along y = 200.
const HAND := Vector2(80, 200)
const AIM := Vector2(500, 200)
## The most planner work (`GrenadeArc.work`) a blocked throw takes: the casts that learn of the
## wardrobe and a few arcs swept (66 sweeping every arc).
const WORK := 18
## The AI's room to spare either side of a lob (`AgentThrow.LOB_MARGIN`).
const LOB_MARGIN := 8.0

var _space: PhysicsDirectSpaceState3D


func describe() -> Dictionary:
	return {
		"name": "A tall piece across every arc blocks the throw in a few casts",
		"description": "A wardrobe a short way before the aim, in a roofed room, is struck by all "
			+ "the arcs and the throw is judged blocked after a few casts (the body struck is "
			+ "learned of, not every arc swept); the wardrobe near the thrower, or a desk, is "
			+ "flown over and the throw is clear. Learning of it never changes an answer.",
		"tags": ["grenade", "lob", "3d", "item", "perf"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "room", "type": "living_room", "rect": ROOM }], [])
	s.switch(&"nav.rebake", false)
	s.set_static(GrenadeArc, "learn_tries", GrenadeArc.learn_tries)  # put back after the test
	s.object(&"wardrobe", "wardrobe", Vector2(350, 200))
	s.object(&"near", "wardrobe", Vector2(250, 80))
	s.object(&"desk", "desk", Vector2(350, 330))


func run(t: TestContext) -> void:
	await t.frames(3)
	_space = t.world.twin_space().space()
	var before := GrenadeArc.work
	var blocked := _clear(HAND, AIM)
	var used := GrenadeArc.work - before
	t.check(not blocked, "a wardrobe 150 px before the aim stops the lob")
	t.check(used <= WORK, "and it takes %d work to find it (at most %d)" % [used, WORK])
	t.check(
		_clear(HAND + Vector2(0, -120), AIM + Vector2(0, -120)),
		"the wardrobe near the thrower is flown over: the lob is clear",
	)
	t.check(
		_clear(HAND + Vector2(0, 130), AIM + Vector2(0, 130)),
		"a desk before the aim does not stop it",
	)
	_same_answers(t)


## Whether the planner's question for a lob from `from` onto `to` answers clear.
func _clear(from: Vector2, to: Vector2) -> bool:
	return GrenadeArc.clear(_course(from, to))


## The course of a lob from `from` onto `to`, asked the cheap question.
func _course(from: Vector2, to: Vector2) -> GrenadeCourse:
	var course := GrenadeCourse.new()
	course.from = from
	course.to = to
	course.release = BodyHeights.release(BodyHeights.STAND)
	course.row = GrenadeConfig.row(&"stun")
	course.space = _space
	course.mask = PhysicsLayers.TWIN_WORLD | PhysicsLayers.TWIN_VEHICLE
	course.margin = LOB_MARGIN
	return course


## The planner answers the same with and without learning of the body struck, over lobs along three
## lanes (the wardrobe across the line, the wardrobe near the thrower, the desk) onto aims every
## 15 px from 200 to 560 px out, asked cheaply and as a throw is made (flown to rest).
func _same_answers(t: TestContext) -> void:
	var differ := 0
	var asked := 0
	for lane in [0.0, -120.0, 130.0]:
		for reach in range(200, 561, 15):
			for verify in [false, true]:
				var answers: Array[GrenadeLaunch] = []
				for tries in [GrenadeArc.learn_tries, 0]:
					GrenadeArc.learn_tries = tries
					var course := _course(HAND + Vector2(0, lane), HAND + Vector2(reach, lane))
					course.verify = verify
					answers.append(GrenadeArc.plan(course))
				GrenadeArc.learn_tries = 3
				asked += 1
				if not _alike(answers[0], answers[1]):
					differ += 1
	t.check(
		differ == 0,
		"%d of %d lobs are answered differently with learning of the body" % [differ, asked],
	)


## Whether two plans are the same throw.
func _alike(a: GrenadeLaunch, b: GrenadeLaunch) -> bool:
	return (
		a.ok == b.ok
		and is_equal_approx(a.speed, b.speed)
		and is_equal_approx(a.rise, b.rise)
		and a.rest.is_equal_approx(b.rest)
	)
