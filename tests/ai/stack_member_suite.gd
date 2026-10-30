extends UnitSuite
## Native unit suite (pure logic) for one member's own claim in a doorway's stack (`StackMember`,
## `scenes/ai/perception/stack/stack_member.gd`): claim, keep and settle against a `DoorStack`, the
## side rule every member weighs its side by, its claim in the radio's field names, and the NPC's
## entry and the human's `PlayerStack` claiming alike, fed plain claims (`tests/_ai/
## stack_radio_probe.gd`) on a plain doorway. Beneath the simulation tests of `tests/ai/stack/` and
## `tests/ai/entry/` (ADR-0002): it supplements them, never replaces them. The expected values are
## read off the rules (`docs/tactical-entry.md` E2, E16, E19 to E21), never worked out the way the
## code does.

const DoorStack := preload("res://scenes/ai/perception/stack/door_stack.gd")
const StackMember := preload("res://scenes/ai/perception/stack/stack_member.gd")
const StackRadio := preload("res://tests/_ai/stack_radio_probe.gd")
## The frame the claims below are made on.
const FRAME := 100


func test_a_member_claims_the_first_free_slot_on_the_side_it_asks_for() -> void:
	# E2, E21: with the point on slot 1, a newcomer takes slot 2, on the side it asks for, first in
	# that side's file; the slot and side are the member's from then on.
	var point_man := StackRadio.claim(StackRadio.speaker(self), { "slot": 1, "side": 1 })
	var stack := DoorStack.new(StackRadio.door(), [point_man])
	var member := _member(Vector2(0, 200))
	assert_int(member.slot_in(stack)).override_failure_message(
		"the stack gives it slot 2",
	).is_equal(2)
	member.ask(-1, stack.team_side(Vector2(0, 200)))
	var at: Dictionary = member.claim(stack)
	var got := [member.slot, member.side, member.place, at["held"]]
	assert_array(got).override_failure_message(
		"slot 2, on the side it asked for, first in that file, held: %s" % str(got),
	).is_equal([2, -1, 1, true])
	assert_that(member.point).is_equal(StackRadio.slot_at(-1, 1))


func test_a_member_keeps_its_slot_and_gives_it_up_to_a_nearer_same_frame_claim() -> void:
	# E2: a claim on its slot made on its frame from nearer the slot keeps the slot; the member
	# takes the next one free and stands there, its claim's frame and spot kept for the settling.
	var mate := StackRadio.speaker(self)
	var member := _member(StackRadio.slot_at(1, 1) + Vector2(0, 150))
	var empty := DoorStack.new(StackRadio.door(), [])
	member.ask(1, empty.team_side(member.claim_pos))
	member.claim(empty)
	assert_int(member.slot).override_failure_message("premise: alone, it is the point").is_equal(1)
	var nearer := StackRadio.claim(mate, {
		"slot": 1, "side": 1, "claim_frame": FRAME,
		"claim_pos": StackRadio.slot_at(1, 1) + Vector2(0, 30),
	})
	member.claim(DoorStack.new(StackRadio.door(), [nearer]))
	var got := [member.slot, member.side, member.place, member.claim_frame]
	assert_array(got).override_failure_message(
		"the nearer keeps slot 1; it is second on that side, still its claim of frame %d: %s"
			% [FRAME, str(got)],
	).is_equal([2, 1, 2, FRAME])
	assert_that(member.point).is_equal(StackRadio.slot_at(1, 2))


func test_the_point_never_weighs_its_side_again() -> void:
	# E19: a member weighs its side on its claim; after that the point never does (a lone entrant
	# crosses in front of the door to slice its other side), and any other member only when the side
	# the team stacks on changed.
	var member := _member(Vector2(0, 200))
	assert_bool(member.weighs_side(1, 1)).override_failure_message(
		"on its claim it weighs its side",
	).is_true()
	member.ask(1, 1)
	assert_bool(member.weighs_side(1, -1)).override_failure_message(
		"the point, the team's side changed: it keeps its side",
	).is_false()
	assert_bool(member.weighs_side(2, 1)).override_failure_message(
		"slot 2, the team's side as it was: it keeps its side",
	).is_false()
	assert_bool(member.weighs_side(2, -1)).override_failure_message(
		"slot 2, the team's side changed: it weighs its side again",
	).is_true()


func test_its_claim_says_what_the_radio_says_by_the_radios_names() -> void:
	# The member as a stack reads one asking about itself: its claim's frame and spot by the radio's
	# names (`claim_frame` / `claim_pos`), and its terms (grenades, order, the human's marks).
	var member := _member(Vector2(10, 20))
	member.terms = { "stuns": 1, "order_id": "7", "human": true }
	var me: Dictionary = member.me()
	var got := [me.get("claim_frame"), me.get("claim_pos"), me.get("stuns"), me.get("order_id"),
		me.get("human"), me.has("frame"), me.has("pos")]
	assert_array(got).override_failure_message(
		"its frame and spot by the radio's names, its terms with them: %s" % str(me),
	).is_equal([FRAME, Vector2(10, 20), 1, "7", true, false, false])


func test_an_npc_and_the_human_claim_and_keep_alike() -> void:
	# E16: the human is a member like any other: claiming from the same spot on the same stack, an
	# NPC's member and the human's take the same slot, side, place and point, and weigh their side
	# by the same rule.
	var point_man := StackRadio.claim(StackRadio.speaker(self), { "slot": 1, "side": 1 })
	var at := Vector2(-80, 200)
	var npc := _member(at)
	var human := _member(at)
	human.terms = { "human": true, "leader": true }
	for m: RefCounted in [npc, human]:
		var stack := DoorStack.new(StackRadio.door(), [point_man])
		var n: int = m.slot_in(stack)
		var now: int = stack.team_side(at)
		if m.weighs_side(n, now):
			m.ask(-1, now)
		m.claim(stack)
	assert_array([human.slot, human.side, human.place, human.point]).override_failure_message(
		"the human's claim %s, the NPC's %s"
			% [str([human.slot, human.side, human.place, human.point]),
				str([npc.slot, npc.side, npc.place, npc.point])],
	).is_equal([npc.slot, npc.side, npc.place, npc.point])
	assert_array([human.weighs_side(2, -1), human.weighs_side(1, -1)]).is_equal(
		[npc.weighs_side(2, -1), npc.weighs_side(1, -1)],
	)


func test_a_member_whose_slot_changes_moves_up_no_more() -> void:
	# E2: a member that moved up from slot 3 into slot 2 and loses slot 2 to a member that moved up
	# into it too (the lower instance id keeps it) takes another slot, and is moving up no more.
	var pair: Array = [StackRadio.speaker(self), StackRadio.speaker(self)]
	pair.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	var member := _member(Vector2(0, 200), pair[1].get_instance_id())
	member.ask(1, 1)
	member.slot = 2
	member.move_up = 3
	var keeper := StackRadio.claim(pair[0], { "slot": 2, "side": 1, "move_up": 4 })
	member.claim(DoorStack.new(StackRadio.door(), [keeper]))
	assert_array([member.slot != 2, member.move_up]).override_failure_message(
		"it lost slot 2 (now %d) and moves up no more (move_up %d)" % [member.slot, member.move_up],
	).is_equal([true, 0])


## A member (instance id `id`, else a fresh speaker's) claiming on `FRAME` from `at`.
func _member(at: Vector2, id := 0) -> RefCounted:
	var m := StackMember.new()
	m.id = id if id != 0 else StackRadio.speaker(self).get_instance_id()
	m.begin(FRAME, at)
	return m
