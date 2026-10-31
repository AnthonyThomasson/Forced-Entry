extends GameTest
## A door is left out of both nav bakes (the planning map and the steering map): a shut door stands
## in its doorway, a driven body the static-collider parse would carve into the map as a wall, yet
## paths go through the doorway as if it were open, so the AI can walk up to the door, open it and
## go on (`docs/doors.md` DR5). Nothing in Navigation names the door: it is found by the group
## `doors`.

const FROM := Vector2(100, 150)
const TO := Vector2(700, 150)
const JAMB := 20.0


func describe() -> Dictionary:
	return {
		"name": "A shut door is not baked into the nav maps",
		"description": "Two rooms share a doorway with a shut door in it: the planning and the "
			+ "steering map both path from one room to the other through it.",
		"tags": ["navigation", "door", "doorway"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 300) },
		{ "key": "east", "type": "kitchen", "rect": Rect2(400, 0, 400, 300) },
	], [{
		"pos": Vector2(400, 150), "width": 52.0,
		"door": {
			"name": "door", "material": "hollow", "style": "flush",
			"hinge": Vector2(400, 150 - JAMB), "swing_into": Vector2.RIGHT,
		},
	}])


func run(t: TestContext) -> void:
	await t.seconds(0.3)
	if not t.require(t.object(&"door") != null, "the door stands in the doorway"):
		return
	var planning := t.world.get_world_2d().navigation_map
	for map in [planning, NavBuilder.steering_map(planning)]:
		var name := "planning" if map == planning else "steering"
		var path := NavigationServer2D.map_get_path(map, FROM, TO, false)
		t.check(
			not path.is_empty() and path[path.size() - 1].x > TO.x - 20.0,
			"the %s map paths through the shut door's doorway (ends at x=%.0f)"
				% [name, path[path.size() - 1].x if not path.is_empty() else 0.0],
		)
