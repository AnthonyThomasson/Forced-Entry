extends UnitSuite
## Native unit suite (pure logic) for the stack module (`scenes/ai/perception/stack/`): the entry
## claim's wire format (`StackClaim`, interface 10), the claims a listener keeps (`ClaimLedger`)
## and the slot rules a doorway's stack settles them by (`DoorStack`), fed plain callout dicts and
## a plain doorway. Beneath the simulation tests of `tests/ai/stack/` and
## `tests/ai/entry/` (ADR-0002): it supplements them, never replaces them. The expected values are
## read off the rules (`docs/tactical-entry.md` E2, E16, E17; `docs/leadership.md` LD7, LD24), never
## worked out the way the code does: a field a claim does not say means what the rule says it means
## (a member that says nothing of its bang never holds a stack back, E17), not what a table holds.

const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const ClaimLedger := preload("res://scenes/ai/perception/stack/claim_ledger.gd")
const DoorStack := preload("res://scenes/ai/perception/stack/door_stack.gd")
## The frame the same-frame claims below are made on.
const FRAME := 100


## A speaker on the radio: a character as a listener reads it (`is_dead`).
func _speaker(dead := false) -> Speaker:
	var s: Speaker = auto_free(Speaker.new())
	s.is_dead = dead
	return s


## A callout from `speaker` of side `faction` at `pos` with `fields` (its claim or other fields)
## over the header every callout carries.
func _callout(
	speaker: Node,
	fields: Dictionary,
	pos := Vector2(100, 50),
	faction := &"invader",
) -> Dictionary:
	var out := {
		"speaker": speaker, "faction": faction, "position": pos, "status": "", "path": "",
		"label": "", "target_id": 0, "point": pos,
	}
	out.merge(fields, true)
	return out


## A ledger hearing side `faction` from anywhere, its claims current for 6 s.
func _ledger(faction := &"invader") -> RefCounted:
	var ledger := ClaimLedger.new()
	ledger.setup({ "faction": faction, "range": 0.0, "ttl": 6.0 })
	return ledger


func test_a_claim_round_trips_through_the_codec() -> void:
	var fields := {
		"opening": "o_3", "into": "kitchen", "slot": 2, "side": -1, "entry_step": "ready",
		"bang": false, "bang_off": true, "stuns": 1, "frags": 2, "cleared_room": "",
		"covering": "o_5", "claim_frame": 812, "claim_pos": Vector2(40, 60), "move_up": 3,
		"pie": true, "order_id": "7", "order_bang": true, "order_mode": "frag",
		"order_hold": true, "order_go": true, "order_side": 1, "join": false, "human": false,
		"leader": true, "own": false,
	}
	var claim := StackClaim.decode(_callout(null, StackClaim.encode(fields)))
	for key in fields:
		assert_that(claim[key]).override_failure_message(
			"%s: %s decoded as %s" % [key, str(fields[key]), str(claim[key])],
		).is_equal(fields[key])
	assert_str(claim["step"]).is_equal("ready")
	assert_that(claim["pos"]).is_equal(Vector2(100, 50))


func test_the_encoding_carries_every_entry_field_and_no_header() -> void:
	var wire := StackClaim.encode({ "opening": "o_1", "slot": 1, "entry_step": "claim" })
	for key in [
		"opening", "into", "slot", "side", "entry_step", "bang", "bang_off", "stuns", "frags",
		"cleared_room", "covering", "claim_frame", "claim_pos", "move_up", "pie", "order_id",
		"order_bang", "order_mode", "order_hold", "order_go", "order_side", "join", "human",
		"leader", "own",
	]:
		assert_bool(wire.has(key)).override_failure_message("%s is on the wire" % key).is_true()
	for key in ["speaker", "faction", "position", "status", "path", "label", "point"]:
		assert_bool(wire.has(key)).override_failure_message("%s is the header's" % key).is_false()


func test_a_claim_that_says_little_decodes_to_the_rules_defaults() -> void:
	# A puppet's or an old claim: only the doorway, slot, side and step.
	var claim := StackClaim.decode(_callout(null, {
		"opening": "o_1", "slot": 2, "side": 1, "entry_step": "claim",
	}, Vector2(30, 70)))
	assert_bool(claim["bang"]).override_failure_message(
		"a member that says nothing of its bang never holds a stack back (E17)",
	).is_true()
	assert_bool(claim["bang_off"]).is_false()
	assert_int(claim["stuns"]).is_equal(0)
	assert_int(claim["frags"]).is_equal(0)
	assert_int(claim["claim_frame"]).override_failure_message("no frame: -1").is_equal(-1)
	assert_that(claim["claim_pos"]).override_failure_message(
		"no spot: where it stands",
	).is_equal(Vector2(30, 70))
	assert_int(claim["move_up"]).is_equal(0)
	assert_bool(claim["pie"]).is_false()
	assert_str(claim["order_id"]).is_equal("")
	assert_str(claim["order_mode"]).override_failure_message("no order: quiet").is_equal("quiet")
	assert_bool(claim["order_go"]).is_false()
	assert_int(claim["order_side"]).is_equal(0)
	for key in ["join", "human", "leader", "own"]:
		assert_bool(claim[key]).override_failure_message("%s unsaid is false" % key).is_false()


func test_a_callout_with_no_entry_step_decodes_to_no_claim() -> void:
	assert_dict(StackClaim.decode(_callout(null, { "path": "combat/engage" }))).is_empty()


func test_grenade_calls_and_order_progress_leave_a_claim_standing() -> void:
	# G16: "grenade!" and the throws' calls; LD7: an order's progress with no entry step.
	for fields in [
		{ "status": "grenade", "kind": &"frag" },
		{ "status": "frag_out", "kind": &"frag" },
		{ "status": "bang_out", "kind": &"stun" },
		{ "order_id": "4", "order_step": "in_position" },
	]:
		var c := _callout(null, fields)
		assert_bool(StackClaim.keeps_claim(c)).override_failure_message(
			"%s keeps the claim" % str(fields),
		).is_true()
		assert_bool(StackClaim.is_claim(c)).is_false()
	# Any other callout is something else the speaker is doing: it is no claim, and keeps none.
	var combat := _callout(null, { "path": "combat/engage", "label": "engage" })
	assert_bool(StackClaim.keeps_claim(combat)).is_false()
	assert_bool(StackClaim.is_claim(combat)).is_false()
	# Every entry step is a claim on the wire, its end too.
	for step in ["claim", "ready", "bang", "going_in", "in", "abort", "done"]:
		assert_bool(StackClaim.is_claim(_callout(null, { "entry_step": step }))).is_true()


func test_the_ledger_keeps_a_claim_through_a_grenade_call_and_drops_it_on_anything_else() -> void:
	var mate := _speaker()
	var ledger := _ledger()
	ledger.hear(_callout(mate, { "opening": "o_1", "slot": 1, "side": 1, "entry_step": "bang" }))
	ledger.hear(_callout(mate, { "status": "bang_out", "kind": &"stun" }))
	ledger.hear(_callout(mate, { "order_id": "2", "order_step": "in_position" }))
	assert_int(ledger.claims("o_1").size()).override_failure_message(
		"the claim stands through a grenade call and an order's progress",
	).is_equal(1)
	ledger.hear(_callout(mate, { "path": "combat/engage", "label": "engage" }))
	assert_array(ledger.claims("o_1")).override_failure_message(
		"a callout about something else drops it",
	).is_empty()


func test_the_ledger_holds_no_ended_claim_nor_a_dead_speakers() -> void:
	var gone := _speaker()
	var dead := _speaker()
	var mate := _speaker()
	var ledger := _ledger()
	ledger.hear(_callout(gone, { "opening": "o_1", "slot": 1, "entry_step": "claim" }))
	ledger.hear(_callout(gone, { "opening": "o_1", "slot": 1, "entry_step": "abort" }))
	ledger.hear(_callout(dead, { "opening": "o_1", "slot": 2, "entry_step": "claim" }))
	ledger.hear(_callout(mate, { "opening": "o_1", "slot": 3, "entry_step": "claim" }))
	dead.is_dead = true
	ledger.hear(_callout(mate, { "opening": "o_1", "slot": 3, "entry_step": "ready" }))
	var slots: Array = ledger.claims("o_1").map(func(c): return c["slot"])
	assert_array(slots).override_failure_message(
		"only the live member's claim (an abort ends one; a dead speaker holds none): %s"
			% str(slots),
	).is_equal([3])


func test_the_ledger_hears_its_own_side_within_range_and_never_its_listener() -> void:
	var me := _speaker()
	var near := _speaker()
	var far := _speaker()
	var foe := _speaker()
	var ledger := ClaimLedger.new()
	ledger.setup({ "faction": &"invader", "range": 500.0, "ttl": 6.0, "listener": me })
	var at := Vector2.ZERO
	var claim := { "opening": "o_1", "entry_step": "claim" }
	ledger.hear(_callout(me, claim.merged({ "slot": 1 }), Vector2(10, 0)), at)
	ledger.hear(_callout(near, claim.merged({ "slot": 2 }), Vector2(400, 0)), at)
	ledger.hear(_callout(far, claim.merged({ "slot": 3 }), Vector2(600, 0)), at)
	ledger.hear(_callout(foe, claim.merged({ "slot": 4 }), Vector2(20, 0), &"household"), at)
	var slots: Array = ledger.claims("o_1").map(func(c): return c["slot"])
	assert_array(slots).override_failure_message(
		"the ally within range only: %s" % str(slots),
	).is_equal([2])


func test_a_doorway_is_stacking_while_a_member_is_on_its_bang() -> void:
	# E17: the member throwing the stun is still on its way in; so is one in its slot for it.
	assert_bool(StackClaim.stacking("bang")).is_true()
	assert_bool(StackClaim.in_slot("bang")).is_true()
	for step in ["claim", "ready", "going_in"]:
		assert_bool(StackClaim.stacking(step)).override_failure_message(step).is_true()
	for step in ["in", "clear", "cover", "rear", "abort", "done"]:
		assert_bool(StackClaim.stacking(step)).override_failure_message(step).is_false()
	var mate := _speaker()
	var ledger := _ledger()
	ledger.hear(_callout(mate, {
		"opening": "o_2", "into": "hall", "slot": 1, "side": 1, "entry_step": "bang",
	}))
	assert_array(ledger.openings_stacking()).is_equal([{ "opening": "o_2", "into": "hall" }])


func test_one_join_rule_reads_orders_leaf_params_and_claims() -> void:
	# LD24: a rally's join is a `stack` order of mode `join`; its leaf params and its claims say
	# `join`.
	assert_bool(StackClaim.is_join({ "kind": "stack", "mode": "join", "opening": "o_1" })).is_true()
	assert_bool(StackClaim.is_join({ "kind": "stack", "mode": "stun" })).is_false()
	assert_bool(StackClaim.is_join({ "kind": "defend_room", "mode": "join" })).is_false()
	assert_bool(StackClaim.is_join({ "opening": "o_1", "join": true, "order_id": "3" })).is_true()
	var ordered := { "opening": "o_1", "order_id": "3", "mode": "quiet" }
	assert_bool(StackClaim.is_join(ordered)).is_false()
	var join := StackClaim.decode(_callout(null, StackClaim.encode({
		"opening": "o_1", "entry_step": "claim", "join": true,
	})))
	assert_bool(StackClaim.is_join(join)).is_true()


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
		var nearer := "the human" if human_first else "the AI"
		assert_array([human_reads, ai_reads]).override_failure_message(
			"%s stood nearer: it keeps slot 1, the other takes 2 (human, AI: %s)"
				% [nearer, str([human_reads, ai_reads])],
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
	var mate := _speaker()
	var me := _speaker()
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
	var who: Array = range(6).map(func(_i): return _speaker())
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
	var a := _speaker()
	var b := _speaker()
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
		var human := _claim(b, { "slot": 2, "side": 1, "entry_step": step, "human": true })
		assert_bool(_releases_7([point_man, human])).override_failure_message(
			"the human in the stack at %s into its room is the go" % step,
		).is_true()


func test_a_held_stack_is_not_released_by_another_stacks_claims() -> void:
	# LD13, D14: a claim left from an earlier entry through the same doorway (a member still holding
	# the room under no order, or another order's member through), another order's go, or a crossing
	# into the other room releases nothing.
	var a := _speaker()
	var b := _speaker()
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
			"human": true, "entry_step": step, "into": "kitchen",
		}
	for why: String in others:
		var other := _claim(b, ({ "slot": 2, "side": 1 } as Dictionary).merged(others[why], true))
		assert_bool(_releases_7([point_man, other])).override_failure_message(
			"%s releases nothing" % why,
		).is_false()


func test_the_layout_lays_each_slot_where_its_holder_settles() -> void:
	# E19, E21: each side's file runs from the door, a member's place in it its slot less the claims
	# across the door ahead of it. The squad's layout (every claim) and each member's own settling
	# (the others' claims: it never hears its own) agree on every point.
	var who: Array = range(4).map(func(_i): return _speaker())
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


## A doorway in a wall along x at the origin, the stack's side out along +y: each side's file of
## six slots against the wall, 30 px apart from 40 px off the door (agent_entry.gd `geometry`, its
## `wall` kind).
func _door() -> Dictionary:
	var files := {}
	for s in [1, -1]:
		files[s] = range(1, 7).map(func(n): return { "point": _slot_at(s, n), "row": 1 })
	return {
		"id": "o_1", "into": "hall", "pos": Vector2.ZERO, "out": Vector2(0, 1),
		"along": Vector2(1, 0), "width": 40.0, "side": 0, "kind": "wall", "files": files,
		"row1": { 1: 6, -1: 6 }, "wall_n": 6,
	}


## Whether `claims` on `_door()` say the held stack under order "7", going into the hall, had its
## go (`DoorStack.released`).
func _releases_7(claims: Array) -> bool:
	return DoorStack.new(_door(), claims).released("7", "hall")


## The point of the `place`th slot of side `side`'s file of `_door()`.
func _slot_at(side: int, place: int) -> Vector2:
	return Vector2(side * (40 + 30 * (place - 1)), 12)


## `speaker`'s claim on `_door()` as a listener holds it (`StackClaim.decode`): `fields` over a
## claim at step `claim`.
func _claim(speaker: Node, fields: Dictionary) -> Dictionary:
	var wire := StackClaim.encode(
		{ "opening": "o_1", "into": "hall", "entry_step": "claim" }.merged(fields, true),
	)
	return StackClaim.decode(_callout(speaker, wire, Vector2(0, 200)))


## `speaker` asking about itself (`DoorStack`'s `me`): holding slot `slot` on side 1, claimed on
## `FRAME` from `pos`.
func _me(speaker: Node, slot: int, pos := Vector2(0, 200)) -> Dictionary:
	return {
		"id": speaker.get_instance_id(), "slot": slot, "side": 1, "frame": FRAME, "pos": pos,
	}


## Two speakers, the lower instance id first.
func _pair() -> Array:
	var two := [_speaker(), _speaker()]
	two.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	return two


## A character on the radio as a listener reads it.
class Speaker:
	extends Node

	var is_dead := false
