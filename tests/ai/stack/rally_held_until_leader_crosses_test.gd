extends GameTest
## D38 (with LD24 and interface 17): a stack the human leader's own claim rallied is held for its
## leader. A puppet stands in for the human leader of a squad of two invader NPCs, built and bound
## the way Main builds it with "Lead the team" on, as `human_leader_rallies`. The human steps up
## beside the bare Terrace house's back door: its own claim rallies both NPCs, which stack ready
## with it. The human then holds the threshold for `HOLD` s, three times the joiners'
## `tuning.entry.ready_timeout`: no joiner crosses, and no stun is thrown, and each joiner's state
## reads its join held for the go (D38's wording). The human crosses; both joiners follow it in,
## after it, and the kitchen is called clear.
##
## Real Von, the whole pipeline; no switch. Each NPC carries one stun as a match arms an invader (a
## test world keeps the default inventory): the premise that a bang could be thrown. The human (a
## puppet) is never killed.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Grenades := preload("res://tests/_ai/grenade_probe.gd")
## How long (s) the NPCs have, once the human has claimed, to stand ready in the stack.
const READY_WITHIN := 20.0
## How long (s) the human holds the threshold after its team stands ready.
const HOLD := 20.0
## How long (s) the joiners have, once the human is in, to follow it in.
const FOLLOW_WITHIN := 20.0
## How long (s) the team has, once the joiners are in, to call the room clear.
const CLEAR_WITHIN := 40.0
## The held join's order sentence (`docs/leadership.md` D38), the back door's room filled in.
const HELD_ORDER := (
	"Your leader ordered you to go into the kitchen by its doorway with them when they give the go."
)


func describe() -> Dictionary:
	return {
		"name": "A human leader's rallied stack holds until the leader steps in",
		"description": "A puppet human leader steps up beside the back door and rallies its two "
			+ "NPC teammates; they stack ready with it and hold for 20 s, no crossing and no "
			+ "stun, until the human crosses: then both follow it in and the room is cleared.",
		"tags": ["ai", "stack", "squad", "join", "leadership", "human", "von"],
		"requires_von": true,
		"timeout": 150.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Stack.human(s, &"me", Vector2(930, 40), { "movement:aim_point": FollowWatch.STEP_UP })
	s.actor(&"m1", &"invader", Vector2(980, 0))
	s.actor(&"m2", &"invader", Vector2(990, 80))
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var me := t.actor(&"me")
	var members: Array = [t.actor(&"m1"), t.actor(&"m2")]
	var squad: Node = t.world.squad(&"invader")
	if not _premises(t, squad, me, members):
		return
	var nodes: Array = [me] + members
	var w := FollowWatch.new_watch()
	if not await FollowWatch.step_up(t, w, nodes, squad):
		return
	var door := String(Entry.BACK["id"])
	if not await _stacked(t, w, nodes, squad, door):
		return

	var crossed := { "at": INF }  # The first time a joiner stood in the kitchen.
	var read := {}  # Member -> every `order` section its decision snapshots held while held.
	var watch := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		if crossed["at"] == INF and members.any(func(m): return _in(m)):
			crossed["at"] = t.time
		_note_read(members, read)
		return false
	var held_from := t.time
	await t.until(watch, HOLD)
	_check_held(t, members, door, held_from, crossed)
	t.check(
		members.all(func(m): return read.get(m, []) == [HELD_ORDER]),
		"each joiner's state read its join held for the go, verbatim (read %s)"
			% str(members.map(func(m): return read.get(m, []))),
	)

	if not t.require(
			await Stack.walk(t, &"me", Stack.crossing(Entry.BACK), 8.0),
			"the human crosses the back door into the kitchen",
	):
		return
	await _check_followed(t, w, nodes, squad, door)


## The set-up's premises: the human has its stack radio, handed its squad, and leads it; each NPC
## carries one stun (armed here as a match arms an invader).
func _premises(t: TestContext, squad: Node, me: Node, members: Array) -> bool:
	if not Stack.require_human_leads(t, squad, me):
		return false
	for m: Node in members:
		Grenades.arm(m, 1, 0)
	return t.require(
		members.all(func(m): return Grenades.count(m, Grenades.STUN) == 1),
		"premise: each NPC carries one stun",
	)


## The human's own claim rallies both NPCs, which stand ready in the stack with it; false after a
## failed `require`.
func _stacked(t: TestContext, w: Dictionary, nodes: Array, squad: Node, door: String) -> bool:
	var me: Node = nodes[0]
	var members: Array = nodes.slice(1)
	var ready := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return members.all(func(m): return Follow.first_call(t, m, "ready", door) < INF)
	await t.until(ready, READY_WITHIN)
	if not t.require(
			Follow.first_call(t, me, "claim", door) < INF and not Follow.raw_joins(t).is_empty(),
			"set-up: the human claimed the back door of its own and the squad posted the joins "
				+ "(joins %s)" % str(Follow.raw_joins(t).map(func(e): return e["data"])),
	):
		return false
	return t.require(
		members.all(func(m): return Follow.first_call(t, m, "ready", door) < INF),
		"set-up: both NPCs joined and stood ready in the stack (ready at %s)"
			% str(members.map(func(m): return Follow.first_call(t, m, "ready", door))),
	)


## No joiner went in, nor called it, while the human held the threshold from `from`, and no stun
## was thrown.
func _check_held(
		t: TestContext,
		members: Array,
		door: String,
		from: float,
		crossed: Dictionary,
) -> void:
	for m: Node in members:
		var going := Follow.first_call(t, m, "going_in", door)
		t.check(
			going == INF,
			"%s held at the threshold for the human's %.0f s, no crossing (going_in at %.2f s, "
				% [m.name, HOLD, going] + "held from %.2f s)" % from,
		)
	t.check(
		crossed["at"] == INF,
		"no joiner stood in the kitchen while held (first at %.2f s)" % crossed["at"],
	)
	t.check(
		Grenades.booms(t, &"stun").is_empty() and not t.happened(&"throw"),
		"no stun was thrown while held",
	)


## Both joiners follow the human in, after it, with no grenade thrown (the bang given up, too late
## once the human stepped in), and the kitchen is called clear.
func _check_followed(
		t: TestContext,
		w: Dictionary,
		nodes: Array,
		squad: Node,
		door: String,
) -> void:
	var me: Node = nodes[0]
	var members: Array = nodes.slice(1)
	var stepped := Follow.first_call(t, me, "going_in", door)
	var followed := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return members.all(func(m): return Follow.first_call(t, m, "in", door) < INF)
	await t.until(followed, FOLLOW_WITHIN)
	for m: Node in members:
		var went := Follow.first_call(t, m, "going_in", door)
		t.check(
			stepped < INF and went > stepped and Follow.first_call(t, m, "in", door) < INF,
			"%s followed the human in (human going_in %.2f s; its going_in %.2f s, in %.2f s)"
				% [m.name, stepped, went, Follow.first_call(t, m, "in", door)],
		)
	var cleared := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return not Follow.clears(t, String(Entry.BACK["room_key"])).is_empty()
	t.check(await t.until(cleared, CLEAR_WITHIN), "the kitchen is called clear")
	t.check(
		Grenades.booms(t).is_empty() and not t.happened(&"throw"),
		"no grenade was thrown after the human stepped in: the bang is given up (booms %d)"
			% Grenades.booms(t).size(),
	)


## Adds to `read` (member -> its `order` sections seen) each of `members`' latest decision
## snapshot's `order` section, once.
func _note_read(members: Array, read: Dictionary) -> void:
	for m: Node in members:
		var b := Follow.brain_of(m)
		var said := String(b.debug_state().get("sections", {}).get("order", "")) if b else ""
		if said != "" and not (read.get(m, []) as Array).has(said):
			read[m] = (read.get(m, []) as Array) + [said]


## Whether NPC `m` stands in the kitchen, past the back door.
func _in(m: Node) -> bool:
	return Entry.in_room(Entry.BACK, m.global_position)
