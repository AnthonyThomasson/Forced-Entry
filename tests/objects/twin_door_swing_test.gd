extends GameTest
## A door's twin (`ObjectTwins`, interface 29): a leaf 84 px tall that turns with the door about
## its hinge. A door swung open is followed frame by frame (its twin's pose is the leaf's of the
## frame it is read or the one before: the door turns in its own script, after the twin is synced),
## a ray dropped on the open leaf lands at 84 and names the door, and the doorway where the shut
## leaf stood is open to a ray at 80 px.

const Probe := preload("res://tests/_general/twin_probe.gd")
## The doorway in the wall at x = 400, 52 wide, the hinge 20 px from its middle.
const MIDDLE := Vector2(400, 300)
const HINGE := Vector2(400, 280)
## A door leaf's height (px).
const LEAF := 84.0


func describe() -> Dictionary:
	return {
		"name": "A door's twin is a leaf 84 px tall that swings with it",
		"description": "A shut door's twin stops a ray at 80 px in its doorway; swung open, "
			+ "its twin has the leaf's pose (at most a frame old) all through the swing, a ray "
			+ "on the open leaf lands at 84 and names the door, and the doorway it left is clear.",
		"tags": ["twins", "3d", "heights", "door"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 800) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 800) },
	], [{
		"pos": MIDDLE, "width": 52.0,
		"door": {
			"name": "swing", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT,
		},
	}])


func run(t: TestContext) -> void:
	await t.frames(3)
	var door: Node2D = t.object(&"swing")
	var shut := Probe.level(t, MIDDLE + Vector2(-60, 0), MIDDLE + Vector2(60, 0), 80.0)
	t.check(shut.get("owner") == door, "a shut door's twin stops a ray at 80 px in the doorway")
	door.toggle(null)
	var off := 0
	var mid := 0
	var previous := door.global_transform
	for i in 120:
		await t.frames(1)
		var twin: Node3D = t.world.twin_space().twin_of(door)
		if not _at(twin, door.global_transform) and not _at(twin, previous):
			off += 1
		previous = door.global_transform
		if door.angle() > 20.0 and door.angle() < door.open_angle - 20.0:
			mid += 1
		if not door.swing.moving() and i > 10:
			break
	t.require(mid >= 3, "premise: the door was seen swinging (%d frames mid-swing)" % mid)
	t.expect_eq(
		off,
		0,
		"the twin had the leaf's pose, at most a frame old, every frame of the swing",
	)
	await t.frames(3)
	t.check(_at(t.world.twin_space().twin_of(door), door.global_transform), "at rest it is exact")
	var leaf := door.global_position
	var hit := Probe.down(t, leaf)
	t.check(hit.get("owner") == door, "a ray dropped on the open leaf names the door")
	t.expect_near(Probe.top_at(t, leaf), LEAF, 0.5, "the leaf is 84 px tall")
	t.check(
		Probe.level(t, MIDDLE + Vector2(-60, 0), MIDDLE + Vector2(60, 0), 80.0).is_empty(),
		"the doorway the leaf left is clear at 80 px",
	)


## Whether `twin` stands where a leaf of 2D transform `xf` does.
func _at(twin: Node3D, xf: Transform2D) -> bool:
	var plan := PlanSpace.plan_transform(twin.global_transform)
	return (
		plan.origin.distance_to(xf.origin) < 0.01
		and absf(angle_difference(plan.get_rotation(), xf.get_rotation())) < 0.001
	)
