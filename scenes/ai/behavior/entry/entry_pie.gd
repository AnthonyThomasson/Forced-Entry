extends RefCounted
## AI BEHAVIOUR sub-domain — TACTICAL ENTRY's pie, a part the entry holds as `pie`: slicing
## the pie (E3, E7, E19): the arc's steps still to look from and the side being sliced, how
## many sides were sliced, the share of the room seen from outside, and what the point does
## at the arc's end.
## Built once by the entry (`entry.gd`) on its shared `state` and `world`, it holds nothing
## else: what it needs of the entry and of its other parts is handed in at the call (`entry`),
## so no reference cycle forms.

## The entry this part is one of, handed in at the call (never held: it holds the part).
const Entry := preload("res://scenes/ai/behavior/entry.gd")
const EntryState := preload("res://scenes/ai/behavior/entry/entry_state.gd")
const EntryWorld := preload("res://scenes/ai/behavior/entry/entry_world.gd")

## The entry's state, shared with it and its other parts.
var state: EntryState
## What the entry works with, shared with it and its other parts.
var world: EntryWorld
## Share of the room's sample points seen from outside during the pie.
var seen_fraction := 0.0
## How many sides of the door the pie was sliced from.
var sides := 0
## This member has begun slicing the pie, and says so on the radio (`pie`): nobody moves up behind
## it from then on.
var begun := false
## Pie steps still to look from (points on the arc).
var queue: Array = []
## The side being sliced now.
var side := 0


## Built once by the entry, on its `state` and `world`.
func _init(entry_state: EntryState, entry_world: EntryWorld) -> void:
	state = entry_state
	world = entry_world


## Forget the running entry's pie (`Entry.reset`).
func reset() -> void:
	seen_fraction = 0.0
	sides = 0
	begun = false
	queue = []
	side = 0


## Become the point: slice the pie from this side (and, alone, from the other side after).
func start_pie(entry: Entry, team: Array) -> void:
	state.solo = entry.orders.alone(team)
	entry.approach.set_phase("pie")
	if not begun:
		begun = true
		if not entry.radio.last_call.is_empty():
			# The pie is begun: on the radio at once, so nobody moves up behind it (E2).
			entry.radio.say(entry, entry.radio.last_call["entry_step"], entry.radio.last_call)
	side = state.member.side
	queue = (state.geo["pie"][state.member.side] as Array).duplicate()
	sides = 1


## Walk the pie arc a step at a time; at each step look through the door until the gaze settles plus
## `tuning.entry.pie_dwell`, noting what is seen. When the arc is done: alone, slice the other side
## too; else wait for the stack, then go in. The other side's front man of a split stack (E19)
## slices its half, radios `ready` and then crosses in its turn, after the point.
func tick_pie(entry: Entry, team: Array, delta: float) -> void:
	entry.sweep.note_seen(entry)
	if not team.is_empty():
		state.solo = false  # An ally claimed a slot: no second side, it joins the stack.
	if state.hostile_in_view and not entry.grenade.in_bang_window():
		# E14: what is in view is fought from where it stands, not walked past or into.
		world.character.movement.move_input = Vector2.ZERO
		state.clock = 0.0
		return
	if entry.grenade.over:
		queue = []  # A burst in the room (its own team's): no more slicing, in at once.
	if queue.is_empty():
		_end_of_pie(entry, team, delta)
		return
	var spot: Vector2 = queue[0]
	if not entry.approach.arrived_at(spot):
		world.loco.move_to(spot)
		entry.sweep.look_toward(_through_door(world.character.global_position), delta)
		state.clock = 0.0
		return
	world.character.movement.move_input = Vector2.ZERO
	var settled := entry.sweep.look_toward(_through_door(spot), delta)
	if settled and state.clock >= world.tuning.entry.pie_dwell:
		queue.pop_front()
		state.clock = 0.0
	elif not settled:
		state.clock = 0.0


## The arc is done, looking through the door: a pass-by is secured (seen from beside the jamb and
## covered: on its way, nothing left behind it); alone, the other side is sliced too; else, ready,
## it waits for the stack, topped off (E11), then goes in: a follower of a split stack after the
## member ahead of it (`readiness.follow`), the point once the stack is ready and no hostile stands
## in view (E14).
func _end_of_pie(entry: Entry, team: Array, delta: float) -> void:
	world.character.movement.move_input = Vector2.ZERO
	entry.sweep.look_toward(state.geo["pos"] - (state.geo["out"] as Vector2) * 300.0, delta)
	if state.secure:
		state.secured = true
		state.phase = "done"
		return
	if state.solo and sides < 2 and not entry.grenade.over:
		_pie_other_side()
		return
	entry.readiness.say_ready(entry)
	var ahead := entry.readiness.members_ahead(entry)
	if not ahead.is_empty():
		if entry.grenade.over or not entry.approach.topping_off(delta):
			entry.readiness.follow(entry, team, ahead)
	elif (entry.readiness.stack_ready(entry, team)
			and (not state.hostile_in_view or entry.grenade.in_bang_window())
			and (entry.grenade.over or not entry.approach.topping_off(delta))):
		entry.sweep.start_cross(entry, team)


## Alone: cross in front of the door (as far out as the arc's end) and slice it from the other side,
## from the axis outward.
func _pie_other_side() -> void:
	side = -state.member.side
	sides = 2
	queue = (state.geo["pie"][-state.member.side] as Array).duplicate()
	queue.reverse()


## A point through the door, on the line from `from` through the threshold: where to look from a pie
## step.
func _through_door(from: Vector2) -> Vector2:
	var door: Vector2 = state.geo["pos"]
	return door + (door - from).normalized() * 300.0
