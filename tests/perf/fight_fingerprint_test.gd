extends GameTest
## The fight fingerprint (`tests/_perf/fight_fingerprint.gd`, perf-fingerprint.md): one
## line per physics frame holding every NPC's rounded position, goal, act and health, then the
## frame's shots and deaths, so two plays of a match can be diffed. A small arena fight: a puppet
## shoots another dead beside an NPC that stands by.

const Fingerprint := preload("res://tests/_perf/fight_fingerprint.gd")
const DIR := "user://fingerprint_test"
const ID := "perf/fight_fingerprint"
## A frame's line: the frame; NPC 0 and 1 (puppets: no goal, no act); NPC 2 (an AI: a goal and an
## act); NPC 3 (a puppet that is freed: `gone`); the shots, the deaths.
const LINE := (
	"^(\\d+)\\t0 (-?\\d+),(-?\\d+) - - (-?\\d+\\.\\d)\\t1 (-?\\d+),(-?\\d+) - - (-?\\d+\\.\\d)"
	+ "\\t2 (-?\\d+),(-?\\d+) -?\\d+,-?\\d+ \\S+ (-?\\d+\\.\\d)"
	+ "\\t3 [^\\t]+\\tS:([-\\d,;]*)\\tD:([\\d,]*)$"
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
	s.actor(&"doomed", &"puppet", Vector2(400, 400))


func run(t: TestContext) -> void:
	t.expect_eq(
		Fingerprint.path_for("/out/dir", "perf/match_5v5_stress"),
		"/out/dir/perf__match_5v5_stress.fp",
		"a test's file is its id with / as __",
	)
	t.expect_eq(Fingerprint.test_id_of(self), ID, "a test's id is its path under tests/")
	t.expect_eq(
		Fingerprint.act_text("combat/t_1245473426825/engage/fire_south", { 1_245_473_426_825: 4 }),
		"combat/t_4/engage/fire_south",
		"a decision's hostile is the NPC's index, never its instance id",
	)
	_check_act_text(t)
	var npcs: Array = [
		t.actor(&"shooter"),
		t.actor(&"target"),
		t.actor(&"bystander"),
		t.actor(&"doomed"),
	]
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
	# An NPC that dies and is freed in one frame still has its death in the line it vanishes on.
	var doomed := t.actor(&"doomed")
	doomed.died.emit()
	doomed.queue_free()
	await t.frames(5)
	# Read while recording: a run whose world is torn down without a close (the last test of a
	# process) must still have written every frame.
	var lines := _lines(Fingerprint.path_for(DIR, ID))
	t.world.get_meta(Fingerprint.META).close()
	_check_lines(t, lines, target)


## `act_text`: every instance id of an act written as an NPC's index or an object's position.
func _check_act_text(t: TestContext) -> void:
	var freed := Node2D.new()
	var freed_id := freed.get_instance_id()
	freed.free()
	t.expect_eq(
		Fingerprint.act_text("combat/t_%d/engage" % freed_id, { 1: 0 }),
		"combat/t_?/engage",
		"a hostile that is none of the NPCs, and no node, is `?`",
	)
	var known := { 1_245_473_426_825: 4, 1_253_207_723_845: 7 }
	t.expect_eq(
		Fingerprint.act_text("lead/lead_ally_1253207723845", known),
		"lead/lead_ally_7",
		"a heard ally's contact id is the NPC's index",
	)
	t.expect_eq(
		Fingerprint.act_text("lead/lead_seen_1245473426825", known),
		"lead/lead_seen_4",
		"a seen contact's id is the NPC's index",
	)
	t.expect_eq(
		Fingerprint.act_text("lead/lead_heading_1253207723845", known),
		"lead/lead_heading_7",
		"a contact's heading id is the NPC's index",
	)
	var chair := t.actor(&"bystander")  # at (200, 100): any Node2D stands for an object
	t.expect_eq(
		Fingerprint.act_text("use/do_%d_sit" % chair.get_instance_id(), known),
		"use/do_@200,100_sit",
		"an object's instance id is its rounded position",
	)
	t.expect_eq(
		Fingerprint.act_text(
			"use/do_%d_sit" % chair.get_instance_id(),
			{ chair.get_instance_id(): 2 },
		),
		"use/do_2_sit",
		"an id that is an NPC's is its index whatever the option names",
	)
	t.expect_eq(
		Fingerprint.act_text("order/stack_door_0_0/lead_window_-3_12/door_2", { 1: 0 }),
		"order/stack_door_0_0/lead_window_-3_12/door_2",
		"short numbers (a grid cell, a door number) are kept as they are",
	)


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
	var doomed_lines: Array[int] = []
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
		for index in m.get_string(12).split(",", false):
			(death_lines if index == "1" else doomed_lines).append(i)
			t.check(index in ["1", "3"], "only the target and the freed one died, not %s" % index)
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
	t.check(
		doomed_lines.size() == 1,
		"the freed NPC's death is in one line (lines %s)" % str(doomed_lines),
	)
	var last := rx.search(lines[lines.size() - 1])
	t.expect_eq(
		float(last.get_string(7)),
		snappedf(target.health, 0.1),
		"the last line holds the target's health",
	)
