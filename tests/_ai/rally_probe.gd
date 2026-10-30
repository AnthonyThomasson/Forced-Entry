extends RefCounted
## Shared helpers for the human leader's rally tests (`docs/leadership.md` LD24, D31; not a test
## itself): `const Rally := preload("res://tests/_ai/rally_probe.gd")`. The world is
## `human_leader_rallies`': a puppet standing in for the human leader of a squad of two invader
## NPCs, built and bound the way Main builds it with "Lead the team" on, in the bare Terrace house's
## back garden. `rallied` walks the human up beside the back door, where its own claim rallies both
## NPCs, and waits until they stand ready in the stack with it, held for its go; `menu_go` gives
## the command menu's go there, in a mode.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Grenades := preload("res://tests/_ai/grenade_probe.gd")
## The two NPC teammates.
const IDS := [&"m1", &"m2"]
## How long (s) the NPCs have, once the human has stepped up, to stand ready in the stack.
const READY_WITHIN := 20.0


## Lay the world into `s`: the bare Terrace house, the human `me` in the back garden walking up
## beside the back door, its NPC teammates `m1` and `m2` (with character `props`), its squad.
static func world(s: TestSetup, props: Dictionary = {}) -> void:
	Maps.house(s, false)
	Stack.human(s, &"me", Vector2(930, 40), { "movement:aim_point": FollowWatch.STEP_UP })
	s.actor(&"m1", &"invader", Vector2(980, 0), props.duplicate())
	s.actor(&"m2", &"invader", Vector2(990, 80), props.duplicate())
	s.squads({ "human": &"me" })


## The NPC teammates (characters).
static func members(t: TestContext) -> Array:
	return IDS.map(func(id): return t.actor(id))


## Arm each NPC teammate with `stuns` stun and `frags` frag grenades as a match arms an invader (a
## test world keeps the default inventory); false after a failed `require`.
static func arm(t: TestContext, stuns: int, frags: int) -> bool:
	for m: Node in members(t):
		Grenades.arm(m, stuns, frags)
	return t.require(
		members(t).all(func(m): return (
			Grenades.count(m, Grenades.STUN) == stuns and Grenades.count(m, Grenades.FRAG) == frags
		)),
		"premise: each NPC carries %d stun and %d frag" % [stuns, frags],
	)


## The human leads its squad and has its stack radio; it steps up beside the back door, its own
## claim rallies both NPCs, and they stand ready in the stack with it, ticking the watch `w`; false
## after a failed `require`.
static func rallied(t: TestContext, w: Dictionary) -> bool:
	var me := t.actor(&"me")
	var squad: Node = t.world.squad(&"invader")
	if not Stack.require_human_leads(t, squad, me):
		return false
	var nodes: Array = [me] + members(t)
	if not await FollowWatch.step_up(t, w, nodes, squad):
		return false
	var door := String(Entry.BACK["id"])
	var ready := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return members(t).all(func(m): return Follow.first_call(t, m, "ready", door) < INF)
	return t.require(
		await t.until(ready, READY_WITHIN) and not Follow.raw_joins(t).is_empty(),
		"set-up: the human's own claim rallied both NPCs, which stand ready in the stack",
	)


## The command menu's go at the back door in `mode` (`Squad.issue({ kind: "go", pos, mode })`):
## the go posted, or {} after a failed `require` (none posted, or not to both NPCs in that mode).
static func menu_go(t: TestContext, mode: String) -> Dictionary:
	var squad: Node = t.world.squad(&"invader")
	var go: Dictionary = squad.issue({ "kind": "go", "pos": Entry.BACK["pos"], "mode": mode })
	var to: Array = go.get("to", [])
	if not t.require(
			String(go.get("mode", "")) == mode and members(t).all(func(m): return to.has(m)),
			"the squad posts the go, %s, to both joiners holding the rally (go %s)" % [mode, go],
	):
		return {}
	return go


## Wait up to `secs` s until both NPC teammates have radioed `in` at the back door, ticking `w`.
static func both_in(t: TestContext, w: Dictionary, secs: float) -> bool:
	var door := String(Entry.BACK["id"])
	var nodes: Array = [t.actor(&"me")] + members(t)
	var squad: Node = t.world.squad(&"invader")
	var done := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return members(t).all(func(m): return Follow.first_call(t, m, "in", door) < INF)
	return await t.until(done, secs)


## The time the first NPC teammate radioed `going_in` at the back door, or INF.
static func first_going_in(t: TestContext) -> float:
	var door := String(Entry.BACK["id"])
	return members(t).map(func(m): return Follow.first_call(t, m, "going_in", door)).min()


## After a menu go: both NPC teammates went in, the human still standing in its slot outside, never
## having crossed (the human's claim is no longer waited for, D31).
static func check_went_without_human(t: TestContext) -> void:
	var door := String(Entry.BACK["id"])
	for m: Node in members(t):
		t.check(
			Follow.first_call(t, m, "in", door) < INF,
			"%s went in (in at %.2f s)" % [m.name, Follow.first_call(t, m, "in", door)],
		)
	var me := t.actor(&"me")
	t.check(
		Follow.first_call(t, me, "going_in", door) == INF
			and not Entry.in_room(Entry.BACK, me.global_position),
		"the human was not waited for: it never crossed, and the AIs went in without it",
	)
