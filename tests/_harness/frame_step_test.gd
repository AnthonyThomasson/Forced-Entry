extends GameTest
## Harness self-test: every physics frame a test waits brings the world a process frame, even after
## a frame that took far longer than one 60 Hz step. Tests rely on it: an overlay updates what it
## draws in `_process`, and a draw test reads it after `t.frames(2)` (`ui/leader_overlay_draw`,
## `ai/debug/vision_overlay_cone_along_wall`). Under `--fixed-fps` (tools/run_tests.sh) each
## main-loop iteration steps physics once, so it holds by itself. A run paced to the clock (the
## editor's GdUnit panel, which gdUnit starts without `--fixed-fps`) would catch up a slow frame
## with several physics steps in the next iteration, before its process frame; the session hook
## (test_report_hook.gd) steps such a run once an iteration too.

## A frame this long (ms) is over three 60 Hz steps: a run paced to the clock owes the sim three.
const SLOW_FRAME_MS := 60


func describe() -> Dictionary:
	return {
		"name": "Each physics frame waited brings a process frame",
		"tags": ["harness"],
		"internal": true,
		"timeout": 4.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var ticker := Ticker.new()
	t.world.add_child(ticker)
	await t.frames(2)
	for i in 3:
		OS.delay_msec(SLOW_FRAME_MS)
		await t.frames(1)
		var before := ticker.count
		await t.frames(1)
		t.check(
			ticker.count > before,
			"slow frame %d: a process frame ran between the two physics frames after it" % i,
		)


## Counts the process frames it sees.
class Ticker:
	extends Node

	var count := 0

	func _process(_delta: float) -> void:
		count += 1
