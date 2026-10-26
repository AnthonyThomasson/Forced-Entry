extends RefCounted
## AI BEHAVIOUR sub-domain — TACTICAL ENTRY's hold, a part the entry holds as `hold`:
## holding the cleared room (E8): the doorway on each member covers and its spot there, the
## rear guard's spot, the teammates seen holding, and the end of the hold.
## Built once by the entry (`entry.gd`) on its shared `state` and `world`, it holds nothing
## else: what it needs of the entry and of its other parts is handed in at the call (`entry`),
## so no reference cycle forms.

## The entry this part is one of, handed in at the call (never held: it holds the part).
const Entry := preload("res://scenes/ai/behavior/entry.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const EntryState := preload("res://scenes/ai/behavior/entry/entry_state.gd")
const EntryWorld := preload("res://scenes/ai/behavior/entry/entry_world.gd")

## The entry's state, shared with it and its other parts.
var state: EntryState
## What the entry works with, shared with it and its other parts.
var world: EntryWorld
## The doorway on (its id) this NPC covers once the room is clear ("" = none).
var covering := ""
## Where the rear guard stands, just inside the doorway.
var rear_spot := Vector2.INF
## The room has been covered by sight (waiting for the rest of the stack to be in).
var covered := false
## Where this NPC stands to cover its doorway.
var cover_spot := Vector2.INF
## A point through that doorway, in the room beyond: where its gun points.
var _cover_aim := Vector2.INF
## Allies seen holding the cleared room (cover / rear): instance id -> true.
var _holders := {}


## Built once by the entry, on its `state` and `world`.
func _init(entry_state: EntryState, entry_world: EntryWorld) -> void:
	state = entry_state
	world = entry_world


## Forget the running entry's hold (`Entry.reset`).
func reset() -> void:
	covering = ""
	rear_spot = Vector2.INF
	covered = false
	cover_spot = Vector2.INF
	_cover_aim = Vector2.INF
	_holders = {}


## The room is clear (by this NPC's sight or an ally's call): it is marked cleared, so nothing walks
## into it unprepared again (the entry guard, E9). Then the room is held (E8): with a team, each
## member covers a different doorway on into a room not yet cleared, and a member left over holds
## the doorway it came by, facing back out. A room with no doorway on leaves only the last of the
## team in on the rear; everyone else is done. Alone, it looks through each doorway on in turn.
func finish(entry: Entry, team: Array) -> void:
	world.perception.entry.mark_cleared(state.into)
	entry.sweep.watch = entry.sweep.watch_doors()
	if entry.sweep.watch.is_empty():
		_hold_rear_or_done(entry)
		return
	if entry.readiness.through.is_empty():
		entry.sweep.queue = entry.sweep.watch.duplicate()
		entry.sweep.dwell = 0.0
		entry.approach.set_phase("cover")
		return
	if _claim_door(entry, team):
		entry.approach.set_phase("cover")
		entry.radio.say(entry, "cover", { "covering": covering })
		return
	_hold_rear_or_done(entry, true)


## Hold the doorway this NPC came by, facing back out (rear security): a member left over when the
## team covers the doorways on (`spare`), or the last of the team in; anyone else is done.
func _hold_rear_or_done(entry: Entry, spare := false) -> void:
	covering = ""
	var last := (not entry.readiness.through.is_empty()
			and entry.readiness.through.values().all(
				func(other_slot): return other_slot < state.slot,
			))
	if not (last or (spare and not entry.readiness.through.is_empty())):
		end_hold(entry)
		return
	# A spot of its own: the slots take turns either side of the doorway, each pair a body's
	# clearance further along the wall, counted from the point's side, the same for every member (a
	# split stack's members stacked on either side, E19).
	var door: Vector2 = state.geo["pos"]
	var rank := maxi(state.slot - 1, 0)
	var first := entry.claim.lead_side if entry.claim.lead_side != 0 else state.side
	var on := first if rank % 2 == 0 else -first
	rear_spot = world.loco.reachable(door - (state.geo["out"] as Vector2) * 30.0
			+ (state.geo["along"] as Vector2) * on
				* (float(state.geo["width"]) * 0.5 + 24.0
					+ Entry.SPOT_SPACING * floorf(rank / 2.0)))
	entry.approach.set_phase("rear")
	entry.radio.say(entry, "rear")
	world.character.movement.move_input = Vector2.ZERO


## Claim the doorway on that is nearest this NPC and that no teammate covers, keeping the one it
## already covers while that stays its own (when two claim one, the lower instance id keeps it, as
## with a stack slot). False when every doorway on is covered.
func _claim_door(entry: Entry, team: Array) -> bool:
	var me: int = world.character.get_instance_id()
	var best := {}
	for w in entry.sweep.watch:
		var mine := team.all(
			func(m): return m["step"] != "cover" or m["covering"] != w["id"] or me < m["id"],
		)
		if not mine:
			continue
		if w["id"] == covering:
			best = w
			break
		if (best.is_empty()
				or world.character.global_position.distance_to(w["spot"])
					< world.character.global_position.distance_to(best["spot"])):
			best = w
	if best.is_empty():
		return false
	covering = best["id"]
	cover_spot = best["spot"]
	_cover_aim = best["aim"]
	return true


## Hold the cleared room covering a doorway on: to the cover spot with the gun through that doorway,
## kept there until a teammate who held the room moves on, or `tuning.entry.cover_time` runs out. A
## teammate that takes the same doorway with a lower instance id makes this NPC take another (or the
## rear). Alone: look through each doorway on in turn, `tuning.entry.watch_dwell` each once the gaze
## has settled, then done.
func tick_cover(entry: Entry, team: Array, delta: float) -> void:
	if state.clock >= world.tuning.entry.cover_time:
		end_hold(entry)
		return
	if not entry.sweep.queue.is_empty():
		entry.sweep.tick_sweep(entry, delta)
		return
	if team_moved(team):
		end_hold(entry)
		return
	var was := covering
	if not _claim_door(entry, team):
		_hold_rear_or_done(entry, true)
		return
	if covering != was:
		entry.radio.say(entry, "cover", { "covering": covering })
	if not entry.approach.arrived_at(cover_spot):
		world.loco.move_to(cover_spot)
	else:
		world.character.movement.move_input = Vector2.ZERO
	entry.sweep.look_toward(_cover_aim, delta, 3.0)


## Hold just inside the doorway facing back out the way the team came, until a teammate who held the
## room moves on or `tuning.entry.rear_security_time` runs out.
func tick_rear(entry: Entry, team: Array, delta: float) -> void:
	if not entry.approach.arrived_at(rear_spot):
		world.loco.move_to(rear_spot)
	else:
		world.character.movement.move_input = Vector2.ZERO
	entry.sweep.look_toward(
		(state.geo["pos"] as Vector2) + (state.geo["out"] as Vector2) * 300.0,
		delta,
		3.0,
	)
	if state.clock >= world.tuning.entry.rear_security_time or team_moved(team):
		end_hold(entry)


## Whether a teammate who was holding the cleared room (covering a doorway or the rear) has moved
## on: its latest call is no longer a hold on this doorway (it radioed `done` or `abort`, or claims
## another doorway).
func team_moved(team: Array) -> bool:
	for m in team:
		if StackClaim.holding(m["step"]):
			_holders[m["id"]] = true
	for id in _holders:
		if not team.any(func(m): return m["id"] == id and StackClaim.holding(m["step"])):
			return true
	return false


## The watch is over: radio `done` (a teammate still holding the room takes it as the team moving
## on) and finish.
func end_hold(entry: Entry) -> void:
	if state.phase in ["cover", "rear"] and not entry.readiness.through.is_empty():
		entry.radio.say(entry, "done")
	state.phase = "done"
