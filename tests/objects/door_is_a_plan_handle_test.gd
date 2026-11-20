extends GameTest
## A house door is a plan handle (#194 del2d-c3, D4, interface 24): a plain `Node2D` in the groups
## `doors`, `TwinSpace.BODIES` and `TwinSpace.HARD`, with no 2D physics body, shape or layer: its
## leaf is the 3D `DoorBody` in the twin space, its footprint when it falls is polygon data on the
## door, and a nav bake and a scan by group find it.

const Probe := preload("res://tests/_general/plan_probe.gd")
const MIDDLE := Vector2(400, 300)
const HINGE := Vector2(400, 280)


func describe() -> Dictionary:
	return {
		"name": "A door is a plain Node2D plan handle",
		"description": "A door is no CollisionObject2D and has no 2D shape; it is in the groups of "
			+ "plan bodies, doors and hard bodies, has a twin, is found by a scan of plan "
			+ "bodies, and a navigation bake lists it.",
		"tags": ["twins", "3d", "door", "del2d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 800) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 800) },
	], [{
		"pos": MIDDLE, "width": 52.0,
		"door": {
			"name": "plan", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT,
		},
	}])


func run(t: TestContext) -> void:
	await t.frames(3)
	var door: Node2D = t.object(&"plan")
	t.check(not door is CollisionObject2D, "the door is no 2D collision object")
	t.check(
		door.find_children("*", "CollisionShape2D", true, false).is_empty(),
		"the door holds no 2D shape",
	)
	for group: StringName in [&"doors", TwinSpace.BODIES, TwinSpace.HARD]:
		t.check(door.is_in_group(group), "the door is in the group %s" % group)
	t.check(not door.is_in_group(TwinSpace.WALLS), "the door is no wall")
	t.check(TwinSpace.twin_for(door) is DoorBody, "a standing door's twin is a DoorBody")
	t.check(Probe.bodies_under(t.world).has(door), "a scan of plan bodies finds the door")
	t.check(
		NavLeaves.doors_of(t.world).has(door),
		"the navigation bake lists the door under its house",
	)
	t.check(door.fallen_footprint().is_empty(), "a standing door has no fallen footprint")
