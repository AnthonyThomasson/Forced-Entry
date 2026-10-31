extends RefCounted
## AI BEHAVIOUR sub-domain — TACTICAL ENTRY's listen, a part the entry holds as `listen`:
## how the entry's mode turns (E17): a bang from `Entry.begin` for a suspect room, a quiet entry
## turned into a bang one by a late reason or by a teammate turning, and the point of a quiet
## stack listening in its slot before the pie.
## Built once by the entry (`entry.gd`) on its shared `state` and `world`, it holds nothing
## else: what it needs of the entry and of its other parts is handed in at the call (`entry`),
## so no reference cycle forms.

## The entry this part is one of, handed in at the call (never held: it holds the part).
const Entry := preload("res://scenes/ai/behavior/entry.gd")
const EntryState := preload("res://scenes/ai/behavior/entry/entry_state.gd")
const EntryWorld := preload("res://scenes/ai/behavior/entry/entry_world.gd")
## Seconds between reads of why the room is suspect, for a quiet entry that may turn into a bang
## (E17).
const SUSPECT_EVERY := 0.25

## The entry's state, shared with it and its other parts.
var state: EntryState
## What the entry works with, shared with it and its other parts.
var world: EntryWorld
## Its bang came from a quiet entry turned (E17): it waits for the rest of the stack to follow
## rather than going quiet.
var upgraded := false
## Teammates whose claims said quiet during this entry: instance id -> true (one that then says bang
## has turned it).
var quiet_seen := {}
## Seconds until the room's suspicion is read again.
var _suspect_clock := 0.0
## The listen hold at the stack was ended early (a hostile in view, or under fire): it is not taken
## up again.
var _listen_over := false


## Built once by the entry, on its `state` and `world`.
func _init(entry_state: EntryState, entry_world: EntryWorld) -> void:
	state = entry_state
	world = entry_world


## Forget the running entry's listen (`Entry.reset`).
func reset() -> void:
	upgraded = false
	quiet_seen = {}
	_suspect_clock = 0.0
	_listen_over = false


## Set the entry's mode at `Entry.begin` (`bang`), its leaf having `asked` for a bang or not: the
## stack's (`DoorStack.mode`): an ordered stack goes in the order's way, whoever claimed first (LD9,
## D10), and a stack already claimed the way its first claimer chose; else, alone, a room already
## suspect means a bang with a stun in the stack (`_suspect_bang`, E17). A bang the leaf did not ask
## for is noted (`Entry.take_turned`).
func begin_mode(entry: Entry, asked: bool) -> void:
	var stack_mode: String = entry.claim.stack.mode(entry.claim.me(entry))
	if stack_mode == "":
		state.bang = _suspect_bang(entry, [], asked)  # (Nobody claims: the team is empty.)
	else:
		state.bang = stack_mode != "quiet"
	entry.readiness.turned = state.bang and not asked


## Whether this entry is a bang one on its own terms (E17): its leaf `asked` for it, or the stack
## carries a stun and the room is suspect now, whatever order brought the NPC here. Never a
## pass-by.
func _suspect_bang(entry: Entry, team: Array, asked: bool) -> bool:
	if state.secure:
		return false
	if asked:
		return true
	return (entry.grenade.stack_has_stun(team)
			and not world.perception.hearing.room_suspicion(state.into).is_empty())


## A quiet entry turns into a bang one (E17, `docs/grenades.md` G18) while nobody has crossed and
## the stack carries a stun, when the NPC suspects the room (footsteps or gunfire heard there, shot
## at from it, an ally's fight in it, a hostile lost in it, by its doorway or heading in; read every
## `SUSPECT_EVERY` s: a reason that came up after the entry began, or one it knew when it joined a
## quiet stack), or when a teammate's claims turn from quiet to bang (it knows the reason). Its
## claims say bang, so the whole stack follows; a point slicing the pie goes back to its slot to
## wait for the bang. Not once the bang was given up in this stack (`bang_off`), nor on a pass-by.
func maybe_upgrade(entry: Entry, team: Array, delta: float) -> void:
	if state.bang or not _may_turn(entry, team):
		return
	var turned := team.any(func(m): return m["bang"] and quiet_seen.has(m["id"]))
	if not turned:
		_suspect_clock -= delta
		if _suspect_clock > 0.0:
			return
		_suspect_clock = SUSPECT_EVERY
		if world.perception.hearing.room_suspicion(state.into).is_empty():
			return
	upgraded = true
	entry.grenade.wait = 0.0
	turn_bang(entry, true)


## Turn the entry to a bang one (`on`) or a quiet one, and radio it with the last call repeated:
## a turn to bang marks the entry turned (`readiness.turned`) and sends a point slicing the pie
## back to its slot to hold for the bang. The step both an upgrade (`maybe_upgrade`) and an
## unordered member following its stack's order (`orders.follow_order`) take.
func turn_bang(entry: Entry, on: bool) -> void:
	state.bang = on
	entry.readiness.turned = entry.readiness.turned or on
	if on and state.phase == "pie":
		entry.pie.queue = []
		# Back to its slot, to hold for the bang instead of slicing on.
		entry.approach.set_phase("stack")
	entry.radio.say(
		entry,
		str(entry.radio.last_call.get("entry_step", "claim")),
		entry.radio.last_call,
	)


## Whether the point of a quiet entry still holds in its slot before the pie (E17): the stack
## carries a stun and a late reason could still turn the entry into a bang one (`_may_turn`), for
## `tuning.entry.listen_time` s from getting to its slot. A hostile in view or coming under fire
## ends the hold for this entry: what is there is fought, or the room is gone into, not waited on.
func listening(entry: Entry, team: Array) -> bool:
	if (_listen_over
			or state.bang
			or not _may_turn(entry, team)
			or state.time - entry.readiness.ready_at >= world.tuning.entry.listen_time):
		return false
	if state.hostile_in_view or world.perception.under_fire():
		_listen_over = true
		return false
	return true


## Whether a late reason could still turn this quiet entry into a bang one (`maybe_upgrade`): the
## stack carries a stun, nobody has crossed, no member gave the bang up, the stack is not over a
## burst already, it is not a pass-by, nobody in it was ordered (LD9: an ordered quiet stack
## stays quiet) and it is no human leader's rally (D38: its mode is its go's).
func _may_turn(entry: Entry, team: Array) -> bool:
	return (not (
		entry.grenade.off or entry.grenade.over or state.secure
		or entry.grenade.vetoed(entry, team) or entry.grenade.crossing(entry)
		or entry.orders.mode_set(entry)
	)
			and entry.grenade.stack_has_stun(team))
