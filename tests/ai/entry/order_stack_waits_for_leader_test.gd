extends GameTest
## LD17 (`docs/leadership.md`, ticket #65 round 2, rule 10): an ordered stack waits for the human
## leader in it. While the human leader holds a slot (its `PlayerStack`) in a stack it ordered, the
## stack waits for it as for an ordered member: until it stands in its slot, at most
## `order_ready_cap`; its slot withdrawn (it walked away) frees them. It is not waited for as an
## unordered teammate is (E16: `entry_ready_timeout`, 6 s, from the point's own arrival, then the
## stack goes without it).
##
## Two stacks on the Terrace house (bare), both ordered by the human leader, quiet and go-when-ready
## (no hold for go: what holds them is the leader alone):
## - At the back door, north of it: `a` and `b`. The human, a puppet with the invader faction given
## the stack radio the way Main gives it (`MatchBuilder.bind_player`) and leading the squad, is
## reserved
##   a slot, then dawdles 20 s in the garden within its reserve range but out of its slot: nobody
##   crosses. It steps into its slot: they go, after it is there.
## - At the front door, north of it: `c` and `d`. The human is reserved a slot there, dawdles 10 s
##   out of it (nobody crosses), then walks away beyond `reserve_range * leave_factor`: its claim is
##   withdrawn and that frees them, they go.
## The human leads the squad, built and bound as a match's (`s.squads`,
## `MatchBuilder.build_squads`): its `PlayerStack` is handed the squad, so its claims are marked
## `leader: true`, as Main wires it.
##
## Scripted Von, down: the members' own decisions hold steady, so what they do is the order's alone.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const BACK_IDS := [&"a", &"b"]
const FRONT_IDS := [&"c", &"d"]
## The front door's stack: a click outside it, north of the opening along its wall (within the
## opening's width of its centre).
const FRONT_NORTH := Vector2(-30, 360)
## How long (s) the human dawdles out of its slot at the back door, and at the front door, with the
## rest ready.
const DAWDLE_BACK := 20.0
const DAWDLE_FRONT := 10.0
## The two spots the human walks between while it dawdles at each door: in reach of the doorway
## (within `reserve_range`), out of its slot, off the doorway's funnel and the members' way to their
## slots.
const LOITER_BACK := [Vector2(1000, 120), Vector2(1045, 70)]
const LOITER_FRONT := [Vector2(-150, 330), Vector2(-190, 290)]
## Where the human walks to leave the front door's stack: more than `reserve_range * leave_factor`
## (450 px) of walking from the doorway.
const AWAY := Vector2(-220, -120)
## How long (s) the stack is given to go once its leader is in its slot, or once its slot is
## withdrawn: the quiet stack's listen (3 s), the pie, then the crossing.
const GO_WITHIN := 25.0


func describe() -> Dictionary:
	return {
		"name": "An ordered stack waits for the human leader in it",
		"description": "The human leader holds a slot in a stack it ordered and dawdles 20 s out "
			+ "of it: nobody crosses; it steps into its slot and they go. At a second door it "
			+ "dawdles, then walks away: its slot withdrawn frees them (LD17).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 200.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"a", &"invader", Vector2(960, 60), { "max_health": 1_000_000.0 })
	s.actor(&"b", &"invader", Vector2(1010, 20), { "max_health": 1_000_000.0 })
	s.actor(&"c", &"invader", Vector2(-120, 230), { "max_health": 1_000_000.0 })
	s.actor(&"d", &"invader", Vector2(-170, 200), { "max_health": 1_000_000.0 })
	Stack.human(s, &"me", LOITER_BACK[0])
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var squad := t.squad(&"invader")
	var stack := t.player_stack()
	if not t.require(stack != null, "the human has a stack radio (MatchBuilder.bind_player)"):
		return
	await t.seconds(0.3)

	# --- The back door: the human dawdles, then steps into its slot. ---
	var back: Dictionary = Entry.BACK
	if not t.require(
			not Order.stack_order(
				squad,
				_actors(t, BACK_IDS),
				Order.BACK_NORTH,
				"quiet",
				false,
			).is_empty(),
			"the squad posts the stack order on the back door (issue)",
	):
		return
	if not t.require(
			await _reserved(t, stack, back["id"]),
			"the human is reserved a slot at the back door (and keeps it)",
	):
		return
	t.check(
		_leads(t, back["id"]),
		"the human's claim at the back door says it leads the stack (leader: true, %s)"
			% str(_my_claim(t, back["id"])),
	)
	var ready := func(): return Order.all_called(t, BACK_IDS, "ready", back["id"])
	if not t.require(
			await t.until(ready, 30.0),
			"a and b are ready in their slots at the back door",
	):
		return
	var crossed := not await _dawdle(
		t,
		LOITER_BACK,
		DAWDLE_BACK,
		func(): return _went_in(t, BACK_IDS, back["id"]).is_empty(),
	)
	t.check(
		not crossed,
		("nobody crosses while the human leader dawdles %.0f s out of its slot (%s went in, the "
				+ "first %.1f s after the rest were ready)")
			% [
				DAWDLE_BACK,
				str(_went_in(t, BACK_IDS, back["id"])),
				_first_going(t, BACK_IDS, back["id"]) - _last_ready(t, BACK_IDS, back["id"]),
			],
	)
	t.check(
		Entry.calls(t, "ready", &"me").filter(
			func(c): return String(c.get("opening", "")) == back["id"]
		).is_empty(),
		"the human was never in its slot meanwhile (premise)",
	)
	t.check(
		Stack.mine(stack) > 0 and String(Stack.view(stack).get("opening", "")) == back["id"],
		"the human still holds its slot after dawdling (view %s)" % str(Stack.view(stack)),
	)
	if not crossed:
		var mine := Stack.mine(stack)
		if t.require(
				await Stack.walk(t, &"me", [Stack.slot_point(stack, mine)], 15.0),
				"the human steps into its slot %d" % mine,
		):
			await t.until(
				func(): return Entry.first_call_time(t, "ready", &"me", back["id"]) < INF,
				3.0,
			)
			var in_slot := Entry.first_call_time(t, "ready", &"me", back["id"])
			t.check(in_slot < INF, "the human's stack radios ready in its slot")
			var gone := await t.until(
				func(): return not _went_in(t, BACK_IDS, back["id"]).is_empty(),
				GO_WITHIN,
			)
			t.check(
				gone,
				"the stack goes once its leader stands in its slot (within %.0f s)" % GO_WITHIN,
			)
			if gone:
				t.check(
					_first_going(t, BACK_IDS, back["id"]) >= in_slot,
					"and only after it (human ready at %.2f s, first going_in at %.2f s)"
						% [in_slot, _first_going(t, BACK_IDS, back["id"])],
				)

	# --- The front door: the human dawdles, then walks away. ---
	var front_id := "door_0_415"
	# Done with the back door: put it by the front door's stack.
	t.actor(&"me").global_position = LOITER_FRONT[0]
	await t.seconds(0.5)
	if not t.require(
			not Order.stack_order(
				squad,
				_actors(t, FRONT_IDS),
				FRONT_NORTH,
				"quiet",
				false,
			).is_empty(),
			"the squad posts the stack order on the front door (issue)",
	):
		return
	if not t.require(
			await _reserved(t, stack, front_id),
			"the human is reserved a slot at the front door (and keeps it)",
	):
		return
	var front_ready := func(): return Order.all_called(t, FRONT_IDS, "ready", front_id)
	if not t.require(
			await t.until(front_ready, 30.0),
			"c and d are ready in their slots at the front door",
	):
		return
	var early := not await _dawdle(
		t,
		LOITER_FRONT,
		DAWDLE_FRONT,
		func(): return _went_in(t, FRONT_IDS, front_id).is_empty(),
	)
	t.check(
		not early,
		("nobody crosses at the front door while the human dawdles %.0f s out of its slot (%s went "
				+ "in)") % [DAWDLE_FRONT, str(_went_in(t, FRONT_IDS, front_id))],
	)
	var walked_at := t.time
	var p := t.puppet(&"me")
	p.walk_to(AWAY)
	var withdrawn := func(): return _withdrawn_at(t, front_id, walked_at) < INF
	if not t.require(
			await t.until(withdrawn, 15.0),
			"the human's slot at the front door is withdrawn once it walks away (abort on the "
				+ "radio)",
	):
		return
	var freed_at := _withdrawn_at(t, front_id, walked_at)
	var went := await t.until(
		func(): return not _went_in(t, FRONT_IDS, front_id).is_empty(),
		GO_WITHIN,
	)
	t.check(
		went,
		"its slot withdrawn frees them: the stack goes (within %.0f s of the withdrawal)"
			% GO_WITHIN,
	)
	if went and not early:
		t.check(
			_first_going(t, FRONT_IDS, front_id) >= freed_at,
			"and only after it (withdrawn at %.2f s, first going_in at %.2f s)"
				% [freed_at, _first_going(t, FRONT_IDS, front_id)],
		)


func _actors(t: TestContext, ids: Array) -> Array:
	return ids.map(func(id): return t.actor(id))


## Wait until the human is reserved a slot at doorway `opening` and keeps it 20 frames.
func _reserved(t: TestContext, stack: Node, opening: String) -> bool:
	var settled := [0, 0]
	var held := func():
		var now := (Stack.mine(stack)
				if String(Stack.view(stack).get("opening", "")) == opening
				else 0)
		settled[1] = settled[1] + 1 if now == settled[0] and now > 0 else 0
		settled[0] = now
		return settled[1] >= 20
	return await t.until(held, 20.0)


## Walk the human back and forth between `spots` for `duration` s while `holds` holds; true when it
## held throughout.
func _dawdle(t: TestContext, spots: Array, duration: float, holds: Callable) -> bool:
	var p := t.puppet(&"me")
	var until := t.time + duration
	var i := 1
	while t.time < until:
		p.walk_to(spots[i % spots.size()])
		i += 1
		var leg_end := minf(until, t.time + 4.0)
		if await t.until(func(): return not holds.call(), maxf(0.05, leg_end - t.time)):
			return false
	return holds.call()


## The ids of `ids` that radioed going_in at doorway `opening`.
func _went_in(t: TestContext, ids: Array, opening: String) -> Array:
	return ids.filter(func(id): return Entry.first_call_time(t, "going_in", id, opening) < INF)


func _first_going(t: TestContext, ids: Array, opening: String) -> float:
	var at := INF
	for id in ids:
		at = minf(at, Entry.first_call_time(t, "going_in", id, opening))
	return at


func _last_ready(t: TestContext, ids: Array, opening: String) -> float:
	var at := -INF
	for id in ids:
		at = maxf(at, Entry.first_call_time(t, "ready", id, opening))
	return at


## The human's latest claim at `opening` (its radio), or {}.
func _my_claim(t: TestContext, opening: String) -> Dictionary:
	var mine := Entry.calls(t, "", &"me").filter(
		func(c): return String(c.get("opening", "")) == opening,
	)
	return mine.back() if not mine.is_empty() else {}


## Whether the human's claims at `opening` mark it as the stack's leader.
func _leads(t: TestContext, opening: String) -> bool:
	return _my_claim(t, opening).get("leader", false) == true


## The sim time of the human's first `abort` at `opening` after `since`, or INF.
func _withdrawn_at(t: TestContext, opening: String, since: float) -> float:
	var who := t.actor(&"me")
	for e in t.events:
		if (e["topic"] == &"callout"
				and float(e["time"]) >= since
				and e["data"].get("speaker") == who
				and String(e["data"].get("entry_step", "")) == "abort"
				and String(e["data"].get("opening", "")) == opening):
			return e["time"]
	return INF
