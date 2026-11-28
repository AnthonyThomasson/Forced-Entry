extends GameTest
## G3: a throw that a tall piece across the line stops at every height its arcs cross it at is
## judged blocked. A wardrobe (78 px, under the highest lob's 90) standing a short way before the
## aim is struck by every arc, because they are already coming down at it; the same wardrobe far
## from the aim is flown over, and a desk (31 px) never stops the throw.

const ROOM := Rect2(0, 0, 700, 400)
## The lane of the blocked lob: the thrower, the wardrobe and the aim, along y = 200.
const HAND := Vector2(80, 200)
const AIM := Vector2(500, 200)
## The AI's room to spare either side of a lob (`AgentThrow.LOB_MARGIN`).
const LOB_MARGIN := 8.0

var _space: PhysicsDirectSpaceState3D


func describe() -> Dictionary:
	return {
		"name": "A tall piece across every arc blocks the throw",
		"description": "A wardrobe a short way before the aim, in a roofed room, is struck by all "
			+ "the arcs and the throw is judged blocked; the wardrobe near the thrower, or a "
			+ "desk, is flown over and the throw is clear.",
		"tags": ["grenade", "lob", "3d", "item"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "room", "type": "living_room", "rect": ROOM }], [])
	s.switch(&"nav.rebake", false)
	s.object(&"wardrobe", "wardrobe", Vector2(350, 200))
	s.object(&"near", "wardrobe", Vector2(250, 80))
	s.object(&"desk", "desk", Vector2(350, 330))


func run(t: TestContext) -> void:
	await t.frames(3)
	_space = t.world.twin_space().space()
	t.check(not _clear(HAND, AIM), "a wardrobe 150 px before the aim stops the lob")
	t.check(
		_clear(HAND + Vector2(0, -120), AIM + Vector2(0, -120)),
		"the wardrobe near the thrower is flown over: the lob is clear",
	)
	t.check(
		_clear(HAND + Vector2(0, 130), AIM + Vector2(0, 130)),
		"a desk before the aim does not stop it",
	)


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
