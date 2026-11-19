extends GameTest
## Performance guard (#194 vehicles3d, D13): a fleet of cars and vans parked in rows, rolled all at
## once and left to stop. A vehicle is a 3D body (the truth) with a 2D footprint written from it
## each frame; the footprint is deleted with the 2D simulation (`del2d`), so what this costs now is
## the 3D body plus a temporary 2D follower. Frame cost rolling and at rest stays within the
## smooth-match budget. Recorded with `tools/perf_ab.sh` against the revision before the change.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const ROWS := 6
const COLUMNS := 4
const MOVING_FRAMES := 180
const RESTING_FRAMES := 60
## The roll along each row (px/s).
const ROLL := 600.0
# Frame budgets are the smooth-match standard (Perf.SMOOTH_*).


func describe() -> Dictionary:
	return {
		"name": "A fleet of rolling vehicles stays cheap",
		"description": "24 cars and vans parked in rows are set rolling at once; frame cost while "
			+ "they roll and once they stop stays within budget, with no node growth.",
		"tags": ["vehicle", "rigid body", "3d"],
		"timeout": 30.0,
	}


func _id(i: int) -> StringName:
	return StringName("v%d" % i)


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 6000, 2600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	for i in ROWS * COLUMNS:
		var at := Vector2(300 + (i % COLUMNS) * 700, 250 + int(i / float(COLUMNS)) * 380)
		s.vehicle(_id(i), &"car" if i % 3 != 0 else &"van", at)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var nodes_before := Perf.nodes()
	var starts: Array[Vector2] = []
	for i in ROWS * COLUMNS:
		var v := t.vehicle(_id(i)) as Node2D
		starts.append(v.global_position)
		v.set("linear_velocity", Vector2(ROLL, 0.0))
	var moving := await Perf.frame_stats(t, MOVING_FRAMES)
	Perf.within_frames(t, "vehicle fleet rolling", moving)
	var travelled := 0.0
	for i in ROWS * COLUMNS:
		travelled += (t.vehicle(_id(i)) as Node2D).global_position.distance_to(starts[i])
	t.check(
		travelled / (ROWS * COLUMNS) > 100.0,
		"the fleet rolled (avg %.1f px)" % (travelled / (ROWS * COLUMNS)),
	)
	await t.seconds(4.0)
	var resting := await Perf.frame_stats(t, RESTING_FRAMES)
	Perf.within(t, "vehicle fleet resting avg ms/frame", resting["avg_ms"], Perf.SMOOTH_AVG_MS)
	var grown := Perf.nodes() - nodes_before
	GameLog.say("PERF vehicle fleet node growth %d" % grown)
	# The 2D body this replaced grew by the same 6 here: one-offs, not a node per vehicle.
	t.check(grown <= 8, "rolling vehicles neither spawn nor leak nodes (grew by %d)" % grown)
