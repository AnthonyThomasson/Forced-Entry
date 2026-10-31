extends RefCounted
## AI BEHAVIOUR sub-domain — TACTICAL ENTRY's orders, a part the entry holds as `orders`:
## the order a stack goes in under (`docs/leadership.md` LD9, LD13, LD17, LD24): the order
## this entry carries out as `Entry.begin` took it (its id, mode, side, hold and frame, or a join),
## the order a stack follows when a teammate's claim carries one, its living recipients and
## the leader it waits for, and the go that releases a held stack.
## Built once by the entry (`entry.gd`) on its shared `state` and `world`, it holds nothing
## else: what it needs of the entry and of its other parts is handed in at the call (`entry`),
## so no reference cycle forms.

## The entry this part is one of, handed in at the call (never held: it holds the part).
const Entry := preload("res://scenes/ai/behavior/entry.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const StackLayout := preload("res://scenes/ai/perception/stack/stack_layout.gd")
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
## The id of the live order this entry carries out, a join's too ("" for none).
var live_id := ""
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
	live_id = ""
	hold = false
	frame = -1
	_pref_side = 0
	ready_at = -1.0


## Take the order an entry's `params` carry out (LD9): its id, mode, hold, go, frame and side, and
## the side this NPC begins on (D6). A join is the member's own entry joining its leader's stack
## (LD24, D10): no order's rules, so its order's id is left out; a pass-by carries none either.
func begin_order(entry: Entry, params: Dictionary) -> void:
	join = not state.secure and StackClaim.is_join(params)
	live_id = "" if state.secure else str(params.get("order_id", ""))
	id = "" if join else live_id
	bang = bool(params.get("bang", false))
	mode = str(params["mode"]) if id != "" else ""
	hold = bool(params.get("wait_go", false))
	entry.readiness.released = bool(params.get("go", false))
	frame = int(_live().get("frame", -1))
	if join and entry.readiness.released:
		mode = str(_live().get("go_mode", ""))  # (The mode its go named, D38.)
	side = _side_named(params)
	_pref_side = world.perception.entry.side_of(state.geo, world.character.global_position)


## The instance id of the leader that gave the order this entry carries out (the live order's
## `leader`, when it is this one and still there); 0 for none.
func leader_id() -> int:
	var held: Dictionary = world.perception.orders.current() if id != "" else {}
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


## Whether this stack is a human leader's rally held for its go (D38, `DoorStack.hold` with no
## order behind it), its go come or not.
func rallied(entry: Entry) -> bool:
	if state.secure:
		return false
	var go: Dictionary = entry.claim.stack.hold(entry.claim.me(entry))
	return not go.is_empty() and str(go["order_id"]) == ""


## Whether this stack's mode is set for it (`DoorStack.mode`): it goes in under an order (LD9) or
## is a human leader's rally (D38), whose go names its mode. Nothing turns it, no first claimer
## makes it quiet and nothing vetoes it but its own members' lost grenade (D1, D15).
func mode_set(entry: Entry) -> bool:
	return stack_ordered(entry) or rallied(entry)


## The order fields of this NPC's claims (`StackClaim.order_terms`): the order it stacks under, or
## the human leader's rally a held join holds for, its go latched (`readiness.released`).
func terms(entry: Entry) -> Dictionary:
	return StackClaim.order_terms({
		"id": id, "join": join, "bang": bang, "mode": mode, "hold": hold,
		"go": entry.readiness.released, "side": side, "frame": frame,
	})


## The live order this entry carries out (`live_id`), as the perception holds it: a join's too;
## {} for an entry that is no order, and once the order has ended.
func _live() -> Dictionary:
	if live_id == "":
		return {}
	var held: Dictionary = world.perception.orders.current()
	return held if str(held.get("id", "")) == live_id else {}


## The side of the door the order in `params` names (D3): the side along the doorway's wall its
## `stack_at` lies on; 0 for a split stack (D6) and for an entry that is no order.
func _side_named(params: Dictionary) -> int:
	if id == "" or bool(params.get("split", false)):
		return 0
	var at = params.get("stack_at")
	if at is Vector2:
		return world.perception.entry.side_of(state.geo, at)
	return StackLayout.stack_side(state.geo, [], world.character.global_position)


## The side an ordered stack (`ordered`, `claim`) has this NPC stack on in its slot `n`: the
## side the order names (D3); on a split stack, D6's (`DoorStack.split_side`), from the side it
## stands on (the one it asked for, else the one it began on, `_pref_side`, which it reaches without
## crossing the doorway's view).
func ordered_side(entry: Entry, ordered: Dictionary, n: int) -> int:
	if int(ordered["order_side"]) != 0:
		return int(ordered["order_side"])
	return entry.claim.stack.split_side(
		{ "id": world.self_id, "slot": n },
		state.member.want if state.member.want != 0 else _pref_side,
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
	entry.listen.upgraded = false
	entry.listen.turn_bang(entry, wanted)


## Whether the stack holds for the leader's go (LD13): it goes in under an order (`claim`, an
## unordered member following it too) that says hold, and has had no go yet (`DoorStack.held`: its
## own latched go, `readiness.released`, latched by `note_go`, or a claim saying it came).
func held_for_go(entry: Entry) -> bool:
	return not state.secure and entry.claim.stack.held(entry.claim.me(entry))


## Latch the go of a held stack (LD13) the first time it comes: the leader's `go` on this NPC's own
## order (given before the stack was ready too: it then goes on the ready barrier), a teammate under
## the same order whose claims say it had it, a member of this stack going in or through into its
## room (`DoorStack.held` false: `DoorStack.released`, one under the order, or the human on a
## crossing begun since the order's `order_frame`, D14: the human leader in the stack stepping in is
## its go), or the leader that gave the order dead (D12; never a rally's, D38). A rally then takes
## the mode its go named (`DoorStack.mode`). Radioed with the next claim (`order_go`).
func note_go(entry: Entry) -> void:
	if entry.readiness.released or state.secure:
		return
	var me: Dictionary = entry.claim.me(entry)
	if entry.claim.stack.hold(me).is_empty():
		return
	var go: bool = not entry.claim.stack.held(me)
	var live := _live()
	if not go and not live.is_empty():
		var leader = live.get("leader")
		go = bool(live.get("go", false)) or (id != "" and (
			not is_instance_valid(leader) or leader.get("is_dead") == true
		))
	if not go:
		return
	entry.readiness.released = true
	if join:
		# A rally goes in the mode its go named, quiet on the leader stepping in (D38): too late for
		# a grenade.
		mode = str(live.get("go_mode", "")) if bool(live.get("go", false)) else ""
		state.bang = entry.claim.stack.mode(entry.claim.me(entry)) != "quiet"
	if not entry.radio.last_call.is_empty():
		entry.radio.say(entry, str(entry.radio.last_call["entry_step"]), entry.radio.last_call)


## The other living recipients of the order this NPC stacks under (D7): the order's `to` less itself
## and the dead (`Squad.alive`; with no squad, the living as the radio tells them). [] for an entry
## that is no order, or once the order has ended.
func recipients() -> Array:
	if id == "":
		return []
	var held: Dictionary = world.perception.orders.current()
	if str(held.get("id", "")) != id:
		return []
	return (held.get("to", []) as Array).filter(
		func(m): return is_instance_valid(m) and m != world.character and _alive(m),
	)


## Whether `member`, a recipient of the order, still lives: as its squad says (`Squad.alive`), else
## by its `is_dead`.
func _alive(member: Node) -> bool:
	if world.squad != null:
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
