extends RefCounted
## AI BEHAVIOUR sub-domain — TACTICAL ENTRY's readiness, a part the entry holds as
## `readiness`: in the slot until its turn to cross (E2, E6, E12, E13, E20): `ready` on the
## radio, the barrier the point waits on, the crossing order and a follower's turn, the last
## man facing back, the security held outside a short room or from the tail, and the hold for
## the leader's go (LD13).
## Built once by the entry (`entry.gd`) on its shared `state` and `world`, it holds nothing
## else: what it needs of the entry and of its other parts is handed in at the call (`entry`),
## so no reference cycle forms.

## The entry this part is one of, handed in at the call (never held: it holds the part).
const Entry := preload("res://scenes/ai/behavior/entry.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const EntryState := preload("res://scenes/ai/behavior/entry/entry_state.gd")
const EntryWorld := preload("res://scenes/ai/behavior/entry/entry_world.gd")
## Most seconds a member that holds outside a short room waits for the room to be called clear
## before it gives up.
const SECURITY_CAP := 30.0

## The entry's state, shared with it and its other parts.
var state: EntryState
## What the entry works with, shared with it and its other parts.
var world: EntryWorld
## `state.time` every living recipient of its order was last found in its slot (-1 = not all are).
var all_in_at := -1.0
## It has radioed `ready` this entry.
var ready_said := false
## `state.time` this NPC got to its slot (-1 = not yet).
var ready_at := -1.0
## How many allies claimed the doorway last tick (a new one restarts the wait).
var team_size := 0
## `state.time` the stack last grew.
var team_grew_at := 0.0
## `state.time` the member ahead of this one was first seen gone (`_ahead_gone`; -1 = not yet).
var turn_at := -1.0
## Allies seen through this doorway this entry: instance id -> slot (kept when they move on).
var through := {}
## The entry became a bang one its order did not ask for since the last `Entry.take_turned()`.
var turned := false
## Seconds spent holding the stack outside a short room (E13).
var _security_clock := 0.0
## `_security_clock` the room was first called clear (-1 = not yet).
var _security_held_at := -1.0
## The physics frame this entry's crossing began on (its first `going_in`, or a through step; -1
## before it): radioed on every claim (`crossed_frame`).
var crossed_frame := -1
## The held stack has had its go (LD13: the leader's, latched; D14 a member going in; D12 no
## leader).
var released := false
## This tick, the member holds in its slot for the go (`Entry.holding_for_go`).
var holding := false


## Built once by the entry, on its `state` and `world`.
func _init(entry_state: EntryState, entry_world: EntryWorld) -> void:
	state = entry_state
	world = entry_world


## Forget the running entry's readiness (`Entry.reset`).
func reset() -> void:
	all_in_at = -1.0
	ready_said = false
	turned = false
	crossed_frame = -1
	released = false
	holding = false
	ready_at = -1.0
	team_size = 0
	team_grew_at = 0.0
	turn_at = -1.0
	through = {}
	_security_clock = 0.0
	_security_held_at = -1.0


## Take note of the stack's claims this tick (`team`): when it grew, the members through the
## doorway, the ones that said quiet, and when an ordered `ready` was first heard or said (D7).
func note_team(entry: Entry, team: Array) -> void:
	if team.size() > team_size:
		team_grew_at = state.time  # Someone joined: the point gives the newcomer the full wait.
	team_size = team.size()
	for m in team:
		if StackClaim.through(m["step"]):
			through[m["id"]] = m["slot"]
		if not m["bang"]:
			entry.listen.quiet_seen[m["id"]] = true
	var ready_heard := func(m): return m["order_id"] == entry.orders.id and m["step"] != "claim"
	if (entry.orders.id != ""
			and entry.orders.ready_at < 0.0
			and (ready_said or team.any(ready_heard))):
		entry.orders.ready_at = state.time


## Radio `ready`, once per walk into the slot: in its slot (E2, E6), or, the other side's front man
## of a split stack, once its half of the pie is sliced (E19), so the point's ready barrier waits
## for that half too.
func say_ready(entry: Entry) -> void:
	if ready_said:
		return
	ready_said = true
	state.member.move_up = 0  # In the slot it moved up into: an ordinary claim from now on.
	entry.radio.say(entry, "ready")


## In the slot, facing the door: the point slices the pie; a follower waits its turn, then crosses.
## On a split stack the other side's front man slices its own half of the pie first (E19).
func tick_stack(entry: Entry, team: Array, delta: float) -> void:
	if entry.claim.move_up_now(entry, delta):
		return
	_keep_to_slot(entry, team, delta)
	if not entry.grenade.over and entry.approach.topping_off(delta):
		return
	if _holds_in_slot(entry, team, delta):
		return
	if entry.grenade.due(entry, team, delta):
		return
	_take_turn(entry, team)


## Stand in the slot (shoved out of it, or stood beside it while a body was on it: step back in),
## facing the door, or, the stack's rear guard (E12), back along the line away from it.
func _keep_to_slot(entry: Entry, team: Array, delta: float) -> void:
	var spot := state.member.point
	if world.character.global_position.distance_to(spot) > StackClaim.SLOT_REACH:
		world.loco.move_to(spot, StackClaim.SLOT_REACH)
	else:
		world.character.movement.move_input = Vector2.ZERO
	if _covers_rear(entry, team):
		entry.sweep.look_toward(
			spot + (state.geo["along"] as Vector2) * state.member.side * 300.0,
			delta,
			3.0,
		)
	else:
		entry.sweep.look_toward(state.geo["pos"], delta)


## Hold in the slot, ready, instead of taking a turn at the door: a member that holds outside a
## short room or is the stack's tail (E13, E20) keeps the stack side as security, and a held stack
## (LD13) waits for its go, with no pie, no bang and no crossing until it comes (the security too:
## nobody is in to secure yet). True while it holds.
func _holds_in_slot(entry: Entry, team: Array, delta: float) -> bool:
	if _holds_outside(entry) or entry.claim.tail():
		say_ready(entry)
		if entry.orders.held_for_go(entry):
			holding = true
			return true
		_tick_security(entry, team, delta)
		return true
	if not entry.orders.held_for_go(entry):
		return false
	say_ready(entry)
	holding = true
	return true


## Take this member's turn at the door: the point (nobody ahead of it) crosses at once after the
## burst while the window lasts (no pie, whatever stands in view), else slices the pie unless it
## holds for the bang or listens (E17); the other side's front man of a split stack slices its own
## half (E19); a follower crosses after the member ahead of it (`follow`).
func _take_turn(entry: Entry, team: Array) -> void:
	var ahead := members_ahead(entry)
	if ahead.is_empty():
		say_ready(entry)
		if entry.grenade.over:
			if (stack_ready(entry, team)
					and (not state.hostile_in_view or entry.grenade.in_bang_window())):
				entry.sweep.start_cross(entry, team)
		elif not (entry.grenade.waits_for_bang(entry, team) or entry.listen.listening(entry, team)):
			entry.pie.start_pie(entry, team)
		return
	if slices_own_half(entry, team):
		entry.pie.start_pie(entry, team)
		return
	say_ready(entry)
	follow(entry, team, ahead)


## A follower's turn (E6): it crosses `tuning.entry.follow_gap` after the member just ahead of it in
## the crossing order goes (`_ahead_gone`), unless a hostile stands in view (E14; not in the moments
## after the stack's stun went off).
func follow(entry: Entry, team: Array, ahead: Array) -> void:
	if _ahead_gone(ahead[-1]):
		if turn_at < 0.0:
			turn_at = state.time
		if (state.time - turn_at >= world.tuning.entry.follow_gap
				and (not state.hostile_in_view or entry.grenade.in_bang_window())):
			entry.sweep.start_cross(entry, team)


## Whether member `m`, just ahead of this one in the crossing order, has gone far enough for this
## one to follow: an AI on this member's side of the door as soon as it starts its crossing, so the
## file walks in on its back; one across the door (a split stack's criss-cross, E19) or the human
## (E16) once it is through, so two never cross the doorway abreast nor walk into the human.
func _ahead_gone(m: Dictionary) -> bool:
	if int(m["side"]) == state.member.side and not bool(m.get("human", false)):
		return StackClaim.crossing(m["step"])
	return StackClaim.through(m["step"])


## Whether this member slices its own half of the pie before it follows the point (E19): the stack
## is split across the door, it is the front man of its side (everyone ahead of it in the crossing
## order is on the other side) and has not sliced yet. Not in a bang entry: the stun takes the place
## of the pie.
func slices_own_half(entry: Entry, team: Array) -> bool:
	if entry.pie.sides > 0 or entry.grenade.over or entry.grenade.banging(entry, team):
		return false
	var before := members_before(entry)
	return not before.is_empty() and before.all(func(m): return int(m["side"]) != state.member.side)


## Whether this member is a rear guard of the stack (E12): the last of its side's file, with two or
## more crossing ahead of it (a stack of three or more; on a split stack each side's file has its
## own), until the member ahead of it is through the door and its own turn to cross is near. It
## faces back along the line the team came by instead of at the door; the point and the second (on a
## split stack, the other side's front man) watch the door.
func _covers_rear(entry: Entry, team: Array) -> bool:
	return turn_at < 0.0 and members_before(entry).size() >= 2 \
		and team.all(
			func(m): return int(m["side"]) != state.member.side or m["slot"] < state.member.slot
		)


## Whether this member holds the stack outside instead of going in (E13): a room too small for the
## team takes two (`geometry.capacity`), so every member with two or more ahead of it in the stack
## stays on the stack side (its place in the stack, not its slot's number: a member that took the
## back of the stack leaves its old slot empty). It does while the two ahead are still on the radio,
## and keeps holding once the room has been called clear. With nobody ahead and the room not cleared
## (they died or gave it up) it is not held back, and takes the lead.
func _holds_outside(entry: Entry) -> bool:
	if members_before(entry).size() < int(state.geo.get("capacity", 99)):
		return false
	return _security_held_at >= 0.0 or not members_ahead(entry).is_empty()


## Hold the stack side as security while the two in the short room clear it (facing back along the
## line, `_covers_rear`): until the room is called clear and a teammate that held it moves on (or
## `tuning.entry.rear_security_time` runs out after that), then done. It never steps into the
## doorway. Gives up after `SECURITY_CAP` s with the room never called clear.
func _tick_security(entry: Entry, team: Array, delta: float) -> void:
	_security_clock += delta
	world.character.movement.move_input = Vector2.ZERO
	if _security_held_at < 0.0 and entry.sweep.cleared_by_team(team):
		_security_held_at = _security_clock
	if _security_held_at >= 0.0:
		if (entry.hold.team_moved(team)
				or _security_clock - _security_held_at >= world.tuning.entry.rear_security_time):
			entry.radio.say(entry, "done")
			state.phase = "done"
	elif _security_clock >= SECURITY_CAP:
		entry.radio.say(entry, "abort")
		state.phase = "done"


## The members of the stack still ahead of this one in the crossing order (`members_before`), the
## first to cross first. One that never reached its slot is dropped once this NPC has waited
## `tuning.entry.ready_timeout` for it (under an order, from when every living recipient of it was
## in its slot, LD17); a recipient of the order this NPC stacks under, and the human leader that
## gave it, only once `tuning.entry.order_ready_cap` has run out (D7). Once a human leader's rally
## has its go, the human is not waited for unless it is crossing (D31): the first AI is the point.
func members_ahead(entry: Entry) -> Array:
	var waited := ready_at >= 0.0 and state.time - ready_at >= world.tuning.entry.ready_timeout
	if entry.orders.id != "":
		waited = all_in_at >= 0.0 and state.time - all_in_at >= world.tuning.entry.ready_timeout
	var gone := released and entry.orders.rallied(entry)
	var still_ahead := func(m):
		if gone and m["human"] and not StackClaim.crossing(m["step"]):
			return false
		return not (
			m["step"] == "claim"
			and (entry.orders.capped() or (waited and not entry.orders.waits_for(entry, m)))
		)
	return members_before(entry).filter(still_ahead)


## Note when every living recipient of this NPC's order (itself among them) stands in its slot
## (`all_in_at`, LD17): an unordered joiner's `tuning.entry.ready_timeout` counts from then.
func note_all_in(entry: Entry, team: Array) -> void:
	if entry.orders.id == "":
		return
	var all_in := ready_at >= 0.0
	for m: Node in entry.orders.recipients():
		var id := m.get_instance_id()
		all_in = all_in and team.any(func(c): return c["id"] == id and c["step"] != "claim")
	if not all_in:
		all_in_at = -1.0
	elif all_in_at < 0.0:
		all_in_at = state.time


## The members of the stack that cross before this one (stack_layout.gd `crossing_order`: by slot,
## and on a split stack the two sides taking turns), the first to cross first.
func members_before(entry: Entry) -> Array:
	return entry.claim.stack.ahead(entry.claim.me(entry))


## Whether the point may go in: every other member of the stack is in its slot, or the wait (from
## when the point was ready, or the stack last grew) has run out. Under an order (D7) every living
## recipient of it is in its slot first, and the human leader that gave it when it holds a slot in
## the stack (LD17), whatever the wait, until `tuning.entry.order_ready_cap` runs out; a member that
## was not ordered is waited for `tuning.entry.ready_timeout` from the moment all of those are in
## their slots (LD17), or the stack last grew.
func stack_ready(entry: Entry, team: Array) -> bool:
	if entry.orders.id == "":
		var waited := state.time - maxf(
			ready_at,
			team_grew_at,
		) >= world.tuning.entry.ready_timeout
		return waited or team.all(func(m): return m["step"] != "claim")
	if entry.orders.capped():
		return true
	if (all_in_at < 0.0
			or team.any(func(m): return m["step"] == "claim" and entry.orders.leads(entry, m))):
		return false
	var waited_all := state.time - maxf(
		all_in_at,
		team_grew_at,
	) >= world.tuning.entry.ready_timeout
	return waited_all or team.all(
		func(m): return m["step"] != "claim" or entry.orders.waits_for(entry, m),
	)
