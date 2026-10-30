extends GameTest
## D31 rule 2: a member of a stack held for its leader fights only on the stack's side of the
## doorway. A puppet human leader rallies its two NPC teammates at the bare Terrace house's back
## door (as `rally_held_until_leader_crosses`) and holds the threshold. Once both stand ready, a
## defender walks into view in the kitchen and fires at the stack through the doorway for `FIGHT`
## s, then walks back out of sight: the joiners fire back from outside, and none crosses into the
## kitchen while held, nor goes after the defender lost in it (`AFTER` s).
##
## Real Von, the whole pipeline; no switch. Premises: the defender (a puppet) and the joiners are
## never killed (`max_health`), so the stack stays held through the fight.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const HeldFight := preload("res://tests/_ai/held_fight_probe.gd")
## How long (s) the NPCs have, once the human has stepped up, to stand ready in the stack.
const READY_WITHIN := 20.0
## How long (s) the defender fires at the held stack.
const FIGHT := 10.0
## How long (s) the stack is watched once the defender is out of sight again.
const AFTER := 15.0


func describe() -> Dictionary:
	return {
		"name": "A human leader's held rally fights from the stack's side",
		"description": "A puppet human leader rallies its two NPC teammates at the back door and "
			+ "holds; a defender in the kitchen fires at them through the doorway: they fire "
			+ "back from outside and never cross while held.",
		"tags": ["ai", "stack", "squad", "join", "leadership", "human", "combat", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Stack.human(s, &"me", Vector2(930, 40), { "movement:aim_point": FollowWatch.STEP_UP })
	# Never killed (premise): the stack stays held through the fight.
	s.actor(&"m1", &"invader", Vector2(980, 0), { "max_health": 1_000_000.0 })
	s.actor(&"m2", &"invader", Vector2(990, 80), { "max_health": 1_000_000.0 })
	s.squads({ "human": &"me" })
	HeldFight.defender(s, &"d")


func run(t: TestContext) -> void:
	var me := t.actor(&"me")
	var members: Array = [t.actor(&"m1"), t.actor(&"m2")]
	var squad: Node = t.world.squad(&"invader")
	if not t.require(
			t.world.player_stack != null and squad.leader() == me,
			"premise: the human has its stack radio and leads its squad (Lead the team)",
	):
		return
	HeldFight.arm(t, &"d")
	var nodes: Array = [me] + members
	var w := FollowWatch.new_watch()
	if not await FollowWatch.step_up(t, w, nodes, squad):
		return
	var door := String(Entry.BACK["id"])
	var ready := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return members.all(func(m): return Follow.first_call(t, m, "ready", door) < INF)
	if not t.require(
			await t.until(ready, READY_WITHIN) and not Follow.raw_joins(t).is_empty(),
			"set-up: the human's own claim rallied both NPCs, which stand ready in the stack",
	):
		return
	var seen := await HeldFight.fight(t, &"d", members, FIGHT, AFTER)
	HeldFight.check_stack_side(t, members, seen)
