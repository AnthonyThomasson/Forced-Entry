extends GameTest
## Harness self-test: the check of `perf/render_3d_post_cost` is red when a sampled frame was not
## drawn, however cheap the times are, and green when every one was. A throwaway context takes the
## probe's verdict on made-up samples; the drawn-frame counter is first a made-up one, then the
## engine's own under headless, which draws nothing.

const Probe := preload("res://tests/perf/render_3d_post_cost_test.gd")
const SIZE := "(1152, 648)"
const MODE := "3D post"

## The made-up drawn-frame counter.
var _count := 0


func describe() -> Dictionary:
	return {
		"name": "The 3D frame probe fails on an undrawn frame",
		"tags": ["harness", "perf", "render"],
		"internal": true,
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	_check_counting(t)
	await _check_engine_counter(t)


## Every frame drawn passes; one frame the counter did not move on fails, and says so.
func _check_counting(t: TestContext) -> void:
	var total := Probe.ROUNDS * (Probe.SETTLE + Probe.FRAMES)
	var drawn: TestContext = _verdict(t, total, -1)
	t.expect_eq(drawn.verdict.conclude(drawn, false), "PASS", "every sampled frame drawn passes")
	drawn.free()
	var skipped: TestContext = _verdict(t, total, int(total * 0.5))
	t.expect_eq(skipped.verdict.conclude(skipped, false), "FAIL", "one undrawn frame fails")
	var failed: Array = skipped.verdict.checks.filter(func(k): return not k["ok"])
	t.check(
		failed.size() == 1 and String(failed[0]["message"]).contains("1 of %d" % total)
			and String(failed[0]["message"]).contains("not drawn"),
		"and the one failed check says 1 of %d was not drawn (%s)" % [total, failed],
	)
	skipped.free()
	var short: TestContext = _verdict(t, total - 1, -1)
	t.expect_eq(
		short.verdict.conclude(short, false),
		"FAIL",
		"a sampled frame nobody looked at fails too",
	)
	short.free()


## A context holding the probe's verdict on cheap, complete frame times, after the probe noted
## `frames` samples of a counter that stood still at sample `still` (-1: never).
func _verdict(t: TestContext, frames: int, still: int) -> TestContext:
	var probe: GameTest = Probe.new()
	_count = 0
	probe.frames_drawn = func() -> int: return _count
	probe.start_noting()
	var noted := { "sampled": 0, "undrawn": 0 }
	for i in frames:
		if i != still:
			_count += 1
		probe.note_drawn(noted)
	var c := TestContext.new(t.world.get_tree(), {})
	var cheap := { "count": Probe.FRAMES * Probe.ROUNDS, "mean": 1.0, "p95": 1.0, "max": 1.0 }
	var lit: Array[float] = [0.3]
	probe._brightness = lit
	probe._check(c, { SIZE: { MODE: { "frame": cheap, "drawn": noted } } })
	return c


## The engine's own counter stands still where nothing is drawn, so the probe reads every frame of a
## headless run as undrawn (a counter of iterations or physics steps would move).
func _check_engine_counter(t: TestContext) -> void:
	if DisplayServer.get_name() != "headless":
		return
	var probe: GameTest = Probe.new()
	probe.start_noting()
	var noted := { "sampled": 0, "undrawn": 0 }
	for i in 5:
		await t.frames(1)
		probe.note_drawn(noted)
	t.expect_eq(noted, { "sampled": 5, "undrawn": 5 }, "headless: no frame counts as drawn")
