extends UnitSuite
## Native unit suite (pure logic) for the NPC's confinement (`scenes/ai/perception/
## perception_confinement.gd`, the perception's part `confinement`): where it may act, from its
## territory (a defender keeps inside the house), the room a `defend_room` order keeps it to
## (`docs/leadership.md` LD8) and its squad leash (LD23). Fed plain rooms and points: no house, no
## world. Beneath the simulation tests of the territory, defend-room, ambush and leash behaviours
## (`tests/ai/flank/flank_territory_*`, `tests/ai/combat/defend_room_*`, `ambush_*`, `leash_*`)
## (ADR-0002): it supplements them, never replaces them. Beside the rules, the planner's COMBAT
## filter on hand-made snapshots and `Combat`'s choice of spot (driven with stand-ins) through the
## confinement's answers. The expected values are read off the rules (ticket #97's C1 to C6), never
## worked out the way the code does.

const Confinement := preload("res://scenes/ai/perception/perception_confinement.gd")
const DecisionPlanner := preload("res://scenes/ai/decision/decision_planner.gd")
const Combat := preload("res://scenes/ai/behavior/combat.gd")
## Two rooms side by side, sharing the wall at x = 100: the hall west of it, the kitchen east.
const HALL := { "key": "hall", "type": "hall", "rect": Rect2(0, 0, 100, 100) }
const KITCHEN := { "key": "kitchen", "type": "kitchen", "rect": Rect2(100, 0, 100, 100) }
const IN_HALL := Vector2(50, 50)
const IN_KITCHEN := Vector2(150, 50)
const OUTSIDE := Vector2(300, 50)
## A defend order for the hall, as a squad posts one (LD5).
const DEFEND_HALL := { "id": "o1", "kind": "defend_room", "room": "hall" }
## The hostile the hand-made snapshots below know of.
const HOSTILE_ID := 7

## The scripted Von's statics as a test found them, put back after it.
var _stub_saved := {}
## The planner of the walk under test.
var _planner: Node


func before_test() -> void:
	super()
	_stub_saved = {
		"active": DecisionStub.active, "fail": DecisionStub.fail,
		"rules": DecisionStub.rules, "requests": DecisionStub.requests,
		"latency_frames": DecisionStub.latency_frames,
	}


func after_test() -> void:
	DecisionStub.active = _stub_saved["active"]
	DecisionStub.fail = _stub_saved["fail"]
	DecisionStub.rules = _stub_saved["rules"]
	DecisionStub.requests = _stub_saved["requests"]
	DecisionStub.latency_frames = _stub_saved["latency_frames"]
	await super()


func test_nothing_confines_an_npc_with_no_rule() -> void:
	var c := _confinement(false, {}, Vector2.INF, 0.0)
	assert_bool(c.confines()).override_failure_message("no rule: nothing confines it").is_false()
	for p in [IN_HALL, IN_KITCHEN, OUTSIDE]:
		assert_bool(c.allows(p)).override_failure_message("no rule: it may act at %s" % p).is_true()


func test_the_territory_keeps_it_in_the_house() -> void:
	var c := _confinement(true, {}, Vector2.INF, 0.0)
	assert_bool(c.confines()).override_failure_message("the territory confines it").is_true()
	assert_bool(c.allows(IN_HALL)).override_failure_message("a room of the house").is_true()
	assert_bool(c.allows(IN_KITCHEN)).override_failure_message("another room of it").is_true()
	assert_bool(c.allows(OUTSIDE)).override_failure_message("outside the house").is_false()


func test_a_defend_order_keeps_it_in_the_room() -> void:
	var c := _confinement(false, DEFEND_HALL, Vector2.INF, 0.0)
	assert_bool(c.confines()).override_failure_message("the order confines it").is_true()
	assert_bool(c.allows(IN_HALL)).override_failure_message("the room it defends").is_true()
	assert_bool(c.allows(IN_KITCHEN)).override_failure_message("the next room").is_false()
	assert_bool(c.allows(OUTSIDE)).override_failure_message("outside the house").is_false()


func test_only_a_defend_order_names_a_room() -> void:
	# LD8 confines a defend order's fight; an ambush (LD15) or a stack keeps no room.
	for order in [
		{ "id": "o2", "kind": "ambush", "room": "hall", "opening": "door_1" },
		{ "id": "o3", "kind": "stack", "opening": "door_1", "into": "hall" },
	]:
		var c := _confinement(false, order, Vector2.INF, 0.0)
		assert_bool(c.confines()).override_failure_message(
			"a %s order confines nothing" % order["kind"],
		).is_false()
		assert_bool(c.allows(IN_KITCHEN)).override_failure_message(
			"a %s order: the next room is allowed" % order["kind"],
		).is_true()


func test_the_leash_keeps_it_near_its_leader() -> void:
	var c := _confinement(false, {}, Vector2(0, 0), 100.0)
	assert_bool(c.confines()).override_failure_message("the leash confines it").is_true()
	assert_bool(c.allows(Vector2(60, 0))).override_failure_message("60 px of 100").is_true()
	assert_bool(c.allows(Vector2(0, -100))).override_failure_message("on the leash's end").is_true()
	assert_bool(c.allows(Vector2(150, 0))).override_failure_message("150 px of 100").is_false()


func test_no_leader_means_no_leash() -> void:
	# C1: with no leash centre the leash is 0 and binds nothing, whatever radius was handed in.
	var c := _confinement(false, {}, Vector2.INF, 320.0)
	assert_bool(c.confines()).override_failure_message("no leash centre, no leash").is_false()
	assert_float(c.leash).override_failure_message("its leash reads 0").is_equal(0.0)
	assert_bool(c.allows(Vector2(5000, 0))).override_failure_message("far off: allowed").is_true()


func test_an_ordered_room_inside_the_territory() -> void:
	# A territorial defender ordered to defend the hall: the hall only, not the rest of the house.
	var c := _confinement(true, DEFEND_HALL, Vector2.INF, 0.0)
	assert_bool(c.allows(IN_HALL)).override_failure_message("the room it defends").is_true()
	assert_bool(c.allows(IN_KITCHEN)).override_failure_message(
		"the kitchen: in the house, but not the room it defends",
	).is_false()
	assert_bool(c.allows(OUTSIDE)).override_failure_message("outside").is_false()


func test_a_leash_crossing_a_rooms_wall() -> void:
	# The leash's circle round a point by the hall's east wall reaches into the kitchen: a point in
	# the kitchen within the leash is still refused while the order keeps it to the hall.
	var c := _confinement(false, DEFEND_HALL, Vector2(80, 50), 100.0)
	var over_the_wall := Vector2(150, 50)
	assert_bool(c.allows(Vector2(20, 50))).override_failure_message(
		"in the hall, within the leash",
	).is_true()
	assert_bool(c.allows(over_the_wall)).override_failure_message(
		"in the kitchen, 70 px of a 100 px leash: the wall bounds it",
	).is_false()
	assert_bool(c.allows(Vector2(-90, 50))).override_failure_message(
		"outside, beyond the leash",
	).is_false()


func test_a_territorial_leash_crossing_the_house_wall() -> void:
	# A territorial follower: the leash reaches out of the house, the territory does not.
	var c := _confinement(true, {}, Vector2(180, 50), 100.0)
	assert_bool(c.allows(IN_KITCHEN)).override_failure_message(
		"in the house, on the leash",
	).is_true()
	assert_bool(c.allows(Vector2(250, 50))).override_failure_message(
		"70 px out of the house, on the leash: still outside the house",
	).is_false()
	assert_bool(c.allows(Vector2(20, 50))).override_failure_message(
		"in the house, 160 px off a 100 px leash",
	).is_false()


func test_an_option_is_judged_where_it_acts_from_else_its_point() -> void:
	# C3: `params.from`, else `params.point`; an option naming no place is allowed.
	var c := _confinement(true, {}, Vector2.INF, 0.0)
	var throw_from_inside := {
		"id": "frag", "params": { "from": IN_HALL, "point": OUTSIDE, "kind": &"frag" },
	}
	var throw_from_outside := { "id": "frag", "params": { "from": OUTSIDE, "point": IN_HALL } }
	var spot_inside := { "id": "fire_n", "params": { "point": IN_KITCHEN } }
	var spot_outside := { "id": "fire_s", "params": { "point": OUTSIDE } }
	var reload := { "id": "reload", "label": "reload your pistol" }
	var punch := { "id": "punch", "params": { "target_id": 7 } }
	var no_place := { "id": "here", "params": { "point": Vector2.INF } }
	_expect_option(c, throw_from_inside, true, "a throw from inside onto a spot outside")
	_expect_option(c, throw_from_outside, false, "a throw from outside onto a spot inside")
	_expect_option(c, spot_inside, true, "a spot in the house")
	_expect_option(c, spot_outside, false, "a spot outside")
	_expect_option(c, reload, true, "a reload, which names no place")
	_expect_option(c, punch, true, "a punch, which names no place")
	_expect_option(c, no_place, true, "an option whose point is no place")


func test_a_copy_is_frozen_against_a_later_refresh() -> void:
	var c := _confinement(true, DEFEND_HALL, Vector2(50, 50), 30.0)
	var frozen = c.copy()
	c.refresh(false, {}, Vector2.INF, 0.0)
	assert_bool(c.allows(OUTSIDE)).override_failure_message(
		"premise: the live one, refreshed with no rule, allows outside",
	).is_true()
	assert_bool(frozen.allows(OUTSIDE)).override_failure_message(
		"the copy still keeps it in the house",
	).is_false()
	assert_bool(frozen.allows(IN_KITCHEN)).override_failure_message(
		"the copy still keeps it to the hall",
	).is_false()
	assert_bool(frozen.allows(IN_HALL)).override_failure_message(
		"and still allows the hall, within its leash",
	).is_true()
	assert_bool(frozen.allows(Vector2(10, 10))).override_failure_message(
		"its leash still holds: in the hall, but 57 px off a 30 px leash",
	).is_false()


func test_combat_offers_only_the_options_the_confinement_allows() -> void:
	# C4: inside COMBAT the planner drops every option the snapshot's confinement does not allow.
	# Von would take the spot outside: it is not offered, so the one inside is taken unasked.
	var snap := _snapshot(_confinement(true, {}, Vector2.INF, 0.0), [
		_spot("fire_in", IN_KITCHEN, true), _spot("fire_out", OUTSIDE, false),
	], [])
	var leaf := await _walk(snap, [{ "pick": "engage" }, { "pick": "fire_out" }])
	var engage := _level(&"engage")
	assert_bool(engage.get("auto", false)).override_failure_message(
		"ENGAGE had one spot left, taken unasked (level %s)" % str(engage),
	).is_true()
	assert_array((engage.get("offered", {}) as Dictionary).keys()).override_failure_message(
		"ENGAGE offers the spot in the house only",
	).is_equal(["fire_in"])
	assert_array(leaf.get("path", [])).override_failure_message(
		"the walk ends at the spot in the house",
	).contains(["fire_in"])


func test_a_territorial_throw_from_inside_onto_a_spot_outside_is_offered() -> void:
	# C3: a grenade option is judged where it is thrown from: from inside the house onto a spot
	# outside it, a territorial defender may throw. Its `inside` tag (the burst spot's) is wording.
	var snap := _snapshot(_confinement(true, {}, Vector2.INF, 0.0), [
		_spot("fire_in", IN_KITCHEN, true),
	], [
		{
			"id": "frag", "label": "frag", "desc": "frag them in the open",
			"params": {
				"point": OUTSIDE, "from": IN_KITCHEN, "kind": &"frag", "target_id": HOSTILE_ID,
			},
			"tags": { "inside": false },
		},
	])
	var leaf := await _walk(snap, [{ "pick": "grenade" }])
	var combat := _level(&"combat")
	assert_array((combat.get("offered", {}) as Dictionary).keys()).override_failure_message(
		"COMBAT offers GRENADE (offered %s)" % str(combat.get("offered", {}).keys()),
	).contains(["grenade"])
	assert_str(String(leaf.get("primitive", ""))).override_failure_message(
		"and the walk ends at the throw (leaf %s)" % str(leaf),
	).is_equal("throw")
	assert_that(leaf.get("params", {}).get("from")).override_failure_message(
		"thrown from inside the house",
	).is_equal(IN_KITCHEN)


func test_nothing_is_dropped_with_nothing_confining() -> void:
	var snap := _snapshot(_confinement(false, {}, Vector2.INF, 0.0), [
		_spot("fire_in", IN_KITCHEN, true), _spot("fire_out", OUTSIDE, false),
	], [])
	await _walk(snap, [{ "pick": "engage" }, { "pick": "fire_out" }])
	var engage := _level(&"engage")
	assert_array((engage.get("offered", {}) as Dictionary).keys()).override_failure_message(
		"ENGAGE offers both spots, the one outside too (level %s)" % str(engage),
	).contains_exactly_in_any_order(["fire_in", "fire_out"])


func test_a_territorial_walk_reads_the_groups_inside_summary() -> void:
	# C4: `summary_inside` is still chosen while the territory is on, so a branch never advertises
	# a place the filter dropped.
	var snap := _snapshot(_confinement(true, {}, Vector2.INF, 0.0), [
		_spot("fire_in", IN_KITCHEN, true), _spot("fire_out", OUTSIDE, false),
	], [
		{
			"id": "frag", "label": "frag", "desc": "frag them",
			"params": { "point": IN_HALL, "from": IN_KITCHEN, "kind": &"frag" },
			"tags": { "inside": true },
		},
	])
	await _walk(snap, [{ "pick": "engage" }])
	var combat := _level(&"combat")
	assert_str(String(combat.get("offered", {}).get("engage", ""))).override_failure_message(
		"ENGAGE's branch reads the inside summary (level %s)" % str(combat),
	).contains("SUMMARY INSIDE")


func test_a_territorial_npc_keeps_its_spots_in_the_house_against_a_contact_inside() -> void:
	var c := _confinement(true, {}, Vector2.INF, 0.0)
	var in_kitchen_corner := Vector2(180, 80)
	var rig := _combat(c, IN_HALL, [OUTSIDE, in_kitchen_corner])
	rig["combat"].peek_cover(0.016, null, IN_KITCHEN)
	assert_vector(rig["loco"].dest).override_failure_message(
		"a territorial NPC fighting a contact in the kitchen peeks from the kitchen spot, not the "
				+ "nearer one outside the house (walks to %s)" % rig["loco"].dest,
	).is_equal(in_kitchen_corner)


func test_a_leashed_npc_with_no_fire_spot_closes_on_a_contact_within_its_leash() -> void:
	var c := _confinement(false, {}, IN_HALL, 200.0)
	var rig := _combat(c, IN_HALL, [])
	rig["combat"].peek_cover(0.016, null, IN_KITCHEN)
	assert_vector(rig["loco"].dest).override_failure_message(
		"with no fire spot, a leashed NPC closes on a contact within its leash (walks to %s)"
				% rig["loco"].dest,
	).is_equal(IN_KITCHEN)


func test_with_no_fire_spot_it_holds_against_a_contact_where_it_may_not_act() -> void:
	var c := _confinement(false, {}, IN_HALL, 60.0)
	var rig := _combat(c, IN_HALL, [])
	rig["combat"].peek_cover(0.016, null, IN_KITCHEN)
	assert_vector(rig["loco"].dest).override_failure_message(
		"with no fire spot, it holds where it stands against a contact off its leash (walks to %s)"
				% rig["loco"].dest,
	).is_equal(IN_HALL)


## A confinement over the two rooms, refreshed with `territorial`, `order` and the leash.
func _confinement(
	territorial: bool,
	order: Dictionary,
	center: Vector2,
	radius: float,
) -> RefCounted:
	var c: RefCounted = Confinement.new()
	c.rooms = [HALL, KITCHEN]
	c.refresh(territorial, order, center, radius)
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


## Walks `snap` from COMBAT with the scripted Von answering by `rules`; the leaf decided ({} when
## the walk failed or did not end).
func _walk(snap: Dictionary, rules: Array) -> Dictionary:
	DecisionStub.active = true
	DecisionStub.fail = false
	DecisionStub.rules = rules
	DecisionStub.requests = []
	DecisionStub.latency_frames = 0
	var tuning: NpcTuning = auto_free(NpcTuning.defaults())
	_planner = auto_free(DecisionPlanner.new())
	add_child(_planner)
	_planner.entry_rules = { &"hostile_known": &"combat" }
	_planner.setup(tuning.decision)
	var out := {}
	_planner.decided.connect(func(leaf: Dictionary) -> void: out.merge(leaf))
	_planner.begin(snap, false)
	for i in 30:
		if not _planner.is_pending():
			break
		await get_tree().process_frame
	return out


## The walk's level at node `node`, the last one there ({} when it never reached it): for COMBAT,
## the level once its hostile is bound (its bind level, taken unasked, comes first).
func _level(node: StringName) -> Dictionary:
	var found := {}
	for level in _planner.debug_state()["levels"]:
		if level["node"] == String(node):
			found = level
	return found


## Asserts `c` allows option `o` (`want`), saying `what` it is.
func _expect_option(c: RefCounted, o: Dictionary, want: bool, what: String) -> void:
	assert_bool(c.allows_option(o)).override_failure_message(
		"%s: %s" % [what, "allowed" if want else "refused"],
	).is_equal(want)


## A `Combat` (no line to its contact, so a peek looks for a spot) for an NPC standing at `at`,
## confined by `c`, whose perception offers the fire and cover spots `spots`: `{ combat, loco }`,
## the locomotion recording where it is sent.
func _combat(c: RefCounted, at: Vector2, spots: Array) -> Dictionary:
	var loco: FakeLoco = auto_free(FakeLoco.new())
	var perception: FakePerception = auto_free(FakePerception.new())
	perception.confinement = c
	perception.spots = spots
	var me: FakeCharacter = auto_free(FakeCharacter.new())
	me.global_position = at
	var combat: RefCounted = Combat.new()
	combat.setup(loco, perception, auto_free(NpcTuning.defaults()))
	combat.bind(me)
	return { "combat": combat, "loco": loco }


## Locomotion that records where it is sent.
class FakeLoco extends Node:
	var dest := Vector2.INF

	func move_to(p: Vector2, _arrive := 0.0) -> void:
		dest = p


## Perception with no line to anything, offering `spots` as both the fire and the cover spots, and
## the confinement it is handed.
class FakePerception extends Node:
	var confinement: RefCounted
	var spots: Array = []

	func combat_spots(_node: Node2D, _pos: Vector2, _radius: float) -> Dictionary:
		return { "fire": spots.duplicate(), "cover": spots.duplicate() }

	func has_line_to(_node: Node2D, _point: Vector2) -> bool:
		return false

	func note_engaged() -> void:
		pass


## A character with just where it stands and faces, and a movement intent `Combat` may write.
class FakeCharacter extends Node:
	var global_position := Vector2.ZERO
	var facing := Vector2.RIGHT
	var movement := FakeMovement.new()


## The stand-in character's movement intent.
class FakeMovement extends RefCounted:
	var move_input := Vector2.ZERO
