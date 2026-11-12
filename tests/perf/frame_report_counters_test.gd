extends GameTest
## The worst-frames report's counters on a live world (`tests/_perf/frame_report.gd`, `perf.md`),
## where the pure suite (`frame_report_suite.gd`) cannot reach: with the game's log on
## (`--verbose`), `Perf.frame_stats` returns what ran in each frame, every counter an int, a shot
## the puppet fires counted in the frame it was posted in; with the log off nothing is counted.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const Report := preload("res://tests/_perf/frame_report.gd")
const FRAMES := 30
## The measured frame the puppet shoots in.
const SHOOT_AT := 10


func describe() -> Dictionary:
	return {
		"name": "The worst-frames report counts what ran in each frame",
		"description": "A puppet fires once in a measured window: with the log on every frame has "
			+ "integer counters and the shot is in the frame it was posted in; with the log off "
			+ "no frame is counted.",
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
	var shots := 0
	var all_ints := true
	for frame: Dictionary in ran:
		for key: String in frame:
			all_ints = all_ints and key in Report.COUNTERS.map(func(c): return c[0])
			all_ints = all_ints and typeof(frame[key]) == TYPE_INT
		shots += frame.get("shots", 0)
	t.check(all_ints, "every count is an int under a known counter key")
	t.expect_eq(shots, t.events_of(&"shot").size(), "the shots counted are the shots posted")
	t.check(shots > 0, "the puppet fired in the window (%d)" % shots)
	var in_frames: Array = []
	for i in FRAMES:
		if ran[i].get("shots", 0) > 0:
			in_frames.append(i)
	t.check(
		in_frames.size() == 1 and in_frames[0] >= SHOOT_AT and in_frames[0] <= SHOOT_AT + 3,
		"the shot is counted in the frame it was fired in, about frame %d (counted in %s)"
			% [SHOOT_AT, str(in_frames)],
	)
