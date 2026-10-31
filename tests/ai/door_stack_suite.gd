extends UnitSuite
## Native unit suite (pure logic) for the slot rules a doorway's stack settles its claims by
## (`DoorStack`, `scenes/ai/perception/stack/`), fed plain claims (callouts from the speakers of
## `tests/_ai/stack_radio_probe.gd`, decoded by `StackClaim`) and a plain doorway; the claim's wire
## format and the ledger are `tests/ai/stack_claim_suite.gd`'s. Beneath the simulation tests of
## `tests/ai/stack/` and `tests/ai/entry/` (ADR-0002): it supplements them, never replaces them. The
## expected values are read off the rules (`docs/tactical-entry.md` E2, E16, E19 to E21;
## `docs/leadership.md` LD9, LD13), never worked out the way the code does.

const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const DoorStack := preload("res://scenes/ai/perception/stack/door_stack.gd")
const StackRadio := preload("res://tests/_ai/stack_radio_probe.gd")
## The frame the same-frame claims below are made on.
const FRAME := 100
## The frame the held stack order "7" below was issued on.
const ORDER_FRAME := 500


func test_a_same_frame_tie_goes_to_the_nearer_claim() -> void:
	# E2: two claims on one slot made on one physics frame settle by distance to the slot, so their
	# walks do not cross; each reads the other's frame and spot off the radio, so both settle alike.
	var pair := _pair()
	var low: Node = pair[0]
	var high: Node = pair[1]
	var near := _slot_at(1, 1) + Vector2(0, 30)
	var far := _slot_at(1, 1) + Vector2(0, 150)
	var lows := _claim(low, { "slot": 1, "side": 1, "claim_frame": FRAME, "claim_pos": far })
	var highs := _claim(high, { "slot": 1, "side": 1, "claim_frame": FRAME, "claim_pos": near })
	var high_reads: int = DoorStack.new(_door(), [lows]).slot_for(_me(high, 1, near))
	var low_reads: int = DoorStack.new(_door(), [highs]).slot_for(_me(low, 1, far))
	assert_int(high_reads).override_failure_message(
		"the nearer keeps slot 1, its higher instance id notwithstanding (got %d)" % high_reads,
	).is_equal(1)
	assert_int(low_reads).override_failure_message(
		"and the farther gives it up for the next (got %d)" % low_reads,
	).is_equal(2)
	# Premise: on two frames it is no tie, and the lower instance id keeps the slot.
	lows["claim_frame"] = FRAME - 1
	assert_int(DoorStack.new(_door(), [lows]).slot_for(_me(high, 1, near))).is_equal(2)


func test_a_same_frame_tie_with_the_human_goes_to_the_nearer_claim() -> void:
	# E2, E16: the human's claim is a full one (its frame and spot), so a tie with it settles by
	# distance as any other, the AI's entry and the human's `PlayerStack` reading it alike.
	var pair := _pair()
	var near := _slot_at(1, 1) + Vector2(0, 30)
	var far := _slot_at(1, 1) + Vector2(0, 150)
	for human_first in [true, false]:
		var reads := _tie_reads(pair, human_first, near, far)
		var nearer := "the human" if human_first else "the AI"
		assert_array(reads).override_failure_message(
			"%s stood nearer: it keeps slot 1, the other takes 2 (human, AI: %s)"
				% [nearer, str(reads)],
		).is_equal([1, 2] if human_first else [2, 1])


func test_a_move_up_holds_against_a_plain_claim_and_its_holder_takes_the_freed_slot() -> void:
	# E2: a member that moved up from slot 3 into slot 2 holds it against the claim still on slot 2,
	# though that claim has the lower instance id, and that claim's member takes slot 3.
	var pair := _pair()
	var holder: Node = pair[0]
	var mover: Node = pair[1]
	var holders := _claim(holder, { "slot": 2, "side": 1 })
	var movers := _claim(mover, { "slot": 2, "side": 1, "move_up": 3 })
	var holder_reads: int = DoorStack.new(_door(), [movers]).slot_for(_me(holder, 2))
	var mover_me := _me(mover, 2).merged({ "move_up": 3 }, true)
	var mover_reads: int = DoorStack.new(_door(), [holders]).slot_for(mover_me)
	assert_int(mover_reads).override_failure_message(
		"the move-up holds slot 2 (got %d)" % mover_reads,
	).is_equal(2)
	assert_int(holder_reads).override_failure_message(
		"the member it moved up past takes slot 3, the one freed (got %d)" % holder_reads,
	).is_equal(3)
	var rows: Array = DoorStack.new(_door(), [holders, movers]).layout()
	var held: Array = rows.filter(func(r): return r["held"]).map(
		func(r): return [r["n"], r["holder"]],
	)
	assert_array(held).override_failure_message(
		"the stack is laid so for whoever reads it: %s" % str(held),
	).is_equal([[2, mover.get_instance_id()], [3, holder.get_instance_id()]])


func test_nobody_moves_up_into_the_humans_slot() -> void:
	# E2, E16: a member stacked behind a free claim may move up into it; never into the human's.
	var mate := StackRadio.speaker(self)
	var me := StackRadio.speaker(self)
	var mine := _me(me, 2).merged({ "want": 1 }, true)
	var ai := _claim(mate, { "slot": 1, "side": 1 })
	var vacancies: Array = DoorStack.new(_door(), [ai]).move_up_vacancies(mine)
	assert_array(vacancies.map(func(v): return v["slot"])).override_failure_message(
		"premise: an AI's slot 1, still at claim, is one to move up into",
	).is_equal([1])
	var human := _claim(mate, { "slot": 1, "side": 1, "human": true })
	assert_array(DoorStack.new(_door(), [human]).move_up_vacancies(mine)).override_failure_message(
		"the human's slot 1 is not",
	).is_empty()


func test_a_split_stack_crosses_point_then_the_sides_in_turn() -> void:
	# E6, E19: the point, then the front man of the other side, then the sides take turns, each in
	# slot order; a side that runs out leaves the rest to the other.
	var who: Array = range(6).map(func(_i): return StackRadio.speaker(self))
	var sides := [1, 1, -1, 1, -1, 1]  # Slots 1 to 6.
	var claims: Array = []
	for i in who.size():
		claims.append(_claim(who[i], { "slot": i + 1, "side": sides[i] }))
	var slots: Array = DoorStack.new(_door(), claims).crossing().map(func(m): return m["slot"])
	assert_array(slots).override_failure_message(
		"crossing order by slot: %s" % str(slots),
	).is_equal([1, 3, 2, 5, 4, 6])


func test_a_held_stack_is_released_by_its_go_or_its_own_crossing() -> void:
	# LD13, D14: a held stack's go is a claim under its order saying the go came, or a member of
	# that stack going in or through the doorway into its room: one under the order, or the human
	# (the human leader stepping in is its go).
	var a := StackRadio.speaker(self)
	var b := StackRadio.speaker(self)
	var held := { "order_id": "7", "order_hold": true }
	var point_man := _claim(a, held.merged({ "slot": 1, "side": 1, "entry_step": "ready" }))
	var waiting := _claim(b, held.merged({ "slot": 2, "side": 1, "entry_step": "ready" }))
	assert_bool(_releases_7([point_man, waiting])).override_failure_message(
		"premise: a stack all at ready holds",
	).is_false()
	var go := _claim(
		b,
		held.merged({ "slot": 2, "side": 1, "entry_step": "ready", "order_go": true }),
	)
	assert_bool(_releases_7([point_man, go])).override_failure_message(
		"a member under the order says the go came",
	).is_true()
	for step in ["going_in", "in", "clear", "cover", "rear"]:
		var own := _claim(b, held.merged({ "slot": 2, "side": 1, "entry_step": step }))
		assert_bool(_releases_7([point_man, own])).override_failure_message(
			"a member under the order at %s into its room is the go" % step,
		).is_true()
	for step in ["going_in", "in"]:
		var human := _claim(b, {
			"slot": 2, "side": 1, "entry_step": step, "human": true,
			"crossed_frame": ORDER_FRAME + 30,
		})
		assert_bool(_releases_7([point_man, human])).override_failure_message(
			"the human in the stack at %s into its room, crossed after the order, is the go" % step,
		).is_true()


func test_a_held_stack_is_not_released_by_another_stacks_claims() -> void:
	# LD13, D14: a claim left from an earlier entry through the same doorway (a member still holding
	# the room under no order, or another order's member through), another order's go, or a crossing
	# into the other room releases nothing.
	var a := StackRadio.speaker(self)
	var b := StackRadio.speaker(self)
	var point_man := _claim(
		a, { "order_id": "7", "order_hold": true, "slot": 1, "side": 1, "entry_step": "ready" },
	)
	var others := {
		"another order's go": { "order_id": "8", "order_go": true, "entry_step": "ready" },
	}
	for step in ["cover", "rear"]:
		others["a leftover %s under no order" % step] = { "entry_step": step }
	for step in ["going_in", "in", "cover"]:
		others["another order's member at %s" % step] = { "order_id": "8", "entry_step": step }
	for step in ["going_in", "in"]:
		others["its own order's member at %s into the other room" % step] = {
			"order_id": "7", "entry_step": step, "into": "kitchen",
		}
		others["the human at %s into the other room" % step] = {
			"human": true, "entry_step": step, "into": "kitchen", "crossed_frame": ORDER_FRAME + 30,
		}
	for why: String in others:
		var other := _claim(b, ({ "slot": 2, "side": 1 } as Dictionary).merged(others[why], true))
		assert_bool(_releases_7([point_man, other])).override_failure_message(
			"%s releases nothing" % why,
		).is_false()


func test_a_human_crossing_releases_a_held_stack_only_once_the_order_was_issued() -> void:
	# LD13, D14: the human's claim carries no order to scope it by, so its crossing is the held
	# stack's go only when it began on or after the frame the order was issued (`since`): an `in`
	# left on the radio from before releases nothing. The human leader that claimed its slot first
	# (its own claim, LD24) and ordered the stack second still releases it by stepping in. A claim
	# under the order releases it whenever it crossed.
	var a := StackRadio.speaker(self)
	var b := StackRadio.speaker(self)
	var point_man := _claim(
		a, { "order_id": "7", "order_hold": true, "slot": 1, "side": 1, "entry_step": "ready" },
	)
	for step in ["going_in", "in"]:
		var crossings := {
			"before the order": [ORDER_FRAME - 30, false],
			"on the order's frame": [ORDER_FRAME, true],
			"after it": [ORDER_FRAME + 30, true],
		}
		for when: String in crossings:
			var human := _claim(b, {
				"slot": 2, "side": 1, "entry_step": step, "human": true,
				"crossed_frame": crossings[when][0],
			})
			assert_bool(_releases_7([point_man, human])).override_failure_message(
				"the human at %s, crossed %s: released %s" % [step, when, str(crossings[when][1])],
			).is_equal(crossings[when][1])
	var own_first := _claim(b, {
		"slot": 1, "side": 1, "entry_step": "going_in", "human": true, "own": true,
		"claim_frame": ORDER_FRAME - 200, "crossed_frame": ORDER_FRAME + 30,
	})
	var follower := _claim(
		a, { "order_id": "7", "order_hold": true, "slot": 2, "side": 1, "entry_step": "ready" },
	)
	assert_bool(_releases_7([own_first, follower])).override_failure_message(
		"its own claim made before the order, its crossing after it: the go",
	).is_true()
	for crossed in [-1, ORDER_FRAME - 30]:
		var under := _claim(b, {
			"order_id": "7", "order_hold": true, "slot": 2, "side": 1, "entry_step": "going_in",
			"crossed_frame": crossed,
		})
		assert_bool(_releases_7([point_man, under])).override_failure_message(
			"a member under the order crossing (crossed_frame %d) is the go" % crossed,
		).is_true()


func test_a_human_crossing_of_unknown_frame_releases_nothing() -> void:
	# D14: a crossing not known to come after the order (the human's claim says no frame, or the
	# held order's frame is unknown) cannot be told from one left on the radio from before.
	var a := StackRadio.speaker(self)
	var b := StackRadio.speaker(self)
	var point_man := _claim(
		a, { "order_id": "7", "order_hold": true, "slot": 1, "side": 1, "entry_step": "ready" },
	)
	var unsaid := _claim(b, { "slot": 2, "side": 1, "entry_step": "in", "human": true })
	assert_bool(_releases_7([point_man, unsaid])).override_failure_message(
		"the human's claim saying no crossed_frame releases nothing",
	).is_false()
	var crossed := _claim(b, {
		"slot": 2, "side": 1, "entry_step": "in", "human": true, "crossed_frame": ORDER_FRAME + 30,
	})
	assert_bool(DoorStack.new(_door(), [point_man, crossed]).released("7", "hall", -1)).is_false()


func test_the_order_a_stack_goes_in_under_names_its_room() -> void:
	# LD13, D10: a held stack's go is read off the claims into the order's room, so the order a
	# stack goes in under names that room, its own or the teammate's it follows alike.
	var a := StackRadio.speaker(self)
	var me := StackRadio.speaker(self)
	var own: Dictionary = DoorStack.new(_door(), []).order_claim({
		"id": me.get_instance_id(), "slot": 1, "order_id": "7", "order_hold": true,
		"into": "hall", "order_frame": ORDER_FRAME,
	})
	assert_array([own.get("into"), own.get("order_frame")]).override_failure_message(
		"its own order, into the hall, issued on frame %d: %s" % [ORDER_FRAME, str(own)],
	).is_equal(["hall", ORDER_FRAME])
	var mate := _claim(a, {
		"slot": 1, "side": 1, "order_id": "7", "order_hold": true, "order_frame": ORDER_FRAME,
	})
	var followed: Dictionary = DoorStack.new(_door(), [mate]).order_claim({
		"id": me.get_instance_id(), "slot": 2,
	})
	assert_array([followed.get("into"), followed.get("order_frame")]).override_failure_message(
		"the teammate's order it follows (D10), into the hall, issued on frame %d: %s"
			% [ORDER_FRAME, str(followed)],
	).is_equal(["hall", ORDER_FRAME])


func test_the_layout_lays_each_slot_where_its_holder_settles() -> void:
	# E19, E21: each side's file runs from the door, a member's place in it its slot less the claims
	# across the door ahead of it. The squad's layout (every claim) and each member's own settling
	# (the others' claims: it never hears its own) agree on every point.
	var who: Array = range(4).map(func(_i): return StackRadio.speaker(self))
	var sides := [1, 1, -1, 1]  # Slots 1 to 4: slot 4 is third on its side.
	var claims: Array = []
	for i in who.size():
		claims.append(_claim(who[i], { "slot": i + 1, "side": sides[i] }))
	var rows: Array = DoorStack.new(_door(), claims).layout()
	var want := [_slot_at(1, 1), _slot_at(1, 2), _slot_at(-1, 1), _slot_at(1, 3)]
	assert_array(rows.map(func(r): return r["point"])).override_failure_message(
		"each slot at its place in its side's file: %s" % str(rows.map(func(r): return r["point"])),
	).is_equal(want)
	for r: Dictionary in rows:
		var own: Dictionary = claims[int(r["n"]) - 1]
		var others: Array = claims.filter(func(c): return c["id"] != own["id"])
		var settled: Dictionary = DoorStack.new(_door(), others).settle({
			"id": own["id"], "slot": r["n"], "want": own["side"],
		})
		assert_that(settled["point"]).override_failure_message(
			"slot %d: laid at %s, settled at %s" % [r["n"], str(r["point"]), str(settled["point"])],
		).is_equal(r["point"])


func test_a_split_stack_evens_its_sides_by_moving_its_last_claimer() -> void:
	# D6, E19: a member stacks on the side it stands on, but when that side would hold two more of
	# the stack than the other, the last of that side to have claimed takes the other side.
	var a := StackRadio.speaker(self)
	var b := StackRadio.speaker(self)
	var c := StackRadio.speaker(self)
	var me := StackRadio.speaker(self)
	var one_sided := [_claim(a, { "slot": 1, "side": 1 }), _claim(b, { "slot": 2, "side": 1 })]
	assert_int(
		DoorStack.new(
			_door(),
			[one_sided[0]],
		).split_side({ "id": me.get_instance_id(), "slot": 2 }, 1),
	).override_failure_message(
		"a second on the point's side, none across: two more there, it takes the other side",
	).is_equal(-1)
	var mine := { "id": me.get_instance_id(), "slot": 3 }
	assert_int(DoorStack.new(_door(), one_sided).split_side(mine, 1)).override_failure_message(
		"a third on a side holding two, none across: it takes the other side",
	).is_equal(-1)
	var even := [_claim(a, { "slot": 1, "side": 1 }), _claim(b, { "slot": 2, "side": -1 })]
	assert_int(DoorStack.new(_door(), even).split_side(mine, 1)).override_failure_message(
		"a side one ahead of the other with it there: it keeps its own side",
	).is_equal(1)
	var later := one_sided + [_claim(c, { "slot": 4, "side": 1 })]
	assert_int(DoorStack.new(_door(), later).split_side(mine, 1)).override_failure_message(
		"a later claimer on its side moves instead: it keeps its own side",
	).is_equal(1)
	var three := one_sided + [_claim(me, { "slot": 3, "side": 1 })]
	var last := { "id": c.get_instance_id(), "slot": 4 }
	assert_int(DoorStack.new(_door(), three).split_side(last, 1)).override_failure_message(
		"and that later claimer, weighing it the same way, takes the other side",
	).is_equal(-1)


func test_the_back_of_the_stack_is_the_slot_behind_the_last_claim() -> void:
	# E2, E20: a member that takes the back of the stack takes the slot behind the last one claimed,
	# unless it is the last already or the doorway has no slot there (a dead end holds so many).
	var who: Array = range(3).map(func(_i): return StackRadio.speaker(self))
	var ahead_and_behind := [
		_claim(who[0], { "slot": 1, "side": 1 }),
		_claim(who[1], { "slot": 3, "side": 1 }),
	]
	assert_int(DoorStack.new(_door(), ahead_and_behind).back_slot(2)).override_failure_message(
		"slot 2 with a claim on slot 3: the back is slot 4",
	).is_equal(4)
	var ahead := [
		_claim(who[0], { "slot": 1, "side": 1 }),
		_claim(who[1], { "slot": 2, "side": 1 }),
	]
	assert_int(DoorStack.new(_door(), ahead).back_slot(3)).override_failure_message(
		"the last already: no back to take",
	).is_equal(0)
	assert_int(DoorStack.new(_dead_end(), ahead_and_behind).back_slot(2)).override_failure_message(
		"a dead end holding three: no slot 4 to take",
	).is_equal(0)


func test_an_ordered_members_place_follows_the_recipients_before_it_and_every_other_claim() -> void:
	# E20, LD9: an ordered member's slot is after the recipients the order names before it and
	# after every claim on the doorway from anyone else, so it knows a dead end has no slot for it
	# before anyone claims.
	var first := StackRadio.speaker(self)
	var me := StackRadio.speaker(self)
	var last_named := StackRadio.speaker(self)
	var stranger := StackRadio.speaker(self)
	var to_ids := [first, me, last_named].map(func(m): return m.get_instance_id())
	var claims := [
		_claim(last_named, { "slot": 1, "side": 1 }),
		_claim(stranger, { "slot": 2, "side": 1 }),
		_claim(me, { "slot": 3, "side": 1 }),
	]
	var stack := DoorStack.new(_door(), claims)
	assert_int(stack.order_place(to_ids, me.get_instance_id())).override_failure_message(
		"one recipient named before it and one claim from outside the order: slot 3",
	).is_equal(3)
	assert_int(stack.order_place([], me.get_instance_id())).override_failure_message(
		"named nowhere in the order: after the two other claims, slot 3",
	).is_equal(3)
	var none: RefCounted = DoorStack.new(_door(), [])
	assert_int(none.order_place(to_ids, last_named.get_instance_id())).override_failure_message(
		"third named, nobody claiming yet: slot 3",
	).is_equal(3)


func test_the_claim_chain_takes_a_free_slot_the_side_asked_for_and_its_point() -> void:
	# E2, E20, E21: a member claims the lowest free slot and stands where the side it asks for in
	# that slot puts it; a dead end holding all it can has no slot for it.
	var a := StackRadio.speaker(self)
	var me := StackRadio.speaker(self)
	var point_man := [_claim(a, { "slot": 1, "side": 1 })]
	var claiming := {
		"id": me.get_instance_id(),
		"slot": 0,
		"claim_frame": FRAME,
		"claim_pos": Vector2(0, 200),
	}
	var at: Dictionary = DoorStack.new(_door(), point_man).claim(
		claiming.merged({ "want": -1 }, true),
	)
	var got := [at["slot"], at["held"], at["side"], at["place"]]
	assert_array(got).override_failure_message(
		"slot 2, held, on the side it asked for, first in that side's file: %s" % str(at),
	).is_equal([2, true, -1, 1])
	assert_that(at["point"]).is_equal(_slot_at(-1, 1))
	var keeping: Dictionary = DoorStack.new(_door(), point_man).claim(
		claiming.merged({ "slot": 2, "want": 1 }, true),
	)
	assert_array([keeping["slot"], keeping["side"], keeping["place"]]).override_failure_message(
		"kept, asking for the point's side: behind the point: %s" % str(keeping),
	).is_equal([2, 1, 2])
	assert_that(keeping["point"]).is_equal(_slot_at(1, 2))
	var full: Array = range(3).map(
		func(i): return _claim(StackRadio.speaker(self), { "slot": i + 1, "side": 1 }),
	)
	var none: Dictionary = DoorStack.new(_dead_end(), full).claim(
		claiming.merged({ "want": 1 }, true),
	)
	assert_array([none["slot"], none["held"]]).override_failure_message(
		"a dead end holding three, all claimed: slot 4, not held (%s)" % str(none),
	).is_equal([4, false])


func test_a_member_whose_slot_changes_is_settled_moving_up_no_more() -> void:
	# E2: a member that moved up from slot 3 into slot 2 and loses slot 2 (another member moved up
	# into it too, and keeps it on the lower instance id) takes the next slot free to it, slot 4,
	# where a plain claim made on its frame gives way to its move-up. Its move-up is over: the claim
	# on slot 4 is not counted at the slot 3 it freed, so on its side it stands third in the file,
	# behind the point and slot 2, with slots 3 and 4 across the door ahead of it in the claims.
	var who: Array = range(5).map(func(_i): return StackRadio.speaker(self))
	who.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	var into_two: Node = who[0]  # The lowest instance id: it keeps slot 2.
	var me: Node = who[4]
	var claims := [
		_claim(who[1], { "slot": 1, "side": 1 }),
		_claim(into_two, { "slot": 2, "side": 1, "move_up": 5 }),
		_claim(who[2], { "slot": 3, "side": -1 }),
		_claim(
			who[3],
			{ "slot": 4, "side": -1, "claim_frame": FRAME, "claim_pos": Vector2(0, 600) },
		),
	]
	var moving := _me(me, 2).merged({ "move_up": 3, "want": 1 }, true)
	var at: Dictionary = DoorStack.new(_door(), claims).claim(moving)
	assert_array([at["slot"], at["side"]]).override_failure_message(
		"premise: it loses slot 2 and takes slot 4, on its side (%s)" % str(at),
	).is_equal([4, 1])
	assert_int(at["place"]).override_failure_message(
		"third in its side's file, slots 3 and 4 across the door (place %d)" % at["place"],
	).is_equal(3)
	assert_that(at["point"]).override_failure_message(
		"its point is that place's, %s (got %s)" % [str(_slot_at(1, 3)), str(at["point"])],
	).is_equal(_slot_at(1, 3))


func test_an_ordered_stack_held_for_the_go_is_held_until_its_go() -> void:
	# LD13, D10, D14: an ordered stack that holds for its leader's go is held, and a member that
	# joined it unordered with it, until the go: latched by the member itself (`order_go`), or off
	# the claims (`released`); an ordered stack with no hold, or no order, is never held.
	var a := StackRadio.speaker(self)
	var me := StackRadio.speaker(self)
	var held := { "order_id": "7", "order_hold": true, "order_frame": ORDER_FRAME, "into": "hall" }
	var mine := _me(me, 2).merged(held, true)
	var point_man := _claim(a, held.merged({ "slot": 1, "side": 1, "entry_step": "ready" }, true))
	var cases := {
		"under the held order, no go": [mine, [point_man], true],
		"its own go latched": [mine.merged({ "order_go": true }, true), [point_man], false],
		"the point's claim saying the go came":
			[mine, [point_man.merged({ "order_go": true }, true)], false],
		"unordered, following the held order (D10)": [_me(me, 2), [point_man], true],
		"an order with no hold":
			[_me(me, 2).merged({ "order_id": "7", "into": "hall" }, true), [], false],
		"no order at all": [_me(me, 2), [], false],
	}
	for why: String in cases:
		var c: Array = cases[why]
		assert_bool(DoorStack.new(_door(), c[1]).held(c[0])).override_failure_message(
			"%s: held %s" % [why, str(c[2])],
		).is_equal(c[2])


func test_a_human_leaders_rally_is_held_until_the_leader_steps_in_or_a_go_comes() -> void:
	# LD24, D38: a join that waits for the human leader's go (the rally of its own claim) is held
	# while the leader's claim stands at claim or ready; the leader stepping in on a crossing begun
	# since the join, or a joiner of that rally saying its go came, releases it. A crossing or go
	# left on the radio from an earlier rally at the doorway releases nothing.
	var human := StackRadio.speaker(self)
	var mate := StackRadio.speaker(self)
	var me := StackRadio.speaker(self)
	var rally := { "join": true, "order_hold": true, "order_frame": ORDER_FRAME, "into": "hall" }
	var mine := _me(me, 3).merged(rally, true)
	var leader := { "slot": 1, "side": 1, "human": true, "leader": true, "own": true }
	var cases := {
		"the leader at ready": [{ "entry_step": "ready" }, {}, true],
		"the leader going in since the join":
			[{ "entry_step": "going_in", "crossed_frame": ORDER_FRAME + 30 }, {}, false],
		"the leader in since the join":
			[{ "entry_step": "in", "crossed_frame": ORDER_FRAME + 30 }, {}, false],
		"the leader in on a crossing begun before the join":
			[{ "entry_step": "in", "crossed_frame": ORDER_FRAME - 30 }, {}, true],
		"a joiner of the rally saying its go came":
			[{ "entry_step": "ready" }, rally.merged({ "order_go": true }, true), false],
		"a joiner of an earlier rally saying its go came": [
			{ "entry_step": "ready" },
			rally.merged({ "order_go": true, "order_frame": ORDER_FRAME - 300 }, true),
			true,
		],
	}
	for why: String in cases:
		var c: Array = cases[why]
		var claims := [_claim(human, leader.merged(c[0], true))]
		if not (c[1] as Dictionary).is_empty():
			claims.append(_claim(mate, (c[1] as Dictionary).merged({ "slot": 2, "side": 1 }, true)))
		assert_bool(DoorStack.new(_door(), claims).held(mine)).override_failure_message(
			"%s: held %s" % [why, str(c[2])],
		).is_equal(c[2])


func test_an_ai_leaders_rally_is_never_held() -> void:
	# LD24, D38: an AI leader's rally takes the point and goes in; its joins wait for no go.
	var ai_rally := _me(StackRadio.speaker(self), 3).merged({ "join": true, "into": "hall" }, true)
	var ai_leader := _claim(
		StackRadio.speaker(self), { "slot": 1, "side": 1, "entry_step": "ready" },
	)
	assert_bool(DoorStack.new(_door(), [ai_leader]).held(ai_rally)).override_failure_message(
		"an AI leader's rally (its joins wait for no go) is never held",
	).is_false()


func test_the_mode_a_stack_goes_in_is_the_orders_else_the_gos_else_its_first_claimers() -> void:
	# LD9, LD14, D1, D38, E17: an ordered stack goes in the order's mode, quiet once a member under
	# that order gave its grenade up; a human leader's rally goes in the mode its go named, quiet
	# before it or when the leader stepped in, and a join left from an earlier rally, gone through
	# into the room it cleared, names no mode to a later stack there; any other stack goes in its
	# first claimer's way, a stun only while every claim says bang and none gave it up; with nobody
	# claiming, the stack says nothing ("").
	var frag := { "order_id": "7", "order_mode": "frag", "order_bang": true, "into": "hall" }
	var rally := { "join": true, "order_hold": true, "order_frame": ORDER_FRAME, "into": "hall" }
	var mine := _me(StackRadio.speaker(self), 2)
	_assert_modes({
		"the order's frag": [mine.merged(frag, true), [], "frag"],
		"the order's frag, a member under it gave it up":
			[mine.merged(frag, true), [{ "order_id": "7", "bang_off": true, "bang": false }],
				"quiet"],
		"the order's frag, another order's member gave it up":
			[mine.merged(frag, true), [{ "order_id": "8", "bang_off": true, "bang": false }],
				"frag"],
		"unordered, following the order's frag (D10)": [mine, [frag], "frag"],
		"a rally held for its go": [mine.merged(rally, true), [{ "bang": true }], "quiet"],
		"a rally whose go named a stun":
			[mine.merged(rally, true).merged({ "order_go": true, "order_mode": "stun" }, true),
				[{ "bang": false }], "stun"],
		"a rally a joiner's go named a frag":
			[mine.merged(rally, true),
				[rally.merged({ "order_go": true, "order_mode": "frag" }, true)], "frag"],
		"unordered, a joiner of an earlier rally holding the room it cleared": [
			mine,
			[rally.merged({ "order_go": true, "order_mode": "frag", "entry_step": "clear" }, true),
				{ "bang": false }],
			"quiet",
		],
		"every claim says bang": [mine, [{ "bang": true }], "stun"],
		"a claim says quiet": [mine, [{ "bang": true }, { "bang": false }], "quiet"],
		"a claim gave the bang up": [mine, [{ "bang": false, "bang_off": true }], "quiet"],
		"nobody claiming": [mine, [], ""],
	})


## Asserts each case of `cases` (why -> `[me, the claims' fields, the mode]`): `me` reads the mode
## (`DoorStack.mode`) off a stack of those claims, the first on slot 1 and the rest from slot 3 on.
func _assert_modes(cases: Dictionary) -> void:
	for why: String in cases:
		var c: Array = cases[why]
		var claims: Array = []
		for i in (c[1] as Array).size():
			var fields: Dictionary = (c[1] as Array)[i]
			claims.append(_claim(
				StackRadio.speaker(self),
				fields.merged({ "slot": i + 1 + int(i >= 1), "side": 1 }, true),
			))
		var got: String = DoorStack.new(_door(), claims).mode(c[0])
		assert_str(got).override_failure_message(
			"%s: %s (got %s)" % [why, c[2], got],
		).is_equal(c[2])


## The probe's plain doorway (`StackRadio.door`).
func _door() -> Dictionary:
	return StackRadio.door()


## `_door()` as a dead end holding three: its wall's first two slots and one on its open floor.
func _dead_end() -> Dictionary:
	return _door().merged({
		"capped": true, "wall_n": 2, "seq": [{ "point": Vector2(0, 120), "row": 1 }],
	}, true)


## Whether `claims` on `_door()` say the held stack under order "7", issued on `ORDER_FRAME`, going
## into the hall, had its go (`DoorStack.released`).
func _releases_7(claims: Array) -> bool:
	return DoorStack.new(_door(), claims).released("7", "hall", ORDER_FRAME)


## The point of the `place`th slot of side `side`'s file of `_door()` (`StackRadio.slot_at`).
func _slot_at(side: int, place: int) -> Vector2:
	return StackRadio.slot_at(side, place)


## `speaker`'s claim on `_door()` as a listener holds it (`StackRadio.claim`).
func _claim(speaker: Node, fields: Dictionary) -> Dictionary:
	return StackRadio.claim(speaker, fields)


## `speaker` asking about itself (`DoorStack`'s `me`, the radio's names): holding slot `slot` on
## side 1, claimed on `FRAME` from `pos`.
func _me(speaker: Node, slot: int, pos := Vector2(0, 200)) -> Dictionary:
	return {
		"id": speaker.get_instance_id(), "slot": slot, "side": 1, "claim_frame": FRAME,
		"claim_pos": pos,
	}


## `test_a_same_frame_tie_with_the_human_goes_to_the_nearer_claim`'s same-frame tie of the
## speakers `pair` on slot 1, the human (the higher instance id when `human_first`, else the lower)
## claiming from `near` when `human_first` (else `far`) and the AI from the other: `[the human's
## slot, the AI's]`, each read from the other's claim.
func _tie_reads(pair: Array, human_first: bool, near: Vector2, far: Vector2) -> Array:
	var human: Node = pair[1] if human_first else pair[0]
	var ai: Node = pair[0] if human_first else pair[1]
	var human_at := near if human_first else far
	var ai_at := far if human_first else near
	var humans := _claim(human, {
		"slot": 1, "side": 1, "claim_frame": FRAME, "claim_pos": human_at, "human": true,
	})
	var ais := _claim(ai, { "slot": 1, "side": 1, "claim_frame": FRAME, "claim_pos": ai_at })
	var ai_reads: int = DoorStack.new(_door(), [humans]).slot_for(_me(ai, 1, ai_at))
	var human_reads: int = DoorStack.new(_door(), [ais]).slot_for(_me(human, 1, human_at))
	return [human_reads, ai_reads]


## Two speakers, the lower instance id first.
func _pair() -> Array:
	var two := [StackRadio.speaker(self), StackRadio.speaker(self)]
	two.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	return two
