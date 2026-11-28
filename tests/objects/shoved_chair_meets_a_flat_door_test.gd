extends GameTest
## D19 (#194, `docs/doors.md` DR11): a free piece meets what lies flat: a chair shoved at a
## door lying on the floor bumps the leaf (and shoves it along); it does not slide over it or come
## to rest under it. The leaf is on `TWIN_WALKOVER`, which a walker and a car pass; a free piece is
## no walker.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const DOORWAY := Vector2(400, 300)
const HINGE := Vector2(400, 280)
const LIES_AT := Vector2(1000, 500)
## How far west of the leaf's middle the chair starts (px), and the shove (a push impulse) it is
## given east: enough to carry it twice that and more over bare floor.
const CHAIR_FROM := 200.0
const SHOVE := 12_000.0
## How many times it is shoved (a shove carries it about 100 px): enough to take it past the leaf.
const SHOVES := 6
## How far past the leaf's middle the chair may end (px): not at all.
const PAST := 0.0


func describe() -> Dictionary:
	return {
		"name": "A shoved chair meets a door lying flat",
		"description": "An armchair shoved along the floor at a hollow door lying flat in the "
			+ "open stops at the leaf (or shoves it on): it neither passes over it nor ends "
			+ "under it.",
		"tags": ["door", "objects", "3d", "walkover", "pushable"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 800) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 1200, 800) },
	], [{
		"pos": DOORWAY, "width": 52.0,
		"door": {
			"name": "felled", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT,
		},
	}])
	s.object(&"chair", "armchair", LIES_AT - Vector2(CHAIR_FROM, 0.0))


func run(t: TestContext) -> void:
	await t.frames(3)
	var door = t.object(&"felled")
	door.take_blow(&"kick", 1000.0, Vector2.RIGHT * 2200.0, 30.0)
	t.require(door.is_down(), "premise: the kick fells the door")
	t.require(await Probe.settle(t, door, 12.0), "premise: it comes to rest")
	var lead := Probe.body(door)
	lead.global_position = PlanSpace.lift(LIES_AT, 4.0)
	lead.linear_velocity = Vector3.ZERO
	lead.angular_velocity = Vector3.ZERO
	lead.sleeping = false
	t.require(await Probe.settle(t, door, 12.0), "premise: it lies at rest in the open")
	var chair = t.object(&"chair")
	t.require(await Probe.settle(t, chair, 12.0), "premise: the chair stands at rest")
	var leaf: Vector2 = Probe.middle(door)
	for _shove in SHOVES:
		Knockback.push(chair, Vector2(SHOVE, 0.0), Vector2.ZERO, -1.0)
		await t.seconds(0.4)
	t.require(await Probe.settle(t, chair, 12.0), "the chair comes to rest")
	await Probe.settle(t, door, 12.0)
	var now: Vector2 = Probe.middle(door)
	t.check(
		Probe.middle(chair).x < now.x + PAST,
		"the chair stops short of the flat leaf, which is where it lay or shoved on (chair %s, "
		% [Probe.middle(chair).round()] + "leaf %s, it lay at %s)" % [now.round(), leaf.round()],
	)
	t.check(
		Probe.lean(door) > 70.0,
		"and the leaf still lies flat (%.0f degrees)" % Probe.lean(door),
	)
