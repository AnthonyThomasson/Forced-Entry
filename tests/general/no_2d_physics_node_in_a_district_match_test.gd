extends GameTest
## No 2D physics node in a built district match (#194, ADR 0014): the tree of the world
## (the district, its towers, the street, the characters, the twin space) holds no 2D physics
## body, shape, area or ray: every sim root is a plain `Node2D` plan handle and the twin space is
## the only physics space. The scan of `scenes/` (`general/no_2d_space_reads_suite`) says no script
## makes one; this says none stands in a match that was built.

const Guard := preload("res://tests/_general/no_2d_physics_nodes.gd")
const SEED := 7
const PLAN := "garage_home"
## Fewer nodes than this means the world was not the one built (a district is thousands).
const LEAST_NODES := 500


func describe() -> Dictionary:
	return {
		"name": "A built district match holds no 2D physics node",
		"description": "Walks the whole tree of a district match with defenders and invaders: no "
			+ "PhysicsBody2D, CollisionObject2D, CollisionShape2D, CollisionPolygon2D, Area2D, "
			+ "RayCast2D or ShapeCast2D.",
		"tags": ["general", "district", "twins", "plan-handle"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED, PLAN)
	s.von_down()
	s.declared_match({ "defenders": { "count": 2 }, "invaders": { "count": 2 } })


func run(t: TestContext) -> void:
	await t.frames(3)
	var looked := Guard.count(t.world)
	t.check(looked >= LEAST_NODES, "premise: a whole district was walked (%d nodes)" % looked)
	t.check(
		t.world.get_tree().get_nodes_in_group(TwinSpace.BODIES).size() > 20,
		"premise: it holds plan handles",
	)
	t.expect_eq(Guard.offenders(t.world), [], "no 2D physics node in the tree")
