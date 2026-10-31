extends RefCounted
## AI BEHAVIOUR sub-domain — TACTICAL ENTRY's radio, a part the entry holds as `radio`: the
## entry's steps on the team radio, each a claim in `StackClaim`'s fields queued for the
## controller to post (`Entry.take_calls`), the latest repeated on the heartbeat.
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
## Steps to radio, oldest first, each a claim in `StackClaim`'s fields (`entry_step`, ...; the
## behaviour adds the doorway, room, slot and side).
var calls: Array = []
## A step of this entry has gone out on the radio (`Entry.take_calls`).
var on_air := false
## The latest step radioed, whole (repeated on the heartbeat).
var last_call := {}
## Seconds until the latest step is radioed again.
var heartbeat := 0.0


## Built once by the entry, on its `state` and `world`.
func _init(entry_state: EntryState, entry_world: EntryWorld) -> void:
	state = entry_state
	world = entry_world


## Forget the running entry's radio (`Entry.reset`).
func reset() -> void:
	calls = []
	on_air = false
	last_call = {}
	heartbeat = StackClaim.HEARTBEAT


## Queue step `what` for the radio, a claim in `StackClaim`'s fields (and remember it, with its
## extra fields, for the heartbeat).
func say(entry: Entry, what: String, extra := {}) -> void:
	if state.secure:
		return  # A pass-by joins no stack and claims nothing on the radio.
	# (A new claim: the heartbeat's repeat keeps the frame it was made on.)
	if what == "claim" and not extra.has("claim_frame"):
		state.member.claim_frame = GameClock.frame()
		state.member.claim_pos = world.character.global_position
	# (D14: the frame its crossing began on, once; its `going_in` is committed.)
	if entry.readiness.crossed_frame < 0 and StackClaim.crossing(what):
		entry.readiness.crossed_frame = GameClock.frame()
	state.member.step = what
	var msg := {
		"entry_step": what,
		"claim_frame": state.member.claim_frame,
		"claim_pos": state.member.claim_pos,
	}
	msg.merge(extra)
	msg["crossed_frame"] = entry.readiness.crossed_frame
	msg["bang"] = state.bang
	msg["bang_off"] = entry.grenade.off
	msg["stuns"] = entry.grenade.stuns
	msg["frags"] = entry.grenade.frags
	# (E2: the slot it moved up from, while it walks into the one it took.)
	msg["move_up"] = state.member.move_up
	msg["pie"] = entry.pie.begun
	# The order it stacks under (LD9, LD13, LD14), a held join's rally (D38); a join's claim, never
	# its holder's own (D30).
	msg.merge(entry.orders.terms(entry), true)
	calls.append(msg)
	last_call = msg.duplicate()
	heartbeat = StackClaim.HEARTBEAT
