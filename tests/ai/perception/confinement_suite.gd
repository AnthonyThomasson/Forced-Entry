extends UnitSuite
## Native unit suite (pure logic) for the NPC's confinement (`scenes/ai/perception/
## perception_confinement.gd`, the perception's part `confinement`): where it may act, from its
## territory (a defender keeps inside the house), the room a `defend_room` order keeps it to
## (`docs/leadership.md` LD8), its squad leash (LD23) and the room a stack held for its leader's go
## keeps it out of (LD13, D31). Fed plain rooms and points: no house, no world. Beneath the
## simulation tests of the territory, defend-room, ambush and leash behaviours
## (`tests/ai/flank/flank_territory_*`, `tests/ai/combat/defend_room_*`, `ambush_*`, `leash_*`, and
## the held stacks' `tests/ai/stack/rally_held_fights_stack_side`,
## `tests/ai/entry/order_stack_hold_fights_stack_side`)
## (ADR-0002): it supplements them, never replaces them. Each rule alone and combined, an option
## judged where it acts and the frozen copy; the planner's COMBAT filter and `Combat`'s choice of
## spot through the confinement's answers are game tests beside them
## (`ai/decision/combat_options_within_confinement`, `ai/combat/combat_spot_within_confinement`).
## The expected values are read off the rules (ticket #97's C1 to C3, C4's frozen copy, and ticket
## #127's keep-out), never worked out the way the code does.

const Confinement := preload("res://scenes/ai/perception/perception_confinement.gd")
## Two rooms side by side, sharing the wall at x = 100: the hall west of it, the kitchen east.
const HALL := { "key": "hall", "type": "hall", "rect": Rect2(0, 0, 100, 100) }
const KITCHEN := { "key": "kitchen", "type": "kitchen", "rect": Rect2(100, 0, 100, 100) }
const IN_HALL := Vector2(50, 50)
const IN_KITCHEN := Vector2(150, 50)
const OUTSIDE := Vector2(300, 50)
## A defend order for the hall, as a squad posts one (LD5).
const DEFEND_HALL := { "id": "o1", "kind": "defend_room", "room": "hall" }


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


func test_a_held_stacks_room_keeps_it_out() -> void:
	# D31: a member of a stack held for its leader's go acts only on the stack's side of the
	# doorway.
	var c := _confinement(false, {}, Vector2.INF, 0.0, "kitchen")
	assert_bool(c.confines()).override_failure_message("the keep-out alone confines it").is_true()
	assert_bool(c.allows(IN_HALL)).override_failure_message("the stack's side").is_true()
	assert_bool(c.allows(OUTSIDE)).override_failure_message("outside the house").is_true()
	assert_bool(c.allows(IN_KITCHEN)).override_failure_message("the held room").is_false()
	_expect_option(c, { "id": "fire_n", "params": { "point": IN_KITCHEN } }, false, "a spot in it")
	_expect_option(c, { "id": "fire_s", "params": { "point": IN_HALL } }, true, "a spot out of it")
	_expect_option(
		c,
		{ "id": "frag", "params": { "from": IN_HALL, "point": IN_KITCHEN } },
		true,
		"a throw from the stack's side into it",
	)


func test_a_held_stacks_room_inside_the_territory() -> void:
	# A territorial member of a held stack: in the house, and out of the held room.
	var c := _confinement(true, {}, Vector2.INF, 0.0, "kitchen")
	assert_bool(c.allows(IN_HALL)).override_failure_message("in the house, out of it").is_true()
	assert_bool(c.allows(IN_KITCHEN)).override_failure_message(
		"in the house, but the held room",
	).is_false()
	assert_bool(c.allows(OUTSIDE)).override_failure_message(
		"out of the held room, but outside the house",
	).is_false()


func test_a_copy_and_the_view_carry_the_keep_out() -> void:
	var c := _confinement(false, {}, Vector2.INF, 0.0, "kitchen")
	var frozen = c.copy()
	c.refresh(false, {}, Vector2.INF, 0.0, "")
	assert_bool(c.allows(IN_KITCHEN)).override_failure_message(
		"premise: the live one, refreshed with no keep-out, allows the kitchen",
	).is_true()
	assert_bool(frozen.allows(IN_KITCHEN)).override_failure_message(
		"the copy still keeps it out of the kitchen",
	).is_false()
	assert_str(String(frozen.view().get("keep_out", ""))).override_failure_message(
		"the view names the room it keeps out of",
	).is_equal("kitchen")
	assert_bool(bool(frozen.view().get("confines", false))).override_failure_message(
		"the view says it is confined",
	).is_true()


## A confinement over the two rooms, refreshed with `territorial`, `order`, the leash and the room
## it keeps out of (`keep_out`).
func _confinement(
	territorial: bool,
	order: Dictionary,
	center: Vector2,
	radius: float,
	keep_out := "",
) -> RefCounted:
	var c: RefCounted = Confinement.new()
	c.rooms = [HALL, KITCHEN]
	c.refresh(territorial, order, center, radius, keep_out)
	return c


## Asserts `c` allows option `o` (`want`), saying `what` it is.
func _expect_option(c: RefCounted, o: Dictionary, want: bool, what: String) -> void:
	assert_bool(c.allows_option(o)).override_failure_message(
		"%s: %s" % [what, "allowed" if want else "refused"],
	).is_equal(want)
