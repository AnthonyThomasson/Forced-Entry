extends GameTest
## D19 (#194, `docs/doors.md` DR11): a door lying flat is on `TWIN_WALKOVER`: no walker and
## no vehicle meets it, but a line and what lands on it do, where it lies at its lying
## height. One probe per reader of the layer: the sight ray, the barrel's ray, a
## dropped item, a casing's or a chip's flight (`PhysicsConfig.twin_mask`); and what must NOT meet
## it: a car driven over it (no touch, no crash, the leaf unmoved) and a car's door beside it.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const BodySweep := preload("res://scenes/character/body/body_sweep.gd")
const DOORWAY := Vector2(400, 300)
const HINGE := Vector2(400, 280)
## Where the leaf is carried to, in the open room: clear of the walls, with the car's run beside.
const LIES_AT := Vector2(1000, 500)
const KICK_IMPULSE := 2200.0
const KICK_HEIGHT := 30.0
## A line's height (px): within the leaf's thickness.
const LOW := 3.0
## The lowest a thing resting on the leaf may lie (px): its top, 6 px, less a margin.
const ON_TOP := 3.0
## The most a leaf lying flat may stand (px): a step over (`DoorFallConfig.step_over`).
const FLAT := 10.0
## How far (px) a line's ends stand from the leaf's middle.
const REACH := 120.0


func describe() -> Dictionary:
	return {
		"name": "A flat door is met by lines and what lands on it, not by a car",
		"description": "A hollow door lying flat in the open: a sight line at its thickness, a "
			+ "barrel's ray, a dropped item, a casing's flight meet it and "
			+ "rest on it; a car driven across it neither touches nor crashes into it and its "
			+ "door opens over it.",
		"tags": ["door", "objects", "3d", "walkover", "vehicle"],
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
	s.actor(&"npc", &"puppet", Vector2(100, 700))
	s.vehicle(&"car", &"car", Vector2(1300, 700))
	s.actor(&"me", &"puppet", Vector2(150, 750))
	s.von_down()


func run(t: TestContext) -> void:
	await t.frames(3)
	var door = t.object(&"felled")
	door.take_blow(&"kick", 1000.0, Vector2.RIGHT * KICK_IMPULSE, KICK_HEIGHT)
	t.require(door.is_down(), "premise: the kick fells the door")
	t.require(await Probe.settle(t, door, 12.0), "premise: it comes to rest")
	await _carried_to(t, door, LIES_AT)
	t.require(await Probe.settle(t, door, 12.0), "premise: it lies at rest in the open")
	t.require(
		Probe.top(door) < FLAT, "premise: it lies flat (top %.1f px)" % Probe.top(door)
	)
	var at: Vector2 = Probe.middle(door)
	var space: PhysicsDirectSpaceState3D = t.world.twin_space().space()
	_sight(t, space, door, at)
	_barrel(t, at)
	await _dropped(t, at)
	await _chip(t, space, at)
	await _car_over(t, door)


## Carry the lying leaf to plan point `to` (a test's hand, not a game path): set down above it.
func _carried_to(t: TestContext, door: Node2D, to: Vector2) -> void:
	var lead := Probe.body(door)
	lead.global_position = PlanSpace.lift(to, 4.0)
	lead.linear_velocity = Vector3.ZERO
	lead.angular_velocity = Vector3.ZERO
	lead.sleeping = false
	await t.frames(2)


## The sight ray (`SightRay`) at the leaf's thickness is stopped by it, from either side.
func _sight(t: TestContext, space: PhysicsDirectSpaceState3D, door: Node2D, at: Vector2) -> void:
	for side: float in [-1.0, 1.0]:
		var found := SightRay.hit(
			space, PlanSpace.lift(at + Vector2(0.0, REACH * side), LOW), PlanSpace.lift(at, LOW)
		)
		t.check(
			not found.is_empty() and TwinSpace.owner_of(found["collider"]) == door,
			"a sight line at %.0f px meets the flat leaf from the %s (hit %s)"
				% [LOW, "north" if side < 0.0 else "south", str(found.get("collider"))],
		)


## A weapon's barrel (`BodySweep.solid_distance`) held at the leaf's thickness is stopped by it.
func _barrel(t: TestContext, at: Vector2) -> void:
	var sweep := BodySweep.new(t.actor(&"me"))
	var from := at + Vector2(0.0, -REACH)
	var reach := sweep.solid_distance(from, Vector2.DOWN, 2.0 * REACH, LOW)
	t.check(
		reach < REACH + 1.0,
		"a barrel at %.0f px is stopped at the flat leaf (%.0f of %.0f px)" % [LOW, reach, REACH],
	)


## A dropped item let go over the leaf lies on it, not under it.
func _dropped(t: TestContext, at: Vector2) -> void:
	var item := DroppedItem.spawn(ItemRegistry.create(6), 0.0, Vector2.ZERO)
	item.place(t.world, at, at)
	await t.seconds(2.0)
	t.check(
		item.altitude() > ON_TOP,
		"a dropped item lies on the flat leaf (%.1f px up), not under it" % item.altitude(),
	)
	item.queue_free()


## A chip's, a casing's flight (`PhysicsConfig.twin_mask`: what debris, casings and blood land on)
## lands on the leaf.
func _chip(t: TestContext, space: PhysicsDirectSpaceState3D, at: Vector2) -> void:
	var flight := SmallFlight.new(3.0)
	flight.mask = PhysicsConfig.twin_mask
	flight.place(at, 30.0)
	for _frame in 240:
		if flight.resting:
			break
		flight.step(space, 1.0 / 60.0)
		await t.frames(1)
	t.check(
		flight.altitude() > ON_TOP,
		"a chip let fall on the flat leaf rests on it (%.1f px up)" % flight.altitude(),
	)


## A car driven across the flat leaf neither crashes into it nor shoves it, and a door of the car
## standing over it opens (it is no obstacle).
func _car_over(t: TestContext, door: Node2D) -> void:
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me")
	var lay: Vector2 = Probe.middle(door)
	var door_spot: Vector2 = car.cabin.door(&"front_left").stand_point(me.radius)
	car.global_position = lay - door_spot
	car.rotation = 0.0
	await t.frames(5)
	me.global_position = car.to_global(door_spot) + Vector2(0.0, 40.0)
	await t.frames(3)
	t.check(
		car.can_board(me, &"front_left"),
		"the car's door, its stand point over the flat leaf, is not held shut by it",
	)
	var starter := t.events_of(&"vehicle", func(d): return d.get("stage") == &"crash").size()
	car.global_position = lay + Vector2(-260.0, 0.0)
	await t.frames(2)
	Probe.body(car).linear_velocity = Vector3(300.0 * RenderConfig.unit, 0.0, 0.0)
	var crossed := await t.until(func(): return car.global_position.x > lay.x + 60.0, 4.0)
	t.check(crossed, "the car rolls on over the leaf (at %s)" % car.global_position)
	var crashes := t.events_of(&"vehicle", func(d): return d.get("stage") == &"crash").size()
	t.check(crashes == starter, "no crash is posted against the flat leaf")
	t.check(
		Probe.middle(door).distance_to(lay) < 5.0,
		"the car does not shove the leaf (%.1f px)" % Probe.middle(door).distance_to(lay),
	)
