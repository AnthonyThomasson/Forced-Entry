extends GameTest
## D31 rule 2: a member of a stack held for its leader fights only on the stack's side of the
## doorway. A puppet human leader rallies its two NPC teammates at the bare Terrace house's back
## door (as `rally_held_until_leader_crosses`) and holds the threshold. One joiner comes from the
## north of the door, the other from the south (held where it starts until it has claimed, so it
## does not follow the human north first), so the stack splits (E19) and the south one holds a
## slot on its own side. Once both stand ready, a defender walks to `SPOT`, in the kitchen's
## north, in view of that south slot through the doorway, and fires at it for `HeldFight.FIGHT` s,
## then walks back out of sight: the joiners fire back from outside, and none crosses into the
## kitchen while held, nor goes after the defender lost in it (`HeldFight.AFTER` s).
##
## The split is the set-up's: on the north side the human holds slot 1 and a joiner's line of fire
## through the doorway runs into the human's body (sight looks over a person, a round does not), so
## a single-file stack behind the human has no shot from its slots.
##
## Real Von, the whole pipeline; no switch. Premises: the defender (a puppet) and the joiners are
## never killed (`max_health`), so the stack stays held through the fight; a joiner stands ready
## south of the door with a clear line (no wall or furniture) from its slot to `SPOT`.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const HeldFight := preload("res://tests/_ai/held_fight_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
## How long (s) the NPCs have, once the human has stepped up, to stand ready in the stack.
const READY_WITHIN := 20.0
## Where the defender fights from: in the kitchen's north, in view through the back door of the
## stack's south slot (and out of the north slots' view).
const SPOT := Vector2(790, 130)


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
	# From the south, out of the doorway's view, held there (speed 0) until it has claimed, or it
	# would follow the human north first: its way to the north side crosses the doorway's view, so
	# it stacks on the south side (E19).
	s.actor(
		&"m2",
		&"invader",
		Vector2(980, 420),
		{ "max_health": 1_000_000.0, "movement:speed": 0.0 },
	)
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
	if not await _stack_up(t, [me] + members, squad):
		return
	var shot_at := _south_first(t, members)
	if shot_at.is_empty():
		return
	var seen := await HeldFight.fight(t, &"d", shot_at, SPOT)
	HeldFight.check_stack_side(t, members, seen)


## The human steps up beside the back door, its rally's join brings m2's claim from the south (m2
## then let go), and both joiners stand ready, `nodes` (the human, then the joiners) watched with
## `squad` meanwhile; false after a failed `require`.
func _stack_up(t: TestContext, nodes: Array, squad: Node) -> bool:
	var w := FollowWatch.new_watch()
	if not await FollowWatch.step_up(t, w, nodes, squad):
		return false
	var door := String(Entry.BACK["id"])
	var m2: Node = nodes[2]
	var claimed := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return Follow.first_call(t, m2, "claim", door) < INF
	if not t.require(
			await t.until(claimed, READY_WITHIN),
			"set-up: the rally's join brought m2's claim from the south",
	):
		return false
	m2.movement.speed = 150.0
	var members := nodes.slice(1)
	var ready := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return members.all(func(m): return Follow.first_call(t, m, "ready", door) < INF)
	return t.require(
		await t.until(ready, READY_WITHIN) and not Follow.raw_joins(t).is_empty(),
		"set-up: the human's own claim rallied both NPCs, which stand ready in the stack",
	)


## The `members` with the one standing south of the door first (the defender shoots at it), after
## the premise that it stands there with a clear line to `SPOT`; [] after a failed `require`.
func _south_first(t: TestContext, members: Array) -> Array:
	var south: Array = members.filter(
		func(m): return Entry.lateral(Entry.BACK, m.global_position) < 0.0
	)
	if not t.require(
			not south.is_empty() and GrenadeAi.line_clear(t, south[0].global_position, SPOT),
			"premise: a joiner stands ready south of the door with a clear line to %s (at %s)"
				% [str(SPOT), str(members.map(func(m): return m.global_position.round()))],
	):
		return []
	return south + members.filter(func(m): return not south.has(m))
