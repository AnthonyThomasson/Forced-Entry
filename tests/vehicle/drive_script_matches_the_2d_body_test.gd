extends GameTest
## V5 (#194, D13): the vehicle is a 3D body now, and it must drive as the 2D body did. A
## fixed input script (full throttle, then full throttle with the wheel hard over, a coast, then the
## brakes) is driven by a car and by a van, and the path (position and heading) and the speed are
## compared with what the 2D rigid body did on the same script (`EXPECTED`), within
## `PATH_TOLERANCE` / `HEADING_TOLERANCE` / `SPEED_TOLERANCE`. The 3D body is read, not its 2D
## footprint (which trails it by a frame), at the same frame the 2D body was read at.
##
## How `EXPECTED` was recorded: this test, with `EXPECTED` empty (it prints `RECORDED` and the
## samples), run on the commit before the vehicle was replaced (the 2D rigid body of that
## commit, whose `global_position`, `global_rotation` and `speed()` it read the same way): the
## numbers are what that body did, not what the 3D body does. This same file, run on `967409b3` (the
## 2D body), also passes against the table within the same tolerances.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")
## How far (px) the path may be from the 2D body's at a sample, and how far (px/s, and as a share of
## the speed) the speed may.
const PATH_TOLERANCE := 3.0
const SPEED_TOLERANCE := 3.0
const SPEED_SHARE := 0.02
## The heading's tolerance (rad).
const HEADING_TOLERANCE := 0.01
## The script: [seconds from its start, throttle, steer] each held until the next row.
const SCRIPT := [[0.0, 1.0, 0.0], [1.5, 1.0, 1.0], [3.0, 0.0, 0.0], [4.0, -1.0, 0.0]]
## How long it runs and how often it is sampled (s).
const RUN := 5.5
const EVERY := 0.5
## The 2D body's samples from the start of the script, per kind: [x, y, heading, speed] each
## EVERY s.
const EXPECTED := {
	&"car":
		[
			[0.0, 0.0, 0.0, 0.0],
			[116.2, 0.0, 0.0, 461.1],
			[443.6, 0.0, 0.0, 842.7],
			[930.3, 0.0, 0.0, 1087.5],
			[1489.6, 70.5, 0.232, 1169.3],
			[2040.1, 295.7, 0.492, 1213.2],
			[2529.4, 661.8, 0.745, 1235.6],
			[2959.3, 1088.6, 0.782, 1186.5],
			[3372.2, 1498.7, 0.782, 1140.2],
			[3689.2, 1813.4, 0.782, 696.2],
			[3859.8, 1982.9, 0.782, 252.5],
		],
	&"van":
		[
			[0.0, 0.0, 0.0, 0.0],
			[61.2, 0.0, 0.0, 243.8],
			[237.3, 0.0, 0.0, 462.8],
			[513.2, 0.0, 0.0, 637.4],
			[850.8, 30.9, 0.141, 718.6],
			[1211.9, 125.5, 0.303, 774.1],
			[1575.3, 282.7, 0.455, 809.7],
			[1927.4, 468.3, 0.483, 781.4],
			[2267.4, 646.8, 0.483, 754.2],
			[2537.4, 788.6, 0.483, 500.3],
			[2703.9, 876.0, 0.483, 244.2],
		],
}
const START := { &"car": Vector2(400, 500), &"van": Vector2(400, 2600) }


func describe() -> Dictionary:
	return {
		"name": "A car and a van drive a fixed input script as the 2D body did",
		"description": "Throttle, then the wheel hard over, a coast and the brakes: the path, the "
			+ "heading and the speed at each half second stay within a few px / a few percent of "
			+ "what the 2D rigid body did on the same input.",
		"tags": ["vehicle", "car", "van", "drive", "3d", "feel"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 7000, 4000), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", START[&"car"])
	s.vehicle(&"van", &"van", START[&"van"])
	s.actor(&"c", &"puppet", START[&"car"] + Vector2(0, -150))
	s.actor(&"v", &"puppet", START[&"van"] + Vector2(0, -150))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"c", &"v"]) or not Probe.ready(t, &"van"):
		return
	var drivers := { &"car": &"c", &"van": &"v" }
	for kind in drivers:
		if not t.require(
				await VehicleRide.board_by(
					t,
					drivers[kind],
					t.vehicle(kind) as Node2D,
					&"front_left",
				),
				"a driver gets into the %s" % kind,
		):
			return
	await t.seconds(0.5)
	var seen := { &"car": [], &"van": [] }
	var origin := { &"car": Vector2.ZERO, &"van": Vector2.ZERO }
	var turn := { &"car": 0.0, &"van": 0.0 }
	for kind in drivers:
		origin[kind] = _where(t.vehicle(kind))
		turn[kind] = _heading(t.vehicle(kind))
	var started := t.time
	var next := 0.0
	while t.time - started < RUN:
		var at := t.time - started
		var row: Array = SCRIPT[0]
		for candidate: Array in SCRIPT:
			if at >= candidate[0]:
				row = candidate
		for kind in drivers:
			t.puppet(drivers[kind]).drive(row[1], row[2], false)
		if at >= next:
			next += EVERY
			for kind in drivers:
				var v := t.vehicle(kind)
				var p: Vector2 = _where(v) - origin[kind]
				seen[kind].append(
					[snappedf(p.x, 0.1), snappedf(p.y, 0.1),
					snappedf(wrapf(_heading(v) - turn[kind], -PI, PI), 0.001),
					snappedf(_speed(v), 0.1)],
				)
		await t.frames(1)
	for kind in drivers:
		t.puppet(drivers[kind]).drive(0.0, 0.0, false)
	if EXPECTED.is_empty():
		print("RECORDED ", JSON.stringify(seen))
	for kind in drivers:
		_compare(t, kind, seen[kind], EXPECTED.get(kind, []))


## Where the vehicle is (px): its 3D body's place, or the 2D body's where there is no 3D body (the
## revision this was recorded on).
func _where(v: Node) -> Vector2:
	var lead := TwinSpace.leader_of(v)
	if lead == null:
		return (v as Node2D).global_position
	return PlanSpace.plan_of(lead.global_position)


## Which way it points (rad).
func _heading(v: Node) -> float:
	var lead := TwinSpace.leader_of(v)
	if lead == null:
		return (v as Node2D).global_rotation
	return PlanSpace.plan_of(lead.global_transform.basis.x).angle()


## How fast it moves (px/s).
func _speed(v: Node) -> float:
	var lead := TwinSpace.leader_of(v)
	return lead.call(&"plan_velocity").length() if lead != null else v.speed()


## Check each sample of `got` against the 2D body's `want`.
func _compare(t: TestContext, kind: StringName, got: Array, want: Array) -> void:
	if not t.require(not want.is_empty(), "the %s has a recorded 2D path" % kind):
		return
	t.require(got.size() >= want.size(), "the %s was sampled all the way" % kind)
	var worst_path := 0.0
	var worst_speed := 0.0
	var worst_turn := 0.0
	for i in mini(got.size(), want.size()):
		var a: Array = got[i]
		var b: Array = want[i]
		worst_path = maxf(worst_path, Vector2(a[0], a[1]).distance_to(Vector2(b[0], b[1])))
		worst_turn = maxf(worst_turn, absf(wrapf(a[2] - b[2], -PI, PI)))
		worst_speed = maxf(worst_speed, absf(a[3] - b[3]) - SPEED_SHARE * b[3])
	t.check(
		worst_path <= PATH_TOLERANCE,
		"the %s's path stays within %.0f px of the 2D body's (worst %.1f)"
			% [kind, PATH_TOLERANCE, worst_path],
	)
	t.check(
		worst_turn <= HEADING_TOLERANCE,
		"and its heading within %.2f rad (worst %.3f)" % [HEADING_TOLERANCE, worst_turn],
	)
	t.check(
		worst_speed <= SPEED_TOLERANCE,
		"and its speed within %.0f px/s + %.0f%% (worst excess %.1f)"
			% [SPEED_TOLERANCE, SPEED_SHARE * 100.0, worst_speed],
	)
