extends GameTest
## LD24 (`docs/leadership.md`, with E16 of `docs/tactical-entry.md`): only the claim the human
## leader makes of its own rallies its team. Its slot in a stack that is already forming (E16: its
## `PlayerStack` reserves it a place in an allied stack) is not its own claim: the human's other
## claims are E16's. A puppet stands in for the human leader of a squad of three invader NPCs (the
## human handed to `Squad.setup` as `human`, its `PlayerStack` attached as
## `MatchBuilder.bind_player` attaches it and handed the squad by `MatchBuilder.bind_squad`). It
## orders `a` and `b` to stack quietly north of the bare Terrace house's back door; standing near
## it, it is reserved a slot in that stack and steps into it. The third teammate, `f`, holds no
## order and follows the human close by: no `join` is posted, and `f` takes no slot at the back
## door.
##
## Scripted Von, down: the members' own decisions hold steady, so what they do is the order's and
## the follow rule's alone (FOLLOW asks Von nothing).

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const STACKERS := [&"a", &"b"]
## How long (s) the squad is watched once the human stands in its slot: its claim's repeats (every
## 2 s) included.
const AFTER_READY := 5.0


func describe() -> Dictionary:
	return {
		"name": "A human leader's slot in a stack it ordered rallies nobody",
		"description": "A puppet human leader orders two teammates to stack at the back door and "
			+ "is reserved a slot in that stack (E16): it steps into it, and the free follower "
			+ "near it is given no join order (LD24).",
		"tags": ["ai", "stack", "squad", "join", "leadership", "human", "order", "scripted"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"a", &"invader", Vector2(960, 60), { "max_health": 1_000_000.0 })
	s.actor(&"b", &"invader", Vector2(1010, 20), { "max_health": 1_000_000.0 })
	s.actor(&"f", &"invader", Vector2(1070, 160), { "max_health": 1_000_000.0 })
	Stack.human(s, &"me", Vector2(1000, 120))
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var me := t.actor(&"me")
	var follower := t.actor(&"f")
	var squad := t.squad(&"invader")
	var stack := t.player_stack()
	if not _leads_with_radio(t, stack, squad, me, follower):
		return
	await t.seconds(0.3)
	var door := String(Entry.BACK["id"])
	if not await _ordered_stack_ready(t, squad, stack, door):
		return
	if not await _human_in_slot(t, stack, me, door):
		return
	await t.seconds(AFTER_READY)

	var joins := Follow.raw_joins(t)
	t.check(
		joins.is_empty(),
		"the human's slot in the stack it ordered rallies nobody: no join order posted (joins %s)"
			% str(joins.map(func(e): return e["data"])),
	)
	t.check(
		Follow.first_call(t, follower, "claim", door) == INF,
		"f, holding no order, took no slot at the back door",
	)


func _leads_with_radio(
		t: TestContext,
		stack: Node,
		squad: Node,
		me: Node,
		follower: Node,
) -> bool:
	if not t.require(stack != null, "the human has a stack radio (MatchBuilder.bind_player)"):
		return false
	return t.require(
		squad.leader() == me and squad.follows(follower),
		"premise: the human leads, and f follows it",
	)


func _ordered_stack_ready(t: TestContext, squad: Node, stack: Node, door: String) -> bool:
	var stackers: Array = STACKERS.map(func(id): return t.actor(id))
	if not t.require(
			not Order.stack_order(squad, stackers, Order.BACK_NORTH, "quiet", false).is_empty(),
			"premise: the human orders a and b to stack at the back door (issue)",
	):
		return false
	var reserved := func() -> bool:
		return String(Stack.view(stack).get("opening", "")) == door and Stack.mine(stack) > 0
	if not t.require(
			await t.until(reserved, 20.0),
			"premise: the human is reserved a slot in the ordered stack at the back door (E16)",
	):
		return false
	var ready := func(): return Order.all_called(t, STACKERS, "ready", door)
	return t.require(await t.until(ready, 30.0), "premise: a and b stand ready in their slots")


func _human_in_slot(t: TestContext, stack: Node, me: Node, door: String) -> bool:
	var mine := Stack.mine(stack)
	if not t.require(
			await Stack.walk(t, &"me", [Stack.slot_point(stack, mine)], 15.0),
			"premise: the human steps into its slot %d" % mine,
	):
		return false
	var in_slot := func() -> bool: return Follow.first_call(t, me, "ready", door) < INF
	return t.require(
		await t.until(in_slot, 3.0),
		"premise: the human's stack radios ready in its slot",
	)
