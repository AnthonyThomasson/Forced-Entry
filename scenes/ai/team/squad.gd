extends Node
## AI domain · TEAM — one side's squad (`docs/leadership.md` LD3 to LD7): its roster, its leader,
## the line of succession and the orders its leader gives. Main builds one per faction under the
## match's `World` node (`setup`, after arming the characters) and hands each NPC its squad
## (`MatchSpawner.bind_squad`).
##
## **The leader (LD3).** The member of the highest `rank`, the first in spawn order among equals:
## the invaders' unit lead (rank 2), and, a defenders' crew carrying no rank, its first spawned. A
## squad the human leads (`setup`'s `human`) is led by the human. **Succession (LD4).** When the
## leader dies, the next in line by the same rule leads at once and the squad posts `&"leader"`
## `{ faction, leader, previous }` (interface 10). The orders already given stand; a later order
## replaces them.
##
## **Orders (LD5).** `issue(request)` turns what a leader asks for
## (`{ kind, to, pos?, room?, bang? }`, the command menu's plain dict) into an order in the AI's
## terms and posts it as `&"order"` `{ id, leader, faction, to, kind, ... }`: `defend_room` names
## its `room` (a key, or the room under `pos`); `stack` names the doorway nearest `pos` within its
## width (`opening`) and the room it goes into (`into`), the stack forming on the side of the wall
## plane `pos` lies on (an exterior door always goes into the house), on the side of the door `pos`
## lies on along the wall (`stack_at`, the click) or, for a click on the opening itself, both
## (`split`), quiet or with a stun or a frag first (`mode`: `quiet` / `stun` / `frag`, from the
## request's `mode`, else its `bang`: true is a stun; `bang` is kept, true for any mode but quiet),
## going in when ready or holding for the leader's go (`wait_go`, LD13); `cancel` ends what the
## recipients were told. `go` (LD13) releases the held stack at the doorway nearest `pos`: it goes
## to every living member holding a held stack order there, whatever the request's `to` (D13), and
## does not replace those orders (they stay held, released: `view()` marks them `go`); when the
## leader that gave a held order dies, the squad releases it itself (a `go` with `auto: true`, D12).
## `ambush` (LD15) names the doorway nearest `pos` and the room on the side of its wall plane the
## click lies on (`room`; an exterior door: the house's room, D17). A `defend_room`, `stack` or
## `ambush` order also carries its target point, `pos` (the room's centre, the doorway's), which the
## order markers draw. No `to` means every living member but the leader. Range is unlimited: the
## recipients take it off the bus, wherever they are. `resolve(request)` is the same resolution,
## read-only (the command menu's labels).
##
## **Progress (LD7).** The members radio how their order goes (`&"callout"` with `order_id` and
## `order_step`: moving, in_position, done, refused); the squad keeps each one's latest step for
## `view()`, which the order markers draw. A done order is no longer held. It reads its members only
## through the Character API (`rank`, `is_dead`, `died`) and the bus, never an NPC's brain.
##
## **Its stacks (LD18).** Every stack its side is forming, ordered or its own, read off the members'
## entry claims on the radio (the human's `PlayerStack` among them) and laid where the AI stands
## them (`AgentEntry.stack_slots`, `stack_point`): `view()["stacks"]`, which the stack markers draw,
## each from its first claim until everyone in it is through, a claim current for the NPCs' own
## `callout_ttl` (handed in by `setup`) and laid on the navigation map and physics space of the
## world the squad itself is in (its viewport's `World2D`).

const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
const AgentGrenades := preload("res://scenes/ai/perception/agent_grenades.gd")
## The order kinds.
const DEFEND := "defend_room"
const STACK := "stack"
const CANCEL := "cancel"
const GO := "go"
const AMBUSH := "ambush"
## A stack order's modes (LD14): in quietly, with a stun first, with a frag first.
const MODES := ["quiet", "stun", "frag"]
## The entry steps of a member still on its way into the room (it holds a place in the stack), and
## of one standing in its slot.
const STACKING := ["claim", "ready", "bang", "going_in"]
const IN_SLOT := ["ready", "bang"]

## The side this squad is (its members' `faction`).
var _faction: StringName = &""
## The roster, in spawn order (the human leader among them when it leads).
var _members: Array = []
## The house's doorways (`WorldGen.get_openings`).
var _openings: Array = []
## The house's rooms (`WorldGen.get_rooms`).
var _rooms: Array = []
## Who leads now (LD3, LD4); null when nobody is left.
var _leader: Node = null
## The human leader, when the human leads (it keeps the lead while it lives).
var _human: Node = null
## Member instance id -> the order it holds (the posted dict).
var _orders := {}
## Member instance id -> the latest `order_step` it radioed about that order.
var _steps := {}
## Orders posted so far (each order's id counts on from it).
var _issued := 0
## The ids of the held stack orders a go released (LD13, D12): order id -> true.
var _released := {}
## Speaker instance id -> { data, at }: the latest entry claim of each member of this side heard
## (LD18).
var _claims := {}
## Seconds a claim heard stays current: the NPCs' `callout_ttl` (`setup`; a claim is repeated every
## 2 s).
var _claim_ttl := 0.0
## `_stacks()` as last laid (`_stacks_now`).
var _stacks_cache: Array = []
## The physics frame `_stacks_cache` was laid on (-1: lay it again on the next read).
var _stacks_at := -1
## The doorway geometry the stacks are laid out by, the same the NPCs build.
var _entry: RefCounted = AgentEntry.new()


## Set the squad up: `faction`, its members (`roster`) in spawn order, the house's `openings` and
## `rooms`, the `human` when the human leads (null: the leader is the rule's) and `claim_ttl`, how
## long its NPCs keep a callout they heard (their `callout_ttl`, `MatchSpawner.callout_ttl_of`): a
## member's entry claim stays in its stacks as long (0: none is kept). Listens to each member's
## `died` and to the radio from here on.
func setup(
	faction: StringName,
	roster: Array,
	openings: Array,
	rooms: Array,
	human: Node = null,
	claim_ttl := 0.0,
) -> void:
	_faction = faction
	_claim_ttl = claim_ttl
	_members = roster.filter(func(m): return m is Node and is_instance_valid(m))
	_openings = openings
	_rooms = rooms
	_entry.set_house(openings, rooms)
	_human = human if human != null and _members.has(human) else null
	for m: Node in _members:
		if m.has_signal(&"died"):
			m.died.connect(_on_died.bind(m))
	if not EventBus.posted.is_connected(_on_event):
		EventBus.posted.connect(_on_event)
	_leader = _next_leader()


## The squad's leader (null when every member is dead).
func leader() -> Node:
	return _leader


## Every member, in spawn order, the dead included.
func members() -> Array:
	return _members.duplicate()


## Whether `member` is a living member of this squad.
func alive(member: Node) -> bool:
	return _members.has(member) and is_instance_valid(member) and member.get("is_dead") != true


## What the squad looks like now, for observers (the order markers, the command menu, the stack
## markers): `{ leader, members: [{ node, order, step, held }], stacks }`, `order` being the order
## the member holds ({} for none, and once it is done; a held stack released by a go carries
## `go: true`), `step` its latest progress on it ("" for none; `done` with no order held once it is
## done) and `held` whether that order is a stack waiting for the leader's go (`_waits_for_go`,
## LD13); `stacks` every stack the side is forming (`_stacks`).
func view() -> Dictionary:
	var rows: Array = []
	for m: Node in _members:
		if not is_instance_valid(m):
			continue
		var id := m.get_instance_id()
		var order: Dictionary = _orders.get(id, {})
		var held := _waits_for_go(order)
		if _released.has(str(order.get("id", ""))):
			order = order.duplicate()
			order["go"] = true  # A held stack the leader said go to (LD13): still held, released.
		rows.append({ "node": m, "order": order, "step": _steps.get(id, ""), "held": held })
	return { "leader": _leader, "members": rows, "stacks": _stacks_now() }


## `_stacks()`, laid at most once a physics frame, and again after a claim heard or a member's
## death: the stack markers, the order markers and the leaders overlay each read `view()` every
## frame (about 0.14 ms a lay with a six-member stack).
func _stacks_now() -> Array:
	var frame := Engine.get_physics_frames()
	if frame != _stacks_at:
		_stacks_cache = _stacks()
		_stacks_at = frame
	return _stacks_cache


## Every stack the side is forming (LD18), from the entry claims heard:
## `[{ opening, into, door, slots: [{ n, point, holder, held, there, mine, side, row }] }]`, a stack
## while one of its members is still on its way in. Its slots run from 1 to the last claimed, each
## where the AI stands it (`AgentEntry.stack_point`: its holder's side, its place in that side's
## file), a free one on the stack's side; `holder` the instance id holding it (0: none), `there` its
## holder standing in it, `mine` the human's, `row` its file (1 against the wall, 2 a step out).
func _stacks() -> Array:
	var now := GameClock.seconds()
	var calls: Array = []
	for id in _claims.keys():
		var rec: Dictionary = _claims[id]
		var speaker = rec["data"].get("speaker")
		if (now - float(rec["at"]) > _claim_ttl
				or not is_instance_valid(speaker)
				or (speaker as Node).get("is_dead") == true):
			_claims.erase(id)
			continue
		var c: Dictionary = (rec["data"] as Dictionary).duplicate()
		c["age"] = now - float(rec["at"])
		c["id"] = id
		calls.append(c)
	var out: Array = []
	var done := {}
	for c in calls:
		var opening := str(c.get("opening", ""))
		if opening == "" or done.has(opening):
			continue
		done[opening] = true
		var team := AgentEntry.claims(opening, calls)
		if not team.any(func(m): return STACKING.has(m["step"])):
			continue
		var g := _geometry(opening, str(c.get("into", "")))
		if g.is_empty():
			continue
		out.append({
			"opening": opening,
			"into": str(c.get("into", "")),
			"door": g["pos"],
			"slots": _slots_of(g, team),
		})
	return out


## The slots of the stack `team` (its claims) at doorway geometry `g`, as `_stacks` gives them.
func _slots_of(g: Dictionary, team: Array) -> Array:
	var holder := {}
	var top := 0
	for m in team:
		top = maxi(top, int(m["slot"]))
		if not holder.has(int(m["slot"])):
			holder[int(m["slot"])] = m
	var lead := AgentEntry.stack_side(g, team, g["pos"])
	var laid := AgentEntry.stack_slots(g, top, lead)
	var human_id := _human.get_instance_id() if _human != null and is_instance_valid(_human) else 0
	var out: Array = []
	for n in range(1, top + 1):
		var m: Dictionary = holder.get(n, {})
		var on := (int(m["side"])
				if not m.is_empty() and int(m["side"]) != 0
				else AgentEntry.side_for(g, team, n, lead))
		var point := AgentEntry.stack_point(g, team, n, on)
		if point == Vector2.INF:
			continue  # A slot the doorway does not hold (a dead end's).
		var row := 1
		var near := INF
		for s in laid:
			if (s["point"] as Vector2).distance_to(point) < near:
				near = (s["point"] as Vector2).distance_to(point)
				row = int(s["row"])
		out.append({
			"n": n, "point": point, "holder": int(m.get("id", 0)), "held": not m.is_empty(),
			"there": not m.is_empty() and IN_SLOT.has(m["step"]),
			"mine": not m.is_empty() and int(m["id"]) == human_id,
			"side": AgentEntry.side_of(g, point) if g.get("kind", "wall") != "wall" else on,
			"row": row,
		})
	return out


## The entry geometry of doorway `opening` into room `into`, on the world the squad is in: its
## viewport's `World2D`, the one its members stand in ({} when none is known, or the squad is not in
## the tree).
func _geometry(opening: String, into: String) -> Dictionary:
	if not is_inside_tree():
		return {}
	var world := get_viewport().find_world_2d()
	return _entry.geometry(opening, into, world.navigation_map, world.direct_space_state)


## Turn a leader's request (`{ kind, to, pos?, room?, bang?, mode?, wait_go? }`) into an order and
## post it as `&"order"`. Returns the order posted, or {} when there is nothing to post (no living
## recipient, an unknown room or doorway, an unknown kind, a go where no held stack waits).
func issue(request: Dictionary) -> Dictionary:
	if String(request.get("kind", "")) == GO:
		var at := resolve(request)
		return {} if at.is_empty() else _release(_held_at(String(at["opening"])), at, false)
	var to: Array = []
	for m in request.get("to", []):
		if m is Node and alive(m) and not to.has(m):
			to.append(m)
	if (request.get("to", []) as Array).is_empty():
		to = _members.filter(func(m): return alive(m) and m != _leader)
	if to.is_empty():
		return {}
	var kind := String(request.get("kind", ""))
	var order := { "leader": _leader, "faction": _faction, "to": to, "kind": kind }
	match kind:
		DEFEND, STACK, AMBUSH:
			var at := resolve(request)
			if at.is_empty():
				return {}
			order.merge(at)
			if kind == STACK:
				var mode := String(request.get("mode", ""))
				if not MODES.has(mode):
					# A bare `bang` request: a grenade first is a stun.
					mode = "stun" if bool(request.get("bang", false)) else "quiet"
				order["mode"] = mode
				order["bang"] = mode != "quiet"
				order["wait_go"] = bool(request.get("wait_go", false))
		CANCEL:
			pass
		_:
			return {}
	_issued += 1
	order["id"] = "%s_%d" % [_faction, _issued]
	for m: Node in to:
		var id := m.get_instance_id()
		if kind == CANCEL:
			_orders.erase(id)
		else:
			_orders[id] = order
		_steps.erase(id)
	EventBus.post(&"order", order)
	return order


## What a leader's request names in the AI's terms, the way `issue` posts it, without posting
## anything (read-only): for `defend_room` `{ room, pos }` (the room key, its centre), for `stack`
## `{ opening, pos, into, split, stack_at? }` (the doorway, its centre, the room it goes into, the
## side, D3), for `go` `{ opening, pos }` (the doorway) and for `ambush`
## `{ opening, pos, room, beyond }` (the doorway, the room on the click's side of its wall plane,
## D17, and the room on its other side, "" for an exterior door); {} when it names nothing (an
## unknown room, no doorway near `pos`, another kind). The command menu names the room a stack goes
## into, and the room an ambush is laid from, from it, so its labels and the orders agree.
func resolve(request: Dictionary) -> Dictionary:
	var pos = request.get("pos")
	match String(request.get("kind", "")):
		DEFEND:
			var room := _room_for(request)
			return {} if room == "" else { "room": room, "pos": _rect_of(room).get_center() }
		STACK:
			var at := _door_for(pos) if pos is Vector2 else {}
			at.erase("from")
			return at
		GO:
			var door := _door_for(pos) if pos is Vector2 else {}
			return {} if door.is_empty() else { "opening": door["opening"], "pos": door["pos"] }
		AMBUSH:
			var door := _door_for(pos) if pos is Vector2 else {}
			if door.is_empty():
				return {}
			return { "opening": door["opening"], "pos": door["pos"], "room": door["from"],
				# (The room the doorway leads into from the ambush's: "" outside.)
				"beyond": door["into"] if door["into"] != door["from"] else "" }
	return {}


## Whether `order` is a stack that waits for the leader's go and no go has released yet (LD13).
func _waits_for_go(order: Dictionary) -> bool:
	return (String(order.get("kind", "")) == STACK
			and bool(order.get("wait_go", false))
			and not _released.has(str(order["id"])))


## The held stack orders at doorway `opening` that no go has released yet (LD13): order id -> the
## order, held by a living member.
func _held_at(opening: String) -> Dictionary:
	var out := {}
	for m: Node in _members:
		var held: Dictionary = _orders.get(m.get_instance_id(), {}) if is_instance_valid(m) else {}
		if alive(m) and _waits_for_go(held) and String(held.get("opening", "")) == opening:
			out[str(held["id"])] = held
	return out


## Release the held stack orders `held` (order id -> order, `_held_at`) with one `go` at `at`
## (`{ opening, pos }`): posted to every living member holding one of them, `auto` when the squad
## gives it because their leader is dead (D12). The stack orders stay held (a go is latched, never a
## replacement); `view()` marks them released. Returns the go posted, or {} when nobody holds one.
func _release(held: Dictionary, at: Dictionary, auto: bool) -> Dictionary:
	var holds := func(m):
		if not alive(m):
			return false
		var order := _orders.get(m.get_instance_id(), {}) as Dictionary
		return held.has(str(order.get("id", "")))
	var to: Array = _members.filter(holds)
	if to.is_empty():
		return {}
	for id in held:
		_released[id] = true
	_issued += 1
	var go := {
		"id": "%s_%d" % [_faction, _issued], "leader": _leader, "faction": _faction, "to": to,
		"kind": GO, "opening": at["opening"], "pos": at["pos"],
	}
	if auto:
		go["auto"] = true
	EventBus.post(&"order", go)
	return go


## The room a defend request names: its `room` key, else the room under its `pos`; "" when neither
## is a room of the house.
func _room_for(request: Dictionary) -> String:
	var key := String(request.get("room", ""))
	for r in _rooms:
		if key != "" and String(r["key"]) == key:
			return key
	var pos = request.get("pos")
	if pos is Vector2:
		for r in _rooms:
			if (r["rect"] as Rect2).has_point(pos):
				return String(r["key"])
	return ""


## Where a click at `pos` stacks (D3): the doorway nearest it within its width (`opening`, and its
## centre as the order's `pos`), the room it goes into (`into`: the room on the far side of the wall
## plane from the click, the house's room for an exterior door), and the side of the door: `split`
## for a click on the opening itself (within its half-width along the wall), else `stack_at`, the
## click, whose side along the wall the stack forms on. {} when no doorway is that near.
func _door_for(pos: Vector2) -> Dictionary:
	if pos == Vector2.INF:
		return {}
	var best := {}
	for o in _openings:
		var d := pos.distance_to(o["pos"])
		if (d <= float(o.get("width", 80.0))
				and (best.is_empty() or d < pos.distance_to(best["pos"]))):
			best = o
	if best.is_empty():
		return {}
	var joins: Array = (best.get("rooms", []) as Array).map(func(k): return String(k))
	if joins.is_empty():
		return {}
	var door: Vector2 = best["pos"]
	var into: String = joins[0]
	var first := _rect_of(joins[0])
	var into_first := AgentEntry.normal_into(first, door)
	if joins.size() == 2 and (pos - door).dot(into_first) > 0.0:
		# The click is on the first room's side of the wall: the stack forms there and goes into the
		# other.
		into = joins[1]
	var along := into_first.orthogonal()
	# The room on the click's side (an ambush's, D17).
	var from: String = joins[0] if into != joins[0] or joins.size() == 1 else joins[1]
	var out := {
		"opening": AgentEntry.opening_id(best),
		"pos": door,
		"into": into,
		"from": from,
		"split": absf((pos - door).dot(along)) <= float(best.get("width", 80.0)) * 0.5,
	}
	if not out["split"]:
		out["stack_at"] = pos
	return out


## The rect of room `key`, or an empty Rect2.
func _rect_of(key: String) -> Rect2:
	for r in _rooms:
		if String(r["key"]) == key:
			return r["rect"]
	return Rect2()


## The leader by the rule (LD3): the human while it leads and lives; else the living member of the
## highest `rank`, the first in spawn order among equals; null when nobody is left.
func _next_leader() -> Node:
	if _human != null and alive(_human):
		return _human
	var best: Node = null
	for m: Node in _members:
		if alive(m) and (best == null or int(m.get("rank")) > int(best.get("rank"))):
			best = m
	return best


## A member died (LD4): when it led, the next in line leads now, and the squad says so on the bus.
## Its own order is dropped. The held stacks it ordered have nobody to say go now (D12): each is
## released (a `go` with `auto: true`), so it goes on the ready barrier.
func _on_died(member: Node) -> void:
	_orders.erase(member.get_instance_id())
	_stacks_at = -1
	if member == _leader:
		var previous := _leader
		_leader = _next_leader()
		EventBus.post(&"leader", { "faction": _faction, "leader": _leader, "previous": previous })
	# Doorway id -> the held stack orders the dead member gave there, not yet released.
	var orphaned := {}
	for m: Node in _members:
		var held: Dictionary = _orders.get(m.get_instance_id(), {}) if is_instance_valid(m) else {}
		if (held.get("leader") == member
				and bool(held.get("wait_go", false))
				and not _released.has(str(held.get("id", "")))):
			var at := String(held["opening"])
			if not orphaned.has(at):
				orphaned[at] = { "orders": {}, "pos": held["pos"] }
			orphaned[at]["orders"][str(held["id"])] = held
	for at in orphaned:
		_release(orphaned[at]["orders"], { "opening": at, "pos": orphaned[at]["pos"] }, true)


## The radio (LD7): a member's progress on the order it holds (`order_id`, `order_step`) is kept as
## its latest step. An order radioed `done` is no longer held (the step `done` stays, the order
## goes), so nothing offers to cancel it; a `refused` one is still held.
func _on_event(topic: StringName, data: Dictionary) -> void:
	if topic != &"callout":
		return
	var speaker = data.get("speaker")
	if (String(data.get("entry_step", "")) != ""
			and speaker is Node
			and is_instance_valid(speaker)
			and StringName(data.get("faction", &"")) == _faction
			and not AgentGrenades.is_call(data.get("status"))):
		# Its place in a stack (LD18).
		_claims[speaker.get_instance_id()] = { "data": data, "at": GameClock.seconds() }
		_stacks_at = -1
	var step := String(data.get("order_step", ""))
	if step == "" or not speaker is Node or not is_instance_valid(speaker):
		return
	var id: int = speaker.get_instance_id()
	var held: Dictionary = _orders.get(id, {})
	if not held.is_empty() and str(held.get("id", "")) == str(data.get("order_id", "")):
		_steps[id] = step
		if step == "done":
			_orders.erase(id)
