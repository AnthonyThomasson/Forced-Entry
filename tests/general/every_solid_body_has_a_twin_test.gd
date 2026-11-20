extends GameTest
## Every solid 2D body in a built district has a 3D twin (`TwinSpace`, interface 29): the player's
## cone and the AI read the twin space only, so a body on `PhysicsLayers.SOLID` that had no twin
## would block nothing for them while the view still watches it (`ViewWatch`). A wall is a plan
## handle with no engine body, so it is read through the group of walls, not a scan by type.

const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const SEED := 18
const PLAN := ""


func describe() -> Dictionary:
	return {
		"name": "Every solid 2D body of a district has a twin",
		"description": "A generated downtown district (towers, streets, doors, furniture): each "
			+ "2D physics body on the solid layer, and each wall, door and vehicle, has a "
			+ "3D twin that names it.",
		"tags": ["twins", "3d", "district"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED, PLAN)


func run(t: TestContext) -> void:
	await t.frames(3)
	var twinless: Array[String] = []
	var solid := 0
	for body in PlanProbe.bodies_under(t.world):
		if not _is_solid(body):
			continue
		solid += 1
		if TwinSpace.owner_of(TwinSpace.twin_for(body)) != body:
			twinless.append("%s (%s)" % [body.get_path(), body.get_script().resource_path])
	var walls := 0
	for node in NavTwins.walls_under(t.world):
		walls += 1
		if TwinSpace.owner_of(TwinSpace.twin_for(node)) != node:
			twinless.append("%s (a wall)" % node.get_path())
	t.require(walls > 10, "premise: the district has many walls (%d)" % walls)
	t.require(solid > 100, "premise: the district has many solid bodies (%d)" % solid)
	t.expect_eq(twinless.size(), 0, "no solid body is twinless: %s" % [twinless.slice(0, 8)])


## Whether `body` is solid: a door or a vehicle (a plan handle in `TwinSpace.HARD`), or a body on
## `PhysicsLayers.SOLID` with a collision shape that is on (a rug or a mat is a body on the default
## layer with no collider: it blocks nothing in 2D either).
func _is_solid(node: Node2D) -> bool:
	if node.is_in_group(TwinSpace.HARD):
		return not node.is_in_group(TwinSpace.WALLS)  # a wall is counted below
	var body := node as CollisionObject2D
	if body == null or body.collision_layer & PhysicsLayers.SOLID == 0:
		return false
	for owner_id in body.get_shape_owners():
		if (not body.is_shape_owner_disabled(owner_id)
				and body.shape_owner_get_shape_count(owner_id) > 0):
			return true
	return false
