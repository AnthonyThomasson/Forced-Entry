extends GameTest
## The grenade planner's failing path was cut without moving an answer (#194, perf-arc): over a few
## thousand throws generated in the world of a real match (the district of the perf guards: its
## furniture, walls and doorways, the combatants standing where they fight), `GrenadeArc.plan` gives
## the launch `GrenadeArcReference.plan` (a frozen copy of the planner before the cut) gives, field
## for field, and counts the same `work` (the AI prices its throw search by it, so a cheaper plan
## must not read as less work). The throws cover the AI's question (`clear`: the combatants' masks,
## margins and release heights, a lob to every range), the thrown grenade's (verified, its thrower's
## twin passed, an apex the thrower chose, all bodies struck) and both kinds of grenade. One throw
## in `REUSE_EVERY` plans a `GrenadeCourse` that has already planned another question (another aim
## and verify), so the plan's memory (`course.made`) must be forgotten at the next plan: the answer
## is the reference's on a fresh course.
##
## **The reference guards this cut only.** `tests/_items/grenade_arc_reference.gd` is a verbatim
## copy of the planner from before the cut. A deliberate change to the planner's rules in the same
## commit re-freezes it: copy the new planner over the reference and say why in the commit message.
## This test and the reference are deleted by the ticket's final perf job (#194, job 20) once every
## guard passes: they are scaffolding for the cut, not a standing spec.
##
## The premise tallies keep the generator honest: a drift that stops it reaching a path the cut
## touched (the one-face early exit, the longer-lob search, the sweep budget, the flight budget)
## fails the test instead of passing it for nothing. They are counted by `_trace`, a shadow of
## `GrenadeArc.plan`'s loop over the planner's own steps.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const Reference := preload("res://tests/_items/grenade_arc_reference.gd")
const PER_SIDE := 3
const THROWS := 4000
const SEED := 194
## Throws are aimed this near and this far (px) from where they leave: beyond the arm's range too.
const NEAREST := 30.0
const FARTHEST := 620.0
const POSTURES: Array[StringName] = [&"stand", &"duck", &"fire_over"]
const KINDS: Array[StringName] = [&"stun", &"frag"]
## How many of the throws a premise wants to be of each kind (a world with nothing in the way, or
## nothing but walls, would prove little).
const WANT_EACH := 150
## One throw in this many plans a course that has already planned another question.
const REUSE_EVERY := 4
## How many of the `GrenadeArc.FIT_TRIES` flights the deepest search of the throws is to fly at
## least. All of them is not asked: a search that flies every one rests off the aim on thirty arcs
## in a row, which this district gives about once in thousands of verified throws (a throw aimed
## at a combatant in the open the skid cannot come near), too seldom to hold the premise. The
## cap's own branch (`GrenadeArc._try`: the best flown so far is the answer at `FIT_TRIES`) is not
## one the cut touched: it is the reference's line for line.
const DEEP := 20

## The most flights one search has flown so far.
var _deepest := 0


func describe() -> Dictionary:
	return {
		"name": "The grenade planner answers as it did before its failing path was cut",
		"description": "Four thousand throws generated in a match's district: the planner and a "
			+ "frozen copy of the old one give the same launch and count the same work.",
		"tags": ["grenade", "throw", "lob", "item", "3d"],
		"timeout": 120.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	Perf.configure_match(s, PER_SIDE)


func run(t: TestContext) -> void:
	var fighters: Array = t.world.match_handle.get("combatants", []).duplicate()
	if not t.require(fighters.size() >= 2, "premise: the match has combatants"):
		return
	await t.seconds(3.0)
	var space := TwinSpace.space_of(fighters[0])
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var tally := {
		"ok": 0, "blocked": 0, "verified_ok": 0, "capped": 0, "differ": 0,
		"faced": 0, "stepped": 0, "spent": 0, "reused": 0,
	}
	var first_difference := ""
	for n in THROWS:
		var thrower: Node2D = fighters[rng.randi() % fighters.size()]
		var spec := _spec(rng, thrower, fighters)
		var told := _compare(spec, space, tally, n % REUSE_EVERY == 0, rng)
		if not told.is_empty() and first_difference.is_empty():
			first_difference = "throw %d: %s" % [n, told]
	GameLog.say("ARC oracle %s" % [tally])
	t.check(
		tally["differ"] == 0,
		"every launch and its work equal the old planner's: %s" % first_difference,
	)
	t.check(tally["ok"] >= WANT_EACH, "premise: lobs that clear (%d)" % tally["ok"])
	t.check(tally["blocked"] >= WANT_EACH, "premise: lobs that are blocked (%d)" % tally["blocked"])
	t.check(tally["verified_ok"] >= 20, "premise: verified throws that clear")
	t.check(tally["capped"] >= 20, "premise: throws aimed past the arm (%d)" % tally["capped"])
	t.check(tally["faced"] >= 100, "premise: lobs one face blocks (%d)" % tally["faced"])
	t.check(tally["stepped"] >= 20, "premise: searches that lob farther (%d)" % tally["stepped"])
	t.check(tally["spent"] >= 5, "premise: searches that spend the sweeps (%d)" % tally["spent"])
	t.check(
		_deepest >= DEEP,
		"premise: a search that flies %d arcs or more (%d)" % [DEEP, _deepest],
	)
	t.check(tally["reused"] >= 100, "premise: reused courses (%d)" % tally["reused"])


## Plan `spec` with the old planner and the new, count what was asked in `tally`; what differs, or
## "" when nothing does. With `reuse` the new planner's course has already planned another question
## (another aim, verified the other way) before it is asked `spec`; the old one's is fresh.
func _compare(
	spec: Dictionary,
	space: PhysicsDirectSpaceState3D,
	tally: Dictionary,
	reuse: bool,
	rng: RandomNumberGenerator,
) -> String:
	var old_course := _course(spec, space)
	var new_course := _course(spec, space)
	if reuse:
		new_course = _used_course(spec, space, rng)
		tally["reused"] += 1
	var asked: Array[int] = [Reference.work, GrenadeArc.work, Reference.plans, GrenadeArc.plans]
	var old_launch: GrenadeLaunch = Reference.plan(old_course)
	var new_launch: GrenadeLaunch = GrenadeArc.plan(new_course)
	tally["ok" if old_launch.ok else "blocked"] += 1
	tally["verified_ok"] += int(old_launch.ok and spec["verify"])
	tally["capped"] += int(old_launch.capped)
	var same := (
		_same(old_launch, new_launch)
		and old_course.top == new_course.top
		and old_course.roof == new_course.roof
		and Reference.work - asked[0] == GrenadeArc.work - asked[1]
		and Reference.plans - asked[2] == GrenadeArc.plans - asked[3]
	)
	_count_paths(spec, space, tally)
	if same:
		return ""
	tally["differ"] += 1
	return "from %s to %s: old %s new %s" % [
		spec["from"], spec["to"], _show(old_launch), _show(new_launch),
	]


## One throw: where it leaves, where it is aimed, and how it is asked.
func _spec(rng: RandomNumberGenerator, thrower: Node2D, fighters: Array) -> Dictionary:
	var from: Vector2 = thrower.global_position + Vector2(
		rng.randf_range(-160.0, 160.0), rng.randf_range(-160.0, 160.0)
	)
	var to := from + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(NEAREST, FARTHEST)
	if rng.randf() < 0.5:
		to = (fighters[rng.randi() % fighters.size()] as Node2D).global_position
	var verify := rng.randf() < 0.5
	return {
		"from": from,
		"to": to,
		"release": BodyHeights.release(POSTURES[rng.randi() % POSTURES.size()]),
		"kind": KINDS[rng.randi() % KINDS.size()],
		"margin": [0.0, 8.0, 14.0][rng.randi() % 3],
		# The AI's lob leaves the characters out, a thrown grenade strikes them.
		"mask": PhysicsLayers.TWIN_ALL if verify else PhysicsLayers.TWIN_SURFACES,
		"apex": rng.randf_range(20.0, 140.0) if verify and rng.randf() < 0.3 else -1.0,
		"verify": verify,
		"passed": verify and rng.randf() < 0.7,
		"thrower": thrower,
	}


## A course that has planned another question and is now asked `spec`: what a plan is worked out
## for (`top` and `roof`, worked out once by design) is reset, the plan's memory is left for the
## planner to forget.
func _used_course(
	spec: Dictionary, space: PhysicsDirectSpaceState3D, rng: RandomNumberGenerator
) -> GrenadeCourse:
	var before := spec.duplicate()
	before["to"] = spec["from"] + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(
		NEAREST, FARTHEST
	)
	before["verify"] = not spec["verify"]
	before["mask"] = PhysicsLayers.TWIN_ALL if before["verify"] else PhysicsLayers.TWIN_SURFACES
	var course := _course(before, space)
	GrenadeArc.plan(course)
	course.top = -1.0
	course.roof = INF
	return _course(spec, space, course)


## Count the paths a plan of `spec` takes inside the planner, on a fresh course (`_trace`).
func _count_paths(spec: Dictionary, space: PhysicsDirectSpaceState3D, tally: Dictionary) -> void:
	var path := _trace(_course(spec, space))
	tally["faced"] += int(path["faced"])
	tally["stepped"] += int(path["step"] >= 1)
	tally["spent"] += int(path["swept"] >= GrenadeArc.SWEEPS)
	_deepest = maxi(_deepest, path["tries"])


## What `GrenadeArc.plan` does on `course` as far as the search goes, by its own steps: whether the
## one-face exit answered, how many steps longer the lobs got, the arcs swept, the flights flown.
func _trace(course: GrenadeCourse) -> Dictionary:
	var path := { "faced": false, "step": 0, "swept": 0, "tries": 0 }
	var sweep := GrenadeArc._sweep(course)
	if GrenadeArc._walled(course, sweep) or GrenadeArc._flattest(course, sweep) != null:
		return path
	var arcs := GrenadeArc._arcs(course)
	if GrenadeArc._faced(course, sweep, arcs):
		path["faced"] = true
		return path
	var fit := GrenadeArc.Fit.new()
	while fit.step == 0 or GrenadeArc._lobs_left(course, fit, arcs):
		for arc: GrenadeArc.Arc in arcs:
			if GrenadeArc._try(course, sweep, fit, arc) != null:
				return _traced(path, fit)
		fit.step += 1
	return _traced(path, fit)


func _traced(path: Dictionary, fit: GrenadeArc.Fit) -> Dictionary:
	path["step"] = fit.step
	path["swept"] = fit.swept
	path["tries"] = fit.tries
	return path


func _course(
	spec: Dictionary, space: PhysicsDirectSpaceState3D, into: GrenadeCourse = null
) -> GrenadeCourse:
	var course := into if into != null else GrenadeCourse.new()
	course.from = spec["from"]
	course.to = spec["to"]
	course.release = spec["release"]
	course.row = GrenadeConfig.row(spec["kind"])
	course.margin = spec["margin"]
	course.mask = spec["mask"]
	course.apex = spec["apex"]
	course.verify = spec["verify"]
	course.space = space
	course.passed = GrenadeArc.passed_by(spec["thrower"]) if spec["passed"] else GrenadeArc.NOBODY
	return course


func _same(a: GrenadeLaunch, b: GrenadeLaunch) -> bool:
	return (
		a.ok == b.ok
		and a.capped == b.capped
		and a.direction == b.direction
		and a.speed == b.speed
		and a.rise == b.rise
		and a.apex == b.apex
		and a.time == b.time
		and a.touchdown == b.touchdown
		and a.rest == b.rest
	)


func _show(a: GrenadeLaunch) -> String:
	return "ok=%s capped=%s dir=%s speed=%s rise=%s apex=%s time=%s touch=%s rest=%s" % [
		a.ok, a.capped, a.direction, a.speed, a.rise, a.apex, a.time, a.touchdown, a.rest,
	]
