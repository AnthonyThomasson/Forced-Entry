extends GameTest
## The grenade planner's failing path was cut without moving an answer (#194, perf-arc): over a few
## thousand throws generated in the world of a real match (the district of the perf guards: its
## furniture, walls and doorways, the combatants standing where they fight), `GrenadeArc.plan` gives
## the launch `GrenadeArcReference.plan` (a frozen copy of the planner before the cut) gives, field
## for field, and counts the same `work` (the AI prices its throw search by it, so a cheaper plan
## must not read as less work). The throws cover the AI's question (`clear`: the combatants' masks,
## margins and release heights, a lob to every range), the thrown grenade's (verified, its thrower's
## twin passed, an apex the thrower chose, all bodies struck) and both kinds of grenade.

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
	var tally := { "ok": 0, "blocked": 0, "verified_ok": 0, "capped": 0, "differ": 0 }
	var first_difference := ""
	for n in THROWS:
		var thrower: Node2D = fighters[rng.randi() % fighters.size()]
		var spec := _spec(rng, thrower, fighters)
		var told := _compare(spec, space, tally)
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


## Plan `spec` with the old planner and the new, count what was asked in `tally`; what differs, or
## "" when nothing does.
func _compare(spec: Dictionary, space: PhysicsDirectSpaceState3D, tally: Dictionary) -> String:
	var old_course := _course(spec, space)
	var new_course := _course(spec, space)
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
	if rng.randf() < 0.3:
		to = (fighters[rng.randi() % fighters.size()] as Node2D).global_position
	var verify := rng.randf() < 0.25
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


func _course(spec: Dictionary, space: PhysicsDirectSpaceState3D) -> GrenadeCourse:
	var course := GrenadeCourse.new()
	course.from = spec["from"]
	course.to = spec["to"]
	course.release = spec["release"]
	course.row = GrenadeConfig.row(spec["kind"])
	course.margin = spec["margin"]
	course.mask = spec["mask"]
	course.apex = spec["apex"]
	course.verify = spec["verify"]
	course.space = space
	if spec["passed"]:
		course.passed = GrenadeArc.passed_by(spec["thrower"])
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
