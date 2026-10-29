extends GameTest
## The planner's COMBAT filter (ticket #97's C3 and C4): inside COMBAT the planner offers only the
## options the snapshot's confinement allows where they act (`params.from`, else `params.point`),
## drops nothing while nothing confines the NPC, and words a branch with the group's inside summary
## while the territory is on. The planner is walked over hand-made snapshots (one hostile known,
## its fire spots and throws laid out in two rooms side by side) with the scripted Von, the
## confinement fed plain rooms; the arena the test world builds plays no part. The expected values
## are read off the rules, never worked out the way the code does.

const Confinement := preload("res://scenes/ai/perception/perception_confinement.gd")
const DecisionPlanner := preload("res://scenes/ai/decision/decision_planner.gd")
## Two rooms side by side, sharing the wall at x = 100: the hall west of it, the kitchen east.
const HALL := { "key": "hall", "type": "hall", "rect": Rect2(0, 0, 100, 100) }
const KITCHEN := { "key": "kitchen", "type": "kitchen", "rect": Rect2(100, 0, 100, 100) }
const IN_HALL := Vector2(50, 50)
const IN_KITCHEN := Vector2(150, 50)
const OUTSIDE := Vector2(300, 50)
## The hostile the hand-made snapshots know of.
const HOSTILE_ID := 7


func describe() -> Dictionary:
	return {
		"name": "COMBAT offers only what the confinement allows",
		"description": "The planner walked over hand-made snapshots: a spot outside a territorial "
			+ "defender's house is not offered, a throw from inside onto a spot outside is, "
			+ "nothing is dropped with nothing confining, and the inside summary words the branch.",
		"tags": ["ai", "decision", "territory", "scripted", "unit"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.von_script([])


func run(t: TestContext) -> void:
	await _filters_the_spots(t)
	await _offers_a_throw_from_inside(t)
	await _drops_nothing_unconfined(t)
	await _reads_the_inside_summary(t)


## C4: inside COMBAT the planner drops every option the snapshot's confinement does not allow. Von
## would take the spot outside: it is not offered, so the one inside is taken unasked.
func _filters_the_spots(t: TestContext) -> void:
	var snap := _snapshot(_confinement(true), [
		_spot("fire_in", IN_KITCHEN, true), _spot("fire_out", OUTSIDE, false),
	], [])
	var walk := await _walk(t, snap, [{ "pick": "engage" }, { "pick": "fire_out" }])
	var engage := _level(walk["planner"], &"engage")
	t.check(
		engage.get("auto", false) == true,
		"ENGAGE had one spot left, taken unasked (level %s)" % str(engage),
	)
	t.expect_eq(_keys(engage), ["fire_in"], "ENGAGE offers the spot in the house only")
	t.check(
		"fire_in" in _strings(walk["leaf"].get("path", [])),
		"the walk ends at the spot in the house (leaf %s)" % str(walk["leaf"]),
	)


## C3: a grenade option is judged where it is thrown from: from inside the house onto a spot
## outside it, a territorial defender may throw. Its `inside` tag (the burst spot's) is wording.
func _offers_a_throw_from_inside(t: TestContext) -> void:
	var snap := _snapshot(_confinement(true), [_spot("fire_in", IN_KITCHEN, true)], [
		{
			"id": "frag", "label": "frag", "desc": "frag them in the open",
			"params": {
				"point": OUTSIDE, "from": IN_KITCHEN, "kind": &"frag", "target_id": HOSTILE_ID,
			},
			"tags": { "inside": false },
		},
	])
	var walk := await _walk(t, snap, [{ "pick": "grenade" }])
	var combat := _level(walk["planner"], &"combat")
	var leaf: Dictionary = walk["leaf"]
	t.check(
		"grenade" in _keys(combat),
		"COMBAT offers GRENADE (offered %s)" % str(_keys(combat)),
	)
	t.expect_eq(
		String(leaf.get("primitive", "")),
		"throw",
		"and the walk ends at the throw (leaf %s)" % str(leaf),
	)
	t.expect_eq(leaf.get("params", {}).get("from"), IN_KITCHEN, "thrown from inside the house")


## With nothing confining the NPC, the planner drops nothing: the spot outside is offered too.
func _drops_nothing_unconfined(t: TestContext) -> void:
	var snap := _snapshot(_confinement(false), [
		_spot("fire_in", IN_KITCHEN, true), _spot("fire_out", OUTSIDE, false),
	], [])
	var walk := await _walk(t, snap, [{ "pick": "engage" }, { "pick": "fire_out" }])
	var engage := _level(walk["planner"], &"engage")
	var offered := _keys(engage)
	offered.sort()
	t.expect_eq(
		offered,
		["fire_in", "fire_out"],
		"ENGAGE offers both spots, the one outside too (level %s)" % str(engage),
	)


## C4: `summary_inside` is still chosen while the territory is on, so a branch never advertises a
## place the filter dropped.
func _reads_the_inside_summary(t: TestContext) -> void:
	var snap := _snapshot(_confinement(true), [
		_spot("fire_in", IN_KITCHEN, true), _spot("fire_out", OUTSIDE, false),
	], [
		{
			"id": "frag", "label": "frag", "desc": "frag them",
			"params": { "point": IN_HALL, "from": IN_KITCHEN, "kind": &"frag" },
			"tags": { "inside": true },
		},
	])
	var walk := await _walk(t, snap, [{ "pick": "engage" }])
	var combat := _level(walk["planner"], &"combat")
	t.check(
		String(combat.get("offered", {}).get("engage", "")).contains("SUMMARY INSIDE"),
		"ENGAGE's branch reads the inside summary (level %s)" % str(combat),
	)


## A confinement over the two rooms with only the territory, on or off.
func _confinement(territorial: bool) -> RefCounted:
	var c: RefCounted = Confinement.new()
	c.rooms = [HALL, KITCHEN]
	c.refresh(territorial, {}, Vector2.INF, 0.0)
	return c


## A hand-made decision snapshot: one hostile known, whose fire spots are `spots` and whose throws
## are `throws`, with the confinement `c`'s frozen copy.
func _snapshot(c: RefCounted, spots: Array, throws: Array) -> Dictionary:
	var per := {
		"fire_positions": {
			"summary": "SUMMARY", "summary_inside": "SUMMARY INSIDE", "options": spots,
		},
	}
	if not throws.is_empty():
		per["grenade_throws"] = {
			"summary": "", "situation": "Your line is blocked", "options": throws,
		}
	var hostile := {
		"id": "intruder", "label": "Intruder", "desc": "Intruder",
		"bind": { "target_id": HOSTILE_ID, "target": "Intruder" },
	}
	return {
		"facts": {
			"threat_known": true, "hostile_known": true, "gun_loaded": true,
			"grenade_ready": not throws.is_empty(),
		},
		"sections": {},
		"sections_per_target": {},
		"options": {
			"hostiles": { "summary": "", "options": [hostile] },
			"per_target": { HOSTILE_ID: per },
		},
		"gun": "pistol",
		"confinement": c.copy(),
	}


## A firing spot option at `p`, its `inside` tag saying whether that is in the house.
func _spot(id: String, p: Vector2, inside: bool) -> Dictionary:
	return {
		"id": id, "label": id, "desc": "fire from %s" % id,
		"params": { "point": p, "style": &"peek_cover" }, "tags": { "inside": inside },
	}


## Walks `snap` from COMBAT on a fresh planner under the world, the scripted Von answering by
## `rules`: `{ planner, leaf }`, the leaf decided ({} when the walk failed or did not end).
func _walk(t: TestContext, snap: Dictionary, rules: Array) -> Dictionary:
	DecisionStub.rules = rules
	DecisionStub.requests = []
	var planner: Node = DecisionPlanner.new()
	t.world.add_child(planner)
	planner.entry_rules = { &"hostile_known": &"combat" }
	planner.setup(_tuning(t))
	var out := {}
	planner.decided.connect(func(leaf: Dictionary) -> void: out.merge(leaf))
	planner.begin(snap, false)
	for i in 30:
		if not planner.is_pending():
			break
		await t.frames(1)
	return { "planner": planner, "leaf": out }


## The default decision tuning, its node kept under the world (freed with it).
func _tuning(t: TestContext) -> NpcDecisionTuning:
	var tuning := NpcTuning.defaults()
	t.world.add_child(tuning)
	return tuning.decision


## The walk's level at node `node`, the last one there ({} when it never reached it): for COMBAT,
## the level once its hostile is bound (its bind level, taken unasked, comes first).
func _level(planner: Node, node: StringName) -> Dictionary:
	var found := {}
	for level in planner.debug_state()["levels"]:
		if level["node"] == String(node):
			found = level
	return found


## The ids a level offered, as Strings.
func _keys(level: Dictionary) -> Array:
	return _strings((level.get("offered", {}) as Dictionary).keys())


## `values` as Strings.
func _strings(values: Array) -> Array:
	return values.map(func(v): return String(v))
