extends GameTest
## A walker pushes a light free piece and is stopped by a heavy one (#194, interface 5):
## the 3D body slides along a chair and a sofa it walks into (the piece is shoved at the contact,
## Jolt contacts), and a sofa as heavy as a vault door does not give: the walker is held at its face
## while the same walk carried the light pieces along.

const HEAVY := 400_000.0
const WALK_TIME := 2.0
## The gap (px) a walker starts from the face of its piece.
const GAP := 6.0
## The most a heavy piece may be driven (px).
const BARELY := 2.0


func describe() -> Dictionary:
	return {
		"name": "A walker shoves a light piece and is blocked by a heavy one",
		"description": "Three puppets walk into a chair, a sofa and a sofa of absurd weight for 2 "
			+ "seconds: the first two are shoved along and the walkers follow; the heavy one stays "
			+ "put and its walker is held at its face.",
		"tags": ["character", "pushable", "3d", "twins", "movement"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 700))
	s.switch(&"nav.rebake", false)
	var heavy := WorldGen.object_definition("sofa").duplicate()
	heavy["weight"] = HEAVY
	s.object(&"chair", "chair", Vector2(300, 100))
	s.object(&"sofa", "sofa", Vector2(300, 250))
	s.object(&"heavy", heavy, Vector2(300, 400))
	s.actor(&"w_chair", &"puppet", Vector2(300 - 16 - 14 - GAP, 100))
	s.actor(&"w_sofa", &"puppet", Vector2(300 - 60 - 14 - GAP, 250))
	s.actor(&"w_heavy", &"puppet", Vector2(300 - 60 - 14 - GAP, 400))


func run(t: TestContext) -> void:
	await t.frames(3)
	var starts := {}
	for id: StringName in [&"chair", &"sofa", &"heavy"]:
		starts[id] = (t.object(id) as Node2D).global_position
		t.puppet(StringName("w_%s" % id)).walk(Vector2.RIGHT)
	await t.seconds(WALK_TIME)
	for id: StringName in [&"chair", &"sofa"]:
		var moved: float = (t.object(id) as Node2D).global_position.x - (starts[id] as Vector2).x
		t.check(moved > 20.0, "the %s is shoved along (%.1f px)" % [id, moved])
	var heavy: Node2D = t.object(&"heavy")
	var drove: float = heavy.global_position.x - (starts[&"heavy"] as Vector2).x
	t.check(drove < BARELY, "the heavy sofa is barely driven (%.1f px)" % drove)
	var walker: Node2D = t.actor(&"w_heavy")
	var face: float = heavy.global_position.x - 60.0 - walker.radius
	t.check(
		walker.global_position.x < face + 1.0,
		"its walker is held at the face (x %.1f of %.1f)" % [walker.global_position.x, face],
	)
	var lead := TwinSpace.twin_for(walker) as CharacterBody3D
	t.check(
		PlanSpace.plan_of(lead.global_position).distance_to(walker.global_position) < 0.1,
		"and its 2D body is written from the 3D one that was blocked",
	)
