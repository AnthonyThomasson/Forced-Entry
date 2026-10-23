extends GameTest
## LD13 / D14 (`docs/leadership.md`): the human in a held stack. When the human leader holds a slot
## at the held doorway through its `PlayerStack`, the held stack waits for the human's Go, and the
## human stepping into the doorway (its `going_in` / `in` on the radio, from a member holding a slot
## at that door) is that Go: the AIs follow it in by the crossing order.
##
## Two invaders are ordered (quiet, hold for go) to stack on the Terrace house's back door from its
## north side. The human leader, a puppet with the invader faction given the stack radio the way
## Main gives it (`MatchBuilder.bind_player`, through `s.squads`), stands beside the stack and is
## reserved a slot, walks to it and is ready. It holds the slot behind theirs (3), not slot 1: the
## AIs claim their slots as they begin, and `PlayerStack` reserves the first free slot only once an
## allied team is stacking, so a human always joins behind them. The held stack does not go for 10
## s; then the human walks in through the door, and both AIs go in after it. The squad reads the go
## off the claims as the members do: while the stack holds, `Squad.view()` says each member's order
## is `held` and the order markers (`OrderMarkers`, as Main builds them for a human leader) label it
## "hold"; once the human steps into the doorway, neither says so any more.
##
## Scripted Von, down: the members' own decisions hold steady, so what they do is the order's alone.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const IDS := [&"a", &"b"]
## How long (s) the held stack is watched not crossing once everyone, the human included, is ready.
const HOLD := 10.0


func describe() -> Dictionary:
	return {
		"name": "A held stack with the human in it waits for the human's go",
		"description": "Two invaders ordered to stack on the back door, hold for go, with the "
			+ "human leader in the stack: nobody goes while the human holds its slot; the human "
			+ "steps in through the door and both AIs follow it in (LD13, D14).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"a", &"invader", Vector2(960, 60))
	s.actor(&"b", &"invader", Vector2(1010, 20))
	Stack.human(s, &"me", Vector2(1000, 120))
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var door: Dictionary = Entry.BACK
	var squad := t.squad(&"invader")
	var stack := t.player_stack()
	if not t.require(stack != null, "the human has a stack radio (MatchBuilder.bind_player)"):
		return
	await t.seconds(0.3)
	var order := Order.stack_order(
		squad,
		IDS.map(func(id): return t.actor(id)),
		Order.BACK_NORTH,
		"quiet",
		true,
	)
	if not t.require(not order.is_empty(), "the squad posts the held stack order (issue)"):
		return
	var markers: Node2D = (load(Order.ORDER_MARKERS_SCRIPT) as GDScript).new()
	t.world.add_child(markers)
	markers.watch(squad.view)
	var settled := [0, 0]  # The human's slot last frame, and the frames it has held it.
	var reserved := func():
		var now := Stack.mine(stack)
		settled[1] = settled[1] + 1 if now == settled[0] and now > 0 else 0
		settled[0] = now
		return settled[1] >= 20
	if not t.require(
			await t.until(reserved, 20.0),
			"the human is reserved a slot at the back door (and keeps it)",
	):
		return
	var mine := Stack.mine(stack)
	if not t.require(
			await Stack.walk(t, &"me", [Stack.slot_point(stack, mine)], 15.0),
			"the human walks to its slot %d" % mine,
	):
		return
	var ready := func(): return Order.all_called(t, IDS + [&"me"], "ready", door["id"])
	if not t.require(await t.until(ready, 30.0), "the whole stack is ready, the human included"):
		return

	var crossed := await t.until(func(): return not Entry.calls(t, "going_in").is_empty(), HOLD)
	t.check(
		not crossed,
		"nobody goes in while the human holds its slot in the held stack (%s went in)"
			% str(Entry.calls(t, "going_in").map(func(c): return c.get("speaker").name)),
	)
	if crossed:
		return
	if not t.require(
			IDS.all(func(id): return _held(squad, t.actor(id))),
			"set-up: the squad says both orders are held for the go (%s)" % str(_rows(squad, t)),
	):
		return
	t.check(
		IDS.all(func(id): return _label(markers, t.actor(id)).contains("hold")),
		"and the order markers say hold (%s)"
			% str(IDS.map(func(id): return _label(markers, t.actor(id)))),
	)

	var way := Stack.crossing(door)
	# Out in front of the door, then into the doorway: its step is `going_in` there, the go (D14).
	if not t.require(
			await Stack.walk(t, &"me", way.slice(0, 2), 8.0),
			"the human walks into the doorway",
	):
		return
	var my_going := Entry.first_call_time(t, "going_in", &"me", door["id"])
	t.check(my_going < INF, "the human's stack radioed going_in as it stepped into the doorway")
	await t.frames(2)
	t.check(
		IDS.all(func(id): return not _held(squad, t.actor(id))),
		"once the human steps in, the squad no longer says the orders are held (%s)"
			% str(_rows(squad, t)),
	)
	t.check(
		IDS.all(func(id): return not _label(markers, t.actor(id)).contains("hold")),
		"nor do the order markers say hold (%s)"
			% str(IDS.map(func(id): return _label(markers, t.actor(id)))),
	)
	if not t.require(
			await Stack.walk(t, &"me", way.slice(2), 8.0),
			"the human walks on into the room",
	):
		return
	var all_in := func():
		return IDS.all(func(id): return Entry.first_call_time(t, "going_in", id, door["id"]) < INF)
	t.check(
		await t.until(all_in, 40.0),
		"both AIs follow the human in (going_in from %s)" % str(IDS.filter(
			func(id): return Entry.first_call_time(t, "going_in", id, door["id"]) < INF,
		)),
	)
	for id in IDS:
		var going := Entry.first_call_time(t, "going_in", id, door["id"])
		t.check(
			going >= my_going,
			"%s went in after the human's go (human at %.2f s, %s at %.2f s)"
				% [id, my_going, id, going],
		)


## The row of `member` in the squad's `view()` ({} when none).
func _row(squad: Node, member: Node) -> Dictionary:
	for row: Dictionary in squad.view().get("members", []):
		if row.get("node") == member:
			return row
	return {}


## Whether the squad's `view()` says `member`'s order is held for the leader's go.
func _held(squad: Node, member: Node) -> bool:
	return bool(_row(squad, member).get("held", false))


## Each member's `held` and step in the squad's `view()`, for the messages.
func _rows(squad: Node, t: TestContext) -> Dictionary:
	var out := {}
	for id in IDS:
		var row := _row(squad, t.actor(id))
		out[id] = [row.get("held"), row.get("step")]
	return out


## The label the order markers draw at `member`'s order target ("" when none).
func _label(markers: Node, member: Node) -> String:
	for m: Dictionary in markers.drawn():
		if m.get("kind") == "order" and m.get("node") == member:
			return String(m.get("label", ""))
	return ""
