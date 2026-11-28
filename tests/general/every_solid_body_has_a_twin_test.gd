extends GameTest
## Every solid plan handle in a built district has a 3D twin (`TwinSpace`, interface 29): the
## player's cone and the AI read the twin space only, so a handle with no twin would block nothing
## for them while the view still watches it (`ViewWatch`). A wall is read through the group of
## walls, a piece through the group of pieces, a door or a vehicle through the group of hard ones.

const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const SEED := 18
const PLAN := ""


func describe() -> Dictionary:
	return {
		"name": "Every solid plan handle of a district has a twin",
		"description": "A generated downtown district (towers, streets, doors, furniture): each "
			+ "solid piece, wall, door and vehicle has a 3D twin that names it.",
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
	for piece in PlanProbe.pieces_under(t.world):  # a piece is a plan handle, no 2D body
		if not piece.solid:
			continue
		solid += 1
		if TwinSpace.owner_of(TwinSpace.twin_for(piece)) != piece:
			twinless.append("%s (a piece)" % piece.get_path())
	var walls := 0
	for node in NavTwins.walls_under(t.world):
		walls += 1
		if TwinSpace.owner_of(TwinSpace.twin_for(node)) != node:
			twinless.append("%s (a wall)" % node.get_path())
	t.require(walls > 10, "premise: the district has many walls (%d)" % walls)
	t.require(solid > 100, "premise: the district has many solid bodies (%d)" % solid)
	t.expect_eq(twinless.size(), 0, "no solid body is twinless: %s" % [twinless.slice(0, 8)])


## Whether `body` is solid here: a door or a vehicle (a plan handle in `TwinSpace.HARD`; a wall is
## counted below).
func _is_solid(node: Node2D) -> bool:
	return node.is_in_group(TwinSpace.HARD) and not node.is_in_group(TwinSpace.WALLS)
