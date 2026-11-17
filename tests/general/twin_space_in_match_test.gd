extends GameTest
## The twin space in a match (`MatchBuilder.stage`, interface 29): a match declared on a generated
## house, headless, has a 3D twin of each of its walls, doors, floors, solid pieces of furniture and
## characters (the NPCs the match spawns after the stage included), exactly one each, in the space
## the match handle names, and a ray dropped on a combatant lands on its capsule.

const Probe := preload("res://tests/_general/twin_probe.gd")
const SEED := 18
const ENTRANCE := Vector2(440, 350)


func describe() -> Dictionary:
	return {
		"name": "A match has a twin for every wall, door, floor, solid piece and character",
		"description": "A match on a generated house, headless: the stage's twin space (named by "
			+ "the match handle) holds exactly one twin per wall, door, floor, solid piece and "
			+ "character, each naming its body, and a ray over a combatant lands on it.",
		"tags": ["twins", "3d", "match", "setup"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED, "", ENTRANCE)
	s.von_down()
	s.declared_match({ "defenders": { "count": 2 }, "invaders": { "count": 2 } })


func run(t: TestContext) -> void:
	await t.frames(3)
	var twins := Probe.twins(t)
	var handle: Dictionary = t.world.match_handle
	t.require(
		twins != null and handle.get("twins") == twins,
		"the match handle names the twin space",
	)
	var bodies := _bodies(t)
	var kinds := _kinds(bodies)
	t.require(
		kinds.get("wall", 0) > 0 and kinds.get("door", 0) > 0 and kinds.get("piece", 0) > 10,
		"premise: the house has walls, doors and furniture %s" % kinds,
	)
	t.expect_eq(kinds.get("character", 0), 4, "premise: four combatants")
	var missing := 0
	for body in bodies:
		if TwinSpace.owner_of(twins.twin_of(body)) != body:
			missing += 1
	t.expect_eq(missing, 0, "every body has a twin that names it")
	t.expect_eq(twins.count, bodies.size(), "and nothing else has one")
	var combatant: Node2D = handle["combatants"][0]
	var hit := Probe.down(t, combatant.global_position, PhysicsLayers.TWIN_CHARACTER)
	t.check(hit.get("owner") == combatant, "a ray over a combatant lands on its capsule")


## Every solid body of the match world: walls, doors, floors, solid pieces and characters.
func _bodies(t: TestContext) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for node in t.world.find_children("*", "PhysicsBody2D", true, false):
		var body := node as Node2D
		if _kind(body) != "":
			out.append(body)
	for floor_node in t.world.get_tree().get_nodes_in_group(&"floors"):
		if t.world.is_ancestor_of(floor_node):
			out.append(floor_node as Node2D)
	return out


## What `body` is, "" for a body with no twin (a part of a body, a non-solid piece).
func _kind(body: Node2D) -> String:
	if body.get("wall_thickness") != null:
		return "wall"
	if body.is_in_group(&"doors"):
		return "door"
	if body.is_in_group(&"characters"):
		return "character"
	if body.get("solid") == true and body.get("shape_type") != null:
		return "piece"
	return ""


## How many bodies of each kind there are.
func _kinds(bodies: Array[Node2D]) -> Dictionary:
	var out := {}
	for body in bodies:
		var kind := _kind(body) if body is PhysicsBody2D else "floor"
		out[kind] = out.get(kind, 0) + 1
	return out
