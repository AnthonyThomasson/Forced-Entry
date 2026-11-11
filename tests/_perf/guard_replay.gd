extends RefCounted
## Plays a match guard's own test once more, in a world of its own, for its fight fingerprint
## (`fight_fingerprint.gd`) and hands the fingerprint back as text, so a perf test can play one
## guard several ways in one process and compare the fights: the `perf/*_replay` tests. Load it
## with `const Replay := preload("res://tests/_perf/guard_replay.gd")`. Not a test (no `_test.gd`
## suffix).
##
## The guard runs unchanged (its `configure`, its warm-up, its window: a `TestSession` plays it as
## the runner does) in a `SubViewport` with a `World2D` of its own, as a match built by `Main` has,
## so it shares no physics space or navigation map with the test that plays it, nor with the plays
## before. Its verdict (budgets met or not) is not asked for: only the fight.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const Fingerprint := preload("res://tests/_perf/fight_fingerprint.gd")
const TestCatalog := preload("res://scenes/testing/test_catalog.gd")
const TestSessionScript := preload("res://scenes/testing/test_session.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
## Physics frames a freed world is given to settle before the next is built.
const SETTLE := 30
## Frames the second and the third play of `check_same_fight` wait before they build their world:
## not multiples of 3 or of each other, so the clock's phase differs in each.
const SECOND_BURN := 7
const THIRD_BURN := 13
## Frames the first fight has at least (the guard's warm-up alone is 360).
const MIN_FRAMES := 360


## Play the guard `guard_id` (`perf/match_5v5_stress`) once, after `burn_frames` physics frames
## (the process's frame count, and so the clock's phase, when the world is built), with the
## switches `extra_switches` (name -> on) added to what the guard declares. Returns `{ fight,
## status, reason }`: the fingerprint's text (empty when the guard wrote none), and the guard's own
## verdict and its reason.
static func play(
	t: TestContext,
	guard_id: String,
	extra_switches := {},
	burn_frames := 0,
) -> Dictionary:
	await t.frames(burn_frames)
	var dir := OS.get_user_data_dir().path_join("guard_replay")
	var file := Fingerprint.path_for(dir, guard_id)
	DirAccess.remove_absolute(file)
	var was := OS.get_environment(Fingerprint.ENV_DIR)
	OS.set_environment(Fingerprint.ENV_DIR, dir)
	var viewport := MainProbe.viewport(t)
	var camera: Camera2D = CameraScript.new()
	camera.name = "ReplayCamera"
	camera.target_path = ^"."
	camera.pan_enabled = false
	viewport.add_child(camera)
	var session: Node = TestSessionScript.new()
	session.name = "ReplaySession"
	viewport.add_child(session)
	session.world_built.connect(func(_setup: TestSetup) -> void:
		camera.make_current()
		camera.frame(session.camera_targets()))
	var entry := TestCatalog.describe("%s/%s%s" % [TestCatalog.ROOT, guard_id, TestCatalog.SUFFIX])
	entry["extra_switches"] = extra_switches
	await session.start(entry)
	var record: Dictionary = await session.close()
	OS.set_environment(Fingerprint.ENV_DIR, was)
	viewport.queue_free()
	await t.frames(SETTLE)
	return {
		"fight": FileAccess.get_file_as_string(file) if FileAccess.file_exists(file) else "",
		"status": record.get("status", ""),
		"reason": record.get("reason", ""),
	}


## Where two fingerprints first differ, in words: "" when they are the same fight, else the first
## differing frame and the field of its line (an NPC's index, `S:` or `D:`) with both values; a
## fingerprint that ends first differs at the frame it ends on.
static func first_difference(a: String, b: String) -> String:
	if a == b:
		return ""
	var left := a.split("\n")
	var right := b.split("\n")
	for i in mini(left.size(), right.size()):
		if left[i] == right[i]:
			continue
		var x := left[i].split("\t")
		var y := right[i].split("\t")
		for k in mini(x.size(), y.size()):
			if x[k] != y[k]:
				return "frame %s: [%s] against [%s]" % [x[0], x[k], y[k]]
		return "frame %s: a line of %d fields against %d" % [x[0], x.size(), y.size()]
	return "one fight ends at frame %d, the other at %d" % [left.size() - 1, right.size() - 1]


## Whether a shot was fired in the fight (`S:` holds a muzzle on some line): the sides made contact.
static func had_a_shot(fight: String) -> bool:
	for line in fight.split("\n"):
		var fields := line.split("\t")
		if fields.size() > 1 and fields[fields.size() - 2].length() > 2:
			return true
	return false


## The replay test of the guard `guard_id`: it is played three times in this process, plain, then
## plain again after `SECOND_BURN` frames and then with allocation padding on after `THIRD_BURN`
## (`testing.allocation_padding`: every instance id and RID the match takes is shifted), and the
## three fights must be the same, line for line, through the warm-up and the whole window. The
## burned frames move the clock's phase the world starts on, so a timer that ends a frame late on
## one start frame shows. Also checks the guard made contact (a shot in its fight).
static func check_same_fight(t: TestContext, guard_id: String) -> void:
	var first: Dictionary = await play(t, guard_id)
	if not t.require(
			first["fight"].count("\n") >= MIN_FRAMES,
			"premise: the guard wrote its fight (%d frames: %s %s)"
				% [first["fight"].count("\n"), first["status"], first["reason"]],
	):
		return
	t.check(
		had_a_shot(first["fight"]),
		"the sides made contact: a shot is in the fight (the guard: %s %s)"
			% [first["status"], first["reason"]],
	)
	var again: Dictionary = await play(t, guard_id, {}, SECOND_BURN)
	t.expect_eq(
		first_difference(first["fight"], again["fight"]),
		"",
		"a second play of the guard, %d frames later in the process, is the same fight"
			% SECOND_BURN,
	)
	var padded: Dictionary = await play(
		t, guard_id, { &"testing.allocation_padding": true }, THIRD_BURN,
	)
	t.expect_eq(
		first_difference(first["fight"], padded["fight"]),
		"",
		"a play with allocation padding on is the same fight",
	)
