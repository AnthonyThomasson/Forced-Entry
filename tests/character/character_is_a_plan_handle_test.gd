extends GameTest
## A character is a plain `Node2D` plan handle (#194, ADR 0014): it has no engine body of
## its own and no 2D shape, so a scan by `PhysicsBody2D` / `CollisionShape2D` / `CharacterBody2D`
## type never meets it. It is in the groups `TwinSpace.BODIES` and `characters`; its 3D twin is the
## truth of where it stands and the handle is written from it; a dead one's twin leaves its layer
## and a riding or seated one's cylinder is off, with no 2D shape or layer to say it.


func describe() -> Dictionary:
	return {
		"name": "A character is a plain Node2D plan handle with no 2D body or shape",
		"description": "A puppet is a Node2D in the groups bodies and characters with no collision "
			+ "shape child; it walks (its plan position follows its 3D twin); killed, its twin "
			+ "leaves the character layer.",
		"tags": ["twins", "character", "plan-handle"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.actor(&"walker", &"puppet", Vector2(300, 250))
	s.actor(&"victim", &"puppet", Vector2(600, 250))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	for id: StringName in [&"walker", &"victim"]:
		var body: Node2D = t.actor(id)
		t.check(body.get_class() == "Node2D", "%s is a plain Node2D (%s)" % [id, body.get_class()])
		t.check(not body is CollisionObject2D, "%s is no 2D physics body" % id)
		t.check(
			body.find_children("*", "CollisionShape2D", true, false).is_empty(),
			"%s has no 2D shape" % id,
		)
		t.check(body.is_in_group(TwinSpace.BODIES), "%s is a plan body" % id)
		t.check(body.is_in_group(&"characters"), "%s is a character" % id)
	var walker: Node2D = t.actor(&"walker")
	var from := walker.global_position
	t.puppet(&"walker").walk(Vector2.RIGHT)
	await t.seconds(0.5)
	var twin := TwinSpace.twin_for(walker) as CollisionObject3D
	t.check(twin != null, "the walker has a 3D twin")
	t.check(walker.global_position.x > from.x + 20.0, "the walker's handle follows its twin")
	t.expect_near(
		PlanSpace.plan_of(twin.global_position).x, walker.global_position.x, 0.01,
		"the handle stands where the twin does",
	)
	var victim: Node2D = t.actor(&"victim")
	var vtwin := TwinSpace.twin_for(victim) as CollisionObject3D
	t.check(vtwin.collision_layer == PhysicsLayers.TWIN_CHARACTER, "the living are on the layer")
	victim.take_damage(10_000.0)
	await t.frames(3)
	t.check(victim.is_dead, "premise: the victim is dead")
	t.check(vtwin.collision_layer == 0, "a dead one's twin is on no layer")
