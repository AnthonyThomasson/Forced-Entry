extends UnitSuite
## Native unit suite (pure logic) for the stack module (`scenes/ai/perception/stack/`): the entry
## claim's wire format (`StackClaim`, interface 10) and the claims a listener keeps
## (`ClaimLedger`), fed plain callout dicts. Beneath the simulation tests of `tests/ai/stack/` and
## `tests/ai/entry/` (ADR-0002): it supplements them, never replaces them. The expected values are
## read off the rules (`docs/tactical-entry.md` E2, E16, E17; `docs/leadership.md` LD7, LD24), never
## worked out the way the code does: a field a claim does not say means what the rule says it means
## (a member that says nothing of its bang never holds a stack back, E17), not what a table holds.

const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const ClaimLedger := preload("res://scenes/ai/perception/stack/claim_ledger.gd")


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


## A character on the radio as a listener reads it.
class Speaker:
	extends Node

	var is_dead := false
