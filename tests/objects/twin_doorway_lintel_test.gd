extends GameTest
## A doorway's lintel (`ObjectTwins`, interface 29): a wall's twin carries a header over each of its
## doorways, from the door's height to the wall's top, so a doorway is open under 84 px and shut
## above it: a lob that rises through it strikes the lintel, as a real doorway's head does. A ray
## through an open doorway passes at 80 px and strikes the wall at 90 px; the jambs stay solid at
## every height.

const Probe := preload("res://tests/_general/twin_probe.gd")
const Wall := preload("res://scenes/objects/wall/wall.gd")
## The doorway in the wall at x = 400, 52 wide.
const MIDDLE := Vector2(400, 300)
## Just under a door leaf's height, and over it (a leaf is 84, a wall 96).
const UNDER := 80.0
const OVER := 90.0


func describe() -> Dictionary:
	return {
		"name": "A doorway has a lintel from the door's height to the wall's top",
		"description": "Through an open doorway a ray at 80 px passes and one at 90 px strikes the "
			+ "wall (its header); beside the doorway the wall is solid at both heights.",
		"tags": ["twins", "3d", "heights", "door", "wall"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 800) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 800) },
	], [{ "pos": MIDDLE, "width": 52.0 }])


func run(t: TestContext) -> void:
	await t.frames(3)
	var west := MIDDLE + Vector2(-60, 0)
	var east := MIDDLE + Vector2(60, 0)
	t.check(Probe.level(t, west, east, UNDER).is_empty(), "the open doorway is clear at 80 px")
	var head := Probe.level(t, west, east, OVER)
	t.check(not head.is_empty(), "at 90 px the doorway is shut by its lintel")
	t.check(head.get("owner") is Wall, "the lintel belongs to the wall: %s" % head.get("owner"))
	var beside := MIDDLE + Vector2(0, 80)
	for height: float in [UNDER, OVER]:
		t.check(
			not Probe.level(
				t,
				beside + Vector2(-60, 0),
				beside + Vector2(60, 0),
				height,
			).is_empty(),
			"the wall beside the doorway is solid at %.0f px" % height,
		)
