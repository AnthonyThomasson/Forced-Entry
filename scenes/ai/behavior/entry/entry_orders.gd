extends RefCounted
## AI BEHAVIOUR sub-domain — TACTICAL ENTRY's orders, a part the entry holds as `orders`:
## the order a stack goes in under (`docs/leadership.md` LD9, LD13, LD17, LD24): the order
## this entry carries out as `begin` took it (its id, mode, side, hold and frame, or a join),
## the order a stack follows when a teammate's claim carries one, its living recipients and
## the leader it waits for, and the go that releases a held stack.
## Built once by the entry (`entry.gd`) on its shared `state` and `world`, it holds nothing
## else: what it needs of the entry and of its other parts is handed in at the call (`entry`),
## so no reference cycle forms.

## The entry this part is one of, handed in at the call (never held: it holds the part).
const Entry := preload("res://scenes/ai/behavior/entry.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const DoorStack := preload("res://scenes/ai/perception/stack/door_stack.gd")
const EntryState := preload("res://scenes/ai/behavior/entry/entry_state.gd")
const EntryWorld := preload("res://scenes/ai/behavior/entry/entry_world.gd")

## The entry's state, shared with it and its other parts.
var state: EntryState
## What the entry works with, shared with it and its other parts.
var world: EntryWorld
## The order this entry carries out (`docs/leadership.md` LD9; "" for the NPC's own ENTER or a
## detour).
var id := ""
## The side of the door the order names (1 / -1 along its wall, from its `stack_at`); 0 for a split
## stack (D6).
var side := 0
## The order's mode: a grenade thrown in first.
var bang := false
## The order's mode by name (LD14): `quiet`, `stun` or `frag`.
var mode := ""
## The order holds the stack for the leader's go (LD13).
var hold := false
## The physics frame the order was issued on (its `frame`, as the perception holds it; -1 unknown):
## a held stack takes the human's crossing as its go only from then on (D14).
var frame := -1
## The entry is a join (LD24, `StackClaim.is_join`): its claims say so, so its squad never takes
## them for the member's own (D30).
var join := false
## The side of the door this NPC began on: the side it reaches without crossing the doorway's view
## (D6).
var _pref_side := 0
## `state.time` an ordered `ready` (its own or a recipient's) was first heard or said: D7's cap runs
## from it.
var ready_at := -1.0


## Built once by the entry, on its `state` and `world`.
func _init(entry_state: EntryState, entry_world: EntryWorld) -> void:
	state = entry_state
	world = entry_world


## Forget the running entry's orders (`Entry.reset`).
func reset() -> void:
	id = ""
	side = 0
	bang = false
	mode = ""
	join = false
	hold = false
	frame = -1
	_pref_side = 0
	ready_at = -1.0


## Take the order an entry's `params` carry out (LD9): its id, mode, hold, go, frame and side, and
## the side this NPC begins on (D6). A join is the member's own entry joining its leader's stack
## (LD24, D10): no order's rules, so its order's id is left out; a pass-by carries none either.
func begin_order(entry: Entry, params: Dictionary) -> void:
	join = not state.secure and StackClaim.is_join(params)
	id = "" if state.secure or join else str(params.get("order_id", ""))
	bang = bool(params.get("bang", false))
	mode = str(params["mode"]) if id != "" else ""
	hold = bool(params.get("wait_go", false))
	entry.readiness.released = bool(params.get("go", false))
	frame = _held_order_frame()
	side = _side_named(params)
	_pref_side = world.perception.entry_side_of(state.geo, world.character.global_position)


## The instance id of the leader that gave the order this entry carries out (the live order's
## `leader`, when it is this one and still there); 0 for none.
func leader_id() -> int:
	var held: Dictionary = world.perception.order() if id != "" else {}
	var leader = held.get("leader") if str(held.get("id", "")) == id else null
	return leader.get_instance_id() if leader is Node and is_instance_valid(leader) else 0


## The order this stack goes in under, as a claim's `{ order_id, order_bang, order_mode, order_hold,
## order_go, order_side, order_frame, into }`: this NPC's own, else the lowest slot's of the
## teammates' claims that carry one (an unordered member that joins an ordered stack follows its
## mode and side, D10). {} for a stack nobody was ordered to, which keeps its own rules, and for a
## pass-by.
func claim(entry: Entry) -> Dictionary:
	return {} if state.secure else entry.claim.stack.order_claim(entry.claim.me(entry))


## Whether this stack goes in under an order (`claim`): its mode and side are the order's,
## not its first claimer's, and nothing turns or vetoes it but its own members' lost stun (D1).
func stack_ordered(entry: Entry) -> bool:
	return not claim(entry).is_empty()


## The frame the order this entry carries out was issued on (`frame`, of the order the perception
## holds, when it is this one); -1 for an entry that is no order, or one whose frame is unknown.
func _held_order_frame() -> int:
	if id == "":
		return -1
	var held: Dictionary = world.perception.order()
	return int(held.get("frame", -1)) if str(held.get("id", "")) == id else -1


## The side of the door the order in `params` names (D3): the side along the doorway's wall its
## `stack_at` lies on; 0 for a split stack (D6) and for an entry that is no order.
func _side_named(params: Dictionary) -> int:
	if id == "" or bool(params.get("split", false)):
		return 0
	var at = params.get("stack_at")
	if at is Vector2:
		return world.perception.entry_side_of(state.geo, at)
	return DoorStack.stack_side(state.geo, [], world.character.global_position)


## The side an ordered stack (`ordered`, `claim`) has this NPC stack on in its slot `n`: the
## side the order names (D3); on a split stack, D6's (`DoorStack.split_side`), from the side it
## stands on (the one it asked for, else the one it began on, `_pref_side`, which it reaches without
## crossing the doorway's view).
func ordered_side(entry: Entry, ordered: Dictionary, n: int) -> int:
	if int(ordered["order_side"]) != 0:
		return int(ordered["order_side"])
	return entry.claim.stack.split_side(
		{ "id": world.self_id, "slot": n },
		entry.claim.want if entry.claim.want != 0 else _pref_side,
	)


## An unordered member of an ordered stack goes in the order's way (D10): with a stun when the order
## says so (and none of the order's own members gave it up, D1), quietly when it does not; radioed
## with its next claim. A point slicing the pie that turns goes back to its slot to hold for the
## bang.
func follow_order(entry: Entry, team: Array) -> void:
	if id != "" or entry.grenade.over:
		return
	var ordered := claim(entry)
	if ordered.is_empty():
		return
	var wanted := (bool(ordered["order_bang"]) and not entry.grenade.off
			and not entry.grenade.vetoed(entry, team))
	if wanted == state.bang:
		return
	state.bang = wanted
	entry.listen.upgraded = false
	entry.readiness.turned = entry.readiness.turned or wanted
	if wanted and state.phase == "pie":
		entry.pie.queue = []
		entry.approach.set_phase("stack")
	entry.radio.say(
		entry,
		str(entry.radio.last_call.get("entry_step", "claim")),
		entry.radio.last_call,
	)


## Whether the stack holds for the leader's go (LD13): it goes in under an order (`claim`, an
## unordered member following it too) that says hold, and has had no go yet (`readiness.released`,
## latched by `note_go`).
func held_for_go(entry: Entry) -> bool:
	var ordered := claim(entry)
	return not entry.readiness.released and not ordered.is_empty() and bool(ordered["order_hold"])


## Latch the go of a held stack (LD13) the first time it comes: the leader's `go` on this NPC's own
## order (given before the stack was ready too: it then goes on the ready barrier), a teammate under
## the same order whose claims say it had it, a member of this stack going in or through into its
## room (`DoorStack.released`: one under the order, or the human on a crossing begun since the
## order's `order_frame`, D14: the human leader in the stack stepping in is its go), or the leader
## that gave the order dead (D12). Radioed with the next claim (`order_go`).
func note_go(entry: Entry) -> void:
	if not held_for_go(entry):
		return
	var ordered := claim(entry)
	var go: bool = entry.claim.stack.released(
		str(ordered["order_id"]), str(ordered["into"]), int(ordered["order_frame"]),
	)
	if not go and id != "":
		var held: Dictionary = world.perception.order()
		if str(held.get("id", "")) == id:
			var leader = held.get("leader")
			go = (bool(held.get("go", false))
					or not is_instance_valid(leader)
					or leader.get("is_dead") == true)
	if not go:
		return
	entry.readiness.released = true
	if not entry.radio.last_call.is_empty():
		entry.radio.say(entry, str(entry.radio.last_call["entry_step"]), entry.radio.last_call)


## The other living recipients of the order this NPC stacks under (D7): the order's `to` less itself
## and the dead (`Squad.alive`; with no squad, the living as the radio tells them). [] for an entry
## that is no order, or once the order has ended.
func recipients() -> Array:
	if id == "":
		return []
	var held: Dictionary = world.perception.order()
	if str(held.get("id", "")) != id:
		return []
	return (held.get("to", []) as Array).filter(
		func(m): return is_instance_valid(m) and m != world.character and _alive(m),
	)


## Whether `member`, a recipient of the order, still lives: as its squad says (`Squad.alive`), else
## as the radio tells the living.
func _alive(member: Node) -> bool:
	if world.squad != null and world.squad.has_method("alive"):
		return world.squad.alive(member)
	return member.get("is_dead") != true


## Whether this NPC goes in alone: nobody claims the doorway, and no other living recipient of its
## order is coming (D7).
func alone(team: Array) -> bool:
	return team.is_empty() and recipients().is_empty()


## Whether this NPC waits for teammate `m` (a claim) past `tuning.entry.ready_timeout`: a recipient
## of the order it stacks under (D7), or the leader that gave it holding a slot in the stack (the
## human's `PlayerStack`, its claims marked `leader`, LD17).
func waits_for(entry: Entry, m: Dictionary) -> bool:
	return id != "" and (m["order_id"] == id or leads(entry, m))


## Whether claim `m` is the leader's that gave this NPC's order (LD17: the human leader stacking
## with the stack it ordered).
func leads(entry: Entry, m: Dictionary) -> bool:
	return (bool(m.get("leader", false)) and entry.claim.leader_id != 0
			and int(m["id"]) == entry.claim.leader_id)


## Whether an ordered stack's wait for its recipients has run out: `tuning.entry.order_ready_cap` s
## since the first ordered `ready` (D7).
func capped() -> bool:
	return (ready_at >= 0.0
			and state.time - ready_at >= world.tuning.entry.order_ready_cap)
