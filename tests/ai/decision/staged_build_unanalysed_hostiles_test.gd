extends GameTest
## A snapshot built in pieces with more hostiles known than get full analysis (#208). Four
## hostiles are in sight, the third of them engaged: the engaged one takes a slot and the nearest
## other the second (`ai/decision/analyses_engaged_and_nearest`), so the second and the fourth are
## listed with their line to them only, one between the two analysed hostiles and one after them
## both. The build runs a piece for each analysed hostile, the line entries ride with them, and
## the snapshot is the one `sense()` makes: the same option groups and sections, the engaged and
## nearest hostiles analysed, all four listed (`max_options_per_level` is four) with their line.

const NPC := Vector2(150, 250)
## Nearest first, left to right.
const SPOTS := [Vector2(300, 100), Vector2(400, 100), Vector2(500, 100), Vector2(600, 100)]
const START := 0
const HOSTILE := 1
const FINISH := 2


func describe() -> Dictionary:
	return {
		"name": "A staged snapshot analyses the engaged and nearest hostiles and lists the rest",
		"description": "With four hostiles known and the third engaged, the build runs a start, "
			+ "a piece for the nearest and one for the engaged hostile, and a finish; all four "
			+ "are listed with their line; the snapshot equals the one-shot build's.",
		"tags": ["ai", "decision", "snapshot", "scripted"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 400))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }, { "pick": "fire_here" }])
	s.switch(&"ai.callouts", false)
	s.actor(&"d", &"defender", NPC, { "movement:speed": 0.0, "facing": Vector2.RIGHT })
	for i in SPOTS.size():
		s.actor(
			StringName("h%d" % i), &"puppet", SPOTS[i],
			{ "faction": &"invader", "max_health": 1_000_000.0 },
		)


func run(t: TestContext) -> void:
	var brain := t.controller(&"d", &"debug_state")
	var seen := func() -> bool: return (
		(brain.debug_state().get("contacts", []) as Array).filter(
			func(c): return c.get("hostile", false)
		).size() == SPOTS.size()
	)
	if not t.require(await t.until(seen, 3.0), "set-up: the defender sees all four hostiles"):
		return
	var ids: Array = []
	for i in SPOTS.size():
		ids.append(t.actor(StringName("h%d" % i)).get_instance_id())
	var perception: Node = brain.get("_perception")
	var whole: Dictionary = perception.sense(brain.get("goal"), "", ids[2])
	var staged = perception.begin_sense(brain.get("goal"), "", ids[2])
	var kinds: Array = []
	while not staged.done():
		kinds.append(staged.next_piece())
		staged.step()
	t.expect_eq(
		kinds, [START, HOSTILE, HOSTILE, FINISH], "a piece for each of the two analysed hostiles"
	)
	var stepped: Dictionary = staged.result()
	_check_analysed(t, whole, [ids[0], ids[2]])
	_check_analysed(t, stepped, [ids[0], ids[2]])
	_check_listed(t, stepped, ids)
	whole["demand"].complete()
	stepped["demand"].complete()
	for key in ["facts", "sections", "options", "sections_per_target", "gun"]:
		t.expect_eq(stepped[key], whole[key], "the snapshot's %s" % key)


## Only the `analysed` hostiles have sections of their own and are kept for what the walk builds
## of them.
func _check_analysed(t: TestContext, snap: Dictionary, analysed: Array) -> void:
	var who: Array = (snap["sections_per_target"] as Dictionary).keys()
	who.sort()
	t.expect_eq(who, analysed, "the engaged and the nearest hostile are analysed")
	var targets: Array = (snap["demand"].targets as Dictionary).keys()
	targets.sort()
	t.expect_eq(targets, analysed, "only they are kept for what the walk builds of them")


## Every hostile is listed to fight, nearest first, with the line to it told.
func _check_listed(t: TestContext, snap: Dictionary, ids: Array) -> void:
	var listed: Array = []
	for o in snap["options"]["hostiles"]["options"]:
		listed.append(o["bind"]["target_id"])
		t.check(
			String(o["desc"]).contains("clear shot at them")
			or String(o["desc"]).contains("line to them is blocked"),
			"%s: its line to the hostile is told (%s)" % [o["label"], o["desc"]],
		)
	t.expect_eq(listed, ids, "all four hostiles are listed, nearest first")
