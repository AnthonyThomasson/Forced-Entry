extends GameTest
## The AI's plan lines (`AgentVision.raycast`, `blocked`, `wall_hit`) are asked of the twin 3D space
## (#194 chars3d-b, interface 29), not the 2D footprints: with every footprint shape off, a line
## along the floor still meets a table and a wall, a line through a doorway at eye height is clear,
## and `wall_hit` looks through furniture but not a wall, as it always did. The 2D space the callers
## hand in is the handle of the world, not the thing asked.

const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const TABLE_AT := Vector2(300, 400)
const DOORWAY_X := 580.0


func describe() -> Dictionary:
	return {
		"name": "The AI's plan lines are asked of the 3D twin space",
		"description": "With the 2D footprints' shapes off, a floor line meets a table, wall_hit "
			+ "meets a wall and not a table, and a line through a doorway is clear.",
		"tags": ["ai", "perception", "vision", "3d"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "north", "type": "living_room", "rect": Rect2(0, 0, 800, 170) },
		{ "key": "south", "type": "bedroom", "rect": Rect2(0, 170, 760, 430) },
	], [{ "pos": Vector2(DOORWAY_X, 170), "width": 52.0 }])
	s.von_down()
	s.object(&"table", "table", TABLE_AT)
	s.actor(&"you", &"puppet", Vector2(100, 500))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var table := t.object(&"table")
	var space: PhysicsDirectSpaceState2D = t.actor(&"you").get_world_2d().direct_space_state
	var vision := AgentVision.new()
	var before := _wall_blocks(vision, space)
	for shape in t.world.find_children("*", "CollisionShape2D", true, false):
		(shape as CollisionShape2D).disabled = true
	await t.frames(2)
	t.require(before, "premise: a wall stopped the line before the footprints went off")
	var across := vision.raycast(space, TABLE_AT + Vector2(-100, 0), TABLE_AT + Vector2(100, 0), [])
	t.check(across.get("collider") == table, "a floor line meets the table by its 3D body")
	t.check(
		vision.blocked(space, TABLE_AT + Vector2(-100, 0), TABLE_AT + Vector2(100, 0), []),
		"and blocked() says so",
	)
	t.check(
		not vision.blocked(space, Vector2(100, 300), Vector2(100, 500), []),
		"a floor line over bare floor is clear",
	)
	t.check(_wall_blocks(vision, space), "wall_hit meets the wall between the rooms")
	t.check(
		vision.wall_hit(space, TABLE_AT + Vector2(-100, 0), TABLE_AT + Vector2(100, 0)).is_empty(),
		"wall_hit looks through the table",
	)
	t.check(
		vision.wall_hit(space, Vector2(DOORWAY_X, 300), Vector2(DOORWAY_X, 100)).is_empty(),
		"a line through the doorway at eye height is clear",
	)


## Whether wall_hit meets the wall between the rooms away from the doorway.
func _wall_blocks(vision: RefCounted, space: PhysicsDirectSpaceState2D) -> bool:
	return not vision.wall_hit(space, Vector2(300, 300), Vector2(300, 100)).is_empty()
