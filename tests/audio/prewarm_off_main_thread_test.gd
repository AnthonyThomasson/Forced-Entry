extends GameTest
## The sound service pre-renders its library on a worker thread, so the frames a window draws while
## it warms pay nothing for it (synthesizing one sound takes 1.5 to 33 ms, more than a frame's
## budget, on whichever thread runs it). The worker only renders; the service files each finished
## sound into the bank's cache on the main thread, a few every frame. A pre-warmed sound is the
## sound an on-demand render makes, byte for byte. Headless, the service warms nothing by itself
## (nothing is heard), so the test starts one.

## Every `STRIDE`th pair of the library is rendered again on demand and compared.
const STRIDE := 7


func describe() -> Dictionary:
	return {
		"name": "The sound pre-warm renders off the main thread",
		"description": "The library is rendered on a worker and filed on the main thread frame by "
			+ "frame; every variant ends up cached, each the same bytes as an on-demand render.",
		"tags": ["sound", "bank"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	var library: Array = Sound.library()
	Sound.finish_warming()
	SoundBank.clear_cache()
	var main_renders := SoundBank.main_thread_renders
	Sound.warm(library)
	t.check(Sound.warming(), "the pre-warm is under way")
	await t.until(func() -> bool: return SoundBank.cached_count() > 0, 5.0)
	t.check(
		SoundBank.cached_count() > 0,
		"the finished sounds are filed as frames go by (%d)" % SoundBank.cached_count(),
	)
	Sound.finish_warming()
	t.check(not Sound.warming(), "the pre-warm is over")
	t.expect_eq(
		SoundBank.main_thread_renders - main_renders,
		0,
		"no sound was synthesized on the main thread",
	)
	var missing: Array[String] = []
	for pair in library:
		if not SoundBank.is_cached(pair[0], pair[1]):
			missing.append("%s#%d" % [pair[0], pair[1]])
	t.check(
		missing.is_empty(),
		"every variant of the library is cached (%d missing: %s)"
			% [missing.size(), ", ".join(missing.slice(0, 5))],
	)
	t.expect_eq(SoundBank.cached_count(), library.size(), "and nothing else")
	_check_same_bytes(t, library)


## Every `STRIDE`th pre-warmed sound of `library` (cached) is an on-demand render's bytes.
func _check_same_bytes(t: TestContext, library: Array) -> void:
	var warmed := {}
	for i in range(0, library.size(), STRIDE):
		warmed[i] = SoundBank.sound(library[i][0], library[i][1])
	SoundBank.clear_cache()
	var differ: Array[String] = []
	for i: int in warmed:
		var pair: Array = library[i]
		var fresh := SoundBank.sound(pair[0], pair[1])
		var was: Dictionary = warmed[i]
		var a: AudioStreamWAV = was["stream"]
		var b: AudioStreamWAV = fresh["stream"]
		if (a.data != b.data
				or a.mix_rate != b.mix_rate
				or a.loop_mode != b.loop_mode
				or a.loop_end != b.loop_end
				or was["level_db"] != fresh["level_db"]):
			differ.append("%s#%d" % [pair[0], pair[1]])
	t.check(
		differ.is_empty(),
		"each of %d pre-warmed sounds is an on-demand render's bytes (%d differ: %s)"
			% [warmed.size(), differ.size(), ", ".join(differ.slice(0, 5))],
	)
	SoundBank.clear_cache()
