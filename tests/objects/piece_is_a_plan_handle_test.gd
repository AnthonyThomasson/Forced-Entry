extends GameTest
## A piece of furniture is a plain `Node2D` plan handle (#194 del2d-c4, ADR 0014): it has no
## engine body of its own and no 2D shape, so a scan by `PhysicsBody2D` / `CollisionShape2D` type
## never meets it. It is in the groups `TwinSpace.BODIES` (twinned, found as a plan body) and
## `TwinSpace.PIECES` (a piece, not a wall, a door or a vehicle); a free one is led by its 3D body
## and pushed through `Knockback.push`, an anchored one is a static twin, a rug (non-solid) has no
## twin. Each answers the pushable contract (`get_mass`, `apply_impulse`).

const Piece := preload("res://tests/_objects/piece_probe.gd")
const Probe := preload("res://tests/_general/plan_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A piece is a plain Node2D plan handle with no 2D body or shape",
		"description": "A table, an anchored streetlight and a rug are Node2Ds in the groups "
			+ "bodies and pieces with no collision shape child; the table is led by a 3D body and "
			+ "moves when pushed, the streetlight has a static twin, the rug none; each answers "
			+ "get_mass and apply_impulse, and a plan scan by body type does not meet them.",
		"tags": ["twins", "furniture", "plan-handle"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.object(&"table", "coffee_table", Vector2(300, 250))
	s.object(&"lamp", "streetlight", Vector2(600, 250))
	s.object(&"rug", "rug", Vector2(450, 120))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var table := t.object(&"table")
	var lamp := t.object(&"lamp")
	var rug := t.object(&"rug")
	for piece: Node2D in [table, lamp, rug]:
		var label := String(piece.name)
		t.check(
			piece.get_class() == "Node2D",
			"%s is a plain Node2D (%s)" % [label, piece.get_class()],
		)
		t.check(not piece is CollisionObject2D, "%s is no 2D physics body" % label)
		t.check(
			piece.find_children("*", "CollisionShape2D", true, false).is_empty(),
			"%s has no 2D shape" % label,
		)
		t.check(piece.is_in_group(TwinSpace.BODIES), "%s is a plan body" % label)
		t.check(piece.is_in_group(TwinSpace.PIECES), "%s is a piece" % label)
		t.check(not piece.is_in_group(TwinSpace.HARD), "%s is not a wall, door or vehicle" % label)
		t.check(
			piece.has_method(&"get_mass") and piece.has_method(&"apply_impulse"),
			"%s answers the pushable contract" % label,
		)
	t.check(Piece.body(table) != null, "the table is led by a free 3D body")
	t.check(TwinSpace.twin_for(lamp) is StaticBody3D, "the anchored lamp has a static twin")
	t.check(TwinSpace.twin_for(rug) == null, "the rug has no twin")
	t.expect_near(
		float(table.call(&"get_mass")),
		Knockback.mass_of(float(table.get("weight"))),
		0.001,
		"its mass is the catalogue's weight",
	)
	var scanned := Probe.bodies_under(table.get_parent())
	t.check(
		scanned.has(table) and scanned.has(lamp) and scanned.has(rug),
		"PlanProbe.bodies_under finds the pieces",
	)
	var from: Vector2 = table.global_position
	Knockback.push(table, Vector2(3000.0, 0.0), Vector2.ZERO, 9.0)
	await t.frames(20)
	t.check(
		table.global_position.x > from.x + 5.0,
		"a shoved table's plan handle follows its 3D body (%s)" % table.global_position,
	)
	var lamp_at: Vector2 = lamp.global_position
	Knockback.push(lamp, Vector2(3000.0, 0.0), Vector2.ZERO, 9.0)
	await t.frames(10)
	t.check(lamp.global_position.is_equal_approx(lamp_at), "an anchored lamp is not moved")
