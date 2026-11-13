extends GameTest
## The worst-frames report's counters on a live world (`tests/_perf/frame_report.gd`, `perf.md`),
## where the pure suite (`frame_report_suite.gd`) cannot reach: with the game's log on
## (`--verbose`), `Perf.frame_stats` returns what ran in each frame, every counter an int, a shot
## the puppet fires counted in the frame it was posted in; with the log off nothing is counted.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const Report := preload("res://tests/_perf/frame_report.gd")
const FRAMES := 30
## The measured frame the puppet shoots in, and the one the target is killed in (its body then
## falls as a ragdoll, stepped until it rests).
const SHOOT_AT := 10
const KILL_AT := 20


func describe() -> Dictionary:
	return {
		"name": "The worst-frames report counts what ran in each frame",
		"description": "A puppet fires once and its target dies in a measured window: with the log "
			+ "on every frame has integer counters, the shot and its sound are in the frame "
			+ "they were posted in and the ragdoll steps follow the death; with the log off no "
			+ "frame is counted.",
		"tags": ["scripted"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"projectile.flyover", false)
	s.von_script([])
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(600, 250))


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	shooter.aim_at(t.actor(&"target"))
	await t.frames(5)
	var logging := GameLog.enabled
	GameLog.enabled = false
	var off := await Perf.frame_stats(t, FRAMES)
	GameLog.enabled = true
	var on := await Perf.frame_stats(
		t, FRAMES, func(i: int) -> void:
			if i == SHOOT_AT:
				shooter.shoot()
			if i == KILL_AT:
				t.actor(&"target").take_damage(1.0e9)
	)
	GameLog.enabled = logging
	t.expect_eq(off["ran"], [], "with the log off nothing is counted")
	t.expect_eq(off["samples"].size(), FRAMES, "every frame is still timed with the log off")
	var ran: Array = on["ran"]
	if not t.require(
		ran.size() == FRAMES,
		"a frame's counts for each measured frame (%d)" % ran.size(),
	):
		return
	_shots(t, ran)
	_sounds(t, ran)
	_ragdolls(t, ran)


## The shot the puppet fired is counted once, in the frame it was posted in; every count is an int.
func _shots(t: TestContext, ran: Array) -> void:
	var shots := 0
	var all_ints := true
	for frame: Dictionary in ran:
		for key: String in frame:
			all_ints = all_ints and (
				key in Report.COUNTERS.map(func(c): return c[0]) or key.begins_with(Report.DEMAND)
			)
			all_ints = all_ints and typeof(frame[key]) == TYPE_INT
		shots += frame.get("shots", 0)
	t.check(all_ints, "every count is an int under a known counter key")
	t.expect_eq(shots, t.events_of(&"shot").size(), "the shots counted are the shots posted")
	t.check(shots > 0, "the puppet fired in the window (%d)" % shots)
	var in_frames := _frames_with(ran, "shots")
	t.check(
		in_frames.size() == 1 and in_frames[0] >= SHOOT_AT and in_frames[0] <= SHOOT_AT + 3,
		"the shot is counted in the frame it was fired in, about frame %d (counted in %s)"
			% [SHOOT_AT, str(in_frames)],
	)


## The sound a shot makes is counted in the frame it is played in, with the shot's own.
func _sounds(t: TestContext, ran: Array) -> void:
	var frames := _frames_with(ran, "sounds")
	t.check(
		not frames.is_empty() and frames[0] >= SHOOT_AT and frames[0] <= SHOOT_AT + 3,
		"the shot's sound is counted in about frame %d (counted in %s)" % [SHOOT_AT, str(frames)],
	)


## The ragdoll steps from the death on, and not before it.
func _ragdolls(t: TestContext, ran: Array) -> void:
	var before_death := 0
	var after_death := 0
	for i in ran.size():
		var steps: int = ran[i].get("ragdolls", 0)
		if i < KILL_AT:
			before_death += steps
		else:
			after_death += steps
	t.expect_eq(before_death, 0, "no ragdoll steps before the target dies")
	t.check(after_death > 0, "the fallen target's ragdoll is stepped after its death")


## The frames (indexes) of `ran` in which the counter `key` rose.
func _frames_with(ran: Array, key: String) -> Array:
	var out := []
	for i in ran.size():
		if (ran[i] as Dictionary).get(key, 0) > 0:
			out.append(i)
	return out
