extends GameTest
## D18 (#194, `docs/doors.md` DR11): a door that falls onto something does not lie flat:
## a hollow door kicked down toward a wardrobe standing close beyond the doorway tops over onto it
## and rests leaning, higher than a step over (`DoorFallConfig.step_over`): its footprint is a solid
## collider (an obstacle), and the nav map, re-baked, has a hole where it leans.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const DOORWAY := Vector2(400, 300)
const HINGE := Vector2(400, 280)
## Close beyond the doorway, in the way of the falling leaf.
const WARDROBE_AT := Vector2(440, 300)
const KICK_IMPULSE := 4000.0
const WAIT := 12.0


func describe() -> Dictionary:
	return {
		"name": "A door that falls onto a wardrobe rests leaning, an obstacle",
		"description": "A hollow door kicked down toward a wardrobe close beyond the doorway "
			+ "rests leaning on it: its top above a step over, its footprint solid, a hole in "
			+ "the re-baked nav map.",
		"tags": ["door", "objects", "3d", "tipping", "navigation"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 600) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 600) },
	], [{
		"pos": DOORWAY, "width": 52.0,
		"door": {
			"name": "felled", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT,
		},
	}])
	s.object(&"wardrobe", "wardrobe", WARDROBE_AT)
	s.switch(&"nav.rebake", true)
	s.von_down()


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var door = t.object(&"felled")
	door.take_blow(&"kick", 1000.0, Vector2.RIGHT * KICK_IMPULSE, 40.0)
	t.require(door.is_down(), "premise: the door is felled")
	t.require(await Probe.settle(t, door, WAIT), "premise: it comes to rest")
	t.check(
		Probe.top(door) > DoorFallConfig.step_over,
		"it rests leaning: its top is %.1f px (lean %.0f)" % [Probe.top(door), Probe.lean(door)],
	)
	var ring: PackedVector2Array = door.fallen_footprint()
	t.check(not ring.is_empty(), "its footprint is an obstacle")
	t.check(not door.footprint.flat, "it does not lie flat: an obstacle characters meet")
	if ring.is_empty():
		return
	var middle := Vector2.ZERO
	for corner in ring:
		middle += corner / ring.size()
	var region: NavigationRegion3D = t.world.find_children(
		"NavRegion", "NavigationRegion3D", true, false,
	)[0]
	var map := region.get_navigation_map()
	t.check(
		await t.until(
			func() -> bool: return NavBuilder.snap(map, middle).distance_to(middle) > 5.0, WAIT,
		),
		"and the nav map, re-baked, has a hole where it leans (%s)" % middle.round(),
	)
