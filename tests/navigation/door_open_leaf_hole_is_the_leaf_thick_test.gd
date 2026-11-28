extends GameTest
## The hole an open leaf leaves in the nav maps is as thick as the leaf (`NavLeaves.hole`, #194).
## The bake's clearance off the hole is the agent's radius (18 px) where the leaf's faces
## need a body's (14 px) and the half of its thickness (3 px): a hole thinner than the leaf leaves
## the margin to the grid. The baker's 4 px cells put a mesh edge up to 3 px nearer than the
## clearance, so a hole 2 px thick left the walkers of `ai/movement/door_ajar_opened_fully` pressed
## against the leaf (14.0 px off); the hole as thick as the leaf keeps them clear of it.
## The hall and bedroom of `door_open_leaf_carved`, the door open.

const HALL := Rect2(0, 0, 400, 400)
const BEDROOM := Rect2(400, 0, 300, 400)
const DOORWAY := Vector2(400, 200)
const HINGE := Vector2(400, 176)
const OPEN := 90.0


func describe() -> Dictionary:
	return {
		"name": "An open door's leaf is carved as thick as the leaf",
		"description": "The hole NavLeaves leaves for a leaf at its open stop is as thick as the "
			+ "leaf and as long, so the bake's clearance off it keeps a body off the leaf's faces "
			+ "on the 4 px grid.",
		"tags": ["navigation", "door", "doorway"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "hall", "type": "hallway", "rect": HALL },
		{ "key": "bedroom", "type": "bedroom", "rect": BEDROOM },
	], [{
		"pos": DOORWAY, "width": 60.0,
		"door": {
			"name": "door", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT,
		},
	}])


func run(t: TestContext) -> void:
	var door: Node = t.object(&"door")
	door.open_fully(null)
	await t.seconds(1.5)
	if not t.require(door.angle() >= OPEN - 1.0, "the door stands open (%.0f)" % door.angle()):
		return
	var hole := NavLeaves.hole(door)
	if not t.require(hole.size() == 4, "the open leaf is carved (%d points)" % hole.size()):
		return
	var size: Vector2 = door.leaf_size()
	t.check(
		(hole[3] - hole[0]).length() >= size.y - 0.01,
		"the hole is as thick as the leaf (%.1f px, the leaf's %.1f)"
			% [(hole[3] - hole[0]).length(), size.y],
	)
	t.check(
		(hole[1] - hole[0]).length() >= size.x - 0.01,
		"the hole is as long as the leaf (%.1f px, the leaf's %.1f)"
			% [(hole[1] - hole[0]).length(), size.x],
	)
