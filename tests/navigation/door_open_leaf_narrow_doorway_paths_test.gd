extends GameTest
## Issue #183 (`docs/doors.md` DR14, ADR 0010): a leaf at its open stop is carved only where the
## doorway past it stays open on the map. Through a doorway too narrow for that, the leaf is left
## out, as a door short of its stop is, and paths go through it as if it were open.
##
## A hand-laid hall and bedroom, the doorway between them 52 px wide (narrower than any a house
## has), its hollow door hinged 6 px in from the north edge of the gap and standing fully open into
## the bedroom. A body passes it (34 px free between the leaf's face and the latch jamb, DR14), but
## the bake's clearance off the leaf and off the latch jamb would meet. Routes from the hall to two
## bedroom points are read on the planning and the steering map.

const DOORWAY := Vector2(400, 200)
const HINGE := Vector2(400, 180)
const FROM := Vector2(300, 200)
const TO := [Vector2(600, 300), Vector2(600, 80)]
## The door's open stop (DR3).
const OPEN := 90.0
## A route longer than this (px) has gone the long way: there is no other way into the bedroom, so
## it is no route through the doorway at all.
const SHORT := 450.0


func describe() -> Dictionary:
	return {
		"name": "A narrow doorway still paths with its door open",
		"description": "A 52 px doorway whose door stands fully open is no wall on the nav maps: "
			+ "routes from the hall reach the bedroom through it.",
		"tags": ["navigation", "door", "doorway"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "hall", "type": "hallway", "rect": Rect2(0, 0, 400, 400) },
		{ "key": "bedroom", "type": "bedroom", "rect": Rect2(400, 0, 300, 400) },
	], [{
		"pos": DOORWAY, "width": 52.0,
		"door": {
			"name": "door", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT, "angle": OPEN,
		},
	}])


func run(t: TestContext) -> void:
	var door: Node = t.object(&"door")
	if not t.require(door.angle() >= OPEN - 1.0, "the door stands open (%.0f)" % door.angle()):
		return
	await t.seconds(0.5)
	var planning: RID = t.world.get_world_2d().navigation_map
	var maps := { "planning": planning, "steering": NavBuilder.steering_map(planning) }
	for name in maps:
		for to in TO:
			var path := NavBuilder.route(maps[name], FROM, to)
			var length := NavBuilder.path_length(path)
			t.check(
				length < SHORT and path[path.size() - 1].distance_to(to) < 2.0,
				"the %s map paths through the doorway to %s (%.0f px, ends %s)"
					% [name, to, length, path[path.size() - 1].round()],
			)
