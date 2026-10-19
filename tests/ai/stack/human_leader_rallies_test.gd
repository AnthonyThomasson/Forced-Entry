extends GameTest
## LD24 and D27 (with interface 17): the human leader's own claim rallies its team. A puppet stands
## in for the human leader of a squad of two invader NPCs, built and bound the way Main builds it
## with "Lead the team" on (the human handed to `Squad.setup` as `human`, its `PlayerStack` attached
## as `MatchSpawner.bind_player` attaches it and handed the squad by `MatchSpawner.bind_squad`). The
## human walks up beside the bare Terrace house's back door, where nobody is stacking: its stack
## radio claims a slot of its own (the human leads a squad with members), and the squad gives both
## NPCs a `join` order there. Both claim the back door and stand ready in the stack with the human.
##
## Real Von, the whole pipeline; no switch. The human (a puppet) is never killed.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const MatchSpawner := preload("res://scenes/match_spawner.gd")
## Where the human stands: against the wall north of the back door, a stack spot beside it.
const STEP_UP := Order.BACK_NORTH
## How long (s) the NPCs have, once the human has claimed, to stand ready in the stack.
const READY_WITHIN := 20.0


func describe() -> Dictionary:
	return {
		"name": "A human leader stepping up to a doorway rallies its team",
		"description": "A puppet human leader walks up beside the back door with nobody stacking: "
			+ "it claims a slot of its own, and both NPC teammates get a join order and stack "
			+ "with it.",
		"tags": ["ai", "stack", "squad", "join", "leadership", "human", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Stack.human(s, &"me", Vector2(930, 40), { "aim_point": STEP_UP })
	s.actor(&"m1", &"invader", Vector2(980, 0))
	s.actor(&"m2", &"invader", Vector2(990, 80))


func run(t: TestContext) -> void:
	var me := t.actor(&"me")
	var members: Array = [t.actor(&"m1"), t.actor(&"m2")]
	var stack := Stack.attach(t, &"me")
	if not t.require(stack != null, "the human has a stack radio (PlayerStack.attach)"):
		return
	var squad := Follow.team(t, [&"me", &"m1", &"m2"], &"me")
	if not t.require(squad != null, "the squad is built and bound (Squad.setup, bind_squad)"):
		return
	# (As Main binds the invaders' human leader: its own claims rally the team, D29.)
	MatchSpawner.new().bind_squad(me, squad, stack, true)
	if not t.require(
			stack.get("squad") == squad and squad.leader() == me,
			"premise: the human's stack is handed its squad, and the human leads (Lead the team)",
	):
		return
	var nodes: Array = [me] + members
	var w := Follow.new_watch()
	var puppet := t.puppet(&"me")
	puppet.walk_to(STEP_UP)
	var arrived := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return puppet.has_arrived()
	if not t.require(await t.until(arrived, 8.0), "the human walked up beside the back door"):
		return
	puppet.stop()
	var door := String(Entry.BACK["id"])
	var claimed := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return Follow.first_call(t, me, "claim", door) < INF
	await t.until(claimed, 4.0)
	var mine := Follow.first_call(t, me, "claim", door)
	var first_npc: float = members.map(func(m): return Follow.first_call(t, m, "claim", door)).min()
	t.check(
		mine < INF and mine <= first_npc,
		"the human claimed a slot on the back door of its own, before any teammate (%.2f s; first "
			% mine + "teammate's claim %.2f s)" % first_npc,
	)
	var ready := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return members.all(func(m): return Follow.first_call(t, m, "ready", door) < INF)
	await t.until(ready, READY_WITHIN)

	var joins := Follow.raw_joins(t)
	var to: Array = joins[0]["data"].get("to", []) if not joins.is_empty() else []
	t.check(
		not joins.is_empty()
			and String(joins[0]["data"].get("opening", "")) == door
			and members.all(func(m): return to.has(m))
			and not to.has(me),
		"the squad gave both NPCs a join order on the back door (joins %s)"
			% str(joins.map(func(e): return e["data"])),
	)
	for m: Node in members:
		t.check(
			Follow.took(w, m, "order"),
			"%s carried out the join order (ORDER; acts %s)" % [m.name, Follow.acts_of(w, m)],
		)
		t.check(
			Follow.first_call(t, m, "claim", door) < INF
				and Follow.first_call(t, m, "ready", door) < INF,
			"%s stacked with the human: claimed the back door and stood ready (claim %.2f s, "
				% [m.name, Follow.first_call(t, m, "claim", door)]
				+ "ready %.2f s)" % Follow.first_call(t, m, "ready", door),
		)
