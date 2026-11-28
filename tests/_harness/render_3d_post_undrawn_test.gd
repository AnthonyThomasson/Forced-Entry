extends GameTest
## Harness self-test: the check of `perf/render_3d_post_cost` is red when a sampled frame was not
## drawn, however cheap the times are, and green when every one was; its blocks note every frame
## they step; and its window is put back down however the test ends. A throwaway context takes the
## probe's verdict on made-up samples; the drawn-frame counter and the window's "can draw" are
## made-up ones, then each the engine's own under headless, which draws nothing.

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
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	_check_counting(t)
	_check_window_cannot_draw(t)
	_check_put_back_down(t)
	await _check_block_notes(t)
	await _check_engine_seams(t)


## Every frame drawn passes; one frame the counter did not move on fails, and says so.
func _check_counting(t: TestContext) -> void:
	var total := Probe.ROUNDS * (Probe.SETTLE + Probe.FRAMES)
	var drawn: TestContext = _verdict(t, total, -1)
	t.expect_eq(drawn.verdict.conclude(drawn, false), "PASS", "every sampled frame drawn passes")
	drawn.free()
	var skipped: TestContext = _verdict(t, total, int(total * 0.5))
	t.expect_eq(skipped.verdict.conclude(skipped, false), "FAIL", "one undrawn frame fails")
	var message := _only_failure(skipped)
	t.check(
		message.contains("1 of %d" % total) and message.contains("not drawn")
			and message.contains("--fixed-fps"),
		"and the one failed check says 1 of %d was not drawn, and what pacing it needs (%s)"
			% [total, message],
	)
	skipped.free()
	var short: TestContext = _verdict(t, total - 1, -1)
	t.expect_eq(
		short.verdict.conclude(short, false),
		"FAIL",
		"a sampled frame nobody looked at fails too",
	)
	short.free()


## The engine also counts frames it draws to free resources while the window shows nothing: the
## counter advances but the window cannot draw. One such reading spoils the frames on both sides.
func _check_window_cannot_draw(t: TestContext) -> void:
	var total := Probe.ROUNDS * (Probe.SETTLE + Probe.FRAMES)
	var covered: TestContext = _verdict(t, total, -1, range(total + 1))
	t.expect_eq(
		covered.verdict.conclude(covered, false),
		"FAIL",
		"the counter advances but the window cannot draw",
	)
	t.check(
		_only_failure(covered).contains("%d of %d" % [total, total]),
		"and none of those frames counts as drawn (%s)" % _only_failure(covered),
	)
	covered.free()
	var blink: TestContext = _verdict(t, total, -1, [int(total * 0.5)])
	t.check(
		_only_failure(blink).contains("2 of %d" % total),
		"one reading that cannot draw spoils the frame before and after it (%s)"
			% _only_failure(blink),
	)
	blink.free()


## The window is above the others while the probe runs, and put back however the test ends: with a
## verdict, or by its world leaving the tree with none (Esc / Back in the runner).
func _check_put_back_down(t: TestContext) -> void:
	for ending: String in ["a verdict", "the world leaving the tree"]:
		var above := [false]
		var probe: GameTest = Probe.new()
		probe.on_top = func() -> bool: return above[0]
		probe.set_on_top = func(on: bool) -> void: above[0] = on
		var c := TestContext.new(t.world.get_tree(), {})
		c.world = Node2D.new()
		t.world.add_child(c.world)
		probe._keep_on_top(c)
		t.check(above[0], "the window is kept on top until %s" % ending)
		if ending == "a verdict":
			c.finish("PASS")
		else:
			t.world.remove_child(c.world)
		t.check(not above[0], "and put back down on %s" % ending)
		c.world.free()
		c.free()


## A block notes every frame it steps, the settle frames and the measured ones, counting from its
## own start: where every frame is drawn it reads all of them drawn, none unnoted and none from
## before it.
func _check_block_notes(t: TestContext) -> void:
	var probe := Blind.new()
	_count = 0
	probe.frames_drawn = func() -> int:
		_count += 1
		return _count
	probe.can_draw = func() -> bool: return true
	var into := {
		"frame": [],
		"gpu": [],
		"cpu": [],
		"settle": [],
		"drawn": { "sampled": 0, "undrawn": 0 },
	}
	await probe._block(t, MODE, Vector2.ZERO, into)
	t.expect_eq(
		into["drawn"],
		{ "sampled": Probe.SETTLE + Probe.FRAMES, "undrawn": 0 },
		"a block notes each of its frames from its start",
	)


## A context holding the probe's verdict on cheap, complete frame times, after the probe noted
## `frames` samples of a counter that stood still at sample `still` (-1: never), the window unable
## to draw at the readings in `blind` (0: the one the noting starts from).
func _verdict(t: TestContext, frames: int, still: int, blind: Array = []) -> TestContext:
	var probe: GameTest = Probe.new()
	_count = 0
	var reading := [0]
	probe.frames_drawn = func() -> int: return _count
	probe.can_draw = func() -> bool:
		reading[0] += 1
		return not blind.has(reading[0] - 1)
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


## The message of the one failed check of `c` ("" if there is not exactly one).
func _only_failure(c: TestContext) -> String:
	var failed: Array = c.verdict.checks.filter(func(k): return not k["ok"])
	return String(failed[0]["message"]) if failed.size() == 1 else ""


## The engine's own two readings under headless, each beside a made-up other: the counter stands
## still where nothing is drawn (a counter of iterations or physics steps would move), and the
## window cannot draw. Either alone reads every frame as undrawn.
func _check_engine_seams(t: TestContext) -> void:
	if DisplayServer.get_name() != "headless":
		return
	var counter: GameTest = Probe.new()
	counter.can_draw = func() -> bool: return true
	var window: GameTest = Probe.new()
	_count = 0
	window.frames_drawn = func() -> int: return _count
	counter.start_noting()
	window.start_noting()
	var by_counter := { "sampled": 0, "undrawn": 0 }
	var by_window := { "sampled": 0, "undrawn": 0 }
	for i in 5:
		await t.frames(1)
		_count += 1
		counter.note_drawn(by_counter)
		window.note_drawn(by_window)
	var none := { "sampled": 5, "undrawn": 5 }
	t.expect_eq(by_counter, none, "headless: the engine counts no frame drawn")
	t.expect_eq(by_window, none, "headless: the engine's window cannot draw")


## The probe with nothing to look at: its blocks run headless, with no view, camera or picture.
class Blind extends Probe:
	func _route(_centre: Vector2, _s: float) -> void:
		pass

	func _render_ms() -> Vector2:
		return Vector2.ZERO

	func _shot(_t: TestContext, _mode: String) -> void:
		pass

	func _mean_brightness(_t: TestContext) -> float:
		return 0.3
