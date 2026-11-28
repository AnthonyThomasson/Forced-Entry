extends GameTest
## D12 (#194): a small flight that looks ahead for a clear corridor and then moves by arithmetic
## flies exactly as one that sweeps the space every frame. Many seeded flights are thrown about a
## room with a desk, a sofa and a fridge in it, in pairs (one looking ahead, one not); frame by
## frame the pair stays together, event for event, and both end in the same place.

const SEED := 20_260_513
const FLIGHTS := 120
const FRAMES := 150
const DELTA := 1.0 / 60.0
## How far two flights of a pair may drift apart (px): none, bar the last bit of a float.
const SAME := 0.001
## A premise: at least this share of the flights ran some frames with no sweep.
const MOST_CORRIDOR := 0.3
## The pieces in the way, and the arena they stand in.
const ROOM := Rect2(0, 0, 700, 500)
const PIECES := [
	[&"desk", "desk", Vector2(250, 150)],
	[&"sofa", "sofa", Vector2(500, 320)],
	[&"fridge", "fridge", Vector2(150, 400)],
]


func describe() -> Dictionary:
	return {
		"name": "A flight's look-ahead corridor flies as the plain sweep does",
		"description": "Seeded small flights thrown about a room with a desk, a sofa and a fridge, "
			+ "each twice (one looking ahead for a clear corridor, one sweeping every frame): "
			+ "they stay together frame by frame, event for event.",
		"tags": ["physics", "3d", "flight", "furniture", "wall"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ROOM)
	s.switch(&"nav.rebake", false)
	for piece in PIECES:
		s.object(piece[0], piece[1], piece[2])


func run(t: TestContext) -> void:
	await t.frames(3)
	var space := TwinSpace.space_of(t.world)
	if not t.require(space != null, "premise: the room has a twin space"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var apart := 0
	var corridor := 0
	var events := 0
	for k in FLIGHTS:
		var result := _fly_pair(space, rng)
		apart += int(result["apart"])
		corridor += int(result["corridor"])
		events += int(result["events"])
	t.expect_eq(apart, 0, "no flight drifts from its plain twin (%d of %d did)" % [apart, FLIGHTS])
	t.check(
		float(corridor) >= MOST_CORRIDOR * FLIGHTS,
		"premise: %d of %d flights ran frames with no sweep" % [corridor, FLIGHTS],
	)
	t.check(events > FLIGHTS, "premise: the flights bounced and struck (%d events)" % events)
	_check_place_ends_corridor(t, space)


## One seeded throw flown twice in lockstep: `{apart, corridor, events}` (1 or 0 for the first two).
func _fly_pair(space: PhysicsDirectSpaceState3D, rng: RandomNumberGenerator) -> Dictionary:
	var throw := _throw(rng)
	var looking := _flight(throw)
	var plain := _flight(throw)
	plain.get(&"_probe").look = false
	var result := { "apart": 0, "corridor": 0, "events": 0 }
	for _frame in FRAMES:
		var a := looking.step(space, DELTA)
		var b := plain.step(space, DELTA)
		if looking.get(&"_probe").frames > 0:
			result["corridor"] = 1
		result["events"] = int(result["events"]) + (1 if a != SmallFlight.NONE else 0)
		var gap := looking.at.distance_to(plain.at) + absf(looking.height - plain.height)
		if a != b or gap > SAME or looking.resting != plain.resting:
			result["apart"] = 1
			break
	return result


## A seeded throw: where from, how high, how fast and which way, how hard up, how big a sphere.
func _throw(rng: RandomNumberGenerator) -> Dictionary:
	return {
		"at": Vector2(rng.randf_range(40.0, 660.0), rng.randf_range(40.0, 460.0)),
		"height": rng.randf_range(4.0, 40.0),
		"velocity": Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, 420.0),
		"rise": rng.randf_range(0.0, 260.0),
		"radius": [1.2, 1.5, 3.0][rng.randi_range(0, 2)],
	}


func _flight(throw: Dictionary) -> SmallFlight:
	var flight := SmallFlight.new(throw["radius"])
	flight.mask = PhysicsConfig.twin_mask
	flight.place(throw["at"], throw["height"])
	flight.velocity = throw["velocity"]
	flight.rise = throw["rise"]
	return flight


## A flight set down somewhere else has not looked the way over: `place` ends the corridor.
func _check_place_ends_corridor(t: TestContext, space: PhysicsDirectSpaceState3D) -> void:
	var flight := _flight({
		"at": Vector2(60, 60), "height": 30.0, "velocity": Vector2(200.0, 0.0),
		"rise": 100.0, "radius": 1.5,
	})
	flight.step(space, DELTA)
	t.check(flight.get(&"_probe").frames > 0, "premise: the flight looked its way over")
	flight.place(Vector2(320, 240), 30.0)
	t.expect_eq(flight.get(&"_probe").frames, 0, "placing a flight ends its corridor")
