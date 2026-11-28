extends GameTest
## D18 (#194): a door that lies on the floor is a real object at its lying height: a level
## line at a leaf's thickness meets it (a round is stopped or slowed by its material: the owner of
## the hit is the door), one a hand above passes. Kicked down from the west it lies east.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const Twins := preload("res://tests/_general/twin_probe.gd")
const DOORWAY := Vector2(400, 300)
const HINGE := Vector2(400, 280)
const KICK_IMPULSE := 2200.0
const KICK_HEIGHT := 30.0
## Heights (px) a line is flown at: inside a leaf lying flat, and clear above it.
const LOW := 2.5
const HIGH := 20.0


func describe() -> Dictionary:
	return {
		"name": "A fallen door stops bullets at its lying height",
		"description": "A hollow door kicked down from the west lies east, flat; a level line at "
			+ "the height of its thickness meets it, one 20 px up passes over.",
		"tags": ["door", "objects", "3d", "cover", "projectile"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 800) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 800) },
	], [{
		"pos": DOORWAY, "width": 52.0,
		"door": {
			"name": "felled", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT,
		},
	}])
	s.von_down()


func run(t: TestContext) -> void:
	await t.frames(3)
	var door = t.object(&"felled")
	door.take_blow(&"kick", 1000.0, Vector2.RIGHT * KICK_IMPULSE, KICK_HEIGHT)
	t.require(door.is_down(), "premise: the kick fells it")
	t.require(await Probe.settle(t, door, 12.0), "premise: it comes to rest")
	var at: Vector2 = Probe.middle(door)
	# along the line across the door's middle, from far each side
	var low := _ray(t, at, LOW)
	t.check(
		low.get("owner") == door,
		"a line at %.1f px meets the fallen door (hit %s)" % [LOW, str(low.get("owner"))],
	)
	var high := _ray(t, at, HIGH)
	t.check(
		high.get("owner") != door,
		"a line at %.0f px passes over it (hit %s)" % [HIGH, str(high.get("owner"))],
	)
	t.check(
		absf(Twins.top_at(t, at) - Probe.top(door)) < 1.0 and Probe.top(door) < HIGH,
		"a ray dropped on its middle lands at its lying top (%.1f px)" % Twins.top_at(t, at),
	)


## The level line at `height` through the door's middle `at`, across the way it fell.
static func _ray(t: TestContext, at: Vector2, height: float) -> Dictionary:
	return Probe.ray_level(t, at - Vector2(120, 0), at + Vector2(120, 0), height)
