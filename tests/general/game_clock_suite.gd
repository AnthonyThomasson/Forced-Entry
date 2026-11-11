extends UnitSuite
## `GameClock.seconds()` (interface 11): a timer "has run N frames" is `seconds() - start >= ttl`,
## and it must end on its frame whatever frame it started on. Read as plain floats, `(f + 48) / 60 -
## f / 60 >= 0.8` is false for nearly half the start frames, so a match played after another in one
## process swung every such timer (a squad's still leader, 0.8 s) by a frame.

const GameClockScript := preload("res://scenes/general/game_clock.gd")
## Frames of start tried: a few minutes of play, every phase of the clock's thirds and sixtieths.
const STARTS := 20_000
## Timers by length in frames, with the time each runs for (s): the lengths the AI's ttls take.
const TIMERS := { 3: 0.05, 6: 0.1, 30: 0.5, 48: 0.8, 60: 1.0, 150: 2.5, 390: 6.5 }


func test_a_timer_ends_on_its_frame_whatever_frame_it_started() -> void:
	var clock: Node = auto_free(GameClockScript.new())
	clock.set("_frames", 0)
	assert_float(clock.seconds()).is_equal(0.0)  # premise: the clock reads from 0
	var early := 0
	var late := 0
	for start in STARTS:
		clock.set("_frames", start)
		var from: float = clock.seconds()
		for frames: int in TIMERS:
			var ttl: float = TIMERS[frames]
			clock.set("_frames", start + frames)
			if clock.seconds() - from < ttl:
				late += 1
			clock.set("_frames", start + frames - 1)
			if clock.seconds() - from >= ttl:
				early += 1
	assert_int(late).is_equal(0)
	assert_int(early).is_equal(0)


## The ms a span of frames reads depends on the frame of the process it starts on (a 60 Hz frame is
## 16 2/3 ms: 1 frame reads 16 or 17), which skews a speed worked out from two sightings. Once
## aligned, as a world does at its start, every span from the world's frame reads the same ms
## whichever frame of the process the world started on, and `msec()` does not jump.
func test_aligned_ms_spans_do_not_follow_the_frame_the_world_started_on() -> void:
	var reads: Array = []
	for start in 12:
		var clock: Node = auto_free(GameClockScript.new())
		clock.set("_frames", 1000 + start)
		var ms_before: int = clock.msec()
		clock.align()
		assert_int(clock.msec()).is_equal(ms_before)  # no jump
		var spans: Array = []
		for w in 40:
			clock.set("_frames", 1000 + start + w)
			spans.append(clock.msec() - ms_before)
		reads.append(spans)
	var differing := 0
	for start in range(1, reads.size()):
		if reads[start] != reads[0]:
			differing += 1
	assert_int(differing).is_equal(0)
	# premise: unaligned, the starts do differ (a one frame span reads 16 or 17 ms)
	var seen := {}
	var bare: Node = auto_free(GameClockScript.new())
	for start in 12:
		bare.set("_frames", 1000 + start)
		var from: int = bare.msec()
		bare.set("_frames", 1001 + start)
		seen[bare.msec() - from] = true
	assert_int(seen.size()).is_equal(2)
