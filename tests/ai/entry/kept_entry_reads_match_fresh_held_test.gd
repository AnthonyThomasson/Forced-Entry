extends "res://tests/ai/entry/kept_entry_reads_match_fresh_test.gd"
## `kept_entry_reads_match_fresh` for an ORDERED stack held for its go (LD13, the setup of
## `order_stack_hold_for_go`): three invaders ordered to stack quiet and hold on the back door, they
## form and hold, the leader's go is posted and they go in. Each frame the kept claim and every
## read the stack keeps equal a fresh one, through the order (`order_claim`), the hold (`hold`,
## `held`) and the go. The premises count each of those reads tallied apart.

const Order := preload("res://tests/_ai/order_probe.gd")
## Seconds the formed stack is held before the leader's go.
const HOLD_S := 6.0

var _ordered := false
var _ready_at := INF
var _went := false


func describe() -> Dictionary:
	return {
		"name": "Kept entry reads match a fresh recompute for an ordered, held stack",
		"description": "Three invaders ordered to hold for go on the back door, then sent in: "
			+ "each frame every entry's claim and each stack read it keeps (order claim, hold, "
			+ "held) equals what is worked out afresh.",
		"tags": ["ai", "entry", "leadership", "order", "scripted"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"a", &"invader", Vector2(960, 60))
	s.actor(&"b", &"invader", Vector2(985, 110))
	s.actor(&"c", &"invader", Vector2(1010, 20))
	s.actor(&"lead", &"puppet", Vector2(1250, 600), { "faction": &"invader" })
	s.squads({ "human": &"lead" })


func ids() -> Array:
	return [&"a", &"b", &"c"]


func _done(t: TestContext) -> bool:
	return _went and ids().all(func(id): return not Entry.calls(t, "going_in", id).is_empty())


func _frame(t: TestContext) -> void:
	var squad: Node = t.world.squad(&"invader")
	if not _ordered and t.time > 0.3:
		_ordered = not Order.stack_order(
			squad, ids().map(func(id): return t.actor(id)), Order.BACK_NORTH, "quiet", true,
		).is_empty()
	var door: String = Entry.BACK["id"]
	if _ordered and _ready_at == INF and Order.all_called(t, ids(), "ready", door):
		_ready_at = t.time
	if _ready_at != INF and not _went and t.time > _ready_at + HOLD_S:
		_went = not Order.go(squad, Order.BACK_NORTH).is_empty()


func _premises(t: TestContext, tally: Array) -> void:
	t.check(_ordered, "premise: the order was posted")
	t.check(_went, "premise: the stack formed, was held, and the go was posted")
	t.check(tally[3] > 0, "premise: a hold was read (%d)" % tally[3])
	t.check(tally[4] > 0, "premise: a held stack was read (held true: %d)" % tally[4])
	t.check(tally[5] > 0, "premise: an order claim was read (%d)" % tally[5])
