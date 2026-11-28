extends "res://tests/ai/entry/kept_entry_reads_match_fresh_test.gd"
## `kept_entry_reads_match_fresh_test` for a JOIN (LD24, the setup of
## `order_stack_unordered_joiner_follows`): a human leader steps up north of the back door and its
## own claim rallies an invader, which joins its stack as an unordered entry; later the human orders
## a second one to stack south with a stun, so the joiner follows an order it did not get. Each
## frame the kept claim (with its join terms) and every read the stack keeps equal a fresh one.

const Order := preload("res://tests/_ai/order_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
## Seconds watched after the order is posted: the joiner and the ordered member claim under it.
const AFTER_ORDER := 14.0

var _ordered := false
var _ordered_at := INF
var _joined := 0


func describe() -> Dictionary:
	return {
		"name": "Kept entry reads match a fresh recompute for a rallied join",
		"description": "An invader joins its human leader's stack at the back door, and follows a "
			+ "later stack order of a teammate: each frame every entry's claim and each stack read "
			+ "it keeps equals what is worked out afresh.",
		"tags": ["ai", "entry", "leadership", "join", "scripted"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	s.actor(&"joiner", &"invader", Vector2(960, 60))
	s.actor(&"ordered", &"invader", Vector2(990, 600))
	Stack.human(s, &"lead", Vector2(930, 40), { "movement:aim_point": Order.BACK_NORTH })
	s.squads({ "human": &"lead" })


func ids() -> Array:
	return [&"joiner", &"ordered"]


func _done(t: TestContext) -> bool:
	return t.time > _ordered_at + AFTER_ORDER


func _frame(t: TestContext) -> void:
	if _joined == 0:
		Probe.arm(t.actor(&"ordered"), 1, 0)
		t.puppet(&"lead").walk_to(Order.BACK_NORTH)
		_joined = 1
	if (_joined == 1 and not _ordered
			and not Entry.calls(t, "claim", &"joiner").is_empty()):
		_ordered_at = t.time
		_ordered = not Order.issue(
			t.world.squad(&"invader"),
			{
				"kind": Order.STACK, "to": [t.actor(&"ordered")], "pos": Order.BACK_SOUTH,
				"bang": true,
			},
		).is_empty()


func _premises(t: TestContext, tally: Array) -> void:
	t.check(_ordered, "premise: the joiner claimed and the order was posted after it")
	t.check(tally[5] > 0, "premise: an order claim was read (%d)" % tally[5])
	t.check(tally[2] > 0, "premise: a mode was read (%d)" % tally[2])
