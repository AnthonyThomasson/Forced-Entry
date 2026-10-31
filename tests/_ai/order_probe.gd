extends RefCounted
## Shared helpers for the leadership tests (`docs/leadership.md` LD1 to LD12; not a test itself):
## `const Order := preload("res://tests/_ai/order_probe.gd")`. A squad per side with a leader,
## orders (`defend_room`, `stack`, `cancel`) carried on the `&"order"` bus topic, the progress radio
## (`order_id`, `order_step` on a callout) and the pausable AI clock (`GameClock`). An NPC's brain
## read under an order (the ORDER decision node) is `order_brain_probe.gd` (`OrderBrain`); the
## command menu and the order markers are `order_menu_probe.gd` (`OrderMenu`).
##
## The squad is read duck-typed (`has_method`, `get`), so a test loads and runs before a read exists
## and goes red on an assertion that names what is missing, never on a parse error. The NPC is read
## only through its radio and the bus.

const SQUAD_SCRIPT := "res://scenes/ai/team/squad.gd"
const Entry := preload("res://tests/_ai/entry_probe.gd")
## The order kinds (LD5).
const DEFEND := "defend_room"
const STACK := "stack"
const CANCEL := "cancel"
## The order kinds of part 2 (LD13, LD15): the leader's go for a held stack, and an ambush on a
## doorway.
const GO := "go"
const AMBUSH := "ambush"
## D7: the safety cap (s) on an ordered stack's wait for all its recipients' `ready`.
const ORDER_READY_CAP := 60.0
# --- Stack orders at the Terrace house's back door (LD9) ------------------------------------------
# The back door (`Entry.BACK`: `door_840_190`, 90 px wide, in the kitchen's east wall) and where a
# leader's click on it lands (D3): the side of the wall plane clicked is the side the stack forms
# on; left or right of the opening along the wall picks the stack's side of the door; a click on the
# opening (within its half-width along the wall) is a split stack; an exterior door always goes into
# the house.
## Outside (the back garden), along the wall north of the opening: a stack north of the door, into
## the kitchen.
const BACK_NORTH := Vector2(870, 125)
## Outside, along the wall south of the opening: a stack south of the door, into the kitchen.
const BACK_SOUTH := Vector2(870, 255)
## Outside, on the opening: a split stack, into the kitchen.
const BACK_ON := Vector2(870, 190)
## Inside the kitchen, north of the opening: an exterior door still goes into the house's room.
const BACK_INSIDE_NORTH := Vector2(810, 125)
## The back door's centre y and half-width: north of the door is y < 190 - 45, south y > 190 + 45.
const BACK_Y := 190.0
const BACK_HALF := 45.0


# --- The squad (LD3, LD4, LD5) --------------------------------------------------------------------


## Build and bind the squad of `faction` over `members` (spawn order, all of that faction) the way
## Main builds a side's (`MatchBuilder.build_squads` under the world, over the test world's house),
## `leader` its human leader or null (no `PlayerStack`). For the squads no setup declares: a test
## with one squad per side declares them (`s.squads`, read with `t.world.squad`).
static func squad(t: TestContext, faction: StringName, members: Array, leader: Node = null) -> Node:
	var spec := SquadsSpec.new()
	spec.members = members
	spec.openings = t.world.get("openings") if t.world.get("openings") != null else []
	spec.rooms = t.rooms
	spec.human = { "node": leader, "lead": true } if leader != null else {}
	var built := MatchBuilder.build_squads(t.world, spec)
	return built.get(faction)


## `squad.issue(request)` (`{ kind, to, pos, room, bang }`, what the command menu emits): the order
## it posted, or {} (also when the squad has no `issue` yet).
static func issue(s: Node, request: Dictionary) -> Dictionary:
	if s == null or not s.has_method("issue"):
		return {}
	var out = s.issue(request)
	return out if out is Dictionary else {}


## The squad's `view()` (`{ leader, members: [{ node, order, step }] }`), or {}.
static func view(s: Node) -> Dictionary:
	return s.view() if s != null and s.has_method("view") else {}


## What the squad's view says of `member`: `{ node, order, step }`, or {}.
static func member_view(s: Node, member: Node) -> Dictionary:
	for m in view(s).get("members", []):
		if m.get("node") == member:
			return m
	return {}


## The `&"order"` events posted so far (their data), optionally only those whose `to` names `who`.
static func orders(t: TestContext, who: Node = null) -> Array:
	return t.events_of(&"order", func(d): return who == null or (d.get("to", []) as Array).has(who))


## The ambush orders posted so far (LD15).
static func ambushes(t: TestContext) -> Array:
	return orders(t).filter(func(o): return String(o.get("kind", "")) == AMBUSH)


## The names of `nodes` (an order's `to`), sorted.
static func names(nodes: Array) -> Array:
	var out := nodes.map(func(n): return String(n.name) if n is Node else str(n))
	out.sort()
	return out


## Post an order straight onto the bus, as a squad does (LD5):
## `{ id, leader, faction, to, kind, ... }`, stamped with the frame it is posted on (`frame`) unless
## it names one.
static func post(order: Dictionary) -> void:
	EventBus.post(&"order", order.merged({ "frame": GameClock.frame() }))


# --- The NPC --------------------------------------------------------------------------------------


## Force a decision on the NPC now without touching its brain: gunfire from nobody it knows lands
## beside it (`&"hit"`, no attacker), which it hears as fire at it.
static func gunfire_near(c: Node) -> void:
	EventBus.post(
		&"hit",
		{
			"position": c.global_position + Vector2(40, 0),
			"direction": Vector2.LEFT,
			"damage": 10.0,
			"attacker": null,
			"victim": null,
		},
	)


# --- The radio (LD7) ------------------------------------------------------------------------------


## The callouts that carry an `order_step` (LD7), optionally only step `step` and / or only from
## character `who`.
static func progress(t: TestContext, step := "", who: Node = null) -> Array:
	return t.events_of(&"callout", func(d):
		if String(d.get("order_step", "")) == "":
			return false
		if step != "" and String(d.get("order_step", "")) != step:
			return false
		return who == null or d.get("speaker") == who)


## The progress steps `member` radioed about `order`, oldest first, those of `of` only (all with
## []).
static func steps(t: TestContext, member: Node, order: Dictionary, of: Array = []) -> Array:
	return progress(t, "", member).filter(
		func(c): return (
			str(c.get("order_id", "")) == str(order.get("id", ""))
			and (of.is_empty() or of.has(String(c.get("order_step", ""))))
		),
	).map(func(c): return String(c.get("order_step", "")))


## The entry claims (any entry step) from `who` that carry an `order_id`.
static func ordered_claims(t: TestContext, who: Node, opening := "") -> Array:
	return t.events_of(&"callout", func(d):
		return (d.get("speaker") == who
				and String(d.get("entry_step", "")) != ""
				and str(d.get("order_id", "")) != ""
				and (opening == "" or String(d.get("opening", "")) == opening)))


## The raw callout events (`{ topic, data, time }`) of entry step `step` from `who` (any step when
## ""), oldest first.
static func raw_calls(t: TestContext, who: Node, step := "") -> Array:
	var out: Array = []
	for e: Dictionary in t.events:
		if e["topic"] != &"callout" or e["data"].get("speaker") != who:
			continue
		var s := String(e["data"].get("entry_step", ""))
		if s == "" or (step != "" and s != step):
			continue
		out.append(e)
	return out


## The sim time of the first raw event of `topic` passing `filter`, or INF.
static func first_time(t: TestContext, topic: StringName, filter: Callable) -> float:
	for e: Dictionary in t.events:
		if e["topic"] == topic and filter.call(e["data"]):
			return float(e["time"])
	return INF


# --- The clock (LD1) ------------------------------------------------------------------------------


## Hold the tree paused for `wall_s` seconds of wall time, then unpause. The test's own clock stops
## with the world (the runner stops counting sim time while paused), so this waits on the wall
## clock, a physics frame at a time.
static func pause_for(t: TestContext, wall_s: float) -> void:
	var tree := t.world.get_tree()
	tree.paused = true
	var since := Time.get_ticks_msec()
	while Time.get_ticks_msec() - since < int(wall_s * 1000.0):
		OS.delay_msec(16)
		await t.frames(1)
	tree.paused = false


# --- Stack orders at the Terrace house's back door (LD9) ------------------------------------------


## Which side of the back door point `p` lies on along its wall: `north`, `south`, or `door` (within
## the opening's width).
static func back_side(p: Vector2) -> String:
	if p.y < BACK_Y - BACK_HALF:
		return "north"
	if p.y > BACK_Y + BACK_HALF:
		return "south"
	return "door"


## Order a stack at the back door through `squad.issue` the way the command menu asks for it (LD16):
## `{ kind: "stack", to, pos, bang, mode, wait_go }`, `bang` being mode != quiet (part 1's key). The
## order posted, or {}.
static func stack_order(
	s: Node,
	to: Array,
	pos: Vector2,
	mode: String,
	wait_go: bool,
) -> Dictionary:
	return issue(
		s,
		{
			"kind": STACK,
			"to": to,
			"pos": pos,
			"bang": mode != "quiet",
			"mode": mode,
			"wait_go": wait_go,
		},
	)


## The leader's Go for the held stack at the doorway nearest `pos` (LD13):
## `squad.issue({ kind: "go", pos })`. The order posted, or {}.
static func go(s: Node, pos: Vector2) -> Dictionary:
	return issue(s, { "kind": GO, "pos": pos })


## Whether every actor of `ids` has radioed entry step `step` about doorway `opening`.
static func all_called(t: TestContext, ids: Array, step: String, opening: String) -> bool:
	return ids.all(func(id): return Entry.first_call_time(t, step, id, opening) < INF)


## The actors of `ids` sorted by the stack slot they last claimed at doorway `opening` (from their
## radio); those with no claim last.
static func by_slot(t: TestContext, ids: Array, opening: String) -> Array:
	var slot_of := {}
	for id in ids:
		var claims := Entry.calls(t, "", id).filter(
			func(c): return String(c.get("opening", "")) == opening,
		)
		slot_of[id] = int(claims.back().get("slot", 99)) if not claims.is_empty() else 99
	var out := ids.duplicate()
	out.sort_custom(func(a, b): return slot_of[a] < slot_of[b])
	return out
