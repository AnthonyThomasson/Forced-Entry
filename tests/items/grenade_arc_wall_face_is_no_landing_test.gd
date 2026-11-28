extends GameTest
## G3: a lob that strikes within a few px of its aim on the way down has landed on top of what is
## there only when it struck a surface that faces up (the floor, a piece's top, its edge); the face
## of a wall, or of a piece's side, rising beside the aim is a strike (`GrenadeArc._lands`), so a
## throw whose arc comes down onto a wall at the aim is judged blocked. Asked of the planner's own
## question at four strikes near the aim of a lob across a hall: in the open, on a desk's top, on
## the wall's face and on the desk's side.

const WALL_X := 700.0
const DESK_AT := Vector2(250, 250)
## The desk's top (px).
const DESK_TOP := 31.0

var _space: PhysicsDirectSpaceState3D


func describe() -> Dictionary:
	return {
		"name": "A wall's face beside the aim is a strike, not a landing",
		"description": "A strike near the aim on the way down is a landing on the open floor and "
			+ "on a desk's top, and a strike against the wall's face or the desk's side is not.",
		"tags": ["grenade", "lob", "3d", "item"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, WALL_X, 800) },
		{ "key": "east", "type": "kitchen", "rect": Rect2(WALL_X, 0, 700, 800) },
	], [{ "pos": Vector2(WALL_X, 150), "width": 80.0 }])
	s.switch(&"nav.rebake", false)
	s.object(&"desk", "desk", DESK_AT)


func run(t: TestContext) -> void:
	await t.frames(3)
	_space = t.world.twin_space().space()
	_case(t, "in the open", Vector3(400, 3.5, 650), true)
	_case(t, "on the desk's top", Vector3(300, DESK_TOP + 3.5, 250), true)
	_case(t, "against the wall's face", Vector3(686, 20.0, 450), false)
	_case(t, "against the desk's side", Vector3(180, 20.0, 250), false)


## The strike at `at` (x, height, y: `PlanSpace.lift`) of an arc coming down onto its plan point
## from the west: whether `GrenadeArc._lands` calls it a landing, against `want`.
func _case(t: TestContext, what: String, at: Vector3, want: bool) -> void:
	var plan := PlanSpace.plan_of(at)
	var course := GrenadeCourse.new()
	course.from = plan - Vector2(300, 0)
	course.to = plan
	course.space = _space
	course.margin = 8.0
	var before := at + Vector3(-6, 10, 0)
	var after := at + Vector3(6, -10, 0)
	var landed := GrenadeArc._lands(course, before, after, at)
	t.check(landed == want, "a strike %s is %s" % [what, "a landing" if landed else "a strike"])
