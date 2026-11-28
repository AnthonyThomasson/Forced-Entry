extends GameTest
## Performance guard (#194, D13): a fleet of cars and vans on a lot with furniture and a crowd,
## rolled at staggered speeds so the rear ones run into the front ones and into the furniture, one
## of them driven by a seated puppet with its engine on. A vehicle is a 3D body (the truth) with a
## plan-space handle written from it each frame, so what it costs is the body and its strike
## queries. The rolling frames hold the frame standard. The crowd and the furniture cost most of a
## frame, whatever the vehicles do, so the vehicles also have a budget of their own: what a frame
## costs over the same lot standing idle (the fleet asleep), at most `EXTRA_MS` (a quiet machine
## measures a fraction of it, so several times the fleet's cost fails). It is not an A/B: a change's
## cost against the revision before is `tools/perf_ab.sh` (this test copied into that tree), when
## the machine is quiet.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")
const ROWS := 6
const COLUMNS := 4
const CROWD := 24
const MOVING_FRAMES := 240
const RESTING_FRAMES := 60
## The rolling speed of the rearmost column (px/s); each column in front rolls this much slower.
const ROLL := 900.0
const SLOWER := 250.0
## What the fleet may add to a frame over the idle lot (ms per frame).
const EXTRA_MS := 4.0
const IDLE_FRAMES := 120


func describe() -> Dictionary:
	return {
		"name": "A fleet of rolling vehicles among furniture and a crowd stays cheap",
		"description": "24 cars and vans roll at staggered speeds into each other, furniture and "
			+ "a crowd, one driven with its engine on; frame cost while they roll and once they "
			+ "stop costs little over the idle lot, with no node growth once they rest.",
		"tags": ["vehicle", "rigid body", "3d", "furniture"],
		"timeout": 40.0,
	}


func _id(i: int) -> StringName:
	return StringName("v%d" % i)


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 6000, 2600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	for i in ROWS * COLUMNS:
		var at := Vector2(300 + (i % COLUMNS) * 600, 250 + int(i / float(COLUMNS)) * 380)
		s.vehicle(_id(i), &"car" if i % 3 != 0 else &"van", at)
	for row in ROWS:
		s.object(StringName("sofa%d" % row), "sofa", Vector2(2900, 250 + row * 380))
		s.object(StringName("chair%d" % row), "chair", Vector2(3300, 250 + row * 380))
	for c in CROWD:
		s.actor(
			StringName("c%d" % c), &"puppet",
			Vector2(3700 + (c % 4) * 90, 250 + int(c / 4.0) * 380),
			{ "max_health": 1_000_000.0 },
		)
	s.actor(&"driver", &"puppet", Vector2(100, 2500))


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	# the crowd's places are the fight's fingerprint (`tools/perf_ab.sh` checks a revision replays
	# its own run)
	var crowd: Array = []
	for c in CROWD:
		crowd.append(t.actor(StringName("c%d" % c)))
	Perf.record_fight(t, self, crowd)
	await t.seconds(0.5)
	if not await VehicleRide.board_by(t, &"driver", t.vehicle(_id(0)) as Node2D, &"front_left"):
		t.check(false, "the driver gets into the first vehicle")
		return
	await t.seconds(0.5)
	var idle := await Perf.frame_stats(t, IDLE_FRAMES)
	GameLog.say("PERF vehicle lot idle avg ms/frame %.2f" % idle["avg_ms"])
	var starts: Array[Vector2] = []
	for i in ROWS * COLUMNS:
		var v := t.vehicle(_id(i)) as Node2D
		starts.append(v.global_position)
		if i != 0:
			v.set("linear_velocity", Vector2(ROLL - (i % COLUMNS) * SLOWER, 0.0))
	t.puppet(&"driver").drive(1.0, 0.0, false)
	var moving := await Perf.frame_stats(t, MOVING_FRAMES)
	_report_rolling(t, moving, idle)
	var travelled := 0.0
	for i in ROWS * COLUMNS:
		travelled += (t.vehicle(_id(i)) as Node2D).global_position.distance_to(starts[i])
	t.check(
		travelled / (ROWS * COLUMNS) > 100.0,
		"the fleet rolled (avg %.1f px)" % (travelled / (ROWS * COLUMNS)),
	)
	t.puppet(&"driver").drive(0.0, 0.0, false)
	# they coast to a stop, a long way (rolling resistance is light), packed among the crowd
	await t.seconds(12.0)
	var nodes_before := Perf.nodes()
	var resting := await Perf.frame_stats(t, RESTING_FRAMES)
	Perf.within(
		t,
		"vehicle fleet resting avg ms/frame over the idle lot",
		resting["avg_ms"] - idle["avg_ms"],
		EXTRA_MS,
	)
	var grown := Perf.nodes() - nodes_before
	GameLog.say("PERF vehicle fleet node growth %d" % grown)
	t.check(grown <= 2, "a resting fleet neither spawns nor leaks nodes (grew by %d)" % grown)


## Report the rolling phase: the lines `tools/perf_ab.sh` reads, held to the frame standard, and
## what the fleet adds over the idle lot, held to `EXTRA_MS`.
func _report_rolling(t: TestContext, moving: Dictionary, idle: Dictionary) -> void:
	Perf.report_worst("vehicle fleet rolling", moving)
	Perf.within(t, "vehicle fleet rolling avg ms/frame", moving["avg_ms"], Perf.SMOOTH_AVG_MS)
	Perf.within(t, "vehicle fleet rolling p95 ms/frame", moving["p95_ms"], Perf.SMOOTH_P95_MS)
	Perf.within(t, "vehicle fleet rolling max ms/frame", moving["max_ms"], Perf.SMOOTH_MAX_MS)
	Perf.within(
		t,
		"vehicle fleet rolling avg ms/frame over the idle lot",
		moving["avg_ms"] - idle["avg_ms"],
		EXTRA_MS,
	)
