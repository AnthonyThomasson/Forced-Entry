extends GameTest
## A match is not started while the sound pre-warm is still rendering the library, so the first
## gunfire (and the footsteps, impacts and callouts before it) plays from the cache: no sound is
## synthesized on the main thread, which costs 9 to 35 ms a sound, a frame's budget several times
## over (#195, first-use). The pre-warm renders on a worker (`Sound.warm`; the game starts it at
## launch and a window needs ~9 s of it); `Main.start_match` waits for it before it builds. Headless
## the service starts no pre-warm of its own, so the test starts one with a cold cache, as a Start
## clicked early in a launch finds it. Read off the world: the main thread's render count
## (`SoundBank.main_thread_renders`) from the pre-warm's start to the first shot of the match.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const MATCH_SEED := 12
## Sim seconds the fight gets to fire its first shot once the match is built.
const FIRST_SHOT_WITHIN := 60.0
## How long (wall clock) the worker gets to render the library.
const WORKER_WAIT_MS := 30_000


func describe() -> Dictionary:
	return {
		"name": "A match starts after the sound pre-warm: no main-thread render by its first shot",
		"description": "With the library pre-warm still under way, Main.start_match waits for it; "
			+ "the match's sounds up to its first gunfire are all cached, none rendered on the "
			+ "main thread.",
		"tags": ["sound", "match", "perf"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.set_static(Settings, &"path", "user://test_match_sounds_prewarmed_settings.json")
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"debug", Settings.debug)
	# The test camera would cull a far sound unrendered: hear every category everywhere.
	var heard := {}
	for category: StringName in SoundConfig.category_range:
		heard[category] = 1.0e9
	s.set_static(SoundConfig, &"category_range", heard)
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", true)


func run(t: TestContext) -> void:
	var library: Array = Sound.library()
	Sound.finish_warming()
	SoundBank.clear_cache()
	var renders_before := SoundBank.main_thread_renders
	Sound.warm(library)
	if not t.require(Sound.warming(), "premise: the pre-warm is under way as the match starts"):
		return
	var viewport := MainProbe.viewport(t)
	var main = MainProbe.open(viewport)
	# Main's start waits for the worker, which renders in real time while the sim outruns the wall
	# clock: start it without awaiting, and give the worker wall time a frame at a time.
	var box := {}
	var start := func():
		box["built"] = await main.start_match(MatchBuilder.spec({
			"seed": MATCH_SEED,
			"defenders": { "count": 1 },
			"invaders": { "count": 1 },
		}))
	start.call()
	await t.frames(3)
	t.check(not box.has("built") and Sound.warming(), "the match waits while the pre-warm runs")
	var give_up := Time.get_ticks_msec() + WORKER_WAIT_MS
	while not box.has("built") and Time.get_ticks_msec() < give_up:
		OS.delay_msec(5)
		await t.frames(1)
	var built: Dictionary = box.get("built", {})
	if t.require(not built.is_empty(), "premise: the match is built once the pre-warm is done"):
		t.check(
			not Sound.warming() and SoundBank.cached_count() == library.size(),
			"the whole library is cached by the time the match is built (%d of %d)"
				% [SoundBank.cached_count(), library.size()],
		)
		if t.require(
				await t.until(func(): return t.happened(&"shot"), FIRST_SHOT_WITHIN),
				"premise: the fight fires a shot (%.0f s)" % t.time,
		):
			await t.seconds(1.0)
			t.expect_eq(
				SoundBank.main_thread_renders - renders_before,
				0,
				"no sound was synthesized on the main thread up to the first gunfire",
			)
	await MainProbe.close(t, viewport)
	await _check_setup_window_stays_up(t)
	SoundBank.clear_cache()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))


## The setup window's Start, clicked while the pre-warm runs, keeps the window up (with a status
## line) until the sounds are ready, then hands over to the match: a window freed at once would
## leave an empty screen for the wait.
func _check_setup_window_stays_up(t: TestContext) -> void:
	Sound.finish_warming()
	SoundBank.clear_cache()
	Sound.warm(Sound.library())
	var viewport := MainProbe.viewport(t)
	var main = MainProbe.open(viewport)
	var menu := MainProbe.setup_menu(main)
	if t.require(
			menu != null and Sound.warming(),
			"premise: the setup window is open and the pre-warm under way",
	):
		menu.start_requested.emit({
			"mode": "watch",
			"seed": MATCH_SEED,
			"defenders": { "count": 1 },
			"invaders": { "count": 1 },
		})
		await t.frames(3)
		t.check(
			is_instance_valid(menu) and not menu.is_queued_for_deletion(),
			"Start while the sounds warm up keeps the setup window up",
		)
		var give_up := Time.get_ticks_msec() + WORKER_WAIT_MS
		while (
				is_instance_valid(menu) and not menu.is_queued_for_deletion()
				and Time.get_ticks_msec() < give_up
		):
			OS.delay_msec(5)
			await t.frames(1)
		t.check(
			not is_instance_valid(menu) or menu.is_queued_for_deletion(),
			"the window hands over to the match once the pre-warm is done",
		)
		t.check(not Sound.warming(), "and the pre-warm is over by then")
	await MainProbe.close(t, viewport)
