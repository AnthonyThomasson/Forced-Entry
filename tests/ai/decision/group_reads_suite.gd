extends UnitSuite
## Native unit suite (pure logic): what the groups built ahead of the walk read of the radio
## (`GroupReads`): a call radioed again as it was, which moves to the end of the callouts' list, is
## no change; a call that changed, a new one and a lapsed one are; time passing is not; the entries
## also read the ledger's slot claims, the leads do not.

const Reads := preload("res://scenes/ai/perception/snapshot/group_reads.gd")

var _reads: RefCounted
var _ledger: FakeLedger


func before_test() -> void:
	_ledger = FakeLedger.new()
	_reads = Reads.new()
	_reads.ledger = _ledger


func _call(id: int, at: Vector2, age := 0.0, path := "combat/flank") -> Dictionary:
	return { "id": id, "path": path, "position": at, "target_pos": at, "age": age }


func _ctx(calls: Array) -> Dictionary:
	return { "callouts": calls }


func test_an_identical_call_radioed_again_moves_in_the_list_and_is_no_change() -> void:
	var first := _call(1, Vector2(10, 10))
	var second := _call(2, Vector2(50, 20))
	_reads.note(_ctx([first, second]), "leads")
	_reads.note(_ctx([first, second]), "entries")
	# The first caller radios the same call again: the list now ends with it, a little older or not.
	var again := _ctx([second, _call(1, Vector2(10, 10), 0.4)])
	assert_bool(_reads.stale(again, "leads")).is_false()
	assert_bool(_reads.stale(again, "entries")).is_false()


func test_time_passing_is_no_change() -> void:
	_reads.note(_ctx([_call(1, Vector2(10, 10), 0.0)]), "leads")
	assert_bool(_reads.stale(_ctx([_call(1, Vector2(10, 10), 2.5)]), "leads")).is_false()


func test_a_call_that_changed_came_or_lapsed_is_a_change() -> void:
	_reads.note(_ctx([_call(1, Vector2(10, 10))]), "leads")
	assert_bool(_reads.stale(_ctx([_call(1, Vector2(90, 10))]), "leads")).is_true()  # it moved
	var both := _ctx([_call(1, Vector2(10, 10)), _call(2, Vector2(5, 5))])
	assert_bool(_reads.stale(both, "leads")).is_true()  # a new caller
	assert_bool(_reads.stale(_ctx([]), "leads")).is_true()  # a lapsed one


func test_a_call_that_is_not_a_combat_call_is_no_change() -> void:
	_reads.note(_ctx([_call(1, Vector2(10, 10))]), "leads")
	var other := _call(2, Vector2(5, 5), 0.0, "order/hold")
	assert_bool(_reads.stale(_ctx([_call(1, Vector2(10, 10)), other]), "leads")).is_false()


func test_a_slot_claim_changes_the_entries_and_not_the_leads() -> void:
	var calls := _ctx([_call(1, Vector2(10, 10))])
	_reads.note(calls, "leads")
	_reads.note(calls, "entries")
	_ledger.claims = { 7: { "opening": "door_a", "slot": 1 } }
	assert_bool(_reads.stale(calls, "entries")).is_true()
	assert_bool(_reads.stale(calls, "leads")).is_false()


func test_a_group_not_noted_is_never_stale_and_forgetting_clears_what_was_noted() -> void:
	var calls := _ctx([_call(1, Vector2(10, 10))])
	assert_bool(_reads.stale(calls, "leads")).is_false()
	_reads.note(calls, "leads")
	_reads.forget("leads")
	assert_bool(_reads.stale(_ctx([]), "leads")).is_false()


## A ledger that holds the claims it is given.
class FakeLedger:
	var claims := {}


	func heard_key() -> Dictionary:
		return claims
