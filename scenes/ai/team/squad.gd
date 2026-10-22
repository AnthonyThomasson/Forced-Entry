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
## through the Character API (`rank`, `is_dead`, the `died` signal, `global_position`, and the
## leader's `facing`; a member is an NPC, one that may follow, when a child of it is in the group
## `npc_controllers` at `setup`, interface 7) and the bus, never an NPC's brain.
##
## **Following (LD19 to LD23).** Every living NPC member but the leader follows it (`follows`): it
## picks no goal of its own and keeps to the spot the squad gives it (`follow_spot`). While the
## leader moves that spot is on the leader's trail, a file behind it (`follow_gap` back, then
## `follow_step` further for each next follower); once the leader has stood `follow_still_time` it
## is a slot on a ring (`follow_ring`) behind the way the leader came, within the leader's sight,
## and never in the leader's way (D28). The trail and the spots are `SquadFollow`'s
## (`squad_follow.gd`); the tunables are here. A follower fights only within the `leash` of the
## leader's live position. A human member who does not lead is never given a spot.
##
## **The rally (LD24 to LD26).** The leader's own entry claim at a doorway gives every follower
## holding no order a `stack` order of mode `JOIN` there (D24), once per doorway per leader; its
## `abort` there cancels them (D25); when the human leader dies, the members holding its defend and
## ambush orders are told `cancel` (LD26).
##
## **Its stacks (LD18).** Every stack its side is forming, ordered or its own, read off the members'
## entry claims on the radio (the human's `PlayerStack` among them) and laid where the AI stands
## them (`DoorStack.layout`): `view()["stacks"]`, which the stack markers draw,
## each from its first claim until everyone in it is through, a claim current for the NPCs' own
## `callout_ttl` (handed in by `setup`) and laid on the navigation map and physics space of the
## world the squad itself is in (its viewport's `World2D`).

const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
## The entry claim's wire format and step lists, and the claims heard on the radio
## (scenes/ai/perception/stack/).
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const ClaimLedger := preload("res://scenes/ai/perception/stack/claim_ledger.gd")
const SquadFollow := preload("res://scenes/ai/team/squad_follow.gd")
## The order kinds.
const DEFEND := "defend_room"
const STACK := "stack"
const CANCEL := "cancel"
const GO := "go"
const AMBUSH := "ambush"
## A stack order's modes a leader's request may name (LD14): in quietly, with a stun first, with a
## frag first.
const MODES := ["quiet", "stun", "frag"]
## The mode of the squad's own rally stack (LD24): the leader's own stack bringing its team in,
## which pins no mode (each member goes in as its own entry would). Not one of `MODES`: no request
## names it, only the rally posts it.
const JOIN := StackClaim.JOIN

## The follow file (px): the first follower keeps this far back along the leader's trail...
var follow_gap := 55.0
## ... and each next one this much further (also the spacing of the slots on a ring, and of the
## rings).
var follow_step := 45.0
## The ring (px) round a still leader its followers stand on, behind its facing.
var follow_ring := 80.0
## Seconds the leader stands (within `SquadFollow.TRAIL_STEP`) before it counts as still.
var follow_still_time := 0.8
## A follower re-aims its walk only once its spot has moved this far (px) from where it is going.
var follow_retarget := 20.0
## A follower is at its spot within this distance (px).
var follow_arrive := 10.0
## A follower fights within this distance (px) of the leader's live position...
var leash := 320.0
## ... and one fighting further than this many leashes from it re-decides.
var leash_break := 1.3
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
## The entry claims of this side heard on the radio, the latest per member (LD18): from anywhere
## (the side's whole view), each current for the NPCs' `callout_ttl` (`setup`; a claim is repeated
## every `StackClaim.HEARTBEAT` s).
var _ledger: RefCounted = ClaimLedger.new()
## `_stacks()` as last laid (`_stacks_now`).
var _stacks_cache: Array = []
## The physics frame `_stacks_cache` was laid on (-1: lay it again on the next read).
var _stacks_at := -1
## The doorway geometry the stacks are laid out by, the same the NPCs build.
var _entry: RefCounted = AgentEntry.new()
## Member instance id -> true for each member an NPC controller drives (the ones that follow).
var _npcs := {}
## The leader's trail and the followers' spots (`setup`; null before it).
var _follow: SquadFollow = null
## "<leader instance id>:<opening>" -> true for each doorway a leader's own claim has rallied its
## team to, until that stack is given up (`_rally`).
var _rallied := {}


## Take the leader's trail every physics frame (`SquadFollow.track`).
func _physics_process(_delta: float) -> void:
	if _follow != null:
		_follow.track()


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
	_ledger.setup({ "faction": faction, "range": 0.0, "ttl": claim_ttl })
	_members = roster.filter(func(m): return m is Node and is_instance_valid(m))
	_openings = openings
	_rooms = rooms
	_entry.set_house(openings, rooms)
	_human = human if human != null and _members.has(human) else null
	for m: Node in _members:
		if m.has_signal(&"died"):
			m.died.connect(_on_died.bind(m))
		if m.get_children().any(func(c): return c.is_in_group(&"npc_controllers")):
			_npcs[m.get_instance_id()] = true
	if not EventBus.posted.is_connected(_on_event):
		EventBus.posted.connect(_on_event)
	_leader = _next_leader()
	_follow = SquadFollow.new(self, openings, rooms)
	_follow.reset()


## The squad's leader (null when every member is dead).
func leader() -> Node:
	return _leader


## Every member, in spawn order, the dead included.
func members() -> Array:
	return _members.duplicate()


## Whether `member` is a living member of this squad.
func alive(member: Node) -> bool:
	return _members.has(member) and is_instance_valid(member) and member.get("is_dead") != true


## Whether `member` follows the leader: a living NPC member of this squad that does not lead it.
func follows(member: Node) -> bool:
	return (
		_leader != null
			and member != _leader
			and alive(member)
			and _npcs.has(member.get_instance_id())
	)


## Where follower `member` keeps to now (`Vector2.INF` when it does not follow): on the leader's
## trail while the leader moves, a slot on the ring behind it once it stands still, and out of the
## leader's way (`SquadFollow.spot`, LD21, D28).
func follow_spot(member: Node) -> Vector2:
	if not follows(member) or _follow == null:
		return Vector2.INF
	return _follow.spot(member)


## Whether `order` (a posted order, or a member's row's `order` in `view()`) is a rally's join: a
## `stack` of mode `JOIN` (LD24).
static func is_join(order: Dictionary) -> bool:
	return StackClaim.is_join(order)


## What the squad looks like now, for observers (the order markers, the command menu, the stack
## markers, the leaders overlay):
## `{ leader, members: [{ node, order, step, held, follow_spot }], stacks, trail, leash }`, `order`
## being the order the member holds ({} for none, and once it is done; a held stack released by a go
## carries `go: true`), `step` its latest progress on it ("" for none; `done` with no order held
## once it is done) and `held` whether that order is a stack waiting for the leader's go
## (`_waits_for_go`, LD13), `follow_spot` its spot when it follows (`Vector2.INF` when not);
## `stacks` every stack the side is forming (`_stacks`); `trail` the leader's trail (oldest point
## first) and `leash` (px).
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
		rows.append({
			"node": m,
			"order": order,
			"step": _steps.get(id, ""),
			"held": held,
			"follow_spot": follow_spot(m),
		})
	return {
		"leader": _leader,
		"members": rows,
		"stacks": _stacks_now(),
		"trail": Array(_follow.trail()) if _follow != null else [],
		"leash": leash,
	}


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
## where the AI stands it (`DoorStack.layout`: its holder's side, its place in that side's file),
## a free one on the stack's side; `holder` the instance id holding it (0: none), `there` its
## holder standing in it, `mine` the human's, `row` its file (1 against the wall, 2 a step out).
func _stacks() -> Array:
	var out: Array = []
	for at: Dictionary in _ledger.openings_stacking():
		var g := _geometry(at["opening"], at["into"])
		if g.is_empty():
			continue
		out.append({
			"opening": at["opening"],
			"into": at["into"],
			"door": g["pos"],
			"slots": _ledger.stack(at["opening"], g).layout(),
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
	return _post_order(order)


## Give `order` (`{ leader, faction, to, kind, ... }`) its id, keep it as what each of its `to`
## holds (a `cancel` ends what they held), and post it as `&"order"`. Returns it.
func _post_order(order: Dictionary) -> Dictionary:
	_issued += 1
	order["id"] = "%s_%d" % [_faction, _issued]
	for m: Node in order["to"]:
		var id := m.get_instance_id()
		if order["kind"] == CANCEL:
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


## Whether `order` is a stack that waits for the leader's go and no go has released yet (LD13): not
## the squad's own `go`, nor one heard off the radio (`_latch_go`), each kept in `_released`.
func _waits_for_go(order: Dictionary) -> bool:
	return (String(order.get("kind", "")) == STACK
			and bool(order.get("wait_go", false))
			and not _released.has(str(order["id"])))


## Keep as released (`_released`) every held stack at doorway `opening` its claims now say had its
## go (`DoorStack.released`: a claim under the order says the go came, or a member of the stack is
## crossing or through, D14), as each member keeps its own: a go once heard stands, whatever the
## claims say after.
func _latch_go(opening: String) -> void:
	var stack: RefCounted = _ledger.stack(opening)
	for id in _held_at(opening):
		if stack.released(str(id)):
			_released[str(id)] = true


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
## released (a `go` with `auto: true`), so it goes on the ready barrier. When the human leader dies
## (LD26), the members it set to defend a room or lie in ambush are told `cancel` (one order) and
## follow the new leader; its stack orders are finished.
func _on_died(member: Node) -> void:
	_orders.erase(member.get_instance_id())
	_stacks_at = -1
	if _follow != null:
		_follow.invalidate()
	if member == _leader:
		var previous := _leader
		_leader = _next_leader()
		if _follow != null:
			_follow.reset()
		EventBus.post(&"leader", { "faction": _faction, "leader": _leader, "previous": previous })
		if previous == _human:
			_take_over()
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


## The new leader takes over from the dead human's (LD26): one `cancel` to the living members
## holding a `defend_room` or an `ambush` order, so each follows it.
func _take_over() -> void:
	_cancel_held(func(held: Dictionary): return held.get("kind") in [DEFEND, AMBUSH])


## Post one `cancel` from the leader to the living members whose held order `holds` (called with it)
## accepts; nothing when none does.
func _cancel_held(holds: Callable) -> void:
	var to: Array = _members.filter(
		func(m): return alive(m) and holds.call(_orders.get(m.get_instance_id(), {})),
	)
	if not to.is_empty():
		_post_order({ "leader": _leader, "faction": _faction, "to": to, "kind": CANCEL })


## The radio (LD7): a member's progress on the order it holds (`order_id`, `order_step`) is kept as
## its latest step. An order radioed `done` is no longer held (the step `done` stays, the order
## goes), so nothing offers to cancel it; a `refused` one is still held (D21), but for a join
## (LD25). The leader's own entry steps rally its team (`_rally`).
func _on_event(topic: StringName, data: Dictionary) -> void:
	if topic != &"callout":
		return
	var speaker = data.get("speaker")
	_ledger.hear(data)
	if StringName(data.get("faction", &"")) == _faction and not StackClaim.keeps_claim(data):
		_stacks_at = -1  # A member's place in a stack (LD18), or its claim gone.
		if StackClaim.is_claim(data):
			_latch_go(StackClaim.decode(data)["opening"])
	if (StackClaim.is_claim(data)
			and speaker == _leader
			and StringName(data.get("faction", &"")) == _faction):
		var claim := StackClaim.decode(data)
		if _own_claim(claim):
			_rally(claim)
	var step := String(data.get("order_step", ""))
	if step == "" or not speaker is Node or not is_instance_valid(speaker):
		return
	var id: int = speaker.get_instance_id()
	var held: Dictionary = _orders.get(id, {})
	if not held.is_empty() and str(held.get("id", "")) == str(data.get("order_id", "")):
		_steps[id] = step
		if step == "done" or (step == "refused" and is_join(held)):
			# (A join refused, no slot for it, is over too: the member follows again.)
			_orders.erase(id)


## The leader's own entry steps (no order behind them, LD24, LD25). Its claim at a doorway rallies
## the team: one `stack` order with mode `join` there, into the room it goes into, to every follower
## holding no order (one carrying out another order keeps it), once for that stack (a new leader
## rallies again). Its `abort` (it gave the stack up) cancels the joins it gave there, so their
## members follow it again, and a later claim there is a new stack.
func _rally(claim: Dictionary) -> void:
	var opening: String = claim["opening"]
	var key := "%d:%s" % [_leader.get_instance_id(), opening]
	match String(claim["step"]):
		"claim":
			if _rallied.has(key):
				return
			var door := _opening_pos(opening)
			if door == Vector2.INF:
				return
			_rallied[key] = true
			var to: Array = _follow.followers().filter(
				func(m): return (_orders.get(m.get_instance_id(), {}) as Dictionary).is_empty(),
			)
			if to.is_empty():
				return
			_post_order({
				"leader": _leader, "faction": _faction, "to": to, "kind": STACK,
				"opening": opening, "into": claim["into"], "pos": door,
				"split": false, "mode": JOIN, "bang": false, "wait_go": false,
			})
		"abort":
			if not _rallied.erase(key):
				return
			_cancel_held(func(held: Dictionary): return (
				is_join(held) and held.get("opening") == opening and held.get("leader") == _leader
			))


## Whether `claim` (`StackClaim.decode`) is its speaker's own (LD24): no order behind it, not a
## join's (`join`: a follower that took over the lead holding one, D30), and, from the human's
## `PlayerStack`, marked `own` (it stepped up to a doorway nobody stacks at); a slot the human is
## reserved in a stack already forming is E16's, which rallies nobody.
func _own_claim(claim: Dictionary) -> bool:
	if claim["order_id"] != "" or claim["join"]:
		return false
	return not claim["human"] or claim["own"]


## The centre of the house's doorway `opening`, or `Vector2.INF` when it has none by that id.
func _opening_pos(opening: String) -> Vector2:
	for o: Dictionary in _openings:
		if AgentEntry.opening_id(o) == opening:
			return o["pos"]
	return Vector2.INF
