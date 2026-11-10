extends GameTest
## The fight fingerprint (`tests/_perf/fight_fingerprint.gd`, perf-fingerprint.md): one
## line per physics frame holding every NPC's rounded position, goal, act and health, then the
## frame's shots and deaths, so two plays of a match can be diffed. A small arena fight: a puppet
## shoots another dead beside an NPC that stands by.

const Fingerprint := preload("res://tests/_perf/fight_fingerprint.gd")
const DIR := "user://fingerprint_test"
const ID := "perf/fight_fingerprint"
## A frame's line: the frame; NPC 0 and 1 (puppets: no goal, no act); NPC 2 (an AI: a goal and an
## act); the shots, the deaths.
const LINE := (
	"^(\\d+)\\t0 (-?\\d+),(-?\\d+) - - (-?\\d+\\.\\d)\\t1 (-?\\d+),(-?\\d+) - - (-?\\d+\\.\\d)"
	+ "\\t2 (-?\\d+),(-?\\d+) -?\\d+,-?\\d+ \\S+ (-?\\d+\\.\\d)\\tS:([-\\d,;]*)\\tD:([\\d,]*)$"
)


func describe() -> Dictionary:
	return {
		"name": "The fight fingerprint holds each frame's NPCs, shots and deaths",
		"description": "A puppet shoots another dead beside an NPC; the fingerprint has a line "
			+ "per frame, NPCs in spawn order with rounded positions and health, the shots and "
			+ "the death.",
		"tags": ["fingerprint", "scripted"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"projectile.flyover", false)
	s.von_script([])
	s.actor(&"shooter", &"puppet", Vector2(200.4, 250.6), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(600, 250), { "max_health": 10.0 })
	s.actor(&"bystander", &"defender", Vector2(200, 100))


func run(t: TestContext) -> void:
	t.expect_eq(
		Fingerprint.path_for("/out/dir", "perf/match_5v5_stress"),
		"/out/dir/perf__match_5v5_stress.fp",
		"a test's file is its id with / as __",
	)
	t.expect_eq(Fingerprint.test_id_of(self), ID, "a test's id is its path under tests/")
	var npcs: Array = [t.actor(&"shooter"), t.actor(&"target"), t.actor(&"bystander")]
	if not t.require(
			Fingerprint.begin(t, ID, npcs, "") == null,
			"premise: with no directory nothing is recorded",
	):
		return
	# Not kept in a variable: a guard calls `Perf.record_fight` and holds nothing, so the recording
	# must stay alive by itself (a signal connection holds no reference).
	Fingerprint.begin(t, ID, npcs, DIR)
	if not t.require(
			t.world.has_meta(Fingerprint.META),
			"a directory starts a recording that outlives the call",
	):
		return
	var shooter := t.puppet(&"shooter")
	var target := t.actor(&"target")
	shooter.aim_at(target)
	await t.frames(5)
	shooter.shoot()
	await t.until(func(): return target.is_dead, 3.0)
	await t.frames(5)
	# Read while recording: a run whose world is torn down without a close (the last test of a
	# process) must still have written every frame.
	var lines := _lines(Fingerprint.path_for(DIR, ID))
	t.world.get_meta(Fingerprint.META).close()
	_check_lines(t, lines, target)


func _lines(path: String) -> PackedStringArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	return file.get_as_text().strip_edges().split("\n")


func _check_lines(t: TestContext, lines: PackedStringArray, target: Node) -> void:
	if not t.require(lines.size() > 10, "the file holds a line per frame (%d)" % lines.size()):
		return
	var rx := RegEx.create_from_string(LINE)
	var shots := 0
	var death_lines: Array[int] = []
	var first_shot := -1
	for i in lines.size():
		var m := rx.search(lines[i])
		if not t.check(m != null, "line %d is a frame line: %s" % [i, lines[i]]):
			return
		t.expect_eq(int(m.get_string(1)), i, "line %d is frame %d" % [i, i])
		var here := m.get_string(11)
		shots += 0 if here == "" else here.count(";") + 1
		if here != "" and first_shot < 0:
			first_shot = i
		if m.get_string(12) != "":
			death_lines.append(i)
			t.expect_eq(m.get_string(12), "1", "the target is the one that died")
	var first := rx.search(lines[0])
	t.expect_eq(
		[first.get_string(2), first.get_string(3), first.get_string(5), first.get_string(6)],
		["200", "251", "600", "250"],
		"the first line holds the rounded positions, NPCs in spawn order",
	)
	t.expect_eq(shots, t.events_of(&"shot").size(), "every shot the run posted is in a line")
	t.check(shots > 0, "the puppet fired (%d shots)" % shots)
	t.check(
		death_lines.size() == 1 and death_lines[0] > first_shot,
		"the target's death is in one line, after the first shot (lines %s, shot at %d)"
			% [str(death_lines), first_shot],
	)
	var last := rx.search(lines[lines.size() - 1])
	t.expect_eq(
		float(last.get_string(7)),
		snappedf(target.health, 0.1),
		"the last line holds the target's health",
	)
