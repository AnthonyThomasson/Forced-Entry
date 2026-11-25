extends RefCounted
## AI orchestrator: the controller's beat, a data leaf it builds once in its `_ready` and holds as
## `_pace`. An NPC senses and acts on a staggered beat, as its decisions are: one frame in `BEAT`
## (its world's frame plus its spawn order, `WorldRng`, so a squad's NPCs fall on different frames
## and a match plays the same whatever the process ran before), unless something wakes it at once
## (`Behavior.needs_every_frame`, a hit, a grenade, an order). A frame between beats is a coast: the
## body goes on with the intent the last beat wrote, the decision job and the queued events run as
## on any frame, and the delta of the coast is carried to the next beat, so every timer the beat
## counts down still counts real time. `docs/gaze-and-fire.md` states the rule.

## Physics frames between two beats of one NPC.
const BEAT := 2
## Beats between two sight tests of a character that stays in view (`PerceptionSight.every_beats`):
## `BEAT * SIGHT_EVERY_BEATS` frames old at most.
const SIGHT_EVERY_BEATS := 2

## Beats the NPC has run, and coasts it has taken (an observable of the tests and the probes).
var beats := 0
var coasts := 0
## The delta of the coasts since the last beat, carried to the next.
var owed := 0.0
## The NPC's spawn order (`WorldRng.order_of`), taken once at bind.
var _order := 0


## Takes the NPC's place in its world's spawn order, on its first tick.
func bind(character: Node) -> void:
	_order = WorldRng.order_of(character.get_instance_id())


## Whether `frame` (its world's, `WorldRng.frame_of`) is on the NPC's beat.
func on_beat(frame: int) -> bool:
	return (frame + _order) % BEAT == 0


## This frame's step, `frame` its world's (`WorldRng.frame_of`): the seconds the beat runs with
## (this frame's `delta` and every coast's since the last beat), or a negative number for a coast.
## `awake`: something wakes the NPC off its beat. Its first tick is always a beat: it has written
## no intent yet, and the body turns to the aim point it holds (the origin) until it does.
func step(frame: int, delta: float, awake: bool) -> float:
	owed += delta
	if not awake and beats > 0 and not on_beat(frame):
		coasts += 1
		return -1.0
	var seconds := owed
	owed = 0.0
	beats += 1
	return seconds
